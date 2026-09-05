# PROJECT_STATE

> 持续更新的工程状态。每个里程碑结束时集中 review。
> 最近更新：2026-09-05

---

## 当前里程碑

**M1 — Closed Loop + AR POC**

目标闭环：
`打开 App → START → 打开自己的脸 → Face Lock → 脸上稳定显示 Mock 动作的起点/终点/动态路线 → 完成 3 分钟 Mock Routine → Done → 保存记录`

---

## ✅ Completed

### 工程骨架
- Repo 结构：`Packages/FaceRitualCore`（纯 Swift 核心）+ `App/FaceRitual`（iOS）+ `tools`（跨平台校验）
- `project.yml`（XcodeGen）、`Makefile`、`.gitignore`、Assets 目录
- 四份必需文档：`MASTER_PLAN.md` / `PROJECT_STATE.md` / `ARCHITECTURE.md` / `AR_POC_REPORT.md`

### 领域模型与内容层（规格 §9 §16）
- `Routine` / `RoutineStep` / `MovementSpec` / `PathGeometry` / `FaceAnchor` / `PracticeSession`
- `AnchorGeometryRule` 组合式规则（landmark / midpoint / lerp / weighted / offset）+ 人工可读 JSON 编解码
- `ContentRepository` 协议 + `JSONContentRepository` + `ContentValidator`
- 宽容解码：缺省字段用默认值，新增字段不破坏旧内容包
- **动作内容零硬编码**：全部在 `Resources/*.json`，代码里没有任何动作字面量
- Mock 内容：Morning Core 180s / Evening Core 300s / 2 个 Quick Ritual，全部标 `mock_unreviewed`
- 内容作者只写一侧 anchor，另一侧自动镜像生成

### Face Geometry 抽象（规格 §7）
- `SemanticLandmark`（33 个语义点）—— 业务层永远看不到 provider 编号
- `FaceGeometry` / `FaceFrame`（瞳距归一的脸部局部坐标系）
- `FaceAnchorResolver` / `PathSampler`（line / curve / arc / circle / press / hold，弧长参数化）
- `OneEuroFilter` + `FaceGeometrySmoother` 抖动抑制
- `GuidanceQualityEvaluator` / `FaceLockTracker`
- **编译期保证**：`FaceRitualCore` 不允许 import ARKit / Vision / CoreML

### Player（规格 §5.2）
- `PlaybackPlan`（`leftThenRight` 自动展开成两段）
- `RoutinePlayerEngine`：纯 tick 驱动，无内部 Timer，掉帧不丢段
- 三种模式共用同一条事件流与同一个引擎

### Provider 层（规格 §15）
- `FaceAlignmentProvider` 协议 + `FaceAlignmentProviderFactory`（运行时可切换）
- `VisionFaceAlignmentProvider` — 默认基线，具名区域，无魔数索引
- `HRFFAFaceAlignmentProvider` — CoreML 接线完成，68/98 点布局自动识别
- `ARKitFaceAlignmentProvider` — 接线完成，顶点索引表外置
- `MockFaceAlignmentProvider` — 合成动画脸
- `DenseLandmarkLayout` — 唯一允许出现 landmark 编号的文件
- `ImageToViewTransform` — 图像/视图坐标与镜像换算

### AR 渲染与会话
- `AROverlayRenderer`（SwiftUI Canvas）：● 起点 / ◎ 终点 / 路径 / 移动光点 / 方向箭头 / ↻ / 手势 / 容差圈 / 左右侧配色
- `ARGuidanceController`：provider ⨯ player 编排，遮挡时冻结最后可信位置
- `PerformanceMonitor`：FPS / latency / p95 / 掉帧 / 丢锁，直接服务 POC 报告

### App 能力（规格 §15）
Home · Routine Detail · Mode Picker · Coach · AR Mirror · Watch & Breathe（技术入口）·
Done · History · Monthly Minutes · Settings · Camera Permission · Reminder ·
Subscription 架构（Mock Unlock + StoreKit2 骨架）· Analytics（含 §15 五个 AR 事件）· Paywall 占位 · Debug 诊断页

### 编译前静态排查（第二轮）
在没有 Swift 工具链的前提下，用 `tools/check_architecture.py` + 人工审查抓出并修复：

| 问题 | 后果 | 状态 |
| --- | --- | --- |
| `MockFaceAlignmentProvider` / `DisplayLinkTicker` 用 `@objc` 但没继承 NSObject | Mac 上**直接编译失败** | 已修 |
| 7 处 iOS 17 专属 API（`.onChange` 双参数版、`.topBarTrailing`）但部署目标是 iOS 16 | Mac 上**直接编译失败** | 已修（提到 iOS 17） |
| `ARMirrorView` 没把 `ARGuidanceController` 声明为 `@ObservedObject` | overlay 不会随帧刷新，画面静止 | 已修 |
| 播放视图的 view model 每次重绘都会被重建 | 重复创建 provider 与相机会话 | 已修（autoclosure + StateObject） |
| `@MainActor` 与 provider 的 nonisolated 回调冲突 | Swift 5 下编译失败 | 已修 |
| `PracticeSession` 用合成 Codable | 以后加字段会让**用户历史记录整体解码失败并被静默清空** | 已修（宽容解码 + 坏文件隔离留存） |
| 空数组字面量的类型推断歧义、retroactive conformance 警告、无用 import | 警告 | 已修 |
| **`SemanticLandmark.mirrored` 漏掉嘴角** —— `mouthLeftCorner` 把侧别写在名字中间，而 `mirrored` 用 `hasPrefix("left")` 判定，于是嘴角**不翻转** | 右脸 Cheek Lift 起点算到脸中间，路径长度左右差 28%。真机上肉眼可见 | 已修（改名为前缀约定 + 镜像实现加固 + 三层检查） |

### 本轮新增
- **`tools/check_architecture.py`** —— 把 ARCHITECTURE.md 的约束变成可执行检查：
  Core 平台隔离 / landmark 编号收敛 / 无对错判断 / `@objc` 需 NSObject /
  API 可用性 vs 部署目标 / 括号配对 / 动作内容零硬编码。
  已用故意写错的代码自测过，7 条规则全部命中。
- **AR 中途退回 Coach**（规格 §4 的真实缺口）：连续 12 秒锁不上时给出**非阻塞**建议，
  切换后摄像头关闭但**计时与动作序列不中断**，会话记录标记 `didFallBackToCoach`。
- **ARKit 顶点标定工具**（`Features/Debug/ARKitCalibrationView.swift`）：
  真机上点自己的脸标出顶点编号并导出 JSON —— 之前只有文档没有工具。
- **CI**（`.github/workflows/ci.yml`）：Linux 跑离线检查，macOS 跑 `swift test` 与 App 构建。
- **`golden --check`**：防止改了 anchors.json 却忘了重新生成 golden。
- **`docs/CONTENT_AUTHORING.md`**：Owner 替换正式内容的完整指南。
- **修掉四个真机上一定会咬人的运行时缺陷**：
  | 缺陷 | 后果 |
  | --- | --- |
  | 播放期间没阻止自动锁屏 | 3–5 分钟不碰屏幕，动作做到一半黑屏，routine 直接断 |
  | 切后台没停摄像头会话 | 后台开着相机：耗电 + 用户信任问题；回来后播放器状态也不对 |
  | 语音提示没配 AVAudioSession | 直接掐掉用户正在放的音乐（而「边听歌边做 3 分钟」正是主场景） |
  | 播放器全是纯图标按钮，零 accessibilityLabel | VoiceOver 只念「按钮」，视障用户完全无法操作 |
- **切后台的行为**：暂停 + 关摄像头 + 释放常亮；回到前台**保持暂停**由用户自己按播放 ——
  他刚切回来手还没抬起来，自动继续只会让他白白错过一个动作。
  跨后台的丢锁次数与首次锁定耗时改为累计/只记一次，否则 POC 指标会被后台切换污染。
- **四条 ⚠️ 文案拟稿 + `docs/COPY_REVIEW.md` 评审清单**。
  医学免责做了短版（页脚）与长版（新增 About & Safety 页）——
  缩成一行小字的免责声明既没人读也保护不了人。
  订阅那条改了做法：真正卡上架的不是「价格占位提示」，而是审核指南 3.1.2 要求的
  自动续订披露 + 两个法务链接，已按要求补齐结构（URL 待 Owner 提供）。
- **把隐私承诺锁成代码事实**：摄像头文案对用户说「画面留在设备上」。
  查证全工程零联网 API（唯一出网 import 是 StoreKit，只走支付），
  并加了检查规则 —— 谁加网络请求，检查就失败并指回那句文案。
- **`tools/check_swift_refs.py`** —— 无编译器版的 Swift 引用检查：枚举 case、init 参数标签、
  协议一致性。在真实代码库上做过正反验证。已知盲区（字符串插值内、尾随闭包）写在脚本里。
- **用户面文案全部改为英文并集中到 `AppCopy.swift`**。目标用户是欧美用户（规格 §3/§14），
  之前 UI 是中英混杂。开发面（Settings→Developer / Diagnostics / ARKit 标定）保留中文。
  新增架构检查「用户面文案为英文」防止回潮。
- **不再把技术错误摊给用户**：AR 出错时显示中性说明 + 退回 Coach 的入口，
  底层原因（缺模型、provider 回落…）只在 Debug 图层显示；购买失败同理。
- **`tools/simulate_routine.py`** —— 无头跑完整 routine，验证每个播放段是否真能在脸上画出东西，
  并断言同一 step 的左右两段互为镜像。**上面那个嘴角 bug 就是它抓到的。**
  内容校验只看 JSON 结构、golden vector 只验几何数学，两者都答不了
  「播放时这一段脸上会不会是空白」这个问题。

### 已在本机**实际运行验证**的项目
- `python tools/check_architecture.py` → 57 个 Swift 文件，**10 条规则 0 errors**（已自测确认非空转）
- `python tools/check_swift_refs.py` → **0 errors**；`--self-test` 三条规则全部命中
- `python tools/validate_content.py` → **0 errors**，1 个预期内 mock 警告
- `python tools/golden/generate_golden.py` → 9 个 anchor 在 6 种尺度/位置/roll 变换下**最大漂移 2.0e-15 瞳距**
- `golden --check` 的正反例：篡改 anchors.json 后退出码 1，还原后 0
- `python tools/simulate_routine.py` → Morning Core 9 个播放段全部可渲染，左右完全对称
- 四个检查器共 14 条规则，每条都做过**故意写错代码的反向验证**，确认不是空转。
  无障碍那条第一版用固定窗口判断，牙齿测试直接不过（窗口串到了相邻控件的 Text 上），
  改成按大括号配对确定按钮范围后才通过 —— 这也是为什么每条规则都要反向验证

---

## 🔄 In Progress

无。M1 的可离线完成部分已全部写完，等待 Mac 环境验证。

---

## ⛔ Blocked

| 阻塞项 | 原因 | 解除条件 |
| --- | --- | --- |
| Swift 代码编译验证 | 开发机是 Windows，无 Swift/Xcode 工具链（已验证 `swift`/`swiftc`/`xcodegen` 均不存在） | 在 Mac 上 `make bootstrap && make core-test && make build` |
| 真机 AR POC（Face Lock / FPS / 遮挡 / 转头 / 漂移） | 需要真实 iPhone | 按 `AR_POC_REPORT.md` §2 执行 |
| HRFFA CoreML 模型 | 转换需 macOS + coremltools；模型文件不在仓库 | 见 `docs/HRFFA_INTEGRATION.md` |
| ARKit 顶点索引表 | Apple 未公布 1220 顶点语义编号，**拒绝猜测**（画错位置比不画更糟） | 标定工具已做好：真机 Settings → Developer → Provider/内容诊断 → ARKit 顶点标定，点 10 个点导出 JSON |

---

## ⏭ Next（按顺序）

1. **Mac 首次构建**：`make bootstrap` → Xcode 填 Team → `make core-test` → `make build`
   - 已用静态检查扫掉几类必然失败的错误（见上表），但**仍会有类型层面的编译错误** ——
     静态检查器不是编译器，抓不到类型不匹配。
   - 推起 CI 后，`build` job 的日志就是一份现成的待修清单，不必在 Mac 前一条条试。
2. **模拟器验证**：用 Mock provider 走通 Home → START → AR Mirror → Done → History
3. **真机 POC**：按 `AR_POC_REPORT.md` §2 逐项测，填表
4. **调参**：根据实测调 One Euro 滤波与 `GuidanceThresholds`
5. **Go / No-Go 判定**（规格 §18）
6. 通过后进入 M2：Owner + 专业人员替换正式动作与穴位定义

---

## ❗ Owner Decision Required

工程侧**不会**代为决定的事项（规格 §20），按紧急程度排序：

### 影响 M1 收尾
0. **最低 iOS 版本 = 17（我自己定的，可推翻）。**
   原因是 SwiftUI 的 `.onChange` 双参数版与 `.topBarTrailing` 都需要 iOS 17，
   而这些 API 在 UI 层用得很密。iOS 17 已发布三年，覆盖率很高。
   如果你要支持 iOS 16，告诉我，我改回旧 API（会引入一批废弃警告，但能跑）。
   改动点：`project.yml` 与 `Package.swift` 各一行。
1. **谁在什么时候用哪台 iPhone 跑 POC。** 没有真机，M1 无法结束。
2. **是否投入 HRFFA CoreML 模型转换。**
   Vision 基线已可跑通全流程；HRFFA 是否值得多背一个模型，建议**先看 POC 里 Vision 的实测表现再决定**。
3. **摄像头权限文案的最终措辞**（`project.yml` 里的 `NSCameraUsageDescription`）—— 涉及合规。
   注意它要和 `AppCopy.cameraNeededMessage` 语义一致。
4. **四条 ⚠️ 文案已拟好草稿，待你与法务确认** —— 见 `docs/COPY_REVIEW.md`。
   每条都写了措辞依据和需要你判断的点。改的话只动 `AppCopy.swift`，不必碰视图。
   其中两项是**硬性上架前置条件，缺了会被拒**：
   - **Terms of Use (EULA) 的 URL**
   - **Privacy Policy 的 URL**
   （App Store 审核指南 3.1.2 要求 Paywall 上必须有这两个可点击链接。
   填在 `SafetyView.swift` 的 `LegalLinks` 里；未填时 Debug 页与 Paywall 会红字提醒。）

### 影响 M2
4. **Morning / Evening / Quick Ritual 的正式动作清单**（顺序、时长、示范素材）—— 规格 §14 明确不得由 Claude 发明。
5. **第一批 3–5 个 AR 位置/区域的专业定义** —— 当前 5 个 anchor 是纯几何占位，无医学含义。
6. **安全审查与免责声明**（眼周、颈部、按压力度的禁忌）。
7. **Coach 视频/虚拟教练素材**，以及它与 AR Motion Template 的共用版本号规则。

### 影响上线
8. 最终产品名与品牌视觉（当前用中性配色占位）。
9. 最终订阅价格与年费方案（代码里只有占位值，且标注「待定」）。
10. 隐私政策、订阅条款、App Store 合规文案。
11. 是否首发仅 iPhone（当前 `TARGETED_DEVICE_FAMILY = 1`）。
12. 是否接入第三方 analytics SDK（当前只有 Console 实现，不发送任何数据）。

---

## 📌 需要 Owner 知情的工程判断

这几条是我在没有 Owner 输入时自行做的决定，**如果不同意可以推翻**：

1. **默认 provider 选 Vision 而不是 HRFFA。**
   理由：Vision 用具名区域，无魔数索引、无模型文件、全机型可用，是 POC 里唯一一开始就必定能跑的对照组。
   HRFFA 已完全接线，放入模型即可在 Settings 切换横评 —— 优先级没有被降低，只是不作为默认。

2. **ARKit 顶点索引表留空而不是填猜测值。**
   在脸上把 ● 画到错误位置，比暂时不显示更糟，也会污染 POC 结论。

3. **`GuidanceQuality` 只有 good/degraded/lost 三态，领域模型里根本没有 correctness 字段。**
   这是把规格 §10 的能力边界做成结构性保证，而不是靠开发纪律。

4. **Mock 内容全部带 `mock_unreviewed` 标记，UI 上有 MOCK 角标，测试会断言它必须为真。**
   目的是让测试动作**不可能**被误当成正式护理内容发布。

5. **内容 JSON 放在 Core package 而不是 App target。**
   这样单元测试加载的是**真实**内容包，不会出现「测试用一份、线上用另一份」的漂移。

6. **AR 退回 Coach 是建议而不是拦截。**
   连续 12 秒锁不上才提示，不弹模态、不暂停计时，用户可以一直无视它把 routine 做完。
   规格 §4 说的是「识别失败不得阻塞 routine」——
   如果我们弹一个必须处理的对话框，那本身就成了阻塞。

7. **语义 landmark 一律用「侧别做前缀」的命名**（`leftMouthCorner` 而不是 `mouthLeftCorner`）。
   这不是风格偏好 —— 违反它会让镜像静默失效，而且 golden vector 测不出来。
   现在有三层防护：命名统一、`mirrored` 对中缀写法也成立、以及
   Swift 测试 + `validate_content.py` + `simulate_routine.py` 三处独立检查。

8. **用户可见文案一律英文，且集中在 `AppCopy.swift`。**
   规格 §19 把最终文案、免责声明、摄像头说明、订阅条款列为 Owner 待办 ——
   集中一处后你和法务只需要看一个文件，不必翻遍 UI 代码。
   标了 ⚠️ 的条目是上线前必须确认的。

9. **`PracticeSession` 改成手写宽容解码。**
   这不是为了这次加的那个字段，而是因为合成 Codable + 「解码失败返回空数组」
   这个组合意味着**以后任何一次加字段都会静默清空所有用户的历史记录**。
   现在缺失字段一律取默认值，坏文件也会改名留存而不是被覆盖。
