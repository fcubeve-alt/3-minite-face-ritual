#!/usr/bin/env python3
"""内容包校验器（Python 参考实现）。

存在的理由：Swift 的 ContentValidator 只有在 Mac 上才跑得起来。
这个脚本复刻同一套规则，让内容 JSON 在任何机器 / CI 上都能被验证，
也让 Owner 在替换正式动作内容后可以自查，而不必先装 Xcode。

用法:
    python tools/validate_content.py
退出码 0 = 无 error（warning 不阻塞）。
"""

from __future__ import annotations

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTENT_DIR = ROOT / "Packages" / "FaceRitualCore" / "Sources" / "FaceRitualCore" / "Resources"

SCHEMA_VERSION = 1
MORNING_TARGET_SECONDS = 180
EVENING_TARGET_SECONDS = 300
DURATION_TOLERANCE = 30

# 必须与 SemanticLandmark.swift 保持一致。
SEMANTIC_LANDMARKS = {
    "leftEyeOuter", "leftEyeInner", "leftEyeUpper", "leftEyeLower", "leftEyeCenter",
    "rightEyeOuter", "rightEyeInner", "rightEyeUpper", "rightEyeLower", "rightEyeCenter",
    "leftBrowInner", "leftBrowOuter", "leftBrowPeak",
    "rightBrowInner", "rightBrowOuter", "rightBrowPeak",
    "glabella",
    "noseBridgeTop", "noseBridgeMid", "noseTip", "subnasale",
    "leftNoseAla", "rightNoseAla",
    "leftMouthCorner", "rightMouthCorner", "upperLipCenter", "lowerLipCenter",
    "chinCenter", "leftJawAngle", "rightJawAngle",
    "leftCheekbone", "rightCheekbone",
    "leftTemple", "rightTemple",
    "foreheadCenter",
}

PATH_TYPES = {"line", "curve", "arc", "circle", "press", "hold"}
SIDES = {"none", "left", "right", "both", "leftThenRight"}
REVIEW_STATUSES = {"mock_unreviewed", "draft", "expert_reviewed"}

issues: list[tuple[str, str, str]] = []


def error(path: str, message: str) -> None:
    issues.append(("error", path, message))


def warn(path: str, message: str) -> None:
    issues.append(("warning", path, message))


def load(name: str) -> dict:
    file = CONTENT_DIR / name
    if not file.exists():
        error(name, "文件不存在")
        return {}
    try:
        return json.loads(file.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        error(name, f"JSON 解析失败: {exc}")
        return {}


def mirror_id(raw: str) -> str:
    if raw.endswith("_left"):
        return raw[: -len("_left")] + "_right"
    if raw.endswith("_right"):
        return raw[: -len("_right")] + "_left"
    return raw


def landmark_side(name: str) -> str:
    """侧别判定必须与 Swift 的 SemanticLandmark.side 完全一致。"""
    if name.startswith("left") or "Left" in name:
        return "left"
    if name.startswith("right") or "Right" in name:
        return "right"
    return "none"


def mirror_landmark(name: str) -> str:
    if name.startswith("left"):
        candidate = "right" + name[len("left"):]
        if candidate in SEMANTIC_LANDMARKS:
            return candidate
    if name.startswith("right"):
        candidate = "left" + name[len("right"):]
        if candidate in SEMANTIC_LANDMARKS:
            return candidate
    if "Left" in name:
        candidate = name.replace("Left", "Right")
        if candidate in SEMANTIC_LANDMARKS:
            return candidate
    if "Right" in name:
        candidate = name.replace("Right", "Left")
        if candidate in SEMANTIC_LANDMARKS:
            return candidate
    return name


def check_landmark_pairing() -> None:
    """每个有侧别的 landmark 都必须能镜像到**另一个**存在的 landmark。

    这条检查是在发现 `mouthLeftCorner` 镜像不动之后加的：
    当时 side 判定用的是 hasPrefix，把它当成了中线点，
    结果右脸的 anchor 起点算到了脸中间，路径长度左右差 38%。
    """
    for name in sorted(SEMANTIC_LANDMARKS):
        side = landmark_side(name)
        if side == "none":
            if mirror_landmark(name) != name:
                error("SemanticLandmark", f"{name} 被判为中线点，却能镜像到 {mirror_landmark(name)}")
            continue
        mirrored = mirror_landmark(name)
        if mirrored == name:
            error("SemanticLandmark", f"{name} 有侧别（{side}）却镜像到自己 —— 对侧点缺失或命名不符合约定")
        elif mirrored not in SEMANTIC_LANDMARKS:
            error("SemanticLandmark", f"{name} 的对侧点 {mirrored} 不存在")
        elif landmark_side(mirrored) == side:
            error("SemanticLandmark", f"{name} 与 {mirrored} 被判为同一侧")


def rule_landmarks(rule: dict, path: str) -> set[str]:
    """递归收集 geometryRule 引用到的 landmark，并校验规则结构。"""
    kind = rule.get("type")
    if kind == "landmark":
        name = rule.get("id")
        if name not in SEMANTIC_LANDMARKS:
            error(path, f"未知 landmark: {name!r}")
            return set()
        return {name}
    if kind == "midpoint":
        return rule_landmarks(rule.get("a", {}), path) | rule_landmarks(rule.get("b", {}), path)
    if kind == "lerp":
        t = rule.get("t")
        if not isinstance(t, (int, float)) or not (0.0 <= t <= 1.0):
            error(path, f"lerp.t 必须在 0…1，当前 {t!r}")
        return rule_landmarks(rule.get("from", {}), path) | rule_landmarks(rule.get("to", {}), path)
    if kind == "weighted":
        items = rule.get("items", [])
        if not items:
            error(path, "weighted 规则没有 items")
            return set()
        total = sum(item.get("weight", 0) for item in items)
        if abs(total) < 1e-9:
            error(path, "weighted 权重之和为 0")
        found = set()
        for item in items:
            name = item.get("landmark")
            if name not in SEMANTIC_LANDMARKS:
                error(path, f"未知 landmark: {name!r}")
            else:
                found.add(name)
        return found
    if kind == "offset":
        return rule_landmarks(rule.get("base", {}), path)
    error(path, f"未知 geometryRule type: {kind!r}")
    return set()


def validate_anchors(doc: dict) -> dict[str, dict]:
    table: dict[str, dict] = {}
    for anchor in doc.get("anchors", []):
        anchor_id = anchor.get("id", "<missing id>")
        path = f"anchors.{anchor_id}"

        if anchor_id in table:
            error(path, "anchor id 重复")
        side = anchor.get("side", "none")
        if side not in SIDES:
            error(path, f"未知 side: {side!r}")
        if anchor.get("reviewStatus", "mock_unreviewed") not in REVIEW_STATUSES:
            error(path, f"未知 reviewStatus: {anchor.get('reviewStatus')!r}")

        tolerance = anchor.get("toleranceRadius", 0.12)
        if tolerance <= 0:
            error(path, "toleranceRadius 必须 > 0")
        elif tolerance > 0.6:
            warn(path, "toleranceRadius 超过 0.6 瞳距，容差圈会大到失去指示意义")

        threshold = anchor.get("confidenceThreshold", 0.5)
        if not (0.0 <= threshold <= 1.0):
            error(path, "confidenceThreshold 必须在 0…1")

        marks = rule_landmarks(anchor.get("rule", {}), path)
        if not marks:
            error(path, "geometryRule 没有引用任何 landmark")

        # 侧向一致性：left 侧 anchor 不应该引用 right 侧 landmark。
        if side in ("left", "right"):
            wrong = {m for m in marks if m.startswith("left" if side == "right" else "right")}
            if wrong:
                warn(path, f"side={side} 但引用了对侧 landmark: {sorted(wrong)}")

        table[anchor_id] = anchor

        # 复刻 FaceAnchor.mirroredToOppositeSide()
        if side in ("left", "right"):
            mirrored = mirror_id(anchor_id)
            if mirrored == anchor_id:
                warn(path, f"side={side} 但 id 没有 _left/_right 后缀，无法自动生成对侧 anchor")
            elif mirrored not in table:
                table[mirrored] = {**anchor, "id": mirrored, "side": "right" if side == "left" else "left"}
    return table


def validate_movement(movement: dict, anchors: dict, path: str) -> None:
    start = movement.get("startAnchor")
    end = movement.get("endAnchor")
    path_type = movement.get("pathType", "line")

    if path_type not in PATH_TYPES:
        error(path, f"未知 pathType: {path_type!r}")

    for label, anchor_id in (("startAnchor", start), ("endAnchor", end)):
        if anchor_id is None:
            continue
        # 播放时会按左右侧改写，两侧都必须存在。
        for candidate in {anchor_id, mirror_id(anchor_id)}:
            if candidate not in anchors:
                error(path, f"{label} 引用了不存在的 anchor: {candidate}")

    if path_type in ("line", "curve", "arc"):
        if not start or not end:
            error(path, f"pathType={path_type} 需要同时提供 startAnchor 与 endAnchor")
    elif path_type == "circle":
        if not start:
            error(path, "pathType=circle 需要 startAnchor 作为圆心")
        if (movement.get("pathGeometry") or {}).get("radius", 0) <= 0:
            warn(path, "circle 未指定 radius，将使用默认 0.35 瞳距")
    else:  # press / hold
        if not start:
            error(path, f"pathType={path_type} 需要 startAnchor")

    if movement.get("repetitions", 1) < 1:
        error(path, "repetitions 必须 >= 1")

    if movement.get("trackingSupport") == "observableCorrectionExperimental":
        warn(path, "trackingSupport=observableCorrectionExperimental 需逐个动作验证达标后才可启用（规格 §10）")

    geometry = movement.get("pathGeometry") or {}
    for index, offset in enumerate(geometry.get("controlOffsets", [])):
        if "along" not in offset or "perpendicular" not in offset:
            error(path, f"controlOffsets[{index}] 缺少 along / perpendicular")


def validate_routines(doc: dict, anchors: dict) -> None:
    seen_routines: set[str] = set()
    has_free_morning = False

    for routine in doc.get("routines", []):
        routine_id = routine.get("id", "<missing id>")
        path = f"routines.{routine_id}"

        if routine_id in seen_routines:
            error(path, "routine id 重复")
        seen_routines.add(routine_id)

        routine_type = routine.get("type")
        is_premium = routine.get("isPremium", False)
        if routine_type == "morning":
            if is_premium:
                error(path, "Morning routine 不得标记为 premium（规格 §11）")
            else:
                has_free_morning = True

        steps = routine.get("steps", [])
        if not steps:
            error(path, "routine 没有任何 step")
            continue

        seen_steps: set[str] = set()
        total = 0.0
        for index, step in enumerate(steps):
            step_id = step.get("id", "<missing id>")
            step_path = f"{path}.steps[{index}]:{step_id}"
            if step_id in seen_steps:
                error(step_path, "step id 在同一 routine 内重复")
            seen_steps.add(step_id)

            duration = step.get("durationSeconds", 0)
            if duration <= 0:
                error(step_path, "durationSeconds 必须 > 0")
            elif duration > 90:
                warn(step_path, "单个动作超过 90 秒，与规格 §4「每个动作短」不符")
            total += duration

            side = step.get("side", "none")
            if side not in SIDES:
                error(step_path, f"未知 side: {side!r}")
            if side == "leftThenRight" and duration / 2 < 5:
                warn(step_path, "leftThenRight 展开后单侧不足 5 秒，节奏会过于仓促")

            if not step.get("shortCue"):
                warn(step_path, "缺少 shortCue，屏幕上会没有文字提示")

            validate_movement(step.get("movement", {}), anchors, step_path)

        target = {"morning": MORNING_TARGET_SECONDS, "evening": EVENING_TARGET_SECONDS}.get(routine_type)
        if target is not None and abs(total - target) > DURATION_TOLERANCE:
            warn(path, f"总时长 {total:.0f}s 偏离目标 {target}s 超过 {DURATION_TOLERANCE}s")

        print(f"  {routine_id:<20} type={routine_type:<8} premium={str(is_premium):<5} "
              f"steps={len(steps):<2} total={total:.0f}s")

    if not has_free_morning:
        error("routines", "缺少免费的 Morning Core（type=morning 且 isPremium=false）。规格 §11 要求它永久免费。")


def main() -> int:
    print(f"内容目录: {CONTENT_DIR}")

    meta = load("content_meta.json")
    if meta.get("schemaVersion") != SCHEMA_VERSION:
        error("content_meta.json", f"schemaVersion 应为 {SCHEMA_VERSION}，实际 {meta.get('schemaVersion')!r}")
    if meta.get("reviewStatus") not in REVIEW_STATUSES:
        error("content_meta.json", f"未知 reviewStatus: {meta.get('reviewStatus')!r}")

    check_landmark_pairing()

    anchors_doc = load("anchors.json")
    routines_doc = load("routines.json")

    print("\nAnchors:")
    anchors = validate_anchors(anchors_doc)
    for anchor_id in sorted(anchors):
        print(f"  {anchor_id:<22} side={anchors[anchor_id].get('side', 'none')}")
    print(f"  → 共 {len(anchors)} 个（含自动镜像）")

    print("\nRoutines:")
    validate_routines(routines_doc, anchors)

    unreviewed = meta.get("reviewStatus") != "expert_reviewed"
    if unreviewed:
        warn("bundle", "内容包含未经专业审核的条目（mock_unreviewed / draft）。发布前必须由 Owner + 专业人员替换。")

    errors = [i for i in issues if i[0] == "error"]
    warnings = [i for i in issues if i[0] == "warning"]

    print("\n校验结果:")
    for severity, path, message in issues:
        print(f"  [{severity}] {path}: {message}")
    if not issues:
        print("  无问题")
    print(f"\nerrors={len(errors)} warnings={len(warnings)}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
