#!/usr/bin/env python3
"""生成浏览器版 AR 概念验证原型。

为什么要有构建这一步：
    原型必须用**和 iOS 完全同一份**动作与位置内容，否则在原型上看到的结论
    不能迁移到产品上。直接 fetch JSON 在 file:// 下会被 CORS 拦掉，
    所以构建时把 JSON 注入进 HTML —— 生成的文件双击就能打开，无需起服务器。

用法:
    python tools/build_prototype.py
输出:
    prototype/index.html
"""

from __future__ import annotations

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTENT = ROOT / "Packages" / "FaceRitualCore" / "Sources" / "FaceRitualCore" / "Resources"
TEMPLATE = ROOT / "tools" / "prototype_template.html"
OUTPUT = ROOT / "prototype" / "index.html"


def load(name: str) -> dict:
    return json.loads((CONTENT / name).read_text(encoding="utf-8"))


def main() -> int:
    anchors = load("anchors.json")
    routines = load("routines.json")

    # 原型只需要这两份数据里真正用得上的部分，注释字段带着也无妨，保持原样最省心。
    template = TEMPLATE.read_text(encoding="utf-8")

    for marker, doc in (("/*__ANCHORS__*/", anchors), ("/*__ROUTINES__*/", routines)):
        if marker not in template:
            print(f"模板里找不到占位符 {marker}")
            return 1
        template = template.replace(marker, json.dumps(doc, ensure_ascii=False), 1)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(template, encoding="utf-8")

    anchor_count = len(anchors["anchors"])
    routine_count = len(routines["routines"])
    size_kb = OUTPUT.stat().st_size / 1024
    print(f"已生成 {OUTPUT.relative_to(ROOT)}")
    print(f"  注入 {anchor_count} 个 anchor（自动镜像后会更多）、{routine_count} 个 routine")
    print(f"  文件大小 {size_kb:.0f} KB")
    print()
    print("  打开方式（必须走 http，不能双击文件）：")
    print("      cd prototype && python -m http.server 8000")
    print("      然后用 Chrome 打开 http://127.0.0.1:8000")
    print("  file:// 下浏览器会拦掉 CDN 模块与摄像头权限，所以要起本地服务。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
