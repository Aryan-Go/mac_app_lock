// swift-tools-version:5.9
import PackageDescription

let linkerSettings: [LinkerSetting] = [
    .linkedFramework("AppKit"),
    .linkedFramework("Carbon"),
    .linkedFramework("Security"),
    .linkedFramework("LocalAuthentication"),
    .linkedFramework("ServiceManagement")
]

let package = Package(
    name: "AppLock",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AppLock", targets: ["AppLock"]),
        .library(name: "AppLockKit", targets: ["AppLockKit"])
    ],
    targets: [
        .target(
            name: "AppLockKit",
            path: "Sources/AppLockKit",
            linkerSettings: linkerSettings
        ),
        .executableTarget(
            name: "AppLock",
            dependencies: ["AppLockKit"],
            path: "Sources/AppLock"
        ),
        .testTarget(
            name: "AppLockKitTests",
            dependencies: ["AppLockKit"],
            path: "Tests/AppLockKitTests"
        )
    ]
)
