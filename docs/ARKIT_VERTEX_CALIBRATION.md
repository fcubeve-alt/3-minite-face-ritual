# ARKit 顶点索引标定

> 为什么这份文档存在：`ARFaceGeometry` 给的是 **1220 个无名顶点**，
> Apple 从未公布「哪个编号是左眼外眼角」。
> 网上流传的索引表来源不明、随 iOS 版本可能变化，而且**不同来源互相矛盾**。
>
> 我们的选择是：**不猜。**
> 在脸上把 ● 画到错误位置，比暂时不显示更糟 —— 它还会污染 POC 结论，
> 让人以为是 anchor 定义有问题，实际是索引表错了。

---

## 当前行为

- 未标定时 `ARKitFaceAlignmentProvider.isAvailable == false`
- App 自动回落到 Vision，并上报 `guidanceFallback` 事件
- Debug 页会显示原因

眼中心是例外：`leftEyeTransform` / `rightEyeTransform` 是 Apple **官方保证**的量，
不依赖任何顶点编号，所以已经在用了。也就是说，即使没有索引表，
ARKit provider 依然能提供正确的 `FaceFrame` 基准（双眼），只是缺其他语义点。

---

## 需要标定哪些点

只需要内容实际用到的那些。当前 `anchors.json` 用到：

| 语义 landmark | 用途 |
| --- | --- |
| `leftEyeCenter` / `rightEyeCenter` | ✅ 已有（eyeTransform，无需标定） |
| `noseTip` | FaceGeometry 必需项 |
| `chinCenter` | FaceGeometry 必需项 |
| `leftBrowInner` / `rightBrowInner` | glabella + brow anchor |
| `leftEyeOuter` / `rightEyeOuter` | temple anchor |
| `mouthLeftCorner` / `mouthRightCorner` | cheek anchor |
| `leftJawAngle` / `rightJawAngle` | jaw anchor |

**只有 9 个点需要标定**（眼中心已有）。这是刻意的：
第一阶段只建 3–5 个测试 anchor（规格 §8），不需要完整的 68 点语义表。

---

## 标定方法

### 方案 A：投影后取最近顶点（推荐）

写一个一次性的标定视图（`Features/Debug/` 下），流程：

1. 跑 `ARFaceTrackingConfiguration`，把全部 1220 顶点投影到屏幕并画成小点。
2. 屏幕上依次提示「请点击你的鼻尖」「请点击左眼外眼角」……
3. 用户点击后，找出屏幕距离最近的顶点，记下它的 index。
4. 全部标完后，导出成 JSON。

关键代码骨架：

```swift
func nearestVertexIndex(to tap: CGPoint, anchor: ARFaceAnchor, camera: ARCamera, viewportSize: CGSize) -> Int? {
    var best: (index: Int, distance: CGFloat)?
    for (index, vertex) in anchor.geometry.vertices.enumerated() {
        let world = anchor.transform * simd_float4(vertex, 1)
        let projected = camera.projectPoint(
            simd_float3(world.x, world.y, world.z),
            orientation: .portrait,
            viewportSize: viewportSize
        )
        let distance = hypot(projected.x - tap.x, projected.y - tap.y)
        if best == nil || distance < best!.distance {
            best = (index, distance)
        }
    }
    return best?.index
}
```

### 方案 B：从中性表情网格离线找

用 ARKit 导出一次中性表情的 1220 顶点（局部坐标），
在 Blender / MeshLab 里可视化，肉眼定位后记录编号。
一次做完，所有设备通用（同一 iOS 大版本内）。

---

## 输出格式

生成 `arkit_vertex_map.json`，放进 `App/FaceRitual/Resources/`：

```json
{
  "noseTip": 0,
  "chinCenter": 0,
  "leftEyeOuter": 0,
  "rightEyeOuter": 0,
  "leftBrowInner": 0,
  "rightBrowInner": 0,
  "mouthLeftCorner": 0,
  "mouthRightCorner": 0,
  "leftJawAngle": 0,
  "rightJawAngle": 0
}
```

键名必须是 `SemanticLandmark` 的 rawValue —— 未知名字会被 Debug 页报出来。

**左右一律是解剖学侧（用户自己的左右）。**
ARKit 的 `leftEyeTransform` 用的也是解剖学约定，与我们一致，
所以这里**不需要**像稠密模型那样做图像侧翻转。

---

## 验证

1. Settings → Developer → Provider 选 ARKit
2. 打开「显示 AR Debug 图层」
3. 绿点应当贴合对应五官；红蓝两条轴应当随歪头一起转
4. 遮住左半边脸，确认左侧 anchor 冻结而不是乱跳

标定完成后 `descriptor.canDriveGuidance` 会自动变为 true，provider 即可用。

---

## 值不值得做

建议**先跑完 Vision 的真机 POC 再决定**。

ARKit 的优势是真 3D，理论上 yaw/pitch 稳定性更好；
代价是需要 TrueDepth 机型 + 这份标定工作 + 更高功耗。

如果 Vision 在 `AR_POC_REPORT.md` §2C（头部姿态）和 §2D（跟脸漂移）两项上已经够用，
这份标定可以推迟到 M2 之后。
