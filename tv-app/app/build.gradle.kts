import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "com.churchtvos.tv"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.churchtvos.tv"
        minSdk = 25 // Fire OS 6 and newer
        targetSdk = 36
        versionCode = 7
        versionName = "1.6.0"
    }

    // Two products from one code base. "store" is what goes to Amazon and Google Play: NO NDI code or libraries.
    // "ndi" is the EXPERIMENTAL build that links the NDI Android SDK (licence unconfirmed: never publish it). See NDI-CONTRACT.md.
    flavorDimensions += "distribution"
    productFlavors {
        create("store") {
            dimension = "distribution"
            isDefault = true
            buildConfigField("boolean", "NDI_AVAILABLE", "false")
        }
        create("ndi") {
            dimension = "distribution"
            versionNameSuffix = "-ndi" // shows in Settings and in the dashboard's screen list (app_version)
            buildConfigField("boolean", "NDI_AVAILABLE", "true")
        }
    }

    val signing = rootProject.file("keystore/keystore.properties").takeIf { it.exists() }?.let { file ->
        Properties().apply { file.inputStream().use(::load) }
    }

    signingConfigs {
        if (signing != null) {
            create("release") {
                storeFile = rootProject.file(signing.getProperty("storeFile"))
                storePassword = signing.getProperty("storePassword")
                keyAlias = signing.getProperty("keyAlias")
                keyPassword = signing.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            // Installs next to the real app on a test TV without touching its pairing.
            applicationIdSuffix = ".dev"
        }
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.findByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true // java.time on Fire OS 6
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

// The ndi variants exist only when the NDI SDK has been dropped into app/ndi-sdk/ (it is gitignored; see NDI-CONTRACT.md),
// so a plain `./gradlew assembleRelease bundleRelease` can only ever produce the store build. -PndiCompileOnly=true enables
// them without the SDK to compile and unit-test the Kotlin side (the result has no NDI libraries and cannot be installed).
val ndiSdkPresent = file("ndi-sdk/include/Processing.NDI.Lib.h").exists()
val ndiCompileOnly = providers.gradleProperty("ndiCompileOnly").isPresent
androidComponents {
    beforeVariants { variant ->
        if (variant.productFlavors.any { it.second == "ndi" }) variant.enable = ndiSdkPresent || ndiCompileOnly
    }
}

dependencies {
    // The NDI native code and libndi.so live in a separate module that only the ndi flavor depends on.
    "ndiImplementation"(project(":ndi-native"))

    val composeBom = platform("androidx.compose:compose-bom:2026.09.00")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.core:core-ktx:1.19.1")
    implementation("androidx.tv:tv-material:1.1.0")

    implementation("androidx.media3:media3-exoplayer:1.11.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.11.1")
    implementation("androidx.media3:media3-ui:1.11.1")

    implementation("io.coil-kt.coil3:coil-compose:3.6.3")
    // Without a network module Coil cannot load https images (church logos).
    implementation("io.coil-kt.coil3:coil-network-okhttp:3.6.3")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")

    testImplementation("junit:junit:4.13.2")

    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
