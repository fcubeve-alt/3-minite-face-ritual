# 决策记录：移除 AR Mirror

> 2026-09-07 · Owner 判定，工程执行
>
> 这份文件取代了原来的 `AR_POC_REPORT.md`。
> 保留它是因为它解释了**代码为什么长成现在这样** ——
> 仓库里有一整套人脸几何代码，却没有任何人脸识别功能，不写清楚会让人困惑。

---

## 结论

**AR Mirror（把动作路线实时贴在用户自己脸上）与 Watch & Breathe 已从产品中移除。**

产品形态改为：**上半屏示范视频，下半屏纯镜像**。
下半屏不做任何人脸识别 —— 它只是一面镜子。

---

## 原本要做什么

规格 V2 §6.2 要求在用户自己脸上稳定显示：
● 起点 / ◎ 终点 / → 动态方向 / 曲线与直线路径 / 圆周 / 手势提示 / 节奏 / 左右切换。

为此建成的东西（M1 阶段，2026-09-05 至 09-06）：

| 部件 | 做了什么 |
| --- | --- |
| Provider 抽象 | Vision / HRFFA / ARKit / Mock 四个实现，业务层不绑定任何一个 |
| `FaceFrame` | 脸部局部坐标系（原点=双眼中点，单位=瞳距），吸收缩放/平移/roll |
| `SemanticLandmark` | 33 个语义点，provider 中立 |
| `AnchorGeometryRule` | 组合式位置规则（landmark / midpoint / lerp / weighted / offset） |
| `PathSampler` | 直线 / 贝塞尔 / 圆弧 / 圆周，按弧长参数化 |
| `OneEuroFilter` | 抖动抑制 |
| 漂移测量 | 真机测量台 + 浏览器原型，两边统计实现交叉验证一致 |

离线验证的结论是正面的：27 个位置在 6 种尺度/位置/roll 变换下**局部坐标漂移 < 2e-15 瞳距** ——
也就是说，坐标系这一层的数学是对的。

---

## 为什么还是砍了

Owner 在浏览器原型上实测后给出的判断：

1. **贴不准。** 位置定位达不到"指哪儿是哪儿"的程度。
2. **跟不住。** 人脸与手机的相对位置一变，overlay 跟不上。
3. **不准就没有意义。** 一个指引类功能，如果用户不能信任它指的位置，
   那它占用的屏幕、复杂度和摄像头权限都不值得。

第 3 条是关键。**这不是"再调调滤波参数"能解决的问题** ——
它是对这个功能价值前提的判断：指引必须可信，否则不如不做。

### 工程侧的补充事实

- Owner 测的是**浏览器原型**（MediaPipe + 网页摄像头），不是 iOS 上的 Vision/ARKit。
  两者有差距，iPhone 上大概率更好。
- 但 **iOS 版从未在真机上跑过**，所以没有数据能反驳这个判断。
- 而且规格 §10 本来就规定这一版**不做实时纠错**。
  如果连"贴得稳"都做不到，这个功能撑不起它占的复杂度。

---

## 砍掉之后换来了什么

不只是少了一个功能，是**少了一整类问题**：

| 原来必须处理 | 现在 |
| --- | --- |
| 丢锁、重新锁定、首次锁定耗时 | 不存在 |
| 漂移、抖动、滤波调参 | 不存在 |
| provider 不可用时的回落链 | 不存在 |
| 遮挡策略（手挡脸时怎么办） | 不存在 |
| ARKit / Vision / CoreML 依赖 | 已移除，上架审核不用解释 ARKit 用途 |
| 摄像头是**必需**的 | 摄像头变成**可选** —— 不开也能完整使用 |

最后一条影响最大：现在没有摄像头权限、或在模拟器上，整套 routine 照样能走完。

---

## 保留了什么，为什么

**人脸几何那套代码留着，而且现在是载荷代码。**

示范视频还没到位时，播放器用一张**合成示意脸**把动作的起点、终点和方向画出来。
它走的正是同一套 `FaceFrame` + `FaceAnchorResolver` + `PathSampler`，
只是喂进去的不是摄像头识别的脸，而是 `SyntheticFace` 里一张标准比例的脸。

所以下面这些**不是**死代码：
`FaceFrame` · `FaceGeometry` · `SemanticLandmark` · `FaceAnchorResolver` · `PathSampler` ·
`anchors.json` · golden vector 交叉验证 · `tools/simulate_routine.py`

> 顺带一提：正因为先查了这一层，才发现示意图当时查的是一张**手写的 9 个位置表**，
> 15 个有轨迹的动作只画得出 4 个。改用真实规则后是 15/15。
> 如果当时按原计划直接删掉这套几何，这个问题会一直藏着。

**删掉的**：provider 抽象与四个实现、`ARGuidanceController`、overlay 渲染器、
漂移测量（`StabilityMeter` / `POCRecorder`）、真机 POC 测量台、ARKit 顶点标定工具、
浏览器原型及其构建与交叉验证。

随之删除的两份文档（内容在 git 历史里）：
`docs/HRFFA_INTEGRATION.md`、`docs/ARKIT_VERTEX_CALIBRATION.md`。

---

## 如果以后想再做

需要重新引入 provider 抽象与实时 geometry，但**内容层不用动** ——
`anchors.json` 的位置规则、`MovementSpec` 的路径定义都是 provider 中立的，
当初就是按"业务层不绑定 HRFFA"的要求设计的。

真要重做，建议先用一台 iPhone 跑 ARKit TrueDepth 测一组漂移数据再决定，
不要再从架构开始建。相关代码在 git 历史里：

```bash
git log --oneline --diff-filter=D -- 'App/FaceRitual/FaceAR/**'
```
