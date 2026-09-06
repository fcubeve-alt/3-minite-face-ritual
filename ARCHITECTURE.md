# ARCHITECTURE — 3-Minute Face Ritual V2

> Source of Truth = `3-Minute_Face_Ritual_Product_v2_CN.docx`。
> 本文件只描述**工程结构**，不定义产品、不定义动作、不定义穴位含义。

---

## 0. 架构第一原则

规格 §15 与 Owner 指令的硬约束，逐条落到结构上：

| 约束 | 结构上的强制手段 |
| --- | --- |
| 动作内容不得硬编码进 UI / 业务逻辑 | 内容只存在于 `Resources/Content/*.json`，代码里没有任何动作字面量；`ContentValidator` 在启动时校验 |
| 业务层不得依赖某个 landmark provider 的编号 | `FaceRitualCore` 是纯 Swift package，**不允许 import ARKit / Vision / CoreML**；provider 编号映射只存在于 App 层 |
| Coach 与 AR 必须共用同一动作真源 | 二者都读同一个 `RoutineStep.movement`；Coach 只是不渲染 overlay |
| 不输出虚假"做对/做错" | `GuidanceQuality` 只有 `good / degraded / lost` 三态，**领域模型里根本不存在 correctness 字段** |
| Provider 可替换 | `FaceAlignmentProvider` 协议 + `FaceAlignmentProviderFactory`，运行时可在 Settings → Developer 切换 |

---

## 1. 模块分层

```
┌─────────────────────────────────────────────────────────────┐
│  FaceRitual (iOS App target)                                │
│  ├─ Features/      SwiftUI 视图 + ViewModel                 │
│  ├─ FaceAR/        ARKit / Vision / CoreML provider 实现     │
│  │                 Overlay Renderer (SwiftUI Canvas)         │
│  │                 ARMirrorSession (provider ⨯ player 编排)  │
│  └─ Platform/      Haptics / Voice / Notification / StoreKit │
└───────────────────────────┬─────────────────────────────────┘
                            │ 只能单向依赖 ↓
┌───────────────────────────┴─────────────────────────────────┐
│  FaceRitualCore (SPM, 纯 Swift, 无 UIKit/ARKit/Vision)       │
│  ├─ Domain/        Routine / RoutineStep / MovementSpec      │
│  │                 FaceAnchor / PracticeSession              │
│  ├─ Content/       ContentRepository 协议 + JSON 解码 + 校验  │
│  ├─ Player/        RoutinePlayerEngine（tick 驱动状态机）     │
│  ├─ FaceGeometry/  SemanticLandmark / FaceGeometry /         │
│  │                 FaceFrame / AnchorResolver / PathSampler  │
│  │                 OneEuroFilter                             │
│  ├─ Practice/      PracticeStore 协议 + 月度统计              │
│  ├─ Entitlement/   EntitlementService 协议                    │
│  └─ Analytics/     AnalyticsEvent + AnalyticsService 协议     │
└─────────────────────────────────────────────────────────────┘
```

`FaceRitualCore` 无平台依赖 ⇒ 可在 Mac 上直接 `swift test`，也可在 Linux CI 跑。
这不是洁癖：它是"业务层不绑定 HRFFA"这条规格要求的**编译期保证**。

---

## 2. AR 链路（规格 §7）

```
Camera
  │  AVCaptureSession (Vision/HRFFA) 或 ARSession (ARKit)
  ▼
FaceAlignmentProvider            ← App 层，可替换
  │  产出 provider 中立的 …
  ▼
FaceGeometry                     ← Core，语义 landmark，无编号
  │  landmarks: [SemanticLandmark: LandmarkSample]（视图坐标）
  │  pose / trackingState / interocularDistance / isMirrored
  ▼
FaceFrame                        ← Core，从 landmark 推出的脸部局部坐标系
  │  origin + xAxis + yAxis + scale(=瞳距)  ⇒ 尺度/旋转/位置不变
  ▼
FaceAnchorResolver               ← Core，AnchorGeometryRule → Point2D
  │  anchors.json 定义规则，不写死像素
  ▼
MovementSpec → PathSampler       ← Core，line/curve/arc/circle/press/hold
  │  产出 MotionPath（多段折线 + progress→point）
  ▼
AROverlayRenderer                ← App 层，SwiftUI Canvas
     ● 起点 / ◎ 终点 / → 方向 / 路径 / ↻ 圆周 / 手势 / 倒计时 / 左右侧
```

### 关键设计：FaceFrame

所有 anchor 与路径都在**脸的局部坐标系**里表达，单位 = 瞳距（interocular distance）。

- `origin` = 双眼中点
- `xAxis` = 左眼中心 → 右眼中心 的单位向量（自动吸收 roll）
- `yAxis` = xAxis 顺时针旋转 90°（屏幕坐标向下）
- `scale` = 瞳距（像素）

因此同一份 `anchors.json` 在不同脸型、不同距离、不同头部倾斜下都成立。
这正是里程碑要验证的东西（"不同用户的脸上，目标位置能否稳定跟随 Face Geometry"）。

### Provider 矩阵

| Provider | 状态 | landmark 来源 | 备注 |
| --- | --- | --- | --- |
| `VisionFaceAlignmentProvider` | **默认 / 基线** | `VNFaceLandmarks2D` 的**具名区域**（leftEye / nose / medianLine…） | 无魔数索引，全机型可用，最稳的对照组 |
| `HRFFAFaceAlignmentProvider` | 已接线，待模型 | CoreML 输出 68/98 点，按 300W-68 / WFLW-98 标准布局映射 | 放入 `HRFFA.mlpackage` 即启用；无模型时自动降级并上报 |
| `ARKitFaceAlignmentProvider` | 已接线，待标定 | `ARFaceAnchor.geometry.vertices`（1220 点） | 顶点索引表从 `arkit_vertex_map.json` 读取，**不写死猜测值**；内置标定工具 |
| `MockFaceAlignmentProvider` | 完成 | 合成动画人脸 | 模拟器 / 单元测试 / UI 预览 |

> Owner 指令是"优先测试 HRFFA，但必须通过 Provider Abstraction 接入"。
> 结构已满足。HRFFA 的 CoreML 模型文件本机无法生成（无 macOS/coremltools），
> 转换脚本与索引映射已写好，见 `docs/HRFFA_INTEGRATION.md`。
> 在拿到模型之前，Vision provider 就是可跑的真实基线——**AR POC 不会被模型卡住**。

---

## 3. Player（规格 §5.2 / §15）

`RoutinePlayerEngine` 是**纯 tick 驱动**的状态机：

```swift
engine.tick(deltaTime: 1.0/60.0)   // 没有内部 Timer
```

- 可测试：单元测试用固定步长推进 3 分钟，断言换步时刻
- 可复用：Coach / AR Mirror / Watch & Breathe 共用同一个 engine
- `side == .leftThenRight` 的步骤在 `PlaybackPlan` 构建时展开成两个 segment，engine 本身不处理左右语义

事件流 `PlayerEvent` 驱动 Voice / Haptic / Analytics / Overlay，三种模式订阅同一条流。

---

## 4. 遮挡与置信度（规格 §10）

`GuidanceQualityEvaluator` 输入 `FaceGeometry` + `MovementSpec.occlusionPolicy`，输出：

```
.good      → 正常渲染
.degraded  → overlay 冻结在最后可信位置 + 降低不透明度 + 文案提示"把脸放回画面中央"
.lost      → 按 occlusionPolicy：continueGuidance（继续计时+语音）/ freezeOverlay / pauseTracking
```

**任何状态下都不产生"正确/错误"判断**，也不因识别失败中断 routine（规格 §4"识别失败不得阻塞 routine"）。
`faceLockLost` / `guidanceFallback` 事件上报 analytics。

---

## 5. 内容层（可替换内容数据）

**动作是资产，routine 只是时间线**（Video Factory v0.2 §4/§9）。
同一个动作会在多个 routine 里出现 —— Prototype A 里 GM-11 与 GM-18 各出现两次，
三套原型都用 GM-02。内联复制迟早会漂移，所以 routine 里只写引用：

```jsonc
{ "move": "GM-08", "durationSeconds": 20 }
```

`ContentAssembler` 在加载时把引用展开成 `RoutineStep`，
并在每一步上留下 `sourceMoveID` —— 校验器靠它把「工具动作不得进 morning」
这类长在 `GoldMove` 上的约束，施加到展开后的 routine 上。


```
Resources/Content/
├── moves.json         # Gold Motion Library —— 动作的唯一真源（GoldMove + MovementSpec）
├── routines.json      # 时间线：只写「第几步用哪个动作」，由 ContentAssembler 展开
├── anchors.json       # FaceAnchor（15 个声明 → 27 个，自动镜像）
└── content_meta.json  # schemaVersion / contentVersion / reviewStatus
```

每个 move / routine / anchor 都带 `reviewStatus` 字段：

```json
"reviewStatus": "draft"
```

`ContentValidator` 把所有非 `expert_reviewed` 的条目报为警告，UI 上以 "MOCK CONTENT" 角标显示，
单元测试断言内容包必须仍是未审核状态 —— 确保未经 Expert Gate 的动作**不可能**被误当成正式内容发布。

用户看到的是英文字段；`GoldMoveSource` 里**逐字保留中文原文**（起始姿势、操作、力度、停止信号）。
安全措辞经翻译会引入偏差，而那恰恰是 Expert Gate 要审的东西，所以两份并存，谁也不覆盖谁。

---

## 6. 权限 / 订阅 / 记录

- `EntitlementService` 协议；`MockEntitlementService`（Settings 里可 Mock Unlock）与 `StoreKit2EntitlementService`（骨架）并存
- Morning Core 恒为 free，硬编码在 `EntitlementPolicy`（这是规格 §11 的产品承诺，不是内容）
- `PracticeStore` 写 JSON 到 Application Support；`MonthlyStats` 只统计次数/分钟，不做连续天数惩罚（规格 §12）

---

## 7. 目录 → 规格条款对照

| 目录 | 规格条款 |
| --- | --- |
| `Domain/MovementSpec.swift` | §9 Movement Specification V2 |
| `Domain/FaceAnchor.swift` | §8 Facial Acupoint / Region Map |
| `Domain/PracticeSession.swift` | §16 概念数据模型 |
| `FaceGeometry/` | §7 技术核心链路 |
| `FaceAR/Session/GuidanceQuality.swift` | §10 遮挡与实时纠错能力边界 |
| `Analytics/AnalyticsEvent.swift` | §15 AR analytics 五事件 |
| `Entitlement/` | §11 免费与付费模型 |
