import Foundation
import UIKit
import FaceRitualCore

/// Provider 的自我描述。Settings / Debug 页与 POC 报告都读它。
public struct FaceProviderDescriptor: Identifiable, Hashable {
    public let id: String
    public let displayName: String
    public let summary: String
    /// 是否需要 TrueDepth 前置深度相机。
    public let requiresTrueDepth: Bool
    /// 是否需要摄像头。Mock provider 生成合成脸，不需要 ——
    /// 这决定了要不要向用户申请摄像头权限（规格 §4：摄像头只在必要时才申请）。
    public let requiresCamera: Bool
    /// 该 provider 能提供的语义 landmark 集合。
    public let supportedLandmarks: Set<SemanticLandmark>
    /// 是否提供可信的头部姿态（yaw/pitch/roll）。
    public let providesHeadPose: Bool
    /// 是否提供逐点遮挡判断。全部实现目前都是 false —— 我们不假装能看穿手指。
    public let providesOcclusionEstimate: Bool

    public init(
        id: String,
        displayName: String,
        summary: String,
        requiresTrueDepth: Bool,
        requiresCamera: Bool = true,
        supportedLandmarks: Set<SemanticLandmark>,
        providesHeadPose: Bool,
        providesOcclusionEstimate: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.requiresTrueDepth = requiresTrueDepth
        self.requiresCamera = requiresCamera
        self.supportedLandmarks = supportedLandmarks
        self.providesHeadPose = providesHeadPose
        self.providesOcclusionEstimate = providesOcclusionEstimate
    }

    /// 是否具备驱动 AR 导航的最小能力。
    public var canDriveGuidance: Bool {
        SemanticLandmark.required.allSatisfy { supportedLandmarks.contains($0) }
    }
}

public struct FaceAlignmentConfiguration {
    /// 渲染视图尺寸（points）。provider 负责把 landmark 投影到这个坐标系。
    public var viewSize: CGSize
    /// 预览是否水平镜像。AR Mirror 默认 true —— 用户期待的是镜子。
    public var isMirrored: Bool
    public var targetFrameRate: Int

    public init(viewSize: CGSize, isMirrored: Bool = true, targetFrameRate: Int = 30) {
        self.viewSize = viewSize
        self.isMirrored = isMirrored
        self.targetFrameRate = targetFrameRate
    }
}

public enum FaceAlignmentProviderError: LocalizedError {
    case unavailable(String)
    case cameraUnavailable
    case modelMissing(String)
    case configurationFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .unavailable(reason): return "Face alignment provider 不可用: \(reason)"
        case .cameraUnavailable: return "无法访问前置摄像头"
        case let .modelMissing(name): return "缺少模型文件: \(name)"
        case let .configurationFailed(reason): return "相机配置失败: \(reason)"
        }
    }
}

/// **Face Alignment 的唯一接入点。**
///
/// 规格 §15 与 Owner 指令：优先测试 HRFFA，但整个 App 业务层不得直接绑定它。
/// 所有实现（Vision / HRFFA / ARKit / Mock）都只通过这个协议向上输出
/// provider 中立的 `FaceGeometry`。业务层永远看不到 68 点索引或 1220 顶点号。
///
/// 换 provider = 换一个实现类，UI、播放器、Overlay、内容层零改动。
public protocol FaceAlignmentProvider: AnyObject {
    var descriptor: FaceProviderDescriptor { get }
    /// 当前设备上是否可用（机型 / 模型文件 / 系统版本）。
    var isAvailable: Bool { get }
    /// 不可用时给用户和 POC 报告看的原因。
    var unavailableReason: String? { get }

    /// 每帧输出。在主线程回调。
    var onGeometry: ((FaceGeometry) -> Void)? { get set }
    var onFailure: ((Error) -> Void)? { get set }

    func start(configuration: FaceAlignmentConfiguration) throws
    func stop()
    func updateViewSize(_ size: CGSize)

    /// 相机预览视图。ARKit 与 AVCapture 的预览方式不同，因此由 provider 自己提供。
    func makePreviewView() -> UIView
}

/// 可选的 provider 列表与创建。Settings → Developer 里可以运行时切换，
/// 这正是 POC 阶段做三方横评所需要的。
public enum FaceAlignmentProviderKind: String, CaseIterable, Identifiable {
    case vision
    case hrffa
    case arkit
    case mock

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vision: return "Vision (基线)"
        case .hrffa: return "HRFFA (CoreML)"
        case .arkit: return "ARKit Face Mesh"
        case .mock: return "Mock (合成脸)"
        }
    }
}

public enum FaceAlignmentProviderFactory {

    /// M1 的默认选择。
    ///
    /// 选 Vision 而不是 HRFFA 作为默认，是工程判断而非产品判断：
    /// Vision 用**具名** landmark 区域，没有魔数索引，全机型可用，无需模型文件，
    /// 因此它是 POC 里唯一一开始就必定能跑的对照组。
    /// HRFFA 一旦放入模型文件即可在 Settings 切换并与之横评。
    public static let defaultKind: FaceAlignmentProviderKind = .vision

    public static func make(_ kind: FaceAlignmentProviderKind) -> FaceAlignmentProvider {
        switch kind {
        case .vision: return VisionFaceAlignmentProvider()
        case .hrffa: return HRFFAFaceAlignmentProvider()
        case .arkit: return ARKitFaceAlignmentProvider()
        case .mock: return MockFaceAlignmentProvider()
        }
    }

    /// 按优先级挑一个当前设备上可用的 provider。
    public static func makeFirstAvailable(
        preferring kind: FaceAlignmentProviderKind
    ) -> (provider: FaceAlignmentProvider, fellBackFrom: FaceAlignmentProviderKind?) {
        let preferred = make(kind)
        if preferred.isAvailable { return (preferred, nil) }

        for candidate in [FaceAlignmentProviderKind.vision, .arkit, .mock] where candidate != kind {
            let provider = make(candidate)
            if provider.isAvailable { return (provider, kind) }
        }
        return (MockFaceAlignmentProvider(), kind)
    }
}
