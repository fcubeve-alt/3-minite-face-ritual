# face3

一个每天用 3 分钟陪用户完成固定面部按摩动作的极简 App。

**上半屏是示范视频，下半屏是你自己的镜像**，跟着做就行。
摄像头是**可选**的 —— 不开也能完整走完一整套。

**Source of Truth：`3-Minute_Face_Ritual_Product_v2_CN.docx`。**
代码与文档都不得覆盖它的产品定义。

> 产品形态于 2026-09-07 调整过一次：原本还有 AR Mirror（把动作路线实时贴在脸上）
> 与 Watch & Breathe，实测贴不稳后移除。
> 原因与取舍见 [docs/DECISION_AR_REMOVED.md](docs/DECISION_AR_REMOVED.md) ——
> 仓库里有一整套人脸几何代码却没有人脸识别功能，那份文档解释了为什么。

---

## ⚠️ 内容尚未通过专家审核

内容来自两份专业文档，工程侧只做**如实转写与结构化**，不增删动作、不改措辞：

- `Face_Ritual_Research_Sprint3_Movement_Specs_Prototypes_v0.3` —— 20 个动作（GM-01…GM-20）+ 3 套 Morning 3 分钟原型
- `Face_Ritual_AI_Video_Factory_v0.2_AR_Guidance` —— Gold Motion Library 架构

**全部 20 个动作与 27 个位置定义仍标 `draft`。**
Sprint 3 开篇即声明动作需人工专家（PT / 皮肤科 / 淋巴引流方向）审核。
在此之前它们不代表任何按摩方法、穴位定义或护理功效。

UI 上有 MOCK 角标，单元测试断言不得有任何一条被标成 `expert_reviewed`。
给专家的审阅表一条命令就能生成：`make review`。

用户看到的是英文；每个动作的 `source` 字段里**逐字保留中文原文**
（起始姿势、操作、力度、停止信号）—— 专家审的是原文，翻译会在安全措辞上引入偏差。

Evening 5-minute 与 Quick Ritual **尚未设计**（Sprint 3 §11 标为「随后设计」），
所以内容包里没有这两类 —— 工程侧不代为编排。

---

## ⛔ 示范视频还没有 —— 这是产品最大的缺口

`make videos` → **0/20**。

产品定位是「上面老师做，下面你跟着做」。**没有视频，"老师"那一半是空的。**

缺素材时播放器会回落到一张合成示意脸，画出动作的起点、路径、方向和手势提示。
它能让流程跑通、能让你测试其它功能，但它**教不会一个新用户做面部按摩** ——
看不出手的形状、按压的深浅、动作的真实速度。

所以要分清两句话：

| | |
| --- | --- |
| 技术上 | 不挡 —— App 不崩、能计时、能记录、能提交审核 |
| 产品上 | **挡** —— 核心的「教」这件事现在是缺的 |

视频放进 `App/FaceRitual/Resources/CoachVideos/` 就自动生效，代码不用改。
交付要求见 [docs/COACH_VIDEO_SPEC.md](docs/COACH_VIDEO_SPEC.md)。

---

## 文档

| 文件 | 内容 |
| --- | --- |
| [PROJECT_STATE.md](PROJECT_STATE.md) | **当前状态**：做完了什么、卡在哪、等谁 |
| [MASTER_PLAN.md](MASTER_PLAN.md) | 规格 → 工程任务的转化与里程碑 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 模块分层与关键设计决策 |
| [docs/APP_STORE_CHECKLIST.md](docs/APP_STORE_CHECKLIST.md) | **上架清单**：哪些是硬性要求、哪些已做好、哪些等你 |
| [docs/COACH_VIDEO_SPEC.md](docs/COACH_VIDEO_SPEC.md) | **示范视频交付规格**（给做视频的人） |
| [docs/CONTENT_AUTHORING.md](docs/CONTENT_AUTHORING.md) | **替换正式动作内容的指南**（Owner 与专家看这份） |
| [docs/COPY_REVIEW.md](docs/COPY_REVIEW.md) | **文案评审清单**（Owner 与法务看这份） |
| [docs/DOMAIN_AND_GROWTH.md](docs/DOMAIN_AND_GROWTH.md) | 域名与获客：现在做什么、先不做什么 |
| [docs/DECISION_AR_REMOVED.md](docs/DECISION_AR_REMOVED.md) | 为什么砍掉 AR Mirror，保留了什么 |
| [docs/TRY_ON_IPHONE.md](docs/TRY_ON_IPHONE.md) | **今天就在自己 iPhone 上试**（免费 Apple ID，20 分钟） |
| [docs/TESTFLIGHT_FROM_WINDOWS.md](docs/TESTFLIGHT_FROM_WINDOWS.md) | TestFlight 分发（要 $99 开发者账号，上架前用） |
| [site/README.md](site/README.md) | 官网发布方法（已上线，GitHub Pages） |

---

## 官网（已上线）

| 用途 | 网址 |
| --- | --- |
| 落地页 | https://fcubeve-alt.github.io/3-minite-face-ritual/ |
| 隐私政策（上架必填） | https://fcubeve-alt.github.io/3-minite-face-ritual/privacy.html |
| 支持页（上架必填） | https://fcubeve-alt.github.io/3-minite-face-ritual/support.html |

还有两个占位符要填：发布者名义、客服邮箱。

---

## 在没有 Mac 的机器上能做什么

```bash
make check       # 全部离线校验（架构 / 引用 / 内容 / 几何 / 素材）
make review      # 生成给专家的动作审阅表
make videos      # 示范视频素材到位情况
```

CI 在 GitHub 的 macOS 机器上真实编译、跑单元测试与端到端 UI 测试。

---

## 当前状态

| | |
| --- | --- |
| 已验证 | macOS 上零编译错误；单元测试 + 4 个端到端 UI 测试全绿 |
| 内容 | 20 个动作、3 套 Morning 3 分钟原型（各 180s）、27 个位置 |
| 未验证 | **从未在真 iPhone 上开过机** —— CI 用的是模拟器。<br>现在就能试：[TRY_ON_IPHONE.md](docs/TRY_ON_IPHONE.md)（免费 Apple ID，20 分钟） |
| 订阅 | Release 走真实 StoreKit，但**需要你在 App Store Connect 配置商品** |
| 下一步 | 见 [PROJECT_STATE.md](PROJECT_STATE.md) 的「等谁」一节 |
