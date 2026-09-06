# 文案评审清单

> 给 Owner 与法务。
> 这四条是 `AppCopy.swift` 里标 ⚠️ 的条目，**我拟了草稿，但需要你确认后才算数**。
>
> 我不是律师。下面每条都写清了「为什么这么措辞」和「你需要判断什么」——
> 你要改的话，直接改 `App/FaceRitual/Features/Components/AppCopy.swift`，
> 不需要动任何视图代码。

---

## 拟稿时守的三条线

规格里已经写死的边界，草稿都没有越过：

1. **只说「不是什么」，不说「有什么用」。**
   规格 §4 / §13 禁止任何功效、抗衰、穴位疗效或「年轻 X 岁」类表述。
   所以全部文案里没有一句说做了会怎样。

2. **不写具体禁忌。**
   哪种皮肤状况不能做、按多大力、每个动作的安全限制 ——
   规格 §20 明确这是 Owner + 专业人员的事。草稿只做「有疑问就去问专业人士」的转介。

3. **提到眼周与颈部，是因为规格 §14 自己点了这两处需要安全限制。**
   草稿只说它们是敏感区域（解剖学事实），没有规定手法。

---

## 1. 医学免责声明

出现在：Settings 页脚、Paywall 页脚、About & Safety 整页。

### 短版（页脚）

> Face Ritual is a self-care routine guide, not a medical service.
> It doesn't diagnose or treat anything, and makes no promises about how your face will look.

### 长版（About & Safety 页）

> Face Ritual guides you through short facial care routines. It is not a medical device and does not provide medical advice.
>
> The app does not diagnose, treat, cure, or prevent any condition, and makes no claim about changes to your appearance.
>
> Use a light touch, and stop if anything hurts. The skin around the eyes and the front of the neck are sensitive areas.
>
> If you have a skin or health condition, have recently had an injury or procedure on your face, or are unsure whether these movements are right for you, check with a qualified professional before you start.
>
> Face Ritual is not a substitute for professional care.

### 为什么做了短/长两版

免责声明缩成页脚一行小字，既没人会读，也保护不了任何人。
所以短版只承担「随处可见的提醒」，完整内容放进 About & Safety 页面（Settings 里可进）。

### 需要你判断

- [ ] 这个保护强度够不够？不同司法辖区对健康类 App 的要求不一样。
- [ ] 「Use a light touch, and stop if anything hurts」——
      这是常识性安全提示还是已经算「指导」？如果法务觉得越界，删掉即可，
      逐动作的安全说明本来就要走 `safetyNote` 字段由专业人员填。
- [ ] 要不要在首次启动时强制展示一次并要求确认？
      **我没有加**，因为规格 §4 要求「打开后尽快进入练习，不做长问卷」——
      加一道确认墙与那条原则直接冲突。这个取舍你来定。

---

## 2. Watch & Breathe 免责

出现在：Watch & Breathe 模式页底部。

> **Watching isn't the same as doing.**
> Following the path with your eyes is a way to learn it — and to take a slow minute for yourself.

### 措辞逻辑

规格 §6.3 划了两条红线：不得宣称「看了等于做了」，不得宣称获得实际按摩的机械刺激效果。

- **第一句必须是无歧义的否定，且放在最前面** —— 用户可能只读第一行。
- 后半句给出这个模式真正的价值（学路线 + 放松片刻），
  对应规格自己的定位 ritual preview / guided awareness / visual relaxation。
  不这么写，整段就只剩劝退，用户会觉得这个功能没意义。

### 需要你判断

- [ ] 这个模式在规格里是「实验性」的。要不要在 MVP 首发就对用户开放？
      现在是开放的（免费用户也能用）。
- [ ] 措辞**不要往「等同」方向松动**。如果营销侧将来想改这句，
      请把这份文档一起给他们看。

---

## 3. 订阅披露

这一条我改了做法。原本的 ⚠️ 是「价格占位提示」，但真正卡上架的不是那个。

### 当前构建（占位）

> Pricing here is a placeholder for testing. Final pricing, the annual plan and subscription terms are set before launch.

### 上线必备（App Store 审核指南 3.1.2）

Paywall 上**必须**同时具备下面全部，少一项就会被拒：

| 要求 | 状态 |
| --- | --- |
| 订阅名称 | ✅ 已有（StoreKit 返回） |
| 时长与周期 | ✅ 已有（StoreKit 返回） |
| 价格 | ✅ 已有（StoreKit 返回，不写死） |
| 自动续订说明 | ✅ 已拟（见下） |
| **可点击的 Terms of Use (EULA) 链接** | ✅ 用 Apple 标准 EULA，已接进代码 |
| **可点击的 Privacy Policy 链接** | ❌ **缺 URL** —— 草稿已写好，等发布 |

自动续订说明草稿（价格与周期由 StoreKit 填入）：

> {price} per {period}, billed to your Apple ID at confirmation of purchase.
>
> The subscription renews automatically unless you turn off auto-renew at least 24 hours before the end of the current period. Your account is charged for renewal within 24 hours before the period ends.
>
> You can manage or cancel your subscription in your Apple ID account settings.

### 需要你提供

- [x] ~~Terms of Use (EULA) 的 URL~~ —— 改用 Apple 标准 EULA，不必自己写，已接进代码
- [ ] **Privacy Policy 的 URL** —— 草稿已写好（`site/privacy.html`），
      发布方法见 `site/README.md`，拿到网址给我即可
- [x] ~~最终月费~~ $4.99（规格 §11 的工作价格，暂按此）
- [x] ~~年费~~ $29.99（Owner 2026-09-06 定）

填在 `App/FaceRitual/Features/Settings/SafetyView.swift` 的 `LegalLinks` 里。
在填之前，Debug 诊断页会显示「缺失（上架会被拒）」，Paywall 在 DEBUG 构建下也会红字提醒。

---

## 4. 摄像头说明

两处必须**语义一致** —— 系统弹窗与 App 内说法不一样，审核会当成误导。

### 系统权限弹窗（`project.yml` 的 `NSCameraUsageDescription`）

> AR Mirror uses the front camera to draw massage start points, end points and movement paths onto your own face. The camera runs only while AR Mirror is open. The video stays on your device — nothing is recorded, saved, or sent anywhere.

### App 内说明（权限被拒时）

> AR Mirror needs the front camera to draw the movement path on your own face.
> The video stays on your device — nothing is recorded or sent anywhere.
> You can also keep going with Coach mode, which never uses the camera.

### 「不离开设备」这句是经代码验证的事实

不是营销话术。我查过：

- 全工程**没有任何联网 API**（URLSession / URLRequest / Network 框架等一个都没有）
- 唯一的出网 import 是 StoreKit，只走 Apple 的支付通道，不经手摄像头或用户内容
- 唯一的写盘是本地练习记录 JSON

而且 `tools/check_architecture.py` 加了一条规则锁住这个前提：
**谁哪天加了网络请求，检查会直接失败，并指回这句文案** ——
要么去掉网络调用，要么先改承诺，但不允许两者不一致。

### 需要你判断

- [ ] 措辞是否需要法务调整（尤其「nothing is recorded, saved, or sent anywhere」这句强承诺）
- [ ] 要不要在请求系统权限**之前**加一个说明页？
      **我没有加**：用户是主动点了「AR Mirror」才触发的，上下文已经很清楚，
      而规格 §4 要求低摩擦。但摄像头拒绝一旦发生就很难挽回，
      而 AR Mirror 又是核心差异化 —— 这是个值得 A/B 的取舍，由你定。
- [ ] 若将来接入第三方 analytics SDK（规格 §19 的待决项），
      隐私政策与这段文案都要重新审 —— 那时「什么都不上传」就不再成立。

---

## 改完之后

```bash
make check
```

`用户面文案为英文` 与 `隐私承诺与代码一致` 两条规则会验证你的改动没有破坏约定。
