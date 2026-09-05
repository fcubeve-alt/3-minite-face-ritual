// swift-tools-version: 5.9
import PackageDescription

// FaceRitualCore 刻意不依赖任何 Apple 平台框架。
// 这是 ARCHITECTURE.md §0 的编译期保证：业务层无法绑定某个 landmark provider。
let package = Package(
    name: "FaceRitualCore",
    // iOS 17 最低版本：SwiftUI 的 onChange 双参数版与 .topBarTrailing 都需要它。
    // 这是可推翻的决策，见 PROJECT_STATE.md 的 Owner Decision 段。
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FaceRitualCore", targets: ["FaceRitualCore"])
    ],
    targets: [
        .target(
            name: "FaceRitualCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FaceRitualCoreTests",
            dependencies: ["FaceRitualCore"],
            resources: [.process("Fixtures")]
        )
    ]
)
