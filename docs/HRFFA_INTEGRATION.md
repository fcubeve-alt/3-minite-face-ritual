# HRFFA CoreML 接入指南

> 目标：让 `HRFFAFaceAlignmentProvider` 从「已接线、待模型」变成「可用」。
> **App 侧代码不需要任何改动** —— 这正是 Provider Abstraction 的意义。

---

## 先说清楚一件事

规格 §22 已经写明：**产品壁垒不在「用了 HRFFA」这件事上。**
开源 face alignment 谁都能用。真正要积累的是 Facial Acupoint/Region Map、
Gold Movement Library、AR Motion Templates 和真实使用数据。

所以 HRFFA 在本工程里的定位是「一个可替换的 provider」，不是地基。
在拿到模型之前，**Vision provider 就是能跑的真实基线，AR POC 不会被模型卡住**。

建议顺序：**先用 Vision 跑完一轮真机 POC，再决定 HRFFA 是否值得投入。**
如果 Vision 的转头稳定性和跟脸漂移已经够用，多背一个模型就是纯成本。

---

## 步骤

### 1. 准备模型（需要 macOS + Python）

```bash
pip install coremltools torch
```

拿到 HRFFA（或任何同级稠密 face alignment 模型）的 PyTorch 权重后：

```python
import torch, coremltools as ct

model = load_your_hrffa_model()          # 你自己的加载代码
model.eval()

# 输入尺寸按模型实际要求填（常见 112 / 192 / 256）
example = torch.rand(1, 3, 256, 256)
traced = torch.jit.trace(model, example)

mlmodel = ct.convert(
    traced,
    inputs=[ct.ImageType(
        name="input",
        shape=example.shape,
        scale=1/255.0,               # 按模型的预处理填
        bias=[0, 0, 0],
        color_layout=ct.colorlayout.BGR,   # 与 CameraController 的 32BGRA 一致
    )],
    minimum_deployment_target=ct.target.iOS16,
    compute_precision=ct.precision.FLOAT16,   # 半精度，Neural Engine 更快
)
mlmodel.save("HRFFA.mlpackage")
```

### 2. 放进 App target

把 `HRFFA.mlpackage` 拖进 Xcode 的 `App/FaceRitual/Resources/`，
勾选 target `FaceRitual`。

> `.gitignore` 已排除 `*.mlpackage` —— 模型文件体积大，不进仓库。
> 团队协作时用 Git LFS 或内部分发。

### 3. 确认输出布局

`HRFFAFaceAlignmentProvider.inferLayout(from:)` 会自动识别：

| 输出 shape | 识别为 |
| --- | --- |
| 含 68 的维度，或展平 136 | `ibug68`（300W / iBUG 68 点） |
| 含 98 的维度，或展平 196 | `wflw98`（WFLW 98 点） |

其他点数（如 106 点的某些国产数据集）会被判为不可用，
需要在 `DenseLandmarkLayout` 里补一张映射表。补表时注意：

**表里的 left/right 一律是「图像侧」，不是解剖学侧。**
前置摄像头原始画面里，用户的解剖学右半边脸出现在图像左侧。
这条换算由 `DenseLandmarkLayout.anatomical(_:)` 统一处理，
所以你只需要照数据集的标注约定填，不要自己翻转。
（`DenseLandmarkLayoutTests` 会验证这一点。）

### 4. 确认坐标约定

`HRFFAFaceAlignmentProvider` 假设模型输出是**裁剪框内的归一化坐标，左上原点**：

```swift
let imagePoint = CGPoint(
    x: cropRect.origin.x + point.x * cropRect.width,
    y: cropRect.origin.y + (1 - point.y) * cropRect.height   // 翻回 Vision 的左下原点
)
```

如果你的模型输出的是**像素坐标**或**左下原点**，改这一段即可，其他都不用动。

验证方法：Settings → Developer → 打开「显示 AR Debug 图层」，
绿点应当整齐贴合五官。如果绿点上下颠倒或整体偏移，问题就在这一段。

### 5. 切换并横评

Settings → Developer → Face Alignment Provider → HRFFA (CoreML)。

按 `AR_POC_REPORT.md` §2 的表格，把 HRFFA 与 Vision 的实测数据填进同一张表对比。

---

## 排错

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| Debug 页显示「未找到 HRFFA.mlmodelc」 | 模型没加进 target | 检查 Xcode 的 Target Membership |
| 「输出点数无法识别」 | 布局不是 68/98 | 在 `DenseLandmarkLayout` 补表 |
| 绿点上下颠倒 | 原点约定不符 | 改步骤 4 的 y 换算 |
| 绿点左右颠倒 | 映射表把图像侧当成了解剖学侧 | 见步骤 3 的说明 |
| 绿点整体缩在一角 | 模型输出是像素而非归一化 | 除以裁剪框尺寸 |
| FPS 很低 | 计算单元回落到 CPU | 确认 `computePrecision=FLOAT16`；用 Instruments 的 Core ML 模板确认是否走了 ANE |
| 转头时点乱飞 | 裁剪余量不够，轮廓点被截断 | 调大 `expandedCropRect(margin:)` |
