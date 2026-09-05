import XCTest
import FaceRitualCore
@testable import FaceRitual

/// 坐标变换是整个 AR 链路最容易出错的一环 ——
/// 原点上下、aspect-fill 裁切、前置镜像，任一处搞反，脸上的 ● 就会落到错误的一侧。
/// 所以它单独有测试。
final class ImageToViewTransformTests: XCTestCase {

    /// 竖屏 720x1280 的相机画面，铺满 390x844 的屏幕。
    private let imageSize = CGSize(width: 720, height: 1280)
    private let viewSize = CGSize(width: 390, height: 844)

    func testImageOriginIsBottomLeftAndViewOriginIsTopLeft() {
        let transform = ImageToViewTransform(imageSize: imageSize, viewSize: viewSize, isMirrored: false)

        // 图像坐标的 y=0 在**底部**，映射后应落在视图的**下方**。
        let bottom = transform.viewPoint(fromImagePoint: CGPoint(x: imageSize.width / 2, y: 0))
        let top = transform.viewPoint(fromImagePoint: CGPoint(x: imageSize.width / 2, y: imageSize.height))
        XCTAssertGreaterThan(bottom.y, top.y, "图像 y=0 必须映射到视图下方")
    }

    func testCenterMapsToCenter() {
        let transform = ImageToViewTransform(imageSize: imageSize, viewSize: viewSize, isMirrored: false)
        let center = transform.viewPoint(
            fromImagePoint: CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        )
        XCTAssertEqual(center.x, Double(viewSize.width) / 2, accuracy: 0.001)
        XCTAssertEqual(center.y, Double(viewSize.height) / 2, accuracy: 0.001)
    }

    func testMirroringFlipsHorizontallyAroundViewCenter() {
        let plain = ImageToViewTransform(imageSize: imageSize, viewSize: viewSize, isMirrored: false)
        let mirrored = ImageToViewTransform(imageSize: imageSize, viewSize: viewSize, isMirrored: true)

        let imagePoint = CGPoint(x: 120, y: 400)
        let a = plain.viewPoint(fromImagePoint: imagePoint)
        let b = mirrored.viewPoint(fromImagePoint: imagePoint)

        XCTAssertEqual(a.y, b.y, accuracy: 0.001, "镜像不应改变纵坐标")
        XCTAssertEqual(a.x + b.x, Double(viewSize.width), accuracy: 0.001, "镜像应关于视图中线对称")
    }

    /// aspect-fill：内容铺满，多出来的边被裁掉，不能有黑边也不能变形。
    func testAspectFillCoversViewWithoutDistortion() {
        let transform = ImageToViewTransform(imageSize: imageSize, viewSize: viewSize, isMirrored: false)

        let bottomLeft = transform.viewPoint(fromImagePoint: .zero)
        let topRight = transform.viewPoint(fromImagePoint: CGPoint(x: imageSize.width, y: imageSize.height))

        // 图像宽高比 0.5625 比屏幕 0.462 更宽 → 左右会被裁掉，上下正好或溢出。
        XCTAssertLessThanOrEqual(min(bottomLeft.x, topRight.x), 0.001)
        XCTAssertGreaterThanOrEqual(max(bottomLeft.x, topRight.x), Double(viewSize.width) - 0.001)

        // 等比：x 与 y 方向的缩放必须一致。
        let dx = transform.viewPoint(fromImagePoint: CGPoint(x: 100, y: 0)).x
            - transform.viewPoint(fromImagePoint: CGPoint(x: 0, y: 0)).x
        let dy = transform.viewPoint(fromImagePoint: CGPoint(x: 0, y: 0)).y
            - transform.viewPoint(fromImagePoint: CGPoint(x: 0, y: 100)).y
        XCTAssertEqual(dx, dy, accuracy: 0.001, "aspect-fill 必须等比，否则脸会被拉变形")
    }

    func testNormalizedRectSurvivesMirroring() {
        let transform = ImageToViewTransform(imageSize: imageSize, viewSize: viewSize, isMirrored: true)
        let rect = transform.viewRect(fromNormalizedRect: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.25))

        XCTAssertGreaterThan(rect.size.width, 0, "镜像后宽度不应变成负数")
        XCTAssertGreaterThan(rect.size.height, 0)
    }
}

/// 稠密 landmark 布局映射。
///
/// 这里唯一要证明的事：**图像侧 → 解剖学侧的翻转是对的**。
/// 前置摄像头原始画面里，用户的解剖学右半边脸出现在图像左侧；
/// 这一步搞反，整套 AR 导航会左右颠倒，而且在正脸时几乎看不出来。
final class DenseLandmarkLayoutTests: XCTestCase {

    func testImageLeftSlotResolvesToAnatomicalRight() {
        // 300W-68 的 36 号点是图像左侧那只眼的外眼角 → 用户的**右**眼外眼角。
        XCTAssertEqual(
            DenseLandmarkLayout.anatomical(.imageLeft(.leftEyeOuter)),
            .rightEyeOuter
        )
        XCTAssertEqual(
            DenseLandmarkLayout.anatomical(.imageRight(.rightEyeOuter)),
            .leftEyeOuter
        )
    }

    func testCenterSlotIsNotFlipped() {
        XCTAssertEqual(DenseLandmarkLayout.anatomical(.center(.noseTip)), .noseTip)
        XCTAssertEqual(DenseLandmarkLayout.anatomical(.center(.glabella)), .glabella)
    }

    func testLayoutIsSelectedByPointCount() {
        XCTAssertEqual(DenseLandmarkLayout.layout(forPointCount: 68), .ibug68)
        XCTAssertEqual(DenseLandmarkLayout.layout(forPointCount: 98), .wflw98)
        XCTAssertNil(DenseLandmarkLayout.layout(forPointCount: 106))
    }

    func testEveryIndexInLayoutIsWithinRange() {
        for layout in DenseLandmarkLayout.allCases {
            for index in layout.directSlots.keys {
                XCTAssertTrue(
                    (0..<layout.pointCount).contains(index),
                    "\(layout.rawValue) 的索引 \(index) 超出 \(layout.pointCount) 点范围"
                )
            }
            for entry in layout.averagedSlots {
                for index in entry.indices {
                    XCTAssertTrue(
                        (0..<layout.pointCount).contains(index),
                        "\(layout.rawValue) 的平均索引 \(index) 超出范围"
                    )
                }
            }
        }
    }

    /// 两种布局都必须能产出驱动导航的最小 landmark 集合，
    /// 否则换上模型后 anchor 会静默解析失败。
    func testBothLayoutsCoverRequiredLandmarks() {
        for layout in DenseLandmarkLayout.allCases {
            let supported = layout.supportedLandmarks
            for required in SemanticLandmark.required {
                XCTAssertTrue(
                    supported.contains(required),
                    "\(layout.rawValue) 缺少必需 landmark \(required.rawValue)"
                )
            }
        }
    }

    func testResolveProducesSymmetricSidesForASyntheticFace() {
        let layout = DenseLandmarkLayout.ibug68
        // 构造一张左右对称的合成脸：所有点关于 x=100 镜像。
        var points = Array(repeating: Point2D(x: 100, y: 100), count: layout.pointCount)
        points[36] = Point2D(x: 60, y: 100)   // 图像左眼外角
        points[45] = Point2D(x: 140, y: 100)  // 图像右眼外角
        points[30] = Point2D(x: 100, y: 130)  // 鼻尖
        points[8] = Point2D(x: 100, y: 190)   // 下巴

        let table = layout.resolve(points: points, confidence: 0.9)

        // 图像左侧的点必须落到解剖学右侧。
        XCTAssertEqual(table[.rightEyeOuter]?.point.x, 60)
        XCTAssertEqual(table[.leftEyeOuter]?.point.x, 140)
        XCTAssertEqual(table[.noseTip]?.point.y, 130)
        XCTAssertEqual(table[.chinCenter]?.point.y, 190)
    }

    func testResolveRejectsWrongPointCount() {
        let layout = DenseLandmarkLayout.ibug68
        let table = layout.resolve(points: Array(repeating: .zero, count: 50), confidence: 1)
        XCTAssertTrue(table.isEmpty, "点数不匹配时必须整体拒绝，而不是画出错位的点")
    }
}
