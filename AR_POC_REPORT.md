# AR_POC_REPORT — Personalized AR Mirror Guidance

> 规格 §18 的 Go / No-Go Gate 报告。
>
> **状态：待真机执行。**
> 本文件当前是**测试协议 + 待填表格**，不是结论。
> 里面没有任何编造的实测数字 —— 空的地方就是还没测。

---

## 0. 为什么现在还不能填

开发机是 Windows，没有 Swift / Xcode 工具链（已验证 `swift`、`swiftc`、`xcodegen` 均不存在）。
因此：

| 项目 | 状态 |
| --- | --- |
| 几何层数学正确性 | ✅ **已验证**（Python 参考实现交叉验证，见 §1.1） |
| 内容包完整性 | ✅ **已验证**（`python tools/validate_content.py`，0 errors） |
| 每个播放段能否渲染 | ✅ **已验证**（`python tools/simulate_routine.py`，见 §1.3） |
| 架构约束 | ✅ **已验证**（`python tools/check_architecture.py`，0 errors） |
| Swift 代码编译 | ❌ 未验证 —— 需在 Mac 上首次构建 |
| 真机 Face Lock / FPS / 遮挡 | ❌ 未测 —— 需 iPhone |

先在 Mac 上跑通 `make bootstrap && make core-test && make build`，再按 §2 执行真机测试。

---

## 1. 已完成的离线验证

### 1.1 几何不变性（M1 真正要证明的性质）

`tools/golden/generate_golden.py` 用一套**独立于 Swift 的** Python 实现，
在 6 种变换下解析全部 9 个 anchor，检查它们在脸部局部坐标系里是否落在同一点：

| 用例 | 瞳距(px) | roll | 画面位置 |
| --- | --- | --- | --- |
| reference | 100 | 0° | 居中 |
| far_small_face | 42 | 0° | 居中 |
| near_large_face | 168 | 0° | 居中 |
| offcenter | 100 | 0° | 偏移 |
| roll_plus_18 | 100 | +18° | 居中 |
| roll_minus_25 | 88 | −25° | 偏移 |

**结果：全部 9 个 anchor 的最大漂移 = 2.0e-15 瞳距**（浮点精度级别，即完全不变）。

```
OK brow_inner_left        最大漂移 = 2.950e-16 瞳距
OK brow_inner_right       最大漂移 = 2.289e-16 瞳距
OK cheek_mid_left         最大漂移 = 7.109e-16 瞳距
OK cheek_mid_right        最大漂移 = 5.837e-16 瞳距
OK glabella_center        最大漂移 = 6.106e-16 瞳距
OK jaw_angle_left         最大漂移 = 2.011e-15 瞳距
OK jaw_angle_right        最大漂移 = 1.093e-15 瞳距
OK temple_left            最大漂移 = 8.752e-16 瞳距
OK temple_right           最大漂移 = 7.153e-16 瞳距
```

**这条结论的边界必须说清楚：**
它只证明了**平面内**变换（尺度 / 平移 / roll）下 anchor 定义是稳定的 ——
也就是「不同脸大小、不同距离、不同歪头角度，目标点仍在脸上同一处」。

它**没有**证明：
- 出平面旋转（yaw / pitch，即抬头低头左右转头）下的稳定性 —— 那取决于 provider 的 3D 能力，只能真机测；
- 不同**脸型**（而非不同尺度）下位置是否合适 —— 需要真人样本；
- 位置在护理意义上是否正确 —— 这是 Owner + 专业人员的事，工程不做判断。

### 1.2 播放段渲染与左右对称（`tools/simulate_routine.py`）

无头跑完整 routine，对每个播放段解析 anchor、采样路径、检查落点：

```
morning_core  —  5 steps → 9 播放段，180s
  0   left      18s Temple Circles    circle   1.26瞳距  temple_left
  1   right     18s Temple Circles    circle   1.26瞳距  temple_right
  2   left      18s Brow Sweep        line     0.89瞳距  brow_inner_left → temple_left
  3   right     18s Brow Sweep        line     0.89瞳距  brow_inner_right → temple_right
  4   left      18s Cheek Lift        curve    0.87瞳距  cheek_mid_left → temple_left
  5   right     18s Cheek Lift        curve    0.87瞳距  cheek_mid_right → temple_right
  6   left      18s Jaw Release       arc      1.67瞳距  jaw_angle_left → temple_left
  7   right     18s Jaw Release       arc      1.67瞳距  jaw_angle_right → temple_right
  8   none      36s Glabella Hold     hold     0.00瞳距  glabella_center
每一段都能正常渲染，无问题
```

**这个检查抓到过一个真实 bug**：`SemanticLandmark.mirrored` 用 `hasPrefix("left")`
判定侧别，而 `mouthLeftCorner` 把侧别写在名字中间 —— 于是嘴角不翻转，
右脸 Cheek Lift 的起点被算到脸中间，路径长度 0.87 vs 1.20（差 28%）。
golden vector 验的是变换不变性，测不出镜像错误；这个 bug 原本只有上真机才会发现。

### 1.3 内容包

```
morning_core     type=morning  premium=False steps=5  total=180s
evening_core     type=evening  premium=True  steps=5  total=300s
quick_depuff     type=quick    premium=True  steps=3  total=180s
quick_tired_eyes type=quick    premium=True  steps=3  total=180s
anchors: 9 个（5 个声明 + 4 个自动镜像）
errors=0 warnings=1（预期内：内容标记为 mock_unreviewed）
```

---

## 2. 真机测试协议

### 2.1 准备

1. Mac 上：`make bootstrap && make open`，在 Xcode 填 Team，跑到 iPhone 上。
2. App 内 **Settings → Developer → 显示 AR Debug 图层** 打开。
   开启后 AR 画面顶部会显示 `provider / fps / lat / lock / loss` 实时读数，
   脸上会叠加绿色语义 landmark 点与红蓝两条脸部坐标轴。
3. 每个 provider 各测一遍：Settings → Developer → Face Alignment Provider。

### 2.2 逐项测试与记录

> 每一格填实测值。测不了的写「未测」，不要留空也不要猜。

#### A. 基础运行

| Provider | 可用 | 首次 Face Lock 耗时 | 平均 FPS | 平均延迟 | p95 延迟 | 备注 |
| --- | --- | --- | --- | --- | --- | --- |
| Vision（基线） | | | | | | |
| HRFFA (CoreML) | | | | | | 需先放入模型 |
| ARKit Face Mesh | | | | | | 需先标定顶点表 |

设备型号：______　iOS 版本：______　室内光照：______

#### B. 距离表现

| 距离 | Vision | HRFFA | ARKit |
| --- | --- | --- | --- |
| 很近（约 15cm） | | | |
| 正常（约 30cm） | | | |
| 较远（约 60cm） | | | |
| 很远（约 1m） | | | |

记录：能否 lock、overlay 是否贴合、是否触发「move closer / move back」提示。

#### C. 头部姿态

| 动作 | 角度 | Vision | HRFFA | ARKit |
| --- | --- | --- | --- | --- |
| 轻微抬头 | ~15° | | | |
| 轻微低头 | ~15° | | | |
| 左转头 | ~20° | | | |
| 右转头 | ~20° | | | |
| 大幅转头 | ~40° | | | |

记录：anchor 是否仍贴在脸上正确位置、是否明显漂移、是否正确降级为 degraded/lost。

#### D. 跟脸漂移（最关键的一项）

固定一个 anchor（建议 `temple_left`），缓慢左右平移头部、前后移动，观察：

- 漂移幅度（用容差圈作参照：漂出圈外没有？）：______
- 是否有「粘滞感」或明显滞后（One Euro 滤波参数是否需要调）：______
- 静止时是否抖动：______

> 若静止抖动明显 → 调 `FaceGeometrySmoother(minCutoff:)` 调小。
> 若跟随滞后明显 → 调 `beta` 调大。位置在 `OneEuroFilter.swift`。

#### E. 手遮挡（规格 §10 的核心边界）

**这是最容易在空手 Demo 里看起来很美、一上手就崩的场景。必须真手做动作。**

| 场景 | 观察项 | 结果 |
| --- | --- | --- |
| 单指点在眉心 | overlay 是否冻结在最后可信位置 | |
| 两指划过太阳穴 | routine 是否继续计时、语音是否继续 | |
| 手掌盖住半张脸 | 是否出现任何「正确/错误」判断（**必须没有**） | |
| 手移开后 | 多久重新 lock | |

**验收红线：任何遮挡场景下都不得出现对错判断。** 若出现，属于违反规格 §10 的缺陷。

#### F. 失败场景

| 场景 | 表现 | 是否阻塞 routine |
| --- | --- | --- |
| 完全无人脸 | | |
| 两个人入镜 | | |
| 逆光 / 极暗 | | |
| 戴眼镜 | | |
| 刘海遮眉 | | |
| 中途切后台再回来 | | |
| （切后台时摄像头指示灯应熄灭） | | |
| 来电打断 | | |

**验收红线：以上任何一项都不得让 routine 卡死或崩溃**（规格 §4：识别失败不得阻塞 routine）。

#### G. 端到端闭环（M1 里程碑本体）

```
[ ] 打开 App
[ ] Home 显示 Morning Ritual 3:00 与 START
[ ] START → 选择 AR Mirror
[ ] 弹出摄像头权限（首次）
[ ] 前置摄像头打开，看到自己的脸
[ ] Face Lock 成功
[ ] 脸上稳定显示 ● 起点
[ ] 脸上稳定显示 ◎ 终点
[ ] 脸上显示动态路线与方向箭头
[ ] 圆周动作显示为圆
[ ] 左右侧自动切换，颜色与标签同步
[ ] 自动倒计时、自动换动作
[ ] 完整走完 3 分钟
[ ] Done 页出现
[ ] 练习记录已保存（History 里能看到）
[ ] 月度分钟数已更新
```

补充验证（规格 §4：识别失败不得阻塞 routine）：

```
[ ] 用手完全遮住脸 12 秒以上，出现「切到 Coach 继续」的建议
[ ] 无视该建议，routine 仍在正常计时与换动作
[ ] 点击该建议后，摄像头关闭、Coach 示意图出现、**计时没有中断**
[ ] 完成后 Done 页与记录里标出了这次发生过 fallback
```

---

## 3. 结论（真机测试后填写）

### 3.1 Go / No-Go

- [ ] **Go** —— 继续投入 AR Mirror
- [ ] **Conditional Go** —— 满足条件后继续，条件：______
- [ ] **No-Go** —— 用 Coach 模式先上线（规格 §18 明确允许）

理由：

```
（填写）
```

### 3.2 是否建议继续 HRFFA

```
（填写。判断依据建议是：相对 Vision 基线，HRFFA 在
 —— 转头稳定性
 —— 跟脸漂移
 —— 遮挡后恢复速度
 三项上是否有可感知的提升，以及提升是否值得多背一个模型的体积与功耗。）
```

### 3.3 是否需要替换 Provider

```
（填写）
```

### 3.4 下一阶段建议

```
（填写）
```

---

## 4. 已知的工程侧限制（不必测也知道）

1. **Vision 不提供逐点遮挡判断。** 手遮脸只能通过置信度下降间接感知，
   `FaceGeometry.occludedLandmarkRatio` 在 Vision 下恒为 0，
   遮挡降级实际走的是 `meanLandmarkConfidence` 路径。这与规格 §10 的承诺一致 ——
   我们本来就不声称能判断接触点。
2. **ARKit 顶点索引表未标定。** Apple 未公布 1220 顶点的语义编号，
   我们拒绝猜测（画错位置比不画更糟）。
   **标定工具已内置**：Settings → Developer → Provider/内容诊断 → ARKit 顶点标定，
   在真机上依次点自己脸上的 10 个位置即可导出 `arkit_vertex_map.json`（约 2 分钟）。
   在标定完成前 ARKit provider 会自动判为不可用并回落 Vision。
3. **HRFFA 模型文件不在仓库里。** 转换需要 macOS + coremltools，见 `docs/HRFFA_INTEGRATION.md`。
4. **HeadPoseEstimator 是几何近似，不解 PnP。** 只够做阈值判断（转头是否过大），
   不可用于任何需要精确角度的场景。
5. **Coach 素材是占位动画。** 由同一份 MovementSpec 驱动，因此不会与 AR 路线矛盾，
   但它不是正式的教练示范。
6. **连续 12 秒锁不上会建议退回 Coach。** 这是建议不是拦截 ——
   不弹模态、不暂停计时，用户可以一直无视它把 routine 做完（规格 §4）。
   测试 §2F 时请留意这个提示是否出现得过早或过晚，阈值在
   `ARMirrorView.fallbackPromptThreshold`。
