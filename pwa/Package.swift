// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "pwa",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "pwa", targets: ["pwa"])
    ],
    targets: [
        .executableTarget(
            name: "pwa",
            path: "Sources/pwa",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("WebKit"),
                .linkedFramework("Security")
            ]
        )
    ]
)

