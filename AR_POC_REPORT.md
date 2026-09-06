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
| Swift 代码编译 | ✅ **已验证** —— GitHub Actions 的 macOS runner，零编译错误 |
| 单元测试（71 个） | ✅ **全部通过** |
| M1 闭环（模拟器 + 合成脸） | ✅ **全部通过** —— 见 §1.2 |
| 真机 Face Lock / FPS / 遮挡 | ❌ 未测 —— **需 iPhone，这是唯一剩下的一项** |

编译与闭环已由 CI 自动验证，不再需要本地 Mac。剩下的只有 §2 的真机测试。

---

## 1. 已完成的离线验证

### 1.1 几何不变性（M1 真正要证明的性质）

`tools/golden/generate_golden.py` 用一套**独立于 Swift 的** Python 实现，
在 6 种变换下解析全部 27 个 anchor，检查它们在脸部局部坐标系里是否落在同一点：

| 用例 | 瞳距(px) | roll | 画面位置 |
| --- | --- | --- | --- |
| reference | 100 | 0° | 居中 |
| far_small_face | 42 | 0° | 居中 |
| near_large_face | 168 | 0° | 居中 |
| offcenter | 100 | 0° | 偏移 |
| roll_plus_18 | 100 | +18° | 居中 |
| roll_minus_25 | 88 | −25° | 偏移 |

**结果：全部 27 个 anchor 的最大漂移 = 2.0e-15 瞳距**（浮点精度级别，即完全不变）。

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
morning_prototype_b  —  12 steps → 12 播放段，180s
  0   none      15s Settle and Breathe       expression      —  仅提示与计时（无 overlay）
  1   both      15s Forehead Sweep           line       1.27瞳距  forehead_center → temple_left
  2   both      15s Temple Circles           circle     1.00瞳距  temple_left
  3   both      15s Cheek Lifter             press      0.00瞳距  cheekbone_left
  4   both      20s Happy Cheeks Sculpting   line       0.81瞳距  mouth_corner_left → cheekbone_left
  5   none      15s Cheek Puff               expression   2 区域  cheek_mid_left, cheek_mid_right
  6   both      15s Midface Sweep            line       0.60瞳距  nose_side_left → cheekbone_left
  7   both      15s Cheek to Temple          curve      0.86瞳距  cheek_mid_left → temple_left
  8   both      15s Jawline Sweep            arc        1.88瞳距  chin_center → preauricular_left
  9   both      15s Forehead Lift            line       0.78瞳距  forehead_lower_left → hairline_left
  10  both      15s Palm Effleurage          line       0.95瞳距  cheek_lower_left → preauricular_left
  11  both      10s Light Tapping            tap          5 区域  forehead_center, cheek_mid_left, ...
（Prototype A / C 同样 12 段 180s）
每一段都能正常渲染，无问题
```

**这个检查抓到过一个真实 bug**：`SemanticLandmark.mirrored` 用 `hasPrefix("left")`
判定侧别，而 `mouthLeftCorner` 把侧别写在名字中间 —— 于是嘴角不翻转，
右脸 Cheek Lift 的起点被算到脸中间，路径长度 0.87 vs 1.20（差 28%）。
golden vector 验的是变换不变性，测不出镜像错误；这个 bug 原本只有上真机才会发现。

### 1.3 内容包

```
Gold Motion Library: 20 个动作（GM-01…GM-20），Sprint 3 v0.3
morning_prototype_b    type=morning  premium=False steps=12 total=180s
morning_prototype_a    type=morning  premium=False steps=12 total=180s
morning_prototype_c    type=morning  premium=False steps=12 total=180s
anchors: 27 个（15 个声明 + 12 个自动镜像）
errors=0 warnings=2（均为预期内：
  · 内容包整体标记为 draft，待 Expert Gate
  · 5 个动作尚未被任何 routine 使用 —— Sprint 3 §11 把 Evening/Quick 标为「随后设计」）
```

`tools/check_validator_teeth.py`：15 条内容校验规则逐条注入缺陷，全部确认会报错。

---

## 2. 真机测试协议

### 2.0 不用等 iPhone 也能先测一轮

浏览器原型现在带同一套测量。**在 Windows 上今天就能拿到第一组真人脸数据。**

```bash
python tools/build_prototype.py
cd prototype && python -m http.server 8000
```

Chrome 打开 `http://127.0.0.1:8000` → 开摄像头 → 选场景 → 点「开始测量」。

统计实现与 Swift 侧**逐字段对应**，并由 `tools/check_prototype_math.py`
在 CI 上交叉验证（4 组用例，容差 1e-9）—— 算得不一样的话两边数据就没法比，
所以这条检查不是可选的。

> ⚠️ **绝对值不可直接当作 iOS 的预期值。**
> MediaPipe 与 Vision/HRFFA 是不同模型，笔记本摄像头也不是 iPhone 前摄。
>
> 能迁移的是这个问题的答案：**FaceFrame 这套坐标系在真人脸上站不站得住。**
> 如果连浏览器上都测出巨大漂移，那不是 provider 的问题，是坐标系或 anchor
> 定义的问题 —— 那种问题换到 iPhone 上也不会消失，早发现早改。

### 2.1 准备

1. Mac 上：`make bootstrap && make open`，在 Xcode 填 Team，跑到 iPhone 上。
2. App 内 **Settings → Developer → Diagnostics → POC 测量（真机）**。
3. 每个 provider 各测一遍：先在 Settings → Developer → Face Alignment Provider
   切换，再进测量台。两轮数据会一起导出，不用分开保存。

### 2.2 用测量台跑（推荐）

下面 B/C/D 三节的数据**不用手抄** —— 测量台会按场景采集并算好。

流程：选一个场景 → 摆好姿势再点 → 保持 10–20 秒 → 「停止并记录」→ 换下一个。
全部测完点「导出全部」，得到一段可以直接贴进本文件的 Markdown 表格
外加一份原始 JSON。

**漂移是怎么算出来的**（这一项以前只能目测）：

anchor 在**脸部局部坐标系**里的位置理论上恒定 —— 坐标系以双眼为原点、
以瞳距为单位，对远近、平移、歪头天然不变。这个性质离线已经证明过：
27 个 anchor 在 6 种变换下漂移 2e-15 瞳距（见 §1.1）。

所以在真人脸上，同一个 anchor 局部坐标的残余波动**就是**漂移本身，
不需要任何真值标注。测量台把它拆成两个数，因为观感完全不同：

| 指标 | 含义 | 用户看到的 | 要调的参数 |
| --- | --- | --- | --- |
| **drift** | 相对整段均值的偏离 | 点慢慢跑偏 | 跟随滞后 → `beta` 调大 |
| **jitter** | 相邻帧的位移 | 点在原地抖 | → `minCutoff` 调小 |

两者都以瞳距为单位，因此**不同的人、不同距离、不同机型之间可以直接比**。
报告里还给出 `漂移/容差` 比值：1.0 表示 95% 的帧刚好落在容差圈边缘。

> 阈值定在哪里，等真机数据出来再谈 —— 测量台刻意**不给「合格/不合格」**，
> 那是规格 §18 的 Go/No-Go 判定，需要先有数据。

`lost` 的帧不计入位置统计（那些帧的位置本来就没有意义，
混进去会让漂移虚高，反而掩盖真实问题），但仍然计入质量分布。

### 2.3 逐项测试与记录

> 下表里 B/C/D 由测量台产出；A/E/F 仍需人来判断。
> 测不了的写「未测」，不要留空也不要猜。

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

> B / C / D 三节可直接粘贴测量台导出的表格，格式为：
> `| 场景 | provider | 时长 | FPS | p95延迟 | good | degraded | lost | 漂移p95(瞳距) | 漂移/容差 |`

#### E. 手遮挡（规格 §10 的核心边界）

**这是最容易在空手 Demo 里看起来很美、一上手就崩的场景。必须真手做动作。**

| 场景 | 观察项 | 结果 |
| --- | --- | --- |
| 单指点在眉心 | overlay 是否冻结在最后可信位置 | |
| 两指划过太阳穴 | routine 是否继续计时、语音是否继续 | |
| 手掌盖住半张脸 | 是否出现任何「正确/错误」判断（**必须没有**） | |
| 手移开后 | 多久重新 lock | |

**验收红线：任何遮挡场景下都不得出现对错判断。** 若出现，属于违反规格 §10 的缺陷。

> 这一条**必须人来看**，测量台答不了。
> 领域模型里根本没有 correctness 字段（`GuidanceQuality` 只有 good/degraded/lost），
> 架构检查也有一条规则盯着 —— 但"屏幕上有没有让用户觉得被评判的东西"
> 是个观感问题，只有人能判断。
>
> 测量台在遮挡场景下会给出 `lost` 占比与丢锁次数，
> 那回答的是另一个问题：**遮挡时系统还撑不撑得住**。两件事不要混。

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
