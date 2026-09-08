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
    dependencies: [
        // Pinned to a specific commit, not a tagged release: the timenote
        // pill needs the Directives API (MarkdownDirective/DirectiveSyntax/…),
        // which landed on `main` after the latest tag (0.12.0) and hasn't
        // been released yet. `revision` pins exactly — it won't move on its
        // own the way `branch: "main"` would.
        .package(url: "https://github.com/nodes-app/swift-markdown-engine", revision: "08ff3c07b198ed639f595d0279ebac62c0410bc7")
    ],
    targets: [
        .target(
            name: "ClassroomCore"
        ),
        .executableTarget(
            name: "ClassroomApp",
            dependencies: [
                "ClassroomCore",
                .product(name: "MarkdownEngine", package: "swift-markdown-engine")
            ],
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
