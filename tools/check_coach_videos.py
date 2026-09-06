#!/usr/bin/env python3
"""检查示范视频素材的到位情况与命名是否正确。

存在的理由：视频是后补的，而文件名错一个字符 App 就找不到，
表现是「回落到示意动画」—— 看起来一切正常，只是视频没播。
这种失败**不会报错**，所以需要主动检查。

用法:
    python tools/check_coach_videos.py
缺素材不算错误（退出码 0）—— 那是正常的进行中状态。
命名不对、放错目录、格式不支持才算错误。
"""

from __future__ import annotations

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTENT = ROOT / "Packages" / "FaceRitualCore" / "Sources" / "FaceRitualCore" / "Resources"
VIDEO_DIR = ROOT / "App" / "FaceRitual" / "Resources" / "CoachVideos"

# 与 LoopingVideoPlayer.resolve 保持一致。
EXTENSIONS = (".mp4", ".mov", ".m4v")
# 与 COACH_VIDEO_SPEC.md 的体积上限一致。
MAX_BYTES = 3 * 1024 * 1024


def expected_asset_name(move_id: str) -> str:
    """复刻 GoldMove.makeStep 里的命名规则：GM-01 → coach_gm_01。"""
    return "coach_" + move_id.lower().replace("-", "_")


def main() -> int:
    try:
        moves = json.loads((CONTENT / "moves.json").read_text(encoding="utf-8"))["moves"]
    except (OSError, KeyError, json.JSONDecodeError) as exc:
        print(f"读取 moves.json 失败：{exc}")
        return 1

    expected = {expected_asset_name(m["id"]): m for m in sorted(moves, key=lambda m: m["id"])}

    present: dict[str, pathlib.Path] = {}
    strays: list[pathlib.Path] = []
    if VIDEO_DIR.exists():
        for path in sorted(VIDEO_DIR.iterdir()):
            if path.is_dir():
                continue
            # 点开头的是工具文件（.gitkeep、.DS_Store），不是素材。
            if path.name.startswith("."):
                continue
            if path.suffix.lower() not in EXTENSIONS:
                strays.append(path)
                continue
            if path.stem in expected:
                present[path.stem] = path
            else:
                strays.append(path)

    errors = 0

    print(f"素材目录：{VIDEO_DIR.relative_to(ROOT)}")
    print(f"内容需要 {len(expected)} 段视频，已到位 {len(present)} 段\n")

    for name, move in expected.items():
        path = present.get(name)
        if path is None:
            print(f"  [ 待补 ] {name:<16} {move.get('title', '')}")
            continue
        size = path.stat().st_size
        flag = ""
        if size > MAX_BYTES:
            flag = f"  ⚠️ {size / 1024 / 1024:.1f}MB 超过 3MB 上限"
            errors += 1
        print(f"  [ 就位 ] {name:<16} {size / 1024:.0f}KB{flag}")

    if strays:
        print()
        for path in strays:
            print(f"  [命名错] {path.name}")
            print(f"           不是内容需要的文件名，App 找不到它。")
            print(f"           规则：GM-01 → coach_gm_01.mp4（见 docs/COACH_VIDEO_SPEC.md）")
            errors += 1

    missing = len(expected) - len(present)
    print()
    if missing:
        print(f"还缺 {missing} 段 —— 这是正常的进行中状态，缺的动作会回落到示意动画。")
    else:
        print("全部素材已到位。")

    if errors:
        print(f"\n{errors} 个问题需要处理（命名或体积）。")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
