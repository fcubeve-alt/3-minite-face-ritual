#!/usr/bin/env python3
"""无头跑一遍完整 routine —— 验证 M1 闭环的渲染侧。

它填的是一个真实的空白：
  - validate_content.py 只看 JSON 结构对不对
  - generate_golden.py 只验几何数学对不对
  - 两者都**没有**回答：「播放时每一段是否真能在脸上画出东西？」

如果某个播放段解析不出 anchor，用户会盯着一张什么都没有的脸看 20 秒。
这种错误在 Mac 上编译得过、单元测试也不一定覆盖，只有上真机才发现。
这个脚本在任何机器上就能发现。

复刻的 Swift 行为：
  PlaybackPlan（leftThenRight 展开）→ FaceAnchorID.resolved(for:)
  → FaceAnchorResolver → PathSampler → 落点合理性检查

用法:
    python tools/simulate_routine.py            # 跑全部 routine
    python tools/simulate_routine.py morning_core
退出码 0 = 每一段都能正常渲染。
"""

from __future__ import annotations

import json
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent / "golden"))

# 直接复用 golden 生成器里的参考实现 —— 保证两边算的是同一套几何。
from generate_golden import (  # noqa: E402
    CANONICAL_FACE,
    FaceFrame,
    evaluate_rule,
    load_anchor_table,
    make_landmarks,
    make_path,
    mirror_id,
)

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTENT_DIR = ROOT / "Packages" / "FaceRitualCore" / "Sources" / "FaceRitualCore" / "Resources"

# 一张标准距离的正脸。瞳距 100px 相当于手机举在约 30cm 处。
FACE_CENTER = (200.0, 300.0)
INTEROCULAR = 100.0

issues: list[tuple[str, str, str]] = []


def error(where: str, message: str) -> None:
    issues.append(("error", where, message))


def warn(where: str, message: str) -> None:
    issues.append(("warning", where, message))


# ---------------------------------------------------------------------------
# PlaybackPlan（对应 PlaybackPlan.swift）
# ---------------------------------------------------------------------------
def build_segments(routine: dict) -> list[dict]:
    """把 steps 展开成播放段，leftThenRight 拆成两段。"""
    segments = []
    offset = 0.0
    for step_index, step in enumerate(routine["steps"]):
        side = step.get("side", "none")
        sides = ["left", "right"] if side == "leftThenRight" else [side]
        per_segment = step["durationSeconds"] / len(sides)
        for segment_index, resolved_side in enumerate(sides):
            segments.append({
                "id": f"{step['id']}#{segment_index}",
                "stepIndex": step_index,
                "step": step,
                "side": resolved_side,
                "duration": per_segment,
                "startOffset": offset,
            })
            offset += per_segment
    return segments


def resolve_anchor_id(anchor_id: str | None, side: str) -> str | None:
    """对应 FaceAnchorID.resolved(for:)。无侧后缀的保持原样。"""
    if anchor_id is None:
        return None
    if not (anchor_id.endswith("_left") or anchor_id.endswith("_right")):
        return anchor_id
    if side == "left":
        return anchor_id if anchor_id.endswith("_left") else mirror_id(anchor_id)
    if side == "right":
        return anchor_id if anchor_id.endswith("_right") else mirror_id(anchor_id)
    return anchor_id


# ---------------------------------------------------------------------------
# 落点合理性
# ---------------------------------------------------------------------------
def face_bounds() -> tuple[float, float, float, float]:
    """合成脸的包围盒（视图坐标），外扩一点点作为「还算在脸上」的判据。"""
    xs = [p[0] * INTEROCULAR + FACE_CENTER[0] for p in CANONICAL_FACE.values()]
    ys = [p[1] * INTEROCULAR + FACE_CENTER[1] for p in CANONICAL_FACE.values()]
    margin = 0.35 * INTEROCULAR
    return min(xs) - margin, min(ys) - margin, max(xs) + margin, max(ys) + margin


def path_length(points: list[tuple[float, float]]) -> float:
    total = 0.0
    for a, b in zip(points, points[1:]):
        total += math.hypot(b[0] - a[0], b[1] - a[1])
    return total


# ---------------------------------------------------------------------------
def simulate(routine: dict, anchors: dict, landmarks: dict, frame: FaceFrame) -> None:
    routine_id = routine["id"]
    segments = build_segments(routine)
    # step id → {side: 路径长度}，用于左右对称性检查
    lengths_by_step: dict[str, dict[str, float]] = {}
    total = sum(s["duration"] for s in segments)
    min_x, min_y, max_x, max_y = face_bounds()

    print(f"\n{routine_id}  —  {len(routine['steps'])} steps → {len(segments)} 播放段，{total:.0f}s")
    print(f"  {'段':<3} {'侧':<6} {'时长':>6} {'动作':<26} {'路径':<7} {'长度':>8}  anchor")

    for index, segment in enumerate(segments):
        step = segment["step"]
        side = segment["side"]
        movement = step.get("movement", {})
        where = f"{routine_id}.{segment['id']}"

        start_id = resolve_anchor_id(movement.get("startAnchor"), side)
        end_id = resolve_anchor_id(movement.get("endAnchor"), side)
        path_type = movement.get("pathType", "line")

        if start_id is None:
            error(where, "没有 startAnchor —— 这一段在脸上什么都不会显示")
            continue
        if start_id not in anchors:
            error(where, f"startAnchor {start_id!r} 不存在（按 side={side} 改写后）")
            continue
        if end_id is not None and end_id not in anchors:
            error(where, f"endAnchor {end_id!r} 不存在（按 side={side} 改写后）")
            continue

        start_local = frame.to_local(evaluate_rule(anchors[start_id]["rule"], landmarks, frame))
        end_local = (
            frame.to_local(evaluate_rule(anchors[end_id]["rule"], landmarks, frame))
            if end_id else None
        )

        try:
            path = make_path(movement, start_local, end_local, frame)
        except Exception as exc:  # noqa: BLE001
            error(where, f"路径生成失败: {exc}")
            continue

        points = path["points"]
        if not points:
            error(where, "路径没有任何点")
            continue

        length = path_length(points)

        # --- 落点合理性 ---
        outside = [p for p in points if not (min_x <= p[0] <= max_x and min_y <= p[1] <= max_y)]
        if outside:
            ratio = len(outside) / len(points)
            message = f"{ratio:.0%} 的路径点落在脸部范围之外（起点 {start_id}）"
            # 少量越界可能只是圆周动作扫到边缘；大面积越界基本是 anchor 定义错了。
            (error if ratio > 0.25 else warn)(where, message)

        if path_type in ("line", "curve", "arc"):
            if length < 0.25 * INTEROCULAR:
                warn(where, f"路径只有 {length / INTEROCULAR:.2f} 瞳距长，短到看不出方向")
        elif path_type == "circle":
            radius = (movement.get("pathGeometry") or {}).get("radius", 0.35)
            if radius < 0.08:
                warn(where, f"圆周半径 {radius} 瞳距，小到画出来像个点")

        # --- 节奏合理性 ---
        tempo = movement.get("tempo")
        reps = movement.get("repetitions", 1)
        if tempo:
            cycle = 60.0 / tempo
            fit = segment["duration"] / cycle
            if abs(fit - reps) > max(1.0, reps * 0.5):
                warn(
                    where,
                    f"节奏对不上：{segment['duration']:.0f}s ÷ {cycle:.1f}s/次 ≈ {fit:.1f} 次，"
                    f"但 repetitions 写的是 {reps}",
                )

        lengths_by_step.setdefault(step["id"], {})[side] = length

        anchor_text = start_id + (f" → {end_id}" if end_id else "")
        print(
            f"  {index:<3} {side:<6} {segment['duration']:>5.0f}s "
            f"{step['title'][:26]:<26} {path_type:<7} "
            f"{length / INTEROCULAR:>6.2f}瞳距  {anchor_text}"
        )

    # --- 左右对称性 ---
    # 合成脸是左右对称的，所以同一个 step 的左右两段路径长度必须相等。
    # 不相等 = anchor 镜像出错，真机上会看到右脸路线明显画歪。
    # 这条检查是在发现 mouthLeftCorner 不翻转那个 bug 之后加的。
    for step_id, sides in lengths_by_step.items():
        if "left" not in sides or "right" not in sides:
            continue
        left, right = sides["left"], sides["right"]
        if left < 1e-9 and right < 1e-9:
            continue
        drift = abs(left - right) / max(left, right, 1e-9)
        if drift > 0.01:
            error(
                f"{routine_id}.{step_id}",
                f"左右路径长度不对称：左 {left / INTEROCULAR:.2f} vs 右 {right / INTEROCULAR:.2f} 瞳距"
                f"（差 {drift:.0%}）—— 多半是 anchor 镜像出错",
            )


def main() -> int:
    landmarks = make_landmarks(FACE_CENTER, INTEROCULAR, 0.0)
    frame = FaceFrame(landmarks)
    anchors = load_anchor_table()
    routines = json.loads((CONTENT_DIR / "routines.json").read_text(encoding="utf-8"))["routines"]

    wanted = sys.argv[1] if len(sys.argv) > 1 else None
    if wanted:
        routines = [r for r in routines if r["id"] == wanted]
        if not routines:
            print(f"找不到 routine: {wanted}")
            return 1

    print("无头 routine 模拟")
    print(f"合成脸：瞳距 {INTEROCULAR:.0f}px，正脸，双眼中点 {FACE_CENTER}")

    for routine in routines:
        simulate(routine, anchors, landmarks, frame)

    errors = [i for i in issues if i[0] == "error"]
    warnings = [i for i in issues if i[0] == "warning"]

    print("\n结果:")
    for severity, where, message in issues:
        print(f"  [{severity}] {where}: {message}")
    if not issues:
        print("  每一段都能正常渲染，无问题")
    print(f"\nerrors={len(errors)} warnings={len(warnings)}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
