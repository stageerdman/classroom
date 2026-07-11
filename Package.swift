// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LocalClassroom",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "LocalClassroom",
            targets: ["LocalClassroomApp"]
        ),
        .executable(
            name: "LocalClassroomSmokeTests",
            targets: ["LocalClassroomSmokeTests"]
        ),
        .library(
            name: "LocalClassroomCore",
            targets: ["LocalClassroomCore"]
        )
    ],
    targets: [
        .target(
            name: "LocalClassroomCore"
        ),
        .executableTarget(
            name: "LocalClassroomApp",
            dependencies: ["LocalClassroomCore"]
        ),
        .executableTarget(
            name: "LocalClassroomSmokeTests",
            dependencies: ["LocalClassroomCore"],
            path: "Tests/LocalClassroomSmokeTests"
        ),
        .testTarget(
            name: "LocalClassroomCoreTests",
            dependencies: ["LocalClassroomCore"]
        )
    ]
)
