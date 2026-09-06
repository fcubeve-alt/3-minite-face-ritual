# 3-Minute Face Ritual — V2

一个每天用 3–5 分钟陪用户完成固定面部护理动作的极简 Face Ritual App。
第一次看老师学，之后可以把位置、路线和方向直接显示在自己的脸上。

**Source of Truth：`3-Minute_Face_Ritual_Product_v2_CN.docx`。**
代码与文档都不得覆盖它的产品定义。

---

## ⚠️ 当前内容全部是 Mock

M1 阶段的动作、路径、面部位置**全部是占位测试数据**，
只用于验证 App 系统、Routine Player 与 AR 链路是否跑通。

它们不代表任何按摩方法、穴位定义或护理功效。
正式内容由 Owner + 专业人员重新筛选和人工审核后替换 `Resources/*.json`，代码无需改动。

内容包与 UI 上都有 `mock_unreviewed` 标记与 MOCK 角标，单元测试会断言它必须存在。

---

## 文档

| 文件 | 内容 |
| --- | --- |
| [MASTER_PLAN.md](MASTER_PLAN.md) | 规格 → 工程任务的转化与里程碑分解 |
| [PROJECT_STATE.md](PROJECT_STATE.md) | Completed / In Progress / Blocked / Owner Decision Required |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 模块分层、AR 链路、关键设计决策 |
| [AR_POC_REPORT.md](AR_POC_REPORT.md) | 真机 POC 协议与 Go/No-Go 报告（待填） |
| [docs/HRFFA_INTEGRATION.md](docs/HRFFA_INTEGRATION.md) | HRFFA CoreML 接入步骤 |
| [docs/ARKIT_VERTEX_CALIBRATION.md](docs/ARKIT_VERTEX_CALIBRATION.md) | ARKit 顶点索引标定 |
| [docs/CONTENT_AUTHORING.md](docs/CONTENT_AUTHORING.md) | **替换正式动作内容的指南**（Owner 与专业审核人员看这份） |
| [docs/COPY_REVIEW.md](docs/COPY_REVIEW.md) | **文案评审清单**（Owner 与法务看这份）：免责、Watch & Breathe、订阅披露、摄像头说明 |
| [docs/APP_STORE_CHECKLIST.md](docs/APP_STORE_CHECKLIST.md) | **上架清单**：哪些是硬性要求、哪些已做好、哪些等你 |
| [site/README.md](site/README.md) | 隐私政策与支持页的发布方法（GitHub Pages 免费） |

---

## 快速开始

### 任何机器（含 Windows / Linux）

```bash
make check
```

跑三件事，都不需要 Xcode：

- `make arch` —— 架构约束 + 轻量 Swift 静态检查（Core 平台隔离、landmark 编号收敛、
  无对错判断、`@objc` 需 NSObject、API 可用性 vs 部署目标、括号配对、动作内容零硬编码）
- `make content` —— 内容包 JSON 校验
- `make refs` —— Swift 引用检查（枚举 case / init 参数标签 / 协议一致性）
- `make golden` —— 重新生成几何 golden vectors
- `make simulate` —— 无头跑一遍全部 routine，验证每个播放段都能在脸上画出东西、且左右互为镜像
- `make prototype` —— 生成浏览器版 AR 概念验证，**在自己脸上看效果，不需要 Mac / iPhone**

### macOS

```bash
brew install xcodegen
make bootstrap    # 生成 FaceRitual.xcodeproj
make core-test    # 跑核心包单元测试（最快的反馈回路）
make open         # 在 Xcode 打开，填 Team，跑到设备上
```

---

## 仓库结构

```
Packages/FaceRitualCore/     纯 Swift 核心：领域模型、内容层、播放器、脸部几何
  Sources/.../Resources/     内容 JSON（唯一的动作真源）
  Tests/                     单元测试 + golden vector 交叉验证

App/FaceRitual/              iOS App
  App/                       入口、DI 容器、设置
  Features/                  SwiftUI 页面
  FaceAR/                    Provider 实现、Overlay Renderer、AR 会话编排
  Platform/                  语音、震动、通知、权限、StoreKit

tools/                       跨平台校验脚本（Python，无需 Xcode）
```

**核心约束**：`FaceRitualCore` 不允许 import ARKit / Vision / CoreML。
这是「业务层不绑定某个 face alignment provider」的编译期保证。

---

## 当前状态

| | |
| --- | --- |
| 已离线验证 | 架构与引用检查 0 errors（12 条规则，每条都反向验证过）；内容包校验 0 errors；9 个 anchor 在 6 种尺度/位置/roll 变换下漂移 < 2e-15 瞳距；Morning Core 9 个播放段全部可渲染且左右对称 |
| CI 已验证 | macOS runner 上零编译错误；71 个单元测试 + 4 个 M1 闭环 UI 测试全绿 |
| 未验证 | 真人脸上的贴合精度 / FPS / 遮挡表现 —— 只能上真机 |
| 下一步 | 真机 AR POC（`AR_POC_REPORT.md` §2） |

详见 [PROJECT_STATE.md](PROJECT_STATE.md)。

---

## 免责

本 App 提供的是日常护理引导，不构成医学诊断、治疗建议或疗效承诺。
工程侧不自行创造医学、美容或穴位功效 —— 这些必须由 Owner 与专业人员定义（规格 §20）。
