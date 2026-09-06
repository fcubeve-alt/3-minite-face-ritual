import AVFoundation
import SwiftUI
import UIKit
import FaceRitualCore

/// 「老师」那一半：播放该动作的示范视频。
///
/// 视频还没有，所以这里必须两种状态都成立：
///   有视频 → 循环播放，静音（语音提示由 App 自己念，两路声音会打架）
///   没视频 → 回落到示意动画 + 一行「素材待补」，**不是空白也不是报错**
///
/// 之所以能这么干净地回落：动作的几何本来就在 `MovementSpec` 里，
/// Coach 与 AR 共用同一份真源（规格 §4）。视频到位之前，
/// 同一份数据先驱动一个示意图形，整条流程照样能跑通、能测、能上架前验收。
///
/// 视频文件命名与规格见 `docs/COACH_VIDEO_SPEC.md`。
struct CoachVideoStage: View {
    let segment: PlaybackSegment?
    let cyclePhase: Double
    /// 透传给回落用的示意图 —— 它要靠这些规则算出位置。
    let anchors: [FaceAnchorID: FaceAnchor]

    @StateObject private var player = LoopingVideoPlayer()

    var body: some View {
        ZStack {
            Color.black

            if let url = player.currentURL {
                VideoLayerView(player: player.avPlayer)
                    .accessibilityHidden(true)
                    .id(url)
            } else {
                // 没有视频时的回落：同一份 MovementSpec 驱动的示意动画。
                CoachStageView(segment: segment, cyclePhase: cyclePhase, anchors: anchors)
                    .padding(.vertical, 12)
            }

            if player.currentURL == nil, let asset = segment?.step.mediaAsset {
                VStack {
                    Spacer()
                    Text(AppCopy.coachVideoPending)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.35), in: Capsule())
                        .padding(.bottom, 10)
                        .accessibilityLabel(AppCopy.coachVideoPending)
                    #if DEBUG
                    Text(asset)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.bottom, 8)
                    #endif
                }
            }
        }
        .clipped()
        .onChange(of: segment?.id) { _, _ in
            player.load(assetName: segment?.step.mediaAsset)
        }
        .onAppear { player.load(assetName: segment?.step.mediaAsset) }
        .onDisappear { player.stop() }
    }
}

/// 循环播放一小段示范视频。
///
/// 刻意不做「视频时长必须等于动作时长」：示范视频通常是一个动作循环（几秒），
/// 而动作要做 15–20 秒。所以循环播放，由 routine 播放器控制何时换段 ——
/// 视频负责"怎么做"，计时归播放器管，两者不耦合。
final class LoopingVideoPlayer: ObservableObject {

    @Published private(set) var currentURL: URL?

    let avPlayer = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var loadedAssetName: String?

    init() {
        avPlayer.isMuted = true          // 语音提示由 App 自己念，避免两路声音打架
        avPlayer.actionAtItemEnd = .none
    }

    func load(assetName: String?) {
        guard loadedAssetName != assetName else { return }
        loadedAssetName = assetName

        guard let assetName, let url = Self.resolve(assetName: assetName) else {
            stop()
            currentURL = nil
            return
        }

        looper = nil
        avPlayer.removeAllItems()
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: avPlayer, templateItem: item)
        avPlayer.play()
        currentURL = url
    }

    func stop() {
        avPlayer.pause()
        looper = nil
        avPlayer.removeAllItems()
    }

    /// 在 App bundle 里找示范视频。
    ///
    /// 找不到就返回 nil —— 这是**正常状态**，不是错误：
    /// 素材是后补的，缺素材时回落到示意动画，流程不能断。
    static func resolve(assetName: String) -> URL? {
        for ext in ["mp4", "mov", "m4v"] {
            if let url = Bundle.main.url(forResource: assetName, withExtension: ext) {
                return url
            }
            // 素材多起来之后会放进子目录，这里一并找。
            if let url = Bundle.main.url(
                forResource: assetName, withExtension: ext, subdirectory: "CoachVideos"
            ) {
                return url
            }
        }
        return nil
    }

    /// 内容里引用到的视频有多少已经就位。Debug 页用它显示素材进度。
    static func availability(for steps: [RoutineStep]) -> (present: Int, total: Int) {
        var seen: Set<String> = []
        var present = 0
        for step in steps {
            guard let asset = step.mediaAsset, seen.insert(asset).inserted else { continue }
            if resolve(assetName: asset) != nil { present += 1 }
        }
        return (present, seen.count)
    }
}

/// 裸 AVPlayerLayer —— 不用 `VideoPlayer`，因为它自带播放控件与手势，
/// 而这里是示范画面，用户不该能拖进度条。
struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerUIView {
        let view = PlayerLayerUIView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

final class PlayerLayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
