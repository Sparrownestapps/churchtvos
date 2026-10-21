// swift-tools-version:5.10
// The SwiftUI content editors (playlists, decks, themes, backgrounds, scheduling, media pickers, shared UI kit).
// Shared by the iPhone/iPad Remote app and the Mac app. Depends only on ChurchTVCore (which owns the supabase dependency).
import PackageDescription

let package = Package(
    name: "ChurchTVEditors",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ChurchTVEditors", targets: ["ChurchTVEditors"]),
    ],
    dependencies: [
        .package(path: "../ChurchTVCore"),
    ],
    targets: [
        .target(
            name: "ChurchTVEditors",
            dependencies: [.product(name: "ChurchTVCore", package: "ChurchTVCore")]
        ),
        .testTarget(name: "ChurchTVEditorsTests", dependencies: ["ChurchTVEditors"]),
    ]
)
