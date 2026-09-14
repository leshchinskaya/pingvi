// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "AgentAttention", platforms: [.macOS(.v14)], products: [.executable(name: "AgentAttention", targets: ["AgentAttention"])], targets: [.executableTarget(name: "AgentAttention"), .testTarget(name: "AgentAttentionTests", dependencies: ["AgentAttention"], path: "TestsSwift")], swiftLanguageModes: [.v5])
