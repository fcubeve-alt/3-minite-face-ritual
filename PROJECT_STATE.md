# PROJECT_STATE

> 当前状态。做完了什么、卡在哪、等谁。
> 最近更新：2026-09-07

---

## 产品形态

**上半屏示范视频，下半屏自己的镜像。跟着做。**

摄像头是**可选**的：不开、没授权、模拟器上没有摄像头，都只是少了下半屏，
整套 routine 照样走完。

> 2026-09-07 之前还有 AR Mirror（把动作路线实时贴在脸上）与 Watch & Breathe。
> Owner 实测后判定"贴不准就没有意义"，已移除。
> 取舍与保留了什么见 [`docs/DECISION_AR_REMOVED.md`](docs/DECISION_AR_REMOVED.md)。

---

## ✅ 已完成并验证

### 系统与闭环
打开 App → START → 跟练播放器 → 自动计时换动作 → Done → 保存记录。
这条闭环在 CI 的 macOS 机器上**每次推代码自动跑一遍**（端到端 UI 测试，真实流程）。

其中一条专门盯着：**没有摄像头也能走完整套** —— 模拟器上根本没有前置摄像头。

### App 能力
Home · Routine 详情 · 跟练播放器（视频 + 镜像）· Done · History · 月度分钟数 ·
Settings · 提醒 · 订阅（Release 走真实 StoreKit）· Paywall · Analytics · Debug 诊断页

### 内容（schema v2）
- **20 个 Gold Move**（GM-01…GM-20），逐条转写自 Sprint 3 v0.3
- **3 套 Morning 3 分钟原型** A/B/C，逐格照搬 §4 时间表，各正好 180s
- **27 个位置**（15 个声明 + 自动镜像）
- 动作是资产、routine 只是引用它的时间线 —— 同一动作在多处出现不会漂

全部标 `draft`。中文原文逐字保留在每个动作的 `source` 字段里，供 Expert Gate 复核。

### 视频框架
放进 `Resources/CoachVideos/` 就自动生效，代码不用改。
缺素材时回落到**合成示意脸**，用内容里的真实位置规则把动作画出来 ——
15 个有轨迹的动作全部画得出（改之前只有 4 个，其余 11 个是空白）。

### 官网
落地页 + 隐私政策 + 支持页，已通过 GitHub Pages 上线。

### 离线检查（19 条规则，每条都反向验证过）

| 工具 | 查什么 |
| --- | --- |
| `check_architecture.py` | 13 条：Core 平台隔离、无对错判断、字符串闭合、括号配对、动作零硬编码、用户面文案英文、无障碍标签、隐私承诺、网站无功效表述、**Release 使用真实订阅** |
| `check_swift_refs.py` | 6 条：枚举 case、init 标签、协议一致性、重复属性、一模一样的声明、**引用了不存在的类型** |
| `validate_content.py` | 内容包完整性（配 `check_validator_teeth.py` 反向验证 15 条规则） |
| `generate_golden.py` | 几何交叉验证：Swift ↔ Python 独立实现算同一批数 |
| `simulate_routine.py` | 无头跑完整 routine，验证每段都画得出东西 |
| `check_coach_videos.py` | 视频素材到位情况与命名 |

**每条规则都用故意写错的代码验证过会报错。** 不会报错的规则等于不存在 ——
这个项目里已经吃过几次亏：括号配对没能拦住未闭合字符串（扫描器把后面内容
一路吞掉，括号数恰好还是平的），月度汇总断言在没回到首页时也能通过。

---

## ⛔ 卡住的（等谁）

| 事项 | 谁能做 | 挡不挡上架 |
| --- | --- | --- |
| **App Store Connect 配置订阅商品** | 只有 Owner | ✅ 挡 —— 没商品 Paywall 是空的 |
| **一台 iPhone 跑一次** | 只有 Owner | ✅ 挡 —— **从未在真机上开过机**。不需要 Mac，走 TestFlight（`docs/TESTFLIGHT_FROM_WINDOWS.md`） |
| 网页两个占位符（发布者名义、客服邮箱） | 只有 Owner | ✅ 挡 —— 上架必填 |
| 专家审 20 个动作 | Owner 找人（`make review` 生成审阅表） | ⚠️ 不挡技术，挡良心 |
| 示范视频 0/20 | Owner 找素材 | ❌ **不挡** —— 回落到示意脸，功能完整 |
| 域名 | Owner | ❌ 不挡 —— GitHub 网址够用，但提交前要定 |
| 正式 App 图标 | Owner | ❌ 不挡 —— 已有占位图标 |

**前三件都是十分钟到半天的事，但只有你能做。**

---

## 📌 需要 Owner 知情的工程判断

不同意可以推翻。

1. **不做注册系统。** 订阅走 StoreKit，苹果自己认人，不需要账号。
   一旦加注册就要有后端、要联网，会推翻「无账号、不联网、画面不出设备」——
   那是这个品类里少见的卖点，而且有代码检查锁着。

2. **Release 走真实 StoreKit，DEBUG 保留 Mock。**
   模拟器没有沙盒商品，不留 Mock 开发和 UI 测试都走不通。
   有静态检查盯着 Mock 不许进 Release —— 那类错误不崩不报警，只有收入报表看得出来。

3. **`GuidanceQuality` 只有 good/degraded/lost，领域模型里没有 correctness 字段。**
   把规格 §10 的能力边界做成结构性保证，而不是靠开发纪律。

4. **内容全部带 `draft` 标记，测试断言它必须为真。**
   让未经 Expert Gate 的动作**不可能**被误当成正式护理内容发布。

5. **只写 3 套 Morning 原型，不写 Evening 与 Quick Ritual。**
   Sprint 3 §11 把这两类标为「随后设计」，补齐它们需要发明动作顺序与时长。

6. **三套原型都进 UI，而不是只放一套。**
   §4 说「目的不是现在选赢家」，§7 建议同一批用户交叉体验。

7. **安全相关的中文原文逐字保留，不翻译覆盖。**
   用户看英文，Expert Gate 审原文。禁忌与停止信号经翻译最容易失真。

8. **人脸几何代码保留。** AR 砍掉了，但 `FaceFrame` / `FaceAnchorResolver` /
   `PathSampler` / `anchors.json` 现在是「视频到位之前把动作画出来」的核心，
   不是死代码。详见 `docs/DECISION_AR_REMOVED.md`。

9. **最低 iOS 版本 = 17。** SwiftUI 的 `.onChange` 双参数版与 `.topBarTrailing` 需要它。
   要支持 iOS 16 可以改回旧 API（会有一批废弃警告）。

10. **`PracticeSession` 用手写宽容解码。**
    合成 Codable + 「解码失败返回空数组」这个组合意味着以后任何一次加字段
    都会静默清空所有用户的历史记录。现在缺字段取默认值，坏文件改名留存。

11. **`PracticeMode` 枚举保留 `arMirror` / `watch` 两个 case。**
    删掉会让历史练习记录解码失败。用户看不到它们，但过去的数据仍读得出。

---

## 📁 内容与素材的替换路径

都不需要改代码：

| 要换什么 | 改哪里 | 验证 |
| --- | --- | --- |
| 动作、时长、安全提示 | `Resources/moves.json` | `make content` |
| routine 时间线 | `Resources/routines.json` | `make content` |
| 面部位置 | `Resources/anchors.json` | `make content && make golden` |
| 示范视频 | `Resources/CoachVideos/` | `make videos` |
| App 图标 | `Assets.xcassets/AppIcon.appiconset/icon_1024.png` | — |
| 网页文案 | `site/*.html` | `make arch` |
