// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Classroom",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Classroom",
            targets: ["ClassroomApp"]
        ),
        .executable(
            name: "ClassroomSmokeTests",
            targets: ["ClassroomSmokeTests"]
        ),
        .library(
            name: "ClassroomCore",
            targets: ["ClassroomCore"]
        )
    ],
    targets: [
        .target(
            name: "ClassroomCore"
        ),
        .executableTarget(
            name: "ClassroomApp",
            dependencies: ["ClassroomCore"],
            resources: [
                .copy("Resources/classroom-icon.png"),
                .copy("Resources/classroom-wordmark.png")
            ]
        ),
        .executableTarget(
            name: "ClassroomSmokeTests",
            dependencies: ["ClassroomCore"],
            path: "Tests/ClassroomSmokeTests"
        ),
        .testTarget(
            name: "ClassroomCoreTests",
            dependencies: ["ClassroomCore"]
        )
    ]
)
