import Foundation

/// 一张标准比例的示意脸。
///
/// 用途：跟练播放器在**示范视频还没到位**时，用它把动作的起点、终点和方向画出来。
/// 这不是任何一个真人的脸，也不假装是 —— 它只需要比例合理、左右对称。
///
/// 为什么要有它：
///
/// 之前示意图用的是一张**手写的 9 个位置表**，而内容里有 27 个位置。
/// 结果是 15 个有轨迹的动作里只画得出 4 个，其余 11 个在屏幕上什么都没有 ——
/// 而视频到位之前，示意图就是全部画面。
///
/// 改成用这张合成脸 + `FaceAnchorResolver` 解析 `anchors.json` 的真实规则之后，
/// **任何**内容里定义过的位置都能画出来，以后加位置也不用改代码。
///
/// 坐标是脸部局部坐标（原点=双眼中点，单位=瞳距），与 `FaceFrame` 的约定一致。
/// 数值与 `tools/golden/generate_golden.py` 里的 `CANONICAL_FACE` 逐条对应 ——
/// 有测试盯着这一点（`testSyntheticFaceMatchesGoldenFixture`），
/// 漂了的话 golden vector 验证的就不再是运行时真正用的那张脸。
public enum SyntheticFace {

    /// 归一化坐标：原点=双眼中点，x 向右，y 向下，单位=瞳距。
    public static let landmarks: [SemanticLandmark: Point2D] = [
        .chinCenter: Point2D(x: 0.000, y: 1.720),
        .foreheadCenter: Point2D(x: 0.000, y: -0.720),
        .glabella: Point2D(x: 0.000, y: -0.280),
        .leftBrowInner: Point2D(x: -0.220, y: -0.320),
        .leftBrowOuter: Point2D(x: -0.800, y: -0.320),
        .leftBrowPeak: Point2D(x: -0.520, y: -0.400),
        .leftCheekbone: Point2D(x: -0.780, y: 0.420),
        .leftEyeCenter: Point2D(x: -0.500, y: 0.000),
        .leftEyeInner: Point2D(x: -0.250, y: 0.020),
        .leftEyeLower: Point2D(x: -0.500, y: 0.100),
        .leftEyeOuter: Point2D(x: -0.780, y: 0.000),
        .leftEyeUpper: Point2D(x: -0.500, y: -0.120),
        .leftJawAngle: Point2D(x: -0.920, y: 1.250),
        .leftMouthCorner: Point2D(x: -0.420, y: 1.050),
        .leftNoseAla: Point2D(x: -0.220, y: 0.700),
        .leftTemple: Point2D(x: -1.050, y: -0.180),
        .lowerLipCenter: Point2D(x: 0.000, y: 1.150),
        .noseBridgeMid: Point2D(x: 0.000, y: 0.250),
        .noseBridgeTop: Point2D(x: 0.000, y: -0.100),
        .noseTip: Point2D(x: 0.000, y: 0.620),
        .rightBrowInner: Point2D(x: 0.220, y: -0.320),
        .rightBrowOuter: Point2D(x: 0.800, y: -0.320),
        .rightBrowPeak: Point2D(x: 0.520, y: -0.400),
        .rightCheekbone: Point2D(x: 0.780, y: 0.420),
        .rightEyeCenter: Point2D(x: 0.500, y: 0.000),
        .rightEyeInner: Point2D(x: 0.250, y: 0.020),
        .rightEyeLower: Point2D(x: 0.500, y: 0.100),
        .rightEyeOuter: Point2D(x: 0.780, y: 0.000),
        .rightEyeUpper: Point2D(x: 0.500, y: -0.120),
        .rightJawAngle: Point2D(x: 0.920, y: 1.250),
        .rightMouthCorner: Point2D(x: 0.420, y: 1.050),
        .rightNoseAla: Point2D(x: 0.220, y: 0.700),
        .rightTemple: Point2D(x: 1.050, y: -0.180),
        .subnasale: Point2D(x: 0.000, y: 0.780),
        .upperLipCenter: Point2D(x: 0.000, y: 0.950),
    ]

    /// 脸在归一化坐标下的纵向范围（含发际线上方一点余量）。
    /// 视图用它决定缩放，好让整张脸连同额头上方的位置都放得下。
    public static let verticalExtent: ClosedRange<Double> = -1.55...1.95

    /// 造一个可以直接喂给 `FaceAnchorResolver` 的 geometry。
    ///
    /// - Parameters:
    ///   - center: 双眼中点在视图坐标里的位置
    ///   - interocular: 瞳距对应多少个视图单位（点）
    public static func makeGeometry(center: Point2D, interocular: Double) -> FaceGeometry {
        var points: [SemanticLandmark: LandmarkSample] = [:]
        points.reserveCapacity(landmarks.count)
        for (mark, local) in landmarks {
            points[mark] = LandmarkSample(
                point: Point2D(
                    x: center.x + local.x * interocular,
                    y: center.y + local.y * interocular
                ),
                // 合成脸没有识别过程，置信度恒为 1 ——
                // 不这么写的话 anchor 会因为低于 confidenceThreshold 而解析失败。
                confidence: 1
            )
        }
        return FaceGeometry(
            providerID: "synthetic",
            timestamp: 0,
            trackingState: .locked,
            landmarks: points,
            isMirrored: false,
            overallConfidence: 1
        )
    }
}
