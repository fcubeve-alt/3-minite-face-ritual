import CoreGraphics
import Foundation
import FaceRitualCore

/// 图像坐标 → 视图坐标。
///
/// 这里是整个 AR 链路最容易出错的一环：
/// Vision 的点原点在**左下**、单位是图像像素；预览层用 `resizeAspectFill` 裁切；
/// 前置摄像头预览还要水平镜像。三者任一处搞反，脸上的 ● 就会落到错误的一侧。
/// 所以把它单独抽出来，并配有单元测试。
struct ImageToViewTransform {
    /// 图像尺寸（已旋转成竖屏方向）。
    let imageSize: CGSize
    let viewSize: CGSize
    let isMirrored: Bool

    private let scale: CGFloat
    private let offsetX: CGFloat
    private let offsetY: CGFloat

    init(imageSize: CGSize, viewSize: CGSize, isMirrored: Bool) {
        self.imageSize = imageSize
        self.viewSize = viewSize
        self.isMirrored = isMirrored

        // resizeAspectFill：取较大的缩放比，多出来的部分被裁掉。
        let candidateScale = max(
            imageSize.width > 0 ? viewSize.width / imageSize.width : 1,
            imageSize.height > 0 ? viewSize.height / imageSize.height : 1
        )
        self.scale = candidateScale
        self.offsetX = (viewSize.width - imageSize.width * candidateScale) / 2
        self.offsetY = (viewSize.height - imageSize.height * candidateScale) / 2
    }

    /// 输入：Vision 的图像坐标（原点左下，像素）。
    /// 输出：视图坐标（原点左上，points）。
    func viewPoint(fromImagePoint point: CGPoint) -> Point2D {
        let flippedY = imageSize.height - point.y
        var x = point.x * scale + offsetX
        let y = flippedY * scale + offsetY
        if isMirrored {
            x = viewSize.width - x
        }
        return Point2D(x: Double(x), y: Double(y))
    }

    /// 输入：Vision 的归一化矩形（原点左下，0…1）。
    func viewRect(fromNormalizedRect rect: CGRect) -> Rect2D {
        // 归一化矩形的四角走同一条变换，再取包围盒 —— 镜像后左右角会互换。
        let corners = [
            CGPoint(x: rect.minX * imageSize.width, y: rect.minY * imageSize.height),
            CGPoint(x: rect.maxX * imageSize.width, y: rect.maxY * imageSize.height)
        ].map(viewPoint(fromImagePoint:))

        let minX = min(corners[0].x, corners[1].x)
        let maxX = max(corners[0].x, corners[1].x)
        let minY = min(corners[0].y, corners[1].y)
        let maxY = max(corners[0].y, corners[1].y)
        return Rect2D(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 输入：已归一化到 [0,1] 的**左上原点**坐标（ARKit 投影后常用）。
    func viewPoint(fromTopLeftNormalized point: CGPoint) -> Point2D {
        var x = point.x * viewSize.width
        let y = point.y * viewSize.height
        if isMirrored { x = viewSize.width - x }
        return Point2D(x: Double(x), y: Double(y))
    }
}

extension Point2D {
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }

    init(_ point: CGPoint) {
        self.init(x: Double(point.x), y: Double(point.y))
    }
}

extension Size2D {
    var cgSize: CGSize { CGSize(width: width, height: height) }

    init(_ size: CGSize) {
        self.init(width: Double(size.width), height: Double(size.height))
    }
}

extension Rect2D {
    var cgRect: CGRect {
        CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }
}
