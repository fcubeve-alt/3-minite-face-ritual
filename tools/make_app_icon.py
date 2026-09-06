#!/usr/bin/env python3
"""生成 App 图标（1024×1024 PNG）。

**这是占位图标，不是最终品牌设计。**

存在的理由很实际：没有图标 App Store **根本提交不了**，
而品牌视觉是 Owner 的待决项（规格 §19）。空着会一直卡在提交那一步。
所以先给一个干净、能过审、随时可替换的版本 —— 拿到正式设计直接覆盖即可。

设计上刻意克制：
  - 不画脸。画脸的图标在这个品类里满大街都是，而且很容易显得像医美广告
  - 不写 "face3" 全名。1024 缩到 60px 之后字母会糊成一团
  - 用三条弧线表示「三分钟」这个核心承诺 —— 短、有节奏、每天重复
  - 纯色底 + 单色图形，缩到最小尺寸仍然认得出

用法:
    python tools/make_app_icon.py
输出:
    App/FaceRitual/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024.png
"""

from __future__ import annotations

import math
import pathlib
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("需要 Pillow：pip install Pillow")
    sys.exit(1)

ROOT = pathlib.Path(__file__).resolve().parents[1]
ICONSET = ROOT / "App" / "FaceRitual" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
SIZE = 1024

# 底色。偏暖的深色 —— 早晨用的东西，纯黑太硬，白底在主屏上会糊成一片。
BACKGROUND = (28, 27, 32)
STROKE = (242, 238, 232)


def draw_icon() -> Image.Image:
    # 4 倍超采样再缩回去 —— Pillow 的 arc 不做抗锯齿，直接画边缘会有锯齿。
    scale = 4
    size = SIZE * scale
    image = Image.new("RGB", (size, size), BACKGROUND)
    draw = ImageDraw.Draw(image)

    center = size / 2
    # 三条同心环，从内到外。半径与线宽都按比例走，缩放后仍然协调。
    radii = [0.19, 0.29, 0.39]
    width = int(size * 0.040)

    # 第一版把三个缺口都放在下方、中心加一个点 —— 结果读起来是 **WiFi 图标**。
    # 弧线朝上加底部一个点正是 wifi 的构图，这在手机主屏上是致命的误读。
    #
    # 改法：每个缺口绕圆周错开 120°，让三个环读作「一圈一圈」而不是「信号强度」；
    # 中心的点也去掉 —— 它正是 wifi 的发射源。
    gap = 46                       # 缺口张角
    for index, ratio in enumerate(radii):
        radius = size * ratio
        box = [center - radius, center - radius, center + radius, center + radius]
        gap_center = -90 + index * 120
        start = gap_center + gap / 2
        draw.arc(box, start=start, end=start + (360 - gap), fill=STROKE, width=width)

    return image.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> int:
    if not ICONSET.exists():
        print(f"找不到 {ICONSET.relative_to(ROOT)}")
        return 1

    icon = draw_icon()
    output = ICONSET / "icon_1024.png"
    # App Store 的图标**不能有 alpha 通道**，否则上传直接被拒。
    icon.convert("RGB").save(output, "PNG")

    contents = ICONSET / "Contents.json"
    contents.write_text(
        '{\n'
        '  "images" : [\n'
        '    {\n'
        '      "filename" : "icon_1024.png",\n'
        '      "idiom" : "universal",\n'
        '      "platform" : "ios",\n'
        '      "size" : "1024x1024"\n'
        '    }\n'
        '  ],\n'
        '  "info" : {\n'
        '    "author" : "xcode",\n'
        '    "version" : 1\n'
        '  }\n'
        '}\n',
        encoding="utf-8",
    )

    size_kb = output.stat().st_size / 1024
    print(f"已生成 {output.relative_to(ROOT)}（{SIZE}×{SIZE}，{size_kb:.0f} KB，无 alpha 通道）")
    print()
    print("⚠️ 这是**占位图标**，不是最终品牌设计。")
    print("   拿到正式设计后覆盖同名文件即可，Contents.json 不用改。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
