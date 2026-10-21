// swift-tools-version:5.10
// The native week/day calendar (SwiftUI) shared by the iPhone/iPad app and, later, the Mac app.
// It depends on ChurchTVCore only. It never imports the editors: opening, creating and re-scheduling go out through callbacks.
import PackageDescription

let package = Package(
    name: "ChurchTVCalendar",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ChurchTVCalendar", targets: ["ChurchTVCalendar"]),
    ],
    dependencies: [
        .package(path: "../ChurchTVCore"),
    ],
    targets: [
        .target(name: "ChurchTVCalendar", dependencies: [.product(name: "ChurchTVCore", package: "ChurchTVCore")]),
        .testTarget(name: "ChurchTVCalendarTests", dependencies: ["ChurchTVCalendar"]),
    ]
)
