import Foundation
import FaceRitualCore

/// 稠密 landmark 布局 → 语义 landmark 的映射表。
///
/// **这个文件是整个工程里唯一允许出现 landmark 编号的地方。**
/// 业务层、内容 JSON、Overlay、Player 都只认 `SemanticLandmark`。
/// 换 provider 就是换一张这里的表（或换一个 provider 类），上层零改动。
///
/// 关键约定：表里的 left/right 一律是**图像侧**（点在图像里出现在哪一边），
/// 不是解剖学侧。原因是 300W / WFLW 这些数据集标注时用的就是图像侧，
/// 而前置摄像头的原始画面里，用户的解剖学右半边脸出现在图像左侧。
/// 解剖学侧在运行时由 `resolve(imageSide:isMirrored:)` 决定，
/// 这样命名歧义只在这一处解决一次。
enum DenseLandmarkLayout: String, CaseIterable {
    /// 300W / iBUG 68 点，face alignment 领域最通用的布局。
    case ibug68
    /// WFLW 98 点。HRFFA 论文常用的布局之一。
    case wflw98

    var pointCount: Int {
        switch self {
        case .ibug68: return 68
        case .wflw98: return 98
        }
    }

    static func layout(forPointCount count: Int) -> DenseLandmarkLayout? {
        allCases.first { $0.pointCount == count }
    }

    /// 图像侧的语义位置。
    enum ImageSideSlot: Hashable {
        case center(SemanticLandmark)
        /// 出现在图像左侧的点，以及它在图像右侧的对应点。
        case imageLeft(SemanticLandmark)
        case imageRight(SemanticLandmark)
    }

    /// index → 语义位置。单个 index 可能是多点求平均的一部分，见 `averagedSlots`。
    var directSlots: [Int: ImageSideSlot] {
        switch self {
        case .ibug68:
            return [
                // 轮廓 0–16：0 在图像左，16 在图像右，8 是下巴。
                0: .imageLeft(.leftJawAngle),
                16: .imageRight(.rightJawAngle),
                8: .center(.chinCenter),
                // 眉 17–21（图像左）/ 22–26（图像右）
                17: .imageLeft(.leftBrowOuter),
                21: .imageLeft(.leftBrowInner),
                19: .imageLeft(.leftBrowPeak),
                22: .imageRight(.rightBrowInner),
                26: .imageRight(.rightBrowOuter),
                24: .imageRight(.rightBrowPeak),
                // 鼻 27–35
                27: .center(.noseBridgeTop),
                29: .center(.noseBridgeMid),
                30: .center(.noseTip),
                33: .center(.subnasale),
                31: .imageLeft(.leftNoseAla),
                35: .imageRight(.rightNoseAla),
                // 眼角 36–47
                36: .imageLeft(.leftEyeOuter),
                39: .imageLeft(.leftEyeInner),
                42: .imageRight(.rightEyeInner),
                45: .imageRight(.rightEyeOuter),
                // 唇 48–59
                48: .imageLeft(.mouthLeftCorner),
                54: .imageRight(.mouthRightCorner),
                51: .center(.upperLipCenter),
                57: .center(.lowerLipCenter)
            ]

        case .wflw98:
            return [
                // 轮廓 0–32：0 图像左，32 图像右，16 下巴。
                0: .imageLeft(.leftJawAngle),
                32: .imageRight(.rightJawAngle),
                16: .center(.chinCenter),
                // 眉 33–41（图像左）/ 42–50（图像右）
                33: .imageLeft(.leftBrowOuter),
                37: .imageLeft(.leftBrowPeak),
                38: .imageLeft(.leftBrowInner),
                46: .imageRight(.rightBrowInner),
                44: .imageRight(.rightBrowPeak),
                50: .imageRight(.rightBrowOuter),
                // 鼻 51–59
                51: .center(.noseBridgeTop),
                53: .center(.noseBridgeMid),
                54: .center(.noseTip),
                57: .center(.subnasale),
                55: .imageLeft(.leftNoseAla),
                59: .imageRight(.rightNoseAla),
                // 眼角 60–75
                60: .imageLeft(.leftEyeOuter),
                64: .imageLeft(.leftEyeInner),
                68: .imageRight(.rightEyeInner),
                72: .imageRight(.rightEyeOuter),
                // 瞳孔 96 / 97 —— 直接给出眼中心，比取眼廓平均更稳。
                96: .imageLeft(.leftEyeCenter),
                97: .imageRight(.rightEyeCenter),
                // 唇 76–87
                76: .imageLeft(.mouthLeftCorner),
                82: .imageRight(.mouthRightCorner),
                79: .center(.upperLipCenter),
                85: .center(.lowerLipCenter)
            ]
        }
    }

    /// 需要多点求平均才稳定的语义位置（眼中心、眉心等）。
    var averagedSlots: [(slot: ImageSideSlot, indices: [Int])] {
        switch self {
        case .ibug68:
            return [
                (.imageLeft(.leftEyeCenter), Array(36...41)),
                (.imageRight(.rightEyeCenter), Array(42...47)),
                (.imageLeft(.leftEyeUpper), [37, 38]),
                (.imageLeft(.leftEyeLower), [40, 41]),
                (.imageRight(.rightEyeUpper), [43, 44]),
                (.imageRight(.rightEyeLower), [46, 47]),
                (.center(.glabella), [21, 22])
            ]
        case .wflw98:
            return [
                (.imageLeft(.leftEyeUpper), [62, 63]),
                (.imageLeft(.leftEyeLower), [66, 67]),
                (.imageRight(.rightEyeUpper), [70, 71]),
                (.imageRight(.rightEyeLower), [74, 75]),
                (.center(.glabella), [38, 46])
            ]
        }
    }

    /// 图像侧 → 解剖学侧。
    ///
    /// 前置摄像头原始画面里，用户的解剖学**右**半边脸出现在图像**左**侧。
    /// 我们已经在 `CameraController` 里让采集连接保持未镜像，
    /// 所以这条换算对所有 provider 都成立；`isMirrored` 只影响坐标，不影响这里的身份判定。
    static func anatomical(_ slot: ImageSideSlot) -> SemanticLandmark {
        switch slot {
        case let .center(mark):
            return mark
        case let .imageLeft(mark), let .imageRight(mark):
            // 两侧都翻转，这不是笔误：
            // 表里的 `.imageLeft(.leftEyeOuter)` 意思是「图像左侧那只眼的外眼角」，
            // 而图像左侧那只眼是用户的**右**眼 —— 所以取 .rightEyeOuter。
            // `.imageRight(.rightEyeOuter)` 同理映射到 .leftEyeOuter。
            return mark.mirrored
        }
    }

    /// 把一组稠密点（图像坐标）解析成语义 landmark 表。
    func resolve(
        points: [Point2D],
        confidence: Double
    ) -> [SemanticLandmark: LandmarkSample] {
        guard points.count == pointCount else { return [:] }
        var table: [SemanticLandmark: LandmarkSample] = [:]

        for (index, slot) in directSlots {
            guard points.indices.contains(index) else { continue }
            table[DenseLandmarkLayout.anatomical(slot)] = LandmarkSample(
                point: points[index],
                confidence: confidence,
                isOccluded: false
            )
        }

        for entry in averagedSlots {
            let valid = entry.indices.filter { points.indices.contains($0) }
            guard valid.isEmpty == false else { continue }
            var x = 0.0
            var y = 0.0
            for index in valid {
                x += points[index].x
                y += points[index].y
            }
            table[DenseLandmarkLayout.anatomical(entry.slot)] = LandmarkSample(
                point: Point2D(x: x / Double(valid.count), y: y / Double(valid.count)),
                confidence: confidence,
                isOccluded: false
            )
        }

        return table
    }

    /// 本布局能产出的全部语义 landmark。
    var supportedLandmarks: Set<SemanticLandmark> {
        var marks = Set(directSlots.values.map(DenseLandmarkLayout.anatomical))
        for entry in averagedSlots {
            marks.insert(DenseLandmarkLayout.anatomical(entry.slot))
        }
        return marks
    }
}
