#!/usr/bin/env python3
"""生成占位用的测试片段，让「视频那条路」在真机上跑得起来。

**这不是示范内容，只是为了验证通路。**
片段上明确写着 TEST CLIP —— 任何人看一眼就知道它不是真素材，
不可能被误当成正式内容发布。

为什么需要它：
    示范视频还没拍，而「上半屏能不能播视频、换动作时会不会跟着换、
    循环接不接得上、静音对不对」这些只有放了视频才验证得了。
    没有它，真机试用时永远只能看到回落的示意脸，视频那条代码路径一次都没跑过。

它会**自动跳过已经有真实视频的动作** —— 真素材放进来之后，
这个工具就只补还缺的那些，不会覆盖任何东西。

⚠️ 绝不要用别人的视频来占位。
   网上的教学视频有著作权，出镜者有肖像权，打包进要上架的 App 里
   会被 App Store 拒、上线后被投诉会下架。占位就该是明显的占位。

用法:
    python tools/make_test_videos.py            # 补齐缺的
    python tools/make_test_videos.py --clean    # 删掉所有测试片段
"""

from __future__ import annotations

import json
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTENT = ROOT / "Packages" / "FaceRitualCore" / "Sources" / "FaceRitualCore" / "Resources"
VIDEO_DIR = ROOT / "App" / "FaceRitual" / "Resources" / "CoachVideos"
# 生成的片段都会留下这个标记文件，--clean 靠它知道哪些是自己造的，
# 不会误删真素材。
MARKER = VIDEO_DIR / ".test-clips"

# 竖屏 9:16，和规格一致。分辨率取小一点：占位片段没必要占体积。
WIDTH, HEIGHT = 540, 960
DURATION = 6
# ffmpeg 的 filter 语法里冒号是参数分隔符，Windows 盘符的冒号必须转义，
# 否则报 "No option name near '/Windows/Fonts/...'" —— 报错信息完全看不出是路径问题。
FONT = "C\:/Windows/Fonts/arial.ttf" if sys.platform == "win32" else "/System/Library/Fonts/Helvetica.ttc"


def asset_name(move_id: str) -> str:
    return "coach_" + move_id.lower().replace("-", "_")


def escape(text: str) -> str:
    """drawtext 的文本里冒号和单引号要转义，否则 ffmpeg 会把它当成参数分隔。"""
    return text.replace("\\", "").replace(":", "\\:").replace("'", "")


def build_clip(move: dict, output: pathlib.Path) -> bool:
    title = escape(move.get("title", "")[:28])
    move_id = move["id"]
    gesture = escape({
        "none": "no hands",
        "singleFinger": "one finger",
        "twoFinger": "two fingers",
        "fingertips": "fingertips",
        "palm": "palm",
        "tool": "tool",
    }.get(move.get("movement", {}).get("gestureHint", "none"), ""))

    # 画面中央显示**正在走的播放时间**。
    #
    # 「能一眼看出画面在动」正是这批片段存在的意义：
    # 静止画面分不清播放器是在播、还是卡在第一帧。
    #
    # 试过两版都不行：脉动方框（drawbox 的宽高表达式渲染出来几乎没变化）、
    # 滑动进度条（drawbox 的位置表达式在这个 ffmpeg 版本里没有逐帧求值）。
    # drawtext 的 %{pts} 是必然逐帧变化的，而且它同时回答了另一个问题：
    # 循环接得上吗 —— 时间跳回 00:00 的那一刻就是循环点。
    filters = (
        f"color=c=0x1c1b20:s={WIDTH}x{HEIGHT}:d={DURATION}:r=30[bg];"
        f"[bg]drawtext=fontfile='{FONT}':text='%{{pts\:hms}}':"
        f"fontcolor=0xff9d3d:fontsize=40:x=(w-tw)/2:y={int(HEIGHT * 0.70)}[bar];"
        f"[bar]drawtext=fontfile='{FONT}':text='TEST CLIP':"
        f"fontcolor=0xff9d3d:fontsize=34:x=(w-tw)/2:y=120[t1];"
        f"[t1]drawtext=fontfile='{FONT}':text='{move_id}':"
        f"fontcolor=white:fontsize=64:x=(w-tw)/2:y=(h-th)/2-30[t2];"
        f"[t2]drawtext=fontfile='{FONT}':text='{title}':"
        f"fontcolor=0xd8d8dd:fontsize=30:x=(w-tw)/2:y=(h/2)+50[t3];"
        f"[t3]drawtext=fontfile='{FONT}':text='{gesture}':"
        f"fontcolor=0x9a9aa2:fontsize=26:x=(w-tw)/2:y=(h/2)+100[t4];"
        f"[t4]drawtext=fontfile='{FONT}':text='not real footage':"
        f"fontcolor=0x77777f:fontsize=22:x=(w-tw)/2:y=h-120"
    )

    result = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-y",
            "-filter_complex", filters,
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-profile:v", "high", "-preset", "veryfast", "-crf", "30",
            "-an",                       # 不要音轨：App 里是静音播放的
            "-movflags", "+faststart",
            str(output),
        ],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        detail = (result.stderr or "").strip()[:200] or "(ffmpeg 没给出原因)"
        print(f"  生成失败 {output.name}：{detail}")
        return False
    return True


def clean() -> int:
    if not MARKER.exists():
        print("没有测试片段可删。")
        return 0
    names = MARKER.read_text(encoding="utf-8").split()
    removed = 0
    for name in names:
        path = VIDEO_DIR / name
        if path.exists():
            path.unlink()
            removed += 1
    MARKER.unlink()
    print(f"已删除 {removed} 段测试片段。真实素材未受影响。")
    return 0


def main() -> int:
    if "--clean" in sys.argv:
        return clean()

    if shutil.which("ffmpeg") is None:
        print("需要 ffmpeg。Windows: choco install ffmpeg / macOS: brew install ffmpeg")
        return 1

    try:
        moves = json.loads((CONTENT / "moves.json").read_text(encoding="utf-8"))["moves"]
    except (OSError, KeyError, json.JSONDecodeError) as exc:
        print(f"读取 moves.json 失败：{exc}")
        return 1

    VIDEO_DIR.mkdir(parents=True, exist_ok=True)
    generated: list[str] = []
    skipped = 0

    for move in sorted(moves, key=lambda m: m["id"]):
        name = asset_name(move["id"])
        target = VIDEO_DIR / f"{name}.mp4"

        # 已经有真素材就跳过 —— 这个工具只补缺口，绝不覆盖。
        if target.exists() and target.name not in _existing_test_clips():
            skipped += 1
            continue

        if build_clip(move, target):
            generated.append(target.name)
            print(f"  {target.name}")

    if generated:
        MARKER.write_text("\n".join(sorted(set(generated + list(_existing_test_clips())))),
                          encoding="utf-8")

    total = sum((VIDEO_DIR / f"{asset_name(m['id'])}.mp4").exists() for m in moves)
    print()
    print(f"生成 {len(generated)} 段测试片段，跳过 {skipped} 段已有真素材。")
    print(f"现在 {total}/{len(moves)} 个动作有视频（含测试片段）。")
    print()
    print("⚠️ 这些是**占位**，画面上写着 TEST CLIP。真素材到位后：")
    print("     python tools/make_test_videos.py --clean")
    print("   然后把真视频按同样的文件名放进去。")
    return 0


def _existing_test_clips() -> set[str]:
    if not MARKER.exists():
        return set()
    return set(MARKER.read_text(encoding="utf-8").split())


if __name__ == "__main__":
    sys.exit(main())
