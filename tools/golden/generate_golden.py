#!/usr/bin/env python3
"""Golden vector 生成器 —— FaceFrame / AnchorResolver / PathSampler 的参考实现。

为什么需要它：
  这台开发机没有 Swift 工具链，几何层的正确性无法靠 `swift test` 验证。
  这个脚本用完全独立的实现算出同一批期望值，Swift 测试再断言自己算出来的一致。
  两边同时算错同一个地方的概率远低于单边实现。

它还直接验证 M1 里程碑真正关心的性质：
  **同一份 anchors.json，在不同脸型（尺度）、不同位置、不同头部倾斜下，
   目标位置在脸部局部坐标系里必须完全不变。**

用法:
    python tools/golden/generate_golden.py            # 生成
    python tools/golden/generate_golden.py --check    # 只校验已提交的文件是否最新（CI 用）
输出:
    Packages/FaceRitualCore/Tests/FaceRitualCoreTests/Fixtures/golden_vectors.json
"""

from __future__ import annotations

import json
import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
CONTENT_DIR = ROOT / "Packages" / "FaceRitualCore" / "Sources" / "FaceRitualCore" / "Resources"
FIXTURE_DIR = ROOT / "Packages" / "FaceRitualCore" / "Tests" / "FaceRitualCoreTests" / "Fixtures"

# ---------------------------------------------------------------------------
# 合成测试脸
# ---------------------------------------------------------------------------
# 单位 = 瞳距，原点 = 双眼中点，+x 朝用户的右侧，+y 朝脸的下方。
# 这是一张用于几何自测的**合成**脸，比例只求大致合理，
# 不代表任何真实人群的解剖学测量数据。
CANONICAL_FACE = {
    "leftEyeCenter": (-0.50, 0.00),
    "rightEyeCenter": (0.50, 0.00),
    "leftEyeOuter": (-0.78, 0.00),
    "rightEyeOuter": (0.78, 0.00),
    "leftEyeInner": (-0.25, 0.02),
    "rightEyeInner": (0.25, 0.02),
    "leftEyeUpper": (-0.50, -0.12),
    "rightEyeUpper": (0.50, -0.12),
    "leftEyeLower": (-0.50, 0.10),
    "rightEyeLower": (0.50, 0.10),
    "leftBrowInner": (-0.22, -0.32),
    "rightBrowInner": (0.22, -0.32),
    "leftBrowOuter": (-0.80, -0.32),
    "rightBrowOuter": (0.80, -0.32),
    "leftBrowPeak": (-0.52, -0.40),
    "rightBrowPeak": (0.52, -0.40),
    "glabella": (0.00, -0.28),
    "noseBridgeTop": (0.00, -0.10),
    "noseBridgeMid": (0.00, 0.25),
    "noseTip": (0.00, 0.62),
    "subnasale": (0.00, 0.78),
    "leftNoseAla": (-0.22, 0.70),
    "rightNoseAla": (0.22, 0.70),
    "mouthLeftCorner": (-0.42, 1.05),
    "mouthRightCorner": (0.42, 1.05),
    "upperLipCenter": (0.00, 0.95),
    "lowerLipCenter": (0.00, 1.15),
    "chinCenter": (0.00, 1.72),
    "leftJawAngle": (-0.92, 1.25),
    "rightJawAngle": (0.92, 1.25),
    "leftCheekbone": (-0.78, 0.42),
    "rightCheekbone": (0.78, 0.42),
    "leftTemple": (-1.05, -0.18),
    "rightTemple": (1.05, -0.18),
    "foreheadCenter": (0.00, -0.72),
}

# (名字, 双眼中点在视图中的位置, 瞳距像素, roll 角度)
# 覆盖：近距离 / 远距离 / 画面偏移 / 头部左右倾斜。
TEST_CASES = [
    ("reference", (200.0, 300.0), 100.0, 0.0),
    ("far_small_face", (200.0, 300.0), 42.0, 0.0),
    ("near_large_face", (200.0, 300.0), 168.0, 0.0),
    ("offcenter", (95.0, 470.0), 100.0, 0.0),
    ("roll_plus_18", (200.0, 300.0), 100.0, 18.0),
    ("roll_minus_25", (210.0, 320.0), 88.0, -25.0),
]


def make_landmarks(center, interocular, roll_degrees):
    """把合成脸变换到视图坐标。"""
    angle = math.radians(roll_degrees)
    cos_a, sin_a = math.cos(angle), math.sin(angle)
    result = {}
    for name, (lx, ly) in CANONICAL_FACE.items():
        sx, sy = lx * interocular, ly * interocular
        result[name] = (
            center[0] + sx * cos_a - sy * sin_a,
            center[1] + sx * sin_a + sy * cos_a,
        )
    return result


# ---------------------------------------------------------------------------
# FaceFrame（对应 FaceFrame.swift）
# ---------------------------------------------------------------------------
class FaceFrame:
    def __init__(self, landmarks):
        left = landmarks["leftEyeCenter"]
        right = landmarks["rightEyeCenter"]
        dx, dy = right[0] - left[0], right[1] - left[1]
        self.scale = math.hypot(dx, dy)
        if self.scale < 12:
            raise ValueError("瞳距过小，无法建立 FaceFrame")
        self.x_axis = (dx / self.scale, dy / self.scale)
        # 屏幕坐标（y 向下）顺时针旋转 90°
        self.y_axis = (-self.x_axis[1], self.x_axis[0])
        self.origin = ((left[0] + right[0]) / 2, (left[1] + right[1]) / 2)

    def to_view(self, local):
        return (
            self.origin[0] + self.x_axis[0] * local[0] * self.scale + self.y_axis[0] * local[1] * self.scale,
            self.origin[1] + self.x_axis[1] * local[0] * self.scale + self.y_axis[1] * local[1] * self.scale,
        )

    def to_local(self, view):
        dx, dy = view[0] - self.origin[0], view[1] - self.origin[1]
        return (
            (dx * self.x_axis[0] + dy * self.x_axis[1]) / self.scale,
            (dx * self.y_axis[0] + dy * self.y_axis[1]) / self.scale,
        )


# ---------------------------------------------------------------------------
# AnchorResolver（对应 FaceAnchorResolver.swift）
# ---------------------------------------------------------------------------
def evaluate_rule(rule, landmarks, frame):
    kind = rule["type"]
    if kind == "landmark":
        return landmarks[rule["id"]]
    if kind == "midpoint":
        a = evaluate_rule(rule["a"], landmarks, frame)
        b = evaluate_rule(rule["b"], landmarks, frame)
        return ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
    if kind == "lerp":
        a = evaluate_rule(rule["from"], landmarks, frame)
        b = evaluate_rule(rule["to"], landmarks, frame)
        t = min(max(rule["t"], 0.0), 1.0)
        return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
    if kind == "weighted":
        items = rule["items"]
        total = sum(i["weight"] for i in items)
        x = sum(landmarks[i["landmark"]][0] * (i["weight"] / total) for i in items)
        y = sum(landmarks[i["landmark"]][1] * (i["weight"] / total) for i in items)
        return (x, y)
    if kind == "offset":
        base = evaluate_rule(rule["base"], landmarks, frame)
        dx, dy = rule.get("dx", 0.0), rule.get("dy", 0.0)
        return (
            base[0] + (frame.x_axis[0] * dx + frame.y_axis[0] * dy) * frame.scale,
            base[1] + (frame.x_axis[1] * dx + frame.y_axis[1] * dy) * frame.scale,
        )
    raise ValueError(f"未知规则 type: {kind}")


def mirror_landmark(name):
    if name.startswith("left"):
        return "right" + name[4:]
    if name.startswith("right"):
        return "left" + name[5:]
    return name


def mirror_rule(rule):
    kind = rule["type"]
    if kind == "landmark":
        return {"type": "landmark", "id": mirror_landmark(rule["id"])}
    if kind == "midpoint":
        return {"type": "midpoint", "a": mirror_rule(rule["a"]), "b": mirror_rule(rule["b"])}
    if kind == "lerp":
        return {"type": "lerp", "from": mirror_rule(rule["from"]), "to": mirror_rule(rule["to"]), "t": rule["t"]}
    if kind == "weighted":
        return {
            "type": "weighted",
            "items": [{"landmark": mirror_landmark(i["landmark"]), "weight": i["weight"]} for i in rule["items"]],
        }
    if kind == "offset":
        return {"type": "offset", "base": mirror_rule(rule["base"]), "dx": -rule.get("dx", 0.0), "dy": rule.get("dy", 0.0)}
    raise ValueError(f"未知规则 type: {kind}")


def mirror_id(raw):
    if raw.endswith("_left"):
        return raw[:-5] + "_right"
    if raw.endswith("_right"):
        return raw[:-6] + "_left"
    return raw


def load_anchor_table():
    doc = json.loads((CONTENT_DIR / "anchors.json").read_text(encoding="utf-8"))
    table = {}
    for anchor in doc["anchors"]:
        table[anchor["id"]] = anchor
        side = anchor.get("side", "none")
        if side in ("left", "right"):
            mid = mirror_id(anchor["id"])
            if mid != anchor["id"] and mid not in table:
                table[mid] = {
                    **anchor,
                    "id": mid,
                    "side": "right" if side == "left" else "left",
                    "rule": mirror_rule(anchor["rule"]),
                }
    return table


# ---------------------------------------------------------------------------
# PathSampler（对应 PathSampler.swift）
# ---------------------------------------------------------------------------
SAMPLE_COUNT = 72


def sample_line(a, b, count):
    return [(a[0] + (b[0] - a[0]) * i / (count - 1), a[1] + (b[1] - a[1]) * i / (count - 1)) for i in range(count)]


def quadratic(p0, p1, p2, t):
    mt = 1 - t
    return (
        mt * mt * p0[0] + 2 * mt * t * p1[0] + t * t * p2[0],
        mt * mt * p0[1] + 2 * mt * t * p1[1] + t * t * p2[1],
    )


def cubic(p0, p1, p2, p3, t):
    mt = 1 - t
    a, b, c, d = mt**3, 3 * mt * mt * t, 3 * mt * t * t, t**3
    return (
        a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0],
        a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1],
    )


def sample_curve(a, b, controls, count):
    ax, ay = b[0] - a[0], b[1] - a[1]
    length = math.hypot(ax, ay)
    if length < 1e-9 or not controls:
        return sample_line(a, b, count)
    ux, uy = ax / length, ay / length
    nx, ny = -uy, ux  # 顺时针 90°

    def control_point(offset):
        return (
            a[0] + ux * offset["along"] * length + nx * offset["perpendicular"],
            a[1] + uy * offset["along"] * length + ny * offset["perpendicular"],
        )

    if len(controls) == 1:
        c = control_point(controls[0])
        return [quadratic(a, c, b, i / (count - 1)) for i in range(count)]
    c1, c2 = control_point(controls[0]), control_point(controls[1])
    return [cubic(a, c1, c2, b, i / (count - 1)) for i in range(count)]


def circumcenter(a, b, c):
    d = 2 * (a[0] * (b[1] - c[1]) + b[0] * (c[1] - a[1]) + c[0] * (a[1] - b[1]))
    if abs(d) < 1e-9:
        return None
    sa = a[0] ** 2 + a[1] ** 2
    sb = b[0] ** 2 + b[1] ** 2
    sc = c[0] ** 2 + c[1] ** 2
    ux = (sa * (b[1] - c[1]) + sb * (c[1] - a[1]) + sc * (a[1] - b[1])) / d
    uy = (sa * (c[0] - b[0]) + sb * (a[0] - c[0]) + sc * (b[0] - a[0])) / d
    return (ux, uy)


def normalize_angle(angle):
    result = math.fmod(angle, 2 * math.pi)
    return result + 2 * math.pi if result < 0 else result


def sample_arc(a, b, sagitta, count):
    ax, ay = b[0] - a[0], b[1] - a[1]
    length = math.hypot(ax, ay)
    if length < 1e-9 or abs(sagitta) < 1e-6:
        return sample_line(a, b, count), None
    nx, ny = -ay / length, ax / length
    mid = ((a[0] + b[0]) / 2 + nx * sagitta, (a[1] + b[1]) / 2 + ny * sagitta)
    center = circumcenter(a, mid, b)
    if center is None:
        return sample_line(a, b, count), None
    radius = math.hypot(a[0] - center[0], a[1] - center[1])
    angle_a = math.atan2(a[1] - center[1], a[0] - center[0])
    angle_mid = math.atan2(mid[1] - center[1], mid[0] - center[0])
    angle_b = math.atan2(b[1] - center[1], b[0] - center[0])

    sweep = normalize_angle(angle_b - angle_a)
    sweep_to_mid = normalize_angle(angle_mid - angle_a)
    if sweep_to_mid > sweep:
        sweep -= 2 * math.pi

    points = []
    for i in range(count):
        angle = angle_a + sweep * (i / (count - 1))
        points.append((center[0] + math.cos(angle) * radius, center[1] + math.sin(angle) * radius))
    return points, center


def sample_circle(center, radius, sweep_degrees, clockwise, count):
    sweep = math.radians(sweep_degrees) * (1 if clockwise else -1)
    start_angle = -math.pi / 2
    return [
        (
            center[0] + math.cos(start_angle + sweep * (i / (count - 1))) * radius,
            center[1] + math.sin(start_angle + sweep * (i / (count - 1))) * radius,
        )
        for i in range(count)
    ]


def make_path(movement, start_local, end_local, frame):
    """全部在脸部局部坐标系计算，最后映射到视图坐标 —— 与 Swift 实现一致。"""
    path_type = movement.get("pathType", "line")
    geometry = movement.get("pathGeometry") or {}

    if path_type in ("press", "hold"):
        return {"kind": path_type, "points": [frame.to_view(start_local)], "center": None}

    if path_type == "line":
        pts = sample_line(start_local, end_local, SAMPLE_COUNT)
        return {"kind": "line", "points": [frame.to_view(p) for p in pts], "center": None}

    if path_type == "curve":
        pts = sample_curve(start_local, end_local, geometry.get("controlOffsets", []), SAMPLE_COUNT)
        return {"kind": "curve", "points": [frame.to_view(p) for p in pts], "center": None}

    if path_type == "arc":
        offsets = geometry.get("controlOffsets", [])
        sagitta = offsets[0]["perpendicular"] if offsets else 0.15
        pts, center = sample_arc(start_local, end_local, sagitta, SAMPLE_COUNT)
        return {
            "kind": "arc",
            "points": [frame.to_view(p) for p in pts],
            "center": frame.to_view(center) if center else None,
        }

    if path_type == "circle":
        pts = sample_circle(
            start_local,
            geometry.get("radius", 0.35),
            geometry.get("sweepDegrees", 360),
            geometry.get("clockwise", True),
            SAMPLE_COUNT,
        )
        return {
            "kind": "circle",
            "points": [frame.to_view(p) for p in pts],
            "center": frame.to_view(start_local),
        }

    raise ValueError(f"未知 pathType: {path_type}")


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
def round_point(p, digits=6):
    return [round(p[0], digits), round(p[1], digits)]


def main() -> int:
    anchors = load_anchor_table()
    routines_doc = json.loads((CONTENT_DIR / "routines.json").read_text(encoding="utf-8"))
    morning = next(r for r in routines_doc["routines"] if r["id"] == "morning_core")

    cases = []
    # anchor_id -> 局部坐标（用于跨变换的不变性检查）
    invariance: dict[str, list[tuple[str, tuple[float, float]]]] = {}

    for name, center, interocular, roll in TEST_CASES:
        landmarks = make_landmarks(center, interocular, roll)
        frame = FaceFrame(landmarks)

        resolved = {}
        for anchor_id in sorted(anchors):
            view = evaluate_rule(anchors[anchor_id]["rule"], landmarks, frame)
            local = frame.to_local(view)
            resolved[anchor_id] = {
                "view": round_point(view),
                "local": round_point(local),
                "toleranceRadiusPoints": round(anchors[anchor_id].get("toleranceRadius", 0.12) * frame.scale, 6),
            }
            invariance.setdefault(anchor_id, []).append((name, local))

        # 用 Morning Core 的每个 step 生成路径（左侧那一段）。
        paths = []
        for step in morning["steps"]:
            movement = step["movement"]
            start_id = movement.get("startAnchor")
            end_id = movement.get("endAnchor")
            if not start_id:
                continue
            start_local = frame.to_local(evaluate_rule(anchors[start_id]["rule"], landmarks, frame))
            end_local = (
                frame.to_local(evaluate_rule(anchors[end_id]["rule"], landmarks, frame)) if end_id else None
            )
            path = make_path(movement, start_local, end_local, frame)
            # 只存首/中/末三点，golden 文件不必臃肿，覆盖度已经够。
            pts = path["points"]
            paths.append({
                "stepID": step["id"],
                "kind": path["kind"],
                "pointCount": len(pts),
                "first": round_point(pts[0]),
                "middle": round_point(pts[len(pts) // 2]),
                "last": round_point(pts[-1]),
                "center": round_point(path["center"]) if path["center"] else None,
            })

        cases.append({
            "name": name,
            "eyeMidpoint": round_point(center),
            "interocularDistance": interocular,
            "rollDegrees": roll,
            "landmarks": {k: round_point(v) for k, v in sorted(landmarks.items())},
            "frame": {
                "origin": round_point(frame.origin),
                "xAxis": round_point(frame.x_axis),
                "yAxis": round_point(frame.y_axis),
                "scale": round(frame.scale, 6),
            },
            "anchors": resolved,
            "paths": paths,
        })

    # --- 不变性自检：这是 M1 真正要证明的性质 ---
    print("尺度 / 位置 / roll 不变性检查（脸部局部坐标）:")
    max_drift = 0.0
    for anchor_id, samples in sorted(invariance.items()):
        _, reference = samples[0]
        worst = 0.0
        for _, local in samples[1:]:
            worst = max(worst, math.hypot(local[0] - reference[0], local[1] - reference[1]))
        max_drift = max(max_drift, worst)
        status = "OK " if worst < 1e-9 else "!! "
        print(f"  {status}{anchor_id:<22} 最大漂移 = {worst:.3e} 瞳距")

    if max_drift >= 1e-9:
        print(f"\n失败：anchor 在不同尺度/位置/倾斜下漂移了（最大 {max_drift:.3e}）")
        return 1
    print(f"\n全部 anchor 在 {len(TEST_CASES)} 种变换下局部坐标完全一致（最大漂移 {max_drift:.3e}）")

    FIXTURE_DIR.mkdir(parents=True, exist_ok=True)
    output = FIXTURE_DIR / "golden_vectors.json"
    payload = json.dumps(
        {
            "_comment": "由 tools/golden/generate_golden.py 生成。请勿手工编辑。"
                        "Swift 测试断言自己的 FaceFrame / AnchorResolver / PathSampler 与这里一致。",
            "generator": "tools/golden/generate_golden.py",
            "sampleCount": SAMPLE_COUNT,
            "cases": cases,
        },
        ensure_ascii=False,
        indent=2,
    )

    # --check：CI 用。防止改了 anchors.json 却忘了重新生成 golden，
    # 那会让 Swift 测试断言一份过期的期望值 —— 比没有测试更糟。
    if "--check" in sys.argv:
        if output.exists() is False:
            print(f"失败：{output.relative_to(ROOT)} 不存在。请运行 make golden。")
            return 1
        if output.read_text(encoding="utf-8") != payload:
            print(f"失败：{output.relative_to(ROOT)} 与当前内容不一致。")
            print("      anchors.json 或采样逻辑改过了，请运行 make golden 并提交结果。")
            return 1
        print(f"{output.relative_to(ROOT)} 已是最新")
        return 0

    output.write_text(payload, encoding="utf-8")
    print(f"已写入 {output.relative_to(ROOT)}（{len(cases)} 个用例，{output.stat().st_size} 字节）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
