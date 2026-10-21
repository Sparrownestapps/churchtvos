// EXPERIMENTAL: the NDI native code (JNI shim) and libndi.so. Only the app's "ndi" flavor depends on this module, so the
// store build never contains any of it. The NDI SDK itself is NOT in the repository: unpack it into ../app/ndi-sdk/ (see
// NDI-CONTRACT.md). Without the SDK this module has no enabled variants unless -PndiCompileOnly=true.
plugins {
    id("com.android.library")
}

val sdkDir = rootProject.file("app/ndi-sdk")
val ndiSdkPresent = sdkDir.resolve("include/Processing.NDI.Lib.h").exists()
val ndiCompileOnly = providers.gradleProperty("ndiCompileOnly").isPresent

android {
    namespace = "com.churchtvos.ndi"
    compileSdk = 37

    defaultConfig {
        minSdk = 25
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") } // Fire TV and Google TV are ARM
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    if (ndiSdkPresent) {
        externalNativeBuild {
            cmake {
                path = file("src/main/cpp/CMakeLists.txt")
                // version "3.22.1" is what the Android SDK manager installs with the NDK; adjust if you have another.
            }
        }
        defaultConfig {
            externalNativeBuild { cmake { arguments += listOf("-DNDI_SDK_DIR=${sdkDir.absolutePath}", "-DANDROID_STL=c++_static") } }
        }
        // libndi.so per ABI, straight from the SDK, packaged next to our own libndi_jni.so.
        sourceSets["main"].jniLibs.srcDir(sdkDir.resolve("lib"))
        packaging { jniLibs.keepDebugSymbols += "**/libndi.so" }
    }
}

androidComponents {
    beforeVariants { variant -> variant.enable = ndiSdkPresent || ndiCompileOnly }
}
