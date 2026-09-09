#!/usr/bin/env python3
"""生成示范视频的拍摄脚本（单文件 HTML，可打印）。

存在的理由：示范视频是产品现在最大的缺口 ——「上面老师做」那一半是空的。
而「去拍 20 段视频」听起来是个项目，实际上是**一下午的事**：
每段只要 4–8 秒，20 段加起来不到两分钟素材。

难点不在拍，在于拍的时候得知道每一段该做什么。这份脚本就是那张清单：
每个动作一格，中文原文的起始姿势与操作照抄进去，配上机位、时长、文件名。
拍的人拿着手机照着做就行，不需要懂产品。

用法:
    python tools/export_shot_list.py
输出:
    build/shot_list.html
"""

from __future__ import annotations

import datetime
import html
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTENT = ROOT / "Packages" / "FaceRitualCore" / "Sources" / "FaceRitualCore" / "Resources"
OUTPUT = ROOT / "build" / "shot_list.html"

GESTURE_ZH = {
    "none": "不用手",
    "singleFinger": "一根手指",
    "twoFinger": "两根手指",
    "fingertips": "指腹（三指）",
    "palm": "掌根 / 手掌",
    "tool": "工具",
}

INTENSITY_ZH = {
    "none": "无手部压力",
    "veryLight": "极轻",
    "light": "轻",
    "lightToModerate": "轻至中轻",
}

TOOL_ZH = {"none": "", "facialRoller": "面部滚轮", "guaSha": "刮痧板"}

REGION_ZH = {
    "wholeFace": "全脸", "forehead": "额头", "glabella": "眉间", "temple": "太阳穴",
    "eyeArea": "眼周", "midface": "中脸", "cheek": "脸颊", "perioral": "口周",
    "jawline": "下颌线", "neck": "颈部",
}


def esc(v) -> str:
    return html.escape(str(v)) if v else ""


def asset_name(move_id: str) -> str:
    return "coach_" + move_id.lower().replace("-", "_")


def render(move: dict, index: int) -> str:
    src = move.get("source", {})
    mv = move.get("movement", {})
    tool = TOOL_ZH.get(move.get("requiresTool"), "")
    no_hands = mv.get("pathType") == "expression"

    return f"""
<article class="shot">
  <header>
    <span class="n">{index}</span>
    <div class="t">
      <div class="zh">{esc(src.get('titleZh'))}</div>
      <div class="file">{esc(asset_name(move['id']))}.mp4</div>
    </div>
    <label class="done"><input type="checkbox"> 拍好了</label>
  </header>

  <div class="grid">
    <div class="k">部位</div><div class="v">{esc(REGION_ZH.get(move.get('region'), move.get('region')))}</div>
    <div class="k">用什么</div><div class="v">{esc(GESTURE_ZH.get(mv.get('gestureHint', 'none')))}{(' · ' + tool) if tool else ''}</div>
    <div class="k">力度</div><div class="v">{esc(INTENSITY_ZH.get(move.get('intensity')))}</div>
    <div class="k">拍多长</div><div class="v"><b>4–8 秒</b>，做 1–2 个完整来回就够（App 会自动循环）</div>
  </div>

  <div class="say">
    <div class="lab">起始姿势</div>
    <p>{esc(src.get('startingPositionZh')) or '—'}</p>
    <div class="lab">这一段要做的动作</div>
    <p>{esc(src.get('instructionZh')) or '—'}</p>
    {'<div class="lab">注意</div><p class="warn">' + esc(src.get('stopSignalsZh')) + '</p>' if src.get('stopSignalsZh') else ''}
  </div>

  {'<p class="hint">⚠️ 这一段<b>不用手</b>，是表情动作 —— 镜头只拍脸，不要有手入镜。</p>' if no_hands else ''}
</article>
"""


def main() -> int:
    try:
        moves = json.loads((CONTENT / "moves.json").read_text(encoding="utf-8"))["moves"]
    except (OSError, KeyError, json.JSONDecodeError) as exc:
        print(f"读取 moves.json 失败：{exc}")
        return 1

    moves = sorted(moves, key=lambda m: m["id"])
    body = "".join(render(m, i + 1) for i, m in enumerate(moves))
    hand_free = sum(1 for m in moves if m["movement"].get("pathType") == "expression")
    today = datetime.date.today().isoformat()

    document = f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>示范视频拍摄脚本 · face3</title>
<style>
  body {{ margin: 0 auto; padding: 28px 20px 70px; max-width: 54rem;
         font: 15px/1.65 -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
         color: #1b1b1e; background: #fff; }}
  h1 {{ font-size: 1.6rem; margin: 0 0 .3rem; }}
  .sub {{ color: #6a6a70; font-size: .9rem; margin: 0 0 1.5rem; }}
  .setup {{ border: 2px solid #2563eb; background: #eff6ff; border-radius: 10px;
            padding: 14px 16px; margin-bottom: 26px; }}
  .setup b {{ color: #1d4ed8; }}
  .setup ul {{ margin: .5rem 0 0; padding-left: 1.2rem; }}
  .setup li {{ margin: .3rem 0; }}
  .shot {{ border: 1px solid #dcdce2; border-radius: 10px; margin-bottom: 18px;
           padding-bottom: 12px; page-break-inside: avoid; }}
  .shot > header {{ display: flex; gap: 12px; align-items: center;
                    background: #f6f6f8; padding: 10px 14px;
                    border-bottom: 1px solid #dcdce2; border-radius: 10px 10px 0 0; }}
  .n {{ flex: none; width: 26px; height: 26px; border-radius: 50%; background: #1b1b1e;
        color: #fff; font-size: .82rem; display: inline-flex;
        align-items: center; justify-content: center; }}
  .t {{ flex: 1; }}
  .t .zh {{ font-weight: 600; }}
  .t .file {{ font-family: ui-monospace, Menlo, monospace; font-size: .78rem; color: #6a6a70; }}
  .done {{ font-size: .84rem; white-space: nowrap; color: #6a6a70; }}
  .grid {{ display: grid; grid-template-columns: 5.5rem 1fr; gap: 2px 10px;
           padding: 10px 14px 4px; font-size: .9rem; }}
  .grid .k {{ color: #6a6a70; }}
  .say {{ padding: 4px 14px 0; }}
  .say .lab {{ font-size: .78rem; color: #6a6a70; margin-top: 8px; }}
  .say p {{ margin: 2px 0 0; }}
  .say .warn {{ color: #b45309; }}
  .hint {{ margin: 10px 14px 0; padding: 8px 10px; background: #fffbeb;
           border-radius: 6px; font-size: .86rem; }}
  @media print {{ body {{ padding: 0; max-width: none; }} .shot {{ break-inside: avoid; }} }}
</style>
</head>
<body>

<h1>示范视频拍摄脚本</h1>
<p class="sub">共 {len(moves)} 段 · 每段 4–8 秒 · 全部素材加起来不到 2 分钟 · 导出于 {today}</p>

<div class="setup">
  <p><b>拍之前先摆好这些，全程不用改：</b></p>
  <ul>
    <li><b>手机竖着</b>架住（书堆、支架都行），镜头对准脸，画面里有头和肩</li>
    <li><b>光</b>：面对窗户，白天自然光最好。别背光，别用顶灯（脸上会有阴影）</li>
    <li><b>背景</b>：干净的墙。别有杂物</li>
    <li><b>不用录声音</b>，App 里是静音播放的，讲解由 App 自己念</li>
    <li><b>动作要慢</b>。这是教学，不是展示 —— 比你平时做慢一点</li>
    <li><b>首尾要接得上</b>：结束时的姿势最好和开始时一样，循环播放才不跳</li>
  </ul>
  <p><b>不要出现：</b>片头片尾、字幕、logo、任何"变紧致/去皱/瘦脸"之类的话
     —— 功效表述是审核红线，代码里也有检查盯着。</p>
  <p style="margin-bottom:0"><b>拍完怎么办：</b>把 20 个文件按下面每格标的文件名命名，
     放进 <code>App/FaceRitual/Resources/CoachVideos/</code>，
     跑 <code>make videos</code> 检查命名对不对。</p>
</div>

{body}

<p class="sub">{len(moves)} 段，其中 {hand_free} 段是表情动作（不用手入镜）。
拍完跑一次 <code>make videos</code>，它会告诉你哪些到位了、哪些命名不对。</p>

</body>
</html>
"""

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(document, encoding="utf-8")

    print(f"已生成 {OUTPUT.relative_to(ROOT)}")
    print(f"  {len(moves)} 段，每段 4–8 秒，总素材不到 2 分钟")
    print(f"  其中 {hand_free} 段是表情动作，不用手入镜")
    print()
    print("  打印出来或用手机打开，照着一段一段拍。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
