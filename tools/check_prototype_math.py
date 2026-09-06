#!/usr/bin/env python3
"""交叉验证浏览器原型的统计实现与 Swift / Python 参考实现是否一致。

存在的理由：漂移测量现在有三份实现 ——
  Swift  `StabilityMeter.swift`（真机 POC）
  JS     `prototype_template.html`（浏览器 POC，在 Windows 上就能跑）
  Python 这里的期望值（golden 的老路子）

三边必须算的是**同一套统计量**，否则浏览器上测出来的数和 iPhone 上测出来的
没法放在一起比 —— 而"能不能比"正是做这套测量的全部意义。

分位数尤其容易漂：取整下标 / 最近秩 / 线性插值三种写法在小样本下差别明显。

用法:
    python tools/check_prototype_math.py
没装 node 时跳过（退出码 0），并明确说明跳过了。
"""

from __future__ import annotations

import json
import math
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
PROTOTYPE = ROOT / "prototype" / "index.html"


# --- Python 参考实现（与 StabilityMeter.swift 的文档注释一致） ---
def percentile(values: list[float], q: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return 0.0
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * min(1.0, max(0.0, q))
    lower = math.floor(position)
    upper = min(len(ordered) - 1, lower + 1)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def reference(points: list[tuple[float, float]]) -> dict:
    cx = sum(p[0] for p in points) / len(points)
    cy = sum(p[1] for p in points) / len(points)
    deviations = [math.hypot(p[0] - cx, p[1] - cy) for p in points]
    steps = [
        math.hypot(points[i][0] - points[i - 1][0], points[i][1] - points[i - 1][1])
        for i in range(1, len(points))
    ]
    return {
        "centerX": cx,
        "driftRMS": math.sqrt(sum(d * d for d in deviations) / len(deviations)),
        "driftP95": percentile(deviations, 0.95),
        "driftMax": max(deviations),
        "jitterMedian": percentile(steps, 0.5),
        "jitterP95": percentile(steps, 0.95),
    }


CASES = {
    "线性斜坡 100 点": [(i * 0.001, 0.0) for i in range(100)],
    "±0.02 交替 50 点": [(0.04 if i % 2 else 0.0, 0.0) for i in range(50)],
    "常量点 200 帧": [(-0.31, 0.42) for _ in range(200)],
    "二维随机游走": [
        (math.sin(i * 0.37) * 0.03, math.cos(i * 0.21) * 0.02) for i in range(150)
    ],
}

TOLERANCE = 1e-9

RUNNER = """
import { StabilityMeter } from './meter.mjs';
import fs from 'fs';
const cases = JSON.parse(fs.readFileSync('./cases.json', 'utf8'));
const out = {};
for (const [name, points] of Object.entries(cases)) {
  const m = new StabilityMeter();
  for (const [x, y] of points) m.record({ x, y });
  out[name] = {
    centerX: m.center.x,
    driftRMS: m.driftRMS,
    driftP95: m.driftP95,
    driftMax: m.driftMax,
    jitterMedian: m.jitterMedian,
    jitterP95: m.jitterP95,
  };
}
fs.writeFileSync('./out.json', JSON.stringify(out));
"""


def extract_meter_source() -> str | None:
    if not PROTOTYPE.exists():
        return None
    html = PROTOTYPE.read_text(encoding="utf-8")
    blocks = re.findall(r"<script[^>]*>(.*?)</script>", html, re.S)
    if not blocks:
        return None
    body = max(blocks, key=len)
    start = body.find("function percentile(")
    end = body.find("// 与 POCRecorder.standardScenarios")
    if start < 0 or end < 0 or end <= start:
        return None
    return body[start:end] + "\nexport { percentile, StabilityMeter };\n"


def main() -> int:
    node = shutil.which("node")
    if node is None:
        print("未找到 node，跳过浏览器原型的数学交叉验证。")
        print("（这条检查不是可选的正确性来源 —— 只是它需要 node 才能跑。）")
        return 0

    source = extract_meter_source()
    if source is None:
        print("失败：在 prototype/index.html 里找不到 StabilityMeter 实现。")
        print("      原型可能没重新生成，或者那段代码被改名了。")
        print("      先跑 python tools/build_prototype.py。")
        return 1

    with tempfile.TemporaryDirectory() as tmp:
        work = pathlib.Path(tmp)
        (work / "meter.mjs").write_text(source, encoding="utf-8")
        (work / "cases.json").write_text(
            json.dumps({k: [list(p) for p in v] for k, v in CASES.items()}),
            encoding="utf-8",
        )
        (work / "run.mjs").write_text(RUNNER, encoding="utf-8")

        proc = subprocess.run(
            [node, "run.mjs"], cwd=work, capture_output=True, text=True, encoding="utf-8"
        )
        if proc.returncode != 0:
            print("失败：浏览器版实现跑不起来")
            print(proc.stderr)
            return 1

        actual = json.loads((work / "out.json").read_text(encoding="utf-8"))

    print("浏览器原型 vs Python 参考实现（漂移/抖动统计）\n")
    failures = 0
    for name, points in CASES.items():
        want = reference(points)
        got = actual.get(name)
        if got is None:
            print(f"  [缺失] {name}")
            failures += 1
            continue
        worst = 0.0
        for key, expected in want.items():
            worst = max(worst, abs(got[key] - expected))
        ok = worst < TOLERANCE
        if not ok:
            failures += 1
        print(f"  [{'OK' if ok else '不一致':>6}] {name:<20} 最大偏差 {worst:.2e}")
        if not ok:
            for key, expected in want.items():
                delta = abs(got[key] - expected)
                if delta >= TOLERANCE:
                    print(f"           {key}: 浏览器 {got[key]!r} vs 参考 {expected!r}")

    print()
    if failures:
        print(f"{failures} 个用例不一致 —— 浏览器与 iOS 的测量数据不可比。")
        return 1
    print(f"全部 {len(CASES)} 个用例一致（容差 {TOLERANCE:g}）。")
    print("Swift 侧由 DiagnosticsTests.swift 断言同一组期望值。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
