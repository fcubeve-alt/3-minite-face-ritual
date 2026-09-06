# MASTER_PLAN — 3-Minute Face Ritual V2 工程执行计划

> 本文件是 `3-Minute_Face_Ritual_Product_v2_CN.docx`（唯一 Source of Truth）到工程任务的转化。
>
> 内容侧另有两份专业文档，工程只负责**如实转写与结构化**，不增删动作、不改措辞：
> - `Face_Ritual_Research_Sprint3_Movement_Specs_Prototypes_v0.3_CN.docx` —— 20 个动作规格 + 3 套 Morning 原型
> - `Face_Ritual_AI_Video_Factory_v0.2_AR_Guidance_CN.docx` —— Gold Motion Library / 虚拟教练 / AR 指引架构
> 规格变更 → 先改 docx → 再改本文件。本文件不新增产品定义。

---

## 里程碑定义

### M1 — Closed Loop + AR POC ← **当前目标**

真机可完成：

```
Open App → Home → Morning Ritual → START → 选择 Coach / AR Mirror
  → 打开前置摄像头 → Face Lock
  → 在自己脸上稳定显示动作的 ● 起点 / ◎ 终点 / → 动态路线
  → 自动倒计时、自动换动作、左右侧切换
  → 完成 3 分钟 Mock Routine → Done → 保存练习记录
```

**M1 不包含**：正式动作库、真实穴位定义、实时纠错、压力判断、Skin Scan、社区、商城。

M1 结束物 = 可运行 App + 真机实测。

> **2026-09-07 产品方向调整**：AR Mirror 与 Watch & Breathe 已移除，
> 形态改为「上面示范视频，下面自己的镜像」。
> 下面 T5 / T6 里与 provider、AR overlay 相关的条目**已作废** ——
> 保留是为了记录做过什么，不代表当前代码里还有。
> 原因与取舍见 [`docs/DECISION_AR_REMOVED.md`](docs/DECISION_AR_REMOVED.md)。

### M2 — Content Gate（M1 通过后）
Owner + 专业人员审核动作与位置 → 替换 Mock JSON → Coach 素材 → Evidence/Expert Gate。

### M3 — Product Polish
Evening Core、全部 Quick Rituals、StoreKit 真实接入、提醒文案、Onboarding、上架合规。

---

## M1 任务分解

图例：`[x]` 已写完（本机不可编译验证） · `[~]` 部分 · `[ ]` 未开始 · `[M]` 需 Mac 验证 · `[O]` 需 Owner 决策

### T1 项目骨架
- [x] T1.1 Repo 结构、`.gitignore`、README
- [x] T1.2 `FaceRitualCore` SPM package（纯 Swift，无平台依赖）
- [x] T1.3 `project.yml`（XcodeGen）+ `Makefile` + `scripts/bootstrap.sh`
- [x] T1.4 `Info.plist`（`NSCameraUsageDescription`）、Assets、App Icon 占位
- [M] T1.5 在 Mac 上 `make bootstrap` 生成 `.xcodeproj` 并首次编译通过

### T2 领域模型与内容层（规格 §9 §16）
- [x] T2.1 `Routine` / `RoutineStep` / `MovementSpec` / `PathGeometry`
- [x] T2.2 `FaceAnchor` / `AnchorGeometryRule`（自定义 Codable，JSON 人工可写）
- [x] T2.3 `PracticeSession`
- [x] T2.4 `ContentRepository` 协议 + `BundledJSONContentRepository`
- [x] T2.5 `ContentValidator`：anchor 引用完整性、时长一致性、premium 标记、reviewStatus
- [x] T2.6 Mock 内容：Morning Core（5 steps / 180s）+ 2 个 Quick Ritual + Evening Core 骨架
- [x] T2.7 `reviewStatus` 全量标记（当前全部 `draft`）+ UI MOCK 角标

### T3 Routine Player（规格 §5.2）
- [x] T3.1 `PlaybackPlan`：steps → segments（展开 leftThenRight）
- [x] T3.2 `RoutinePlayerEngine`：tick 驱动状态机，倒计时/自动换步/暂停恢复/跳过
- [x] T3.3 `PlayerEvent` 事件流（countdown / stepWillStart / halfway / sideSwitch / completed）
- [x] T3.4 `DisplayLinkTicker` 把 engine 接到 CADisplayLink
- [x] T3.5 Voice cue（AVSpeechSynthesizer）与 Haptic 接口
- [x] T3.6 单元测试：3 分钟推进、换步时刻、暂停、跳过

### T4 Face Geometry 抽象（规格 §7，"业务层不绑定 provider"）
- [x] T4.1 `SemanticLandmark` 语义 landmark 集合（33 点）
- [x] T4.2 `FaceGeometry` / `LandmarkSample` / `HeadPose` / `FaceTrackingState`
- [x] T4.3 `FaceFrame`（origin/xAxis/yAxis/scale，瞳距归一）
- [x] T4.4 `FaceAnchorResolver`：landmark / midpoint / lerp / weighted / offset
- [x] T4.5 `PathSampler`：line / curve / arc / circle / press / hold
- [x] T4.6 `OneEuroFilter` 抖动抑制
- [x] T4.7 Golden-vector 测试（Python 参考实现交叉验证，本机可跑）

### T5 Face Alignment Providers（规格 §7 §15）—— ⛔ 已作废（AR 移除）
- [x] T5.1 `FaceAlignmentProvider` 协议 + `FaceAlignmentProviderFactory`
- [x] T5.2 `MockFaceAlignmentProvider`（合成脸，模拟器/测试）
- [x] T5.3 `VisionFaceAlignmentProvider`（具名区域 → 语义 landmark，**默认基线**）
- [x] T5.4 `HRFFAFaceAlignmentProvider`（CoreML 接线 + 300W-68 / WFLW-98 索引映射）
- [x] T5.5 `ARKitFaceAlignmentProvider`（顶点索引表外置 JSON + 标定工具）
- [⛔] T5.6 HRFFA CoreML 模型转换 —— 随 AR 移除，不再需要
- [⛔] T5.7 三 provider 真机横评 —— 随 AR 移除，不再需要

### T6 Facial Anchor Map（规格 §8）
- [x] T6.1 anchor 几何规则定义（`anchors.json`）——
      M1 起步是 5 个测试点；按 Sprint 3 的 20 个动作扩到 15 个声明 → 27 个（自动镜像）
- [x] T6.2 `toleranceRadius` / `poseConstraints` / `confidenceThreshold` 字段
- [⛔] T6.3 Debug 页实时 landmark 显示 —— 随 AR 移除
- [O] T6.4 正式穴位/区域定义（Owner + 专业资料，**当前不由 Claude 决定**）

### T7 AR Overlay Renderer（规格 §6.2）
- [x] T7.1 `AROverlayRenderer`（SwiftUI Canvas）
- [x] T7.2 ● 起点 / ◎ 终点 / 路径折线 / 移动光点 / 方向箭头 / ↻ 圆周
- [x] T7.3 手势提示（singleFinger / twoFinger / fingertips / palm / tool）
- [x] T7.4 倒计时环 + 次数 + 左右侧指示
- [x] T7.5 `degraded` / `lost` 视觉降级（冻结 + 提示，**不显示对错**）
- [M] T7.6 真机小屏 / 距离变化 / 转头实测

### T8 遮挡与置信度策略（规格 §10）
- [x] T8.1 `GuidanceQualityEvaluator`（good / degraded / lost 三态）
- [x] T8.2 `OcclusionPolicy` 三种行为
- [x] T8.3 领域模型中**不存在** correctness 字段（结构性保证）
- [M] T8.4 真机手遮挡实测

### T9 App 能力（规格 §15）
- [x] T9.1 Home（Good morning/evening、Morning Ritual 3:00 卡、START、Quick Rituals、本月记录）
- [x] T9.2 Routine Detail + Mode Picker（Coach / AR Mirror / Watch & Breathe）
- [x] T9.3 Coach Mode（占位视频/动画 asset，不等正式素材）
- [x] T9.4 AR Mirror Mode
- [x] T9.5 Watch & Breathe（仅技术入口，复用 renderer）
- [x] T9.6 Done 页 + 保存 `PracticeSession`
- [x] T9.7 History + Monthly Minutes
- [x] T9.8 Settings（provider 切换、Mock Unlock、提醒、隐私、重置）
- [x] T9.9 Camera Permission 流程（用户主动开启，可随时关闭）
- [x] T9.10 Reminder（UNUserNotificationCenter，morning/evening）
- [x] T9.11 Subscription Architecture（`EntitlementService` + Mock Unlock + StoreKit2 骨架）
- [x] T9.12 Analytics Interface（含 §15 五个 AR 事件）
- [x] T9.13 Paywall 占位（价格从 config 读，不写死）

### T10 测试与报告
- [x] T10.1 Core 单元测试（player / anchor / path / content / stats）
- [x] T10.2 Golden vector 交叉验证（Python ↔ Swift）+ `--check` 防漂移
- [⛔] T10.3 真机 POC 测量台 —— 随 AR 移除；决策记录见 `docs/DECISION_AR_REMOVED.md`
- [M] T10.4 真机执行 POC → 填报告 → Go/No-Go（规格 §18）

### T11 工程护栏（第二轮补充）
- [x] T11.1 `tools/check_architecture.py`：把 ARCHITECTURE.md 的约束变成可执行检查
- [x] T11.2 编译前静态排查并修复（`@objc`/NSObject、iOS 17 API、观察缺失、actor 隔离）
- [x] T11.3 `PracticeSession` 宽容解码 + 坏记录文件隔离留存
- [x] T11.4 AR 中途退回 Coach（规格 §4：识别失败不得阻塞 routine）
- [x] T11.5 ARKit 顶点标定工具（真机导出 `arkit_vertex_map.json`）
- [x] T11.6 CI：Linux 离线检查 + macOS `swift test` 与 App 构建
- [x] T11.7 `docs/CONTENT_AUTHORING.md`：Owner 替换正式内容的指南
- [x] T11.8 `tools/check_swift_refs.py`：枚举 case / init 标签 / 协议一致性检查
- [x] T11.9 用户面文案改英文并集中到 `AppCopy.swift`（规格 §3/§14）
- [x] T11.10 四条 ⚠️ 文案拟稿 + `docs/COPY_REVIEW.md` 评审清单
- [x] T11.14 About & Safety 页面（长版免责的落点）
- [x] T11.15 订阅披露结构（审核指南 3.1.2）+ 隐私承诺的代码级锁定
- [O] T11.16 Terms of Use / Privacy Policy 的 URL —— **缺了会被拒，Owner 待提供**
- [x] T11.11 运行时护栏：屏幕常亮、切后台停摄像头、语音 duck 背景音乐
- [x] T11.12 无障碍标签（纯图标按钮 + 合成汇总卡）+ 防回潮检查
- [x] T11.13 Analytics 契约测试：钉死规格 §15 的五个 AR 事件名

---

## 明确不做（规格 §13 + Owner 指令）

100 个动作研究 · Gold Motion Library · 新穴位模型训练 · AI Skin Scan · 大模型聊天教练 ·
社区 · 商城 · 复杂游戏化 · 全动作实时纠错评分 · 自创医学/美容/穴位功效 · 强制摄像头 ·
把 AR 变成必过考试 · 严重遮挡下宣称精确接触点 · 压力测量。

---

## Owner 决策队列

见 `PROJECT_STATE.md` 的 **Owner Decision Required** 段，不在此重复。
