// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "AgentAttention",
    platforms: [.macOS(.v14), .iOS(.v18), .watchOS(.v11)],
    products: [
        .executable(name: "AgentAttention", targets: ["AgentAttention"]),
        .library(name: "PingviLink", targets: ["PingviLink"])
    ],
    targets: [
        .target(name: "PingviLink"),
        .executableTarget(name: "AgentAttention", dependencies: ["PingviLink"]),
        .testTarget(
            name: "AgentAttentionTests",
            dependencies: ["AgentAttention", "PingviLink"],
            path: "TestsSwift"
        )
    ],
    swiftLanguageModes: [.v5]
)
