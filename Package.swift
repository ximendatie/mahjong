// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AgentsPet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AgentsPet", targets: ["AgentsPet"])
    ],
    targets: [
        .executableTarget(
            name: "AgentsPet",
            path: "Sources"
        ),
        .testTarget(
            name: "AgentsPetTests",
            dependencies: ["AgentsPet"],
            path: "Tests/AgentsPetTests"
        )
    ]
)
