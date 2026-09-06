# 内容编写指南

> 给 Owner 与专业审核人员。
> **替换正式动作内容不需要改任何 Swift 代码** —— 只改 `Resources/` 下的四个 JSON。
>
> 规格 §14 与 §20 明确：动作、穴位含义、疗效、安全性由 Owner 与专业人员定义，
> 工程侧不代为决定。这份文档只讲**怎么写**，不讲**写什么**。

---

## 文件在哪

```
Packages/FaceRitualCore/Sources/FaceRitualCore/Resources/
├── content_meta.json   # 版本与审核状态
├── anchors.json        # 面部位置定义
├── moves.json          # Gold Motion Library —— 动作的唯一真源
└── routines.json       # 时间线：只写「第几分几秒做哪个动作」
```

### 动作是资产，routine 只是时间线

Video Factory v0.2 §4/§9「一次动作资产，多处复用」。
一个动作在多个 routine 里出现是常态 —— Prototype A 里 GM-11 与 GM-18 各出现两次，
三套原型都用 GM-02。如果每处都内联一份定义，改了一处忘了另一处，
两个地方就变成了两个不同的动作，而且没人会发现。

所以 `routines.json` 里的一步长这样：

```jsonc
{ "move": "GM-08", "durationSeconds": 20, "roleNote": "脸颊静态" }
```

只有 `durationSeconds` 与 `side` 可以覆盖（同一动作在不同原型里时长确实不同），
其余一律来自动作库。

放在 Core package 而不是 App target，是为了让单元测试加载的就是**线上那一份**，
不会出现「测试用一份、发布用另一份」。

改完在任意机器上跑：

```bash
python tools/validate_content.py
```

`errors=0` 才算过。改了 `anchors.json` 还要跑：

```bash
python tools/golden/generate_golden.py
```

想看每一段在脸上到底画出了什么（哪一段是空白、左右是否对称）：

```bash
python tools/simulate_routine.py
```

---

## 审核状态：三档

每个 routine / step / anchor 都有 `reviewStatus`：

| 值 | 含义 |
| --- | --- |
| `mock_unreviewed` | 占位测试数据。UI 上会显示 MOCK 角标 |
| `draft` | 已写好但未经专业审核。**当前 20 个动作与 27 个位置全部是这一档** |
| `expert_reviewed` | 已通过 Expert Gate，可发布 |

**只有全部为 `expert_reviewed` 时，`content_meta.json` 才可以标 `expert_reviewed`。**
单元测试 `testShippedContentIsFlaggedAsUnreviewed` 会在 M1 阶段断言内容仍是未审核状态 ——
正式内容替换完成后，记得同时更新那条测试。

---

## anchors.json：面部位置

### 核心原则

**位置必须相对用户自己的 landmark 与脸部比例计算，不能写固定像素**（规格 §8）。

坐标系（`FaceFrame`）：

- 原点 = 双眼中点
- `dx > 0` 朝**用户自己的右侧**
- `dy > 0` 朝**脸的下方**
- 单位 = **瞳距**（两眼中心的距离）

用瞳距做单位，同一份定义在大脸、小脸、离得远、离得近、歪着头时都成立。
这条性质由 `tools/golden/generate_golden.py` 自动验证。

### 只写一侧

带 `_left` 后缀、`side: "left"` 的 anchor，系统会**自动生成** `_right` 版本
（landmark 换成对侧，`dx` 取反）。**不要手写右侧** —— 两份定义迟早会漂移。

中线位置用 `side: "none"`，id 不带侧后缀（如 `glabella_center`）。

### 五种规则

```jsonc
// 1. 直接取一个语义 landmark
{ "type": "landmark", "id": "leftBrowInner" }

// 2. 两点中点
{ "type": "midpoint",
  "a": { "type": "landmark", "id": "leftBrowInner" },
  "b": { "type": "landmark", "id": "rightBrowInner" } }

// 3. 两点之间按比例插值，t ∈ [0,1]
{ "type": "lerp",
  "from": { "type": "landmark", "id": "leftEyeCenter" },
  "to":   { "type": "landmark", "id": "leftMouthCorner" },
  "t": 0.55 }

// 4. 多点加权平均（权重自动归一化）
{ "type": "weighted", "items": [
    { "landmark": "leftJawAngle", "weight": 0.7 },
    { "landmark": "chinCenter",   "weight": 0.3 } ] }

// 5. 在上述任一结果上做偏移，单位 = 瞳距
{ "type": "offset",
  "base": { "type": "landmark", "id": "leftEyeOuter" },
  "dx": -0.30, "dy": -0.08 }
```

规则可以任意嵌套。

### 可用的语义 landmark

只能用这些名字（定义在 `SemanticLandmark.swift`）：

```
眼   leftEyeOuter/Inner/Upper/Lower/Center   right 同
眉   leftBrowInner/Outer/Peak                right 同
     glabella
鼻   noseBridgeTop  noseBridgeMid  noseTip  subnasale
     leftNoseAla  rightNoseAla
口   leftMouthCorner  rightMouthCorner  upperLipCenter  lowerLipCenter
轮廓 chinCenter  leftJawAngle  rightJawAngle
     leftCheekbone  rightCheekbone  leftTemple  rightTemple  foreheadCenter
```

> ⚠️ 不是每个 provider 都能提供全部 landmark。
> 用了 provider 不支持的点，那个 anchor 会静默解析失败（脸上什么都不显示）。
> **在 App 里 Settings → Developer → Provider / 内容诊断 可以看到覆盖情况。**
> `cheekbone` / `temple` / `foreheadCenter` 目前**没有** provider 直接提供 ——
> 需要用 `offset` 从眼角、眉毛这类可靠点推导出来。

### 其他字段

| 字段 | 含义 |
| --- | --- |
| `toleranceRadius` | 容差半径（瞳距）。表达「大概这一带」，不是「必须精确命中」。会画成容差圈 |
| `poseConstraints` | 超出这个转头角度就认为该位置不可靠，overlay 会降级 |
| `confidenceThreshold` | 低于此置信度不显示 |
| `safetyNote` | 安全提示。眼周、颈部、按压类**必须**填 |
| `evidenceRef` | 依据来源。专业审核时填 |

---

## moves.json：Gold Motion Library

动作的唯一真源。每条对应专业文档里的一个动作（当前是 Sprint 3 v0.3 的 GM-01…GM-20）。

```jsonc
{
  "id": "GM-08",
  "title": "Happy Cheeks Sculpting",      // 用户看到的英文
  "shortCue": "Smile, tuck lips, hold",
  "voiceCue": "...",
  "safetyNote": "...",                     // ⚠️ 这是翻译，见下

  "region": "cheek",                       // 覆盖度检查与主题匹配
  "defaultDurationSeconds": 20,
  "side": "both",
  "intensity": "light",                    // none|veryLight|light|lightToModerate
  "requiresTool": "none",                  // none|facialRoller|guaSha
  "evidenceLevel": "randomisedTrial",      // 只用于排序与风险判断，不得对外表述
  "allowedRoutineTypes": ["morning", "evening", "quick"],

  "movement": { /* 见下一节，与 AR / Coach 共用 */ },

  "source": {                              // 逐字保留的中文原文，不翻译
    "documentRef": "Sprint 3 v0.3 · GM-08",
    "titleZh": "...", "startingPositionZh": "...", "instructionZh": "...",
    "durationZh": "...", "intensityZh": "...", "stopSignalsZh": "...",
    "evidenceZh": "...", "usageZh": "...", "researchNoteZh": "..."
  },
  "reviewStatus": "draft",
  "version": "0.3.0-draft"
}
```

### 为什么中英并存

**用户看英文字段，Expert Gate 审 `source.*` 里的中文原文。**

安全相关的措辞（禁忌、停止信号、力度）经翻译一定会引入偏差，
而那恰恰是专家要审的东西。所以两份并存，谁也不覆盖谁。
校验器强制：**填了英文 `safetyNote` 就必须有 `source.stopSignalsZh`**，
否则专家无从对照复核。

### 硬性约束

| 约束 | 依据 | 违反后果 |
| --- | --- | --- |
| 需要工具的动作不得 `allowedRoutineTypes` 含 `morning` | Sprint 3 §9：Gua Sha / Roller 不得作为免费核心操的必要条件 | error |
| 需要工具的动作不得出现在 morning routine 里 | 同上（双重拦截） | error |
| routine 类型必须在动作的 `allowedRoutineTypes` 里 | Video Factory §4 | error |
| `allowedRoutineTypes` 不得为空 | 否则这个动作永远用不上 | error |
| 必须有 `source.documentRef` 与 `source.titleZh` | 无法溯源就无法审 | error |

### 尚未被使用的动作

校验器会警告「N 个动作尚未被任何 routine 使用」。
**这是提醒不是缺陷** —— Sprint 3 §11 把 Evening 5-minute 与 Quick Rituals 标为
「随后设计」，剩余动作正是留给它们的。

---

## routines.json：时间线

```jsonc
{
  "id": "morning_prototype_b",
  "title": "Morning Ritual",
  "type": "morning",            // morning | evening | quick
  "isPremium": false,
  "reviewStatus": "draft",
  "steps": [
    { "move": "GM-01", "roleNote": "准备" },
    { "move": "GM-08", "durationSeconds": 20, "roleNote": "脸颊静态" }
  ]
}
```

step id 由系统合成为 `<routineID>_<两位序号>_<moveID>` ——
同一动作在一个 routine 里重复出现时不会撞 id。

### 时长约定

- Morning Core 约 180 秒，Evening Core 约 300 秒（校验器会检查，偏差 >30s 报 warning）
- 单个动作建议不超过 90 秒（超过报 warning，规格 §4「每个动作短」）
- `side: "leftThenRight"` 的动作会被**平分成两段**：36 秒 = 左 18 秒 + 右 18 秒

### side 的取值

| 值 | 行为 |
| --- | --- |
| `none` | 中线动作，不分左右 |
| `left` / `right` | 只做一侧 |
| `both` | 两侧同时显示 |
| `leftThenRight` | 自动展开成先左后右两段，语音会提示换边 |

### movement：AR 与 Coach 的共同真源（写在 moves.json 里）

**同一份 `movement` 同时驱动 Coach 示范与脸上的 AR 路线**（规格 §4「一个动作真源」）。
所以不会出现「老师往上、脸上路线往下」这种矛盾。

```jsonc
"movement": {
  "startAnchor": "cheek_mid_left",   // 只写 _left，播放时按当前侧自动改写
  "endAnchor": "temple_left",
  "pathType": "curve",               // line|curve|arc|circle|press|hold|expression|tap
  "pathGeometry": {
    // 控制点表达在 start→end 的局部框架里：
    //   along        沿轴向的比例（0=起点，1=终点）
    //   perpendicular 垂直偏移，单位=瞳距，正值朝脸的下方
    "controlOffsets": [{ "along": 0.5, "perpendicular": -0.22 }]
  },
  "direction": "upward",             // 只影响文案与箭头样式，不影响路径几何
  "gestureHint": "twoFinger",        // singleFinger|twoFinger|fingertips|palm|tool
  "tempo": 15,                       // 每分钟循环次数 → 移动光点的节奏
  "repetitions": 4,
  "occlusionPolicy": "continueGuidance",
  "trackingSupport": "guidanceOnly",
  "version": "1.0.0"
}
```

### pathType 各自需要什么

| pathType | 必需 | 可选 |
| --- | --- | --- |
| `line` | start + end | — |
| `curve` | start + end | `controlOffsets`（1 个=二次贝塞尔，2 个=三次） |
| `arc` | start + end | `controlOffsets[0].perpendicular` 作为弧高 |
| `circle` | start（作圆心） | `radius`（瞳距）、`sweepDegrees`、`clockwise` |
| `press` / `hold` | start | `holdSeconds` |
| `expression` | 无 | `focusAnchors` |
| `tap` | `focusAnchors` 或 start | — |

#### expression：表情肌动作

**没有手部接触，所以脸上没有轨迹可画。**
GM-01 呼吸、GM-09 鼓气、GM-10 元音、GM-16 噘嘴都是这类。

AR 模式下这一段退化为「提示 + 计时」：填了 `focusAnchors` 就柔和地点亮那几片区域，
不填就只有语音与倒计时 —— **这不是错误**，是这类动作本来的样子。

填了 `startAnchor` / `endAnchor` / `gestureHint` 会报 warning：
表情动作不用手，画 ● 起点会让人以为要用手指去碰那个位置。

#### tap：跨区域轻拍

GM-15 全脸轻拍跨额头、双颊、下颌外侧，没有单一轨迹。
用 `focusAnchors` 列出要点到的区域，AR 会按顺序轮流点亮 ——
全部同时闪看上去像报错。

```jsonc
"movement": {
  "pathType": "tap",
  "focusAnchors": ["forehead_center", "cheek_mid_left", "cheek_mid_right",
                   "jaw_angle_left", "jaw_angle_right"],
  "gestureHint": "fingertips", "tempo": 120, "repetitions": 20
}
```

### occlusionPolicy

手遮住脸是**正常的按摩动作**，不是错误。三种处理：

| 值 | 行为 |
| --- | --- |
| `continueGuidance` | overlay 冻结在最后可信位置，计时与语音继续（**推荐默认**） |
| `freezeOverlay` | 同上但更暗 |
| `pauseTracking` | 完全隐藏 overlay |

**任何一种都不会中断 routine**（规格 §4：识别失败不得阻塞 routine）。

### trackingSupport

| 值 | 含义 |
| --- | --- |
| `guidanceOnly` | 只做导航，不判断对错。**MVP 阶段一律用这个** |
| `observableCorrectionExperimental` | 声称支持实时纠错 |

⚠️ 规格 §10：只有逐个动作验证达标后才可能升级。
校验器会对 `observableCorrectionExperimental` 报 warning，
单元测试 `testNoMovementClaimsRealtimeCorrection` 会直接失败。

---

## 工程侧不会替你决定的事

规格 §20 划的线，这里再说一遍：

- 具体做哪些动作、什么顺序、各多久
- 穴位的位置与含义
- 任何疗效、护理效果的表述
- 眼周 / 颈部 / 按压力度的安全限制与禁忌
- 品牌文案与医学免责声明

代码里所有相关字段（`safetyNote`、`evidenceRef`、`reviewStatus`）都是空着等你填的。

---

## 替换流程建议

1. **Expert Gate 先审动作库**（`moves.json` 的 20 条）。

   给专家的材料一条命令就能生成：

   ```bash
   python tools/export_review_sheet.py     # 或 make review
   ```

   得到 `build/expert_review_sheet.html` —— 单文件、无外部依赖，
   直接发邮件或用浏览器打印成 PDF。每条动作是**中文原文在上、英文译文在下**，
   右上角有「通过 / 需修改 / 不通过」，下面留了批注格。

   专业人员既不会读 JSON，也没装我们的 TestFlight ——
   这一步不解决，Expert Gate 就一直卡着。

   （开发自己看的话，App 里 Settings → Developer → Debug → Gold Motion Library
   也有同一份数据。）
2. 顺带审这些动作用到的 `anchors.json` 位置定义（当前全是几何草案）。
3. 真机上跑一遍，确认位置与路线在几个不同的人脸上都合适。
4. 三套 Morning 原型交叉体验后选定（Sprint 3 §7）。
5. 补 Evening 5-minute 与 Quick Rituals 的时间表 —— 只需在 `routines.json` 加条目。
6. 审过的条目 `reviewStatus` 改成 `expert_reviewed`。
7. 全部通过后，`content_meta.json` 的 `reviewStatus` 改成 `expert_reviewed`，`contentVersion` 升版本。
8. 更新这两条测试（它们当前断言内容**必须**未审核）：
   `testShippedContentIsFlaggedAsUnreviewed`、`testEveryGoldMoveIsStillAwaitingExpertGate`。
9. `python tools/validate_content.py` + `python tools/golden/generate_golden.py` + `python tools/simulate_routine.py`
10. 提交
