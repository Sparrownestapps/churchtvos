// swift-tools-version:5.10
// Shared code for every Church TV OS Apple app (iPhone/iPad remote now, Mac later).
import PackageDescription

let package = Package(
    name: "ChurchTVCore",
    // iOS 17 is the app's deployment target; supabase-swift itself needs iOS 16 / macOS 13.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ChurchTVCore", targets: ["ChurchTVCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.55.4"),
    ],
    targets: [
        .target(
            name: "ChurchTVCore",
            dependencies: [.product(name: "Supabase", package: "supabase-swift")]
        ),
        .testTarget(name: "ChurchTVCoreTests", dependencies: ["ChurchTVCore"]),
    ]
)
