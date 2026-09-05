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
    }

    public static func makeSource(bundle: Bundle = .module) throws -> JSONContentRepository.Source {
        JSONContentRepository.Source(
            metaData: try data(named: ResourceName.meta, bundle: bundle),
            routinesData: try data(named: ResourceName.routines, bundle: bundle),
            anchorsData: try data(named: ResourceName.anchors, bundle: bundle)
        )
    }

    public static func makeRepository(
        bundle: Bundle = .module,
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
