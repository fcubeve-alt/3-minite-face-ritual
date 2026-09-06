import Foundation

/// 从 `FaceRitualCore` 的资源包读取内容。
///
/// 内容 JSON 刻意放在 Core package 而不是 App target：
/// 这样单元测试可以直接加载**真实**内容包做校验，
/// 不会出现「测试用的是 fixture，线上用的是另一份」的漂移。
public enum BundledContent {

    public enum ResourceName {
        public static let meta = "content_meta"
        public static let routines = "routines"
        public static let anchors = "anchors"
        public static let moves = "moves"
    }

    /// 注意 `bundle` 是 optional 而不是默认 `.module`。
    ///
    /// SPM 生成的 `Bundle.module` 是 **internal** 的，不能出现在 public 函数的
    /// 默认参数值里（默认参数在调用方展开，那里看不到 internal 符号）。
    /// 写成 `.module` 会编译失败：
    /// "static property 'module' is internal and cannot be referenced from a default argument value"。
    /// 所以默认值给 nil，进函数体之后再取 —— 函数体在模块内部，访问 internal 没问题。
    public static func makeSource(bundle: Bundle? = nil) throws -> JSONContentRepository.Source {
        let resolved = bundle ?? .module
        return JSONContentRepository.Source(
            metaData: try data(named: ResourceName.meta, bundle: resolved),
            routinesData: try data(named: ResourceName.routines, bundle: resolved),
            anchorsData: try data(named: ResourceName.anchors, bundle: resolved),
            movesData: try data(named: ResourceName.moves, bundle: resolved)
        )
    }

    public static func makeRepository(
        bundle: Bundle? = nil,
        failOnValidationError: Bool = true
    ) throws -> JSONContentRepository {
        JSONContentRepository(
            source: try makeSource(bundle: bundle),
            failOnValidationError: failOnValidationError
        )
    }

    private static func data(named name: String, bundle: Bundle) throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw ContentLoadError.resourceNotFound("\(name).json")
        }
        return try Data(contentsOf: url)
    }
}
