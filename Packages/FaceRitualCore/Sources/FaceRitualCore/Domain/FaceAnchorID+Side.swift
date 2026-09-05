import Foundation

/// Anchor ID 的左右侧约定。
///
/// 内容 JSON 里只写一侧（例如 `temple_left`），
/// 播放器按当前段的解剖学侧自动改写成 `temple_right`。
/// 这样两侧定义永远不会漂移 —— 只有一份真源。
public extension FaceAnchorID {

    static let leftSuffix = "_left"
    static let rightSuffix = "_right"

    var hasSideSuffix: Bool {
        rawValue.hasSuffix(FaceAnchorID.leftSuffix) || rawValue.hasSuffix(FaceAnchorID.rightSuffix)
    }

    /// 换到另一侧。无侧后缀的（如 `glabella_center`）返回自身。
    var mirrored: FaceAnchorID {
        if rawValue.hasSuffix(FaceAnchorID.leftSuffix) {
            return FaceAnchorID(rawValue: rawValue.replacingOccurrences(
                of: FaceAnchorID.leftSuffix,
                with: FaceAnchorID.rightSuffix,
                options: .anchored,
                range: rawValue.range(of: FaceAnchorID.leftSuffix, options: .backwards)
            ))
        }
        if rawValue.hasSuffix(FaceAnchorID.rightSuffix) {
            return FaceAnchorID(rawValue: rawValue.replacingOccurrences(
                of: FaceAnchorID.rightSuffix,
                with: FaceAnchorID.leftSuffix,
                options: .anchored,
                range: rawValue.range(of: FaceAnchorID.rightSuffix, options: .backwards)
            ))
        }
        return self
    }

    /// 解析到指定解剖学侧。`.both` / `.none` 保持原样。
    func resolved(for side: BodySide) -> FaceAnchorID {
        guard hasSideSuffix else { return self }
        switch side {
        case .left:
            return rawValue.hasSuffix(FaceAnchorID.leftSuffix) ? self : mirrored
        case .right:
            return rawValue.hasSuffix(FaceAnchorID.rightSuffix) ? self : mirrored
        case .both, .none, .leftThenRight:
            return self
        }
    }
}
