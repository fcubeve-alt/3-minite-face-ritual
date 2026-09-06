#!/usr/bin/env python3
"""生成 Expert Gate 的动作审阅表（单文件 HTML，可直接打印或发邮件）。

存在的理由：Expert Gate 是 M2 的前置条件，而它现在卡在一个很蠢的地方 ——
专家看不到要审的东西。动作只存在于 moves.json 和 App 里一个调试页，
而 PT / 皮肤科 / 淋巴引流方向的专业人员既不会读 JSON，也没装我们的 TestFlight。

这个脚本把动作库导出成一页 HTML：中文原文在上、英文译文在下、
每条留出「通过 / 需修改 / 不通过」和批注位置。打印出来能直接在纸上批。

设计上的关键取舍：**中文原文放在最显眼的位置。**
专家审的是原文（起始姿势、操作、力度、停止信号），
英文是给用户看的翻译，翻译本身也需要被复核 —— 所以两者并排，谁也不覆盖谁。

用法:
    python tools/export_review_sheet.py
输出:
    build/expert_review_sheet.html
"""

from __future__ import annotations

import datetime
import html
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTENT = ROOT / "Packages" / "FaceRitualCore" / "Sources" / "FaceRitualCore" / "Resources"
OUTPUT = ROOT / "build" / "expert_review_sheet.html"

INTENSITY_ZH = {
    "none": "无手部压力",
    "veryLight": "极轻",
    "light": "轻",
    "lightToModerate": "轻至中轻",
}

EVIDENCE_ZH = {
    "classicPractice": "传统/专业实践成熟，缺少直接研究",
    "indirect": "有相近方向研究，徒手应用属间接证据",
    "protocolLevel": "出现在已发表的整套方案里（方案级结果）",
    "randomisedTrial": "有随机对照试验（样本仍小）",
    "supportive": "辅助/仪式性动作，不以外观为目的",
}

TOOL_ZH = {"none": "不需要", "facialRoller": "面部滚轮", "guaSha": "刮痧板"}

REGION_ZH = {
    "wholeFace": "全脸", "forehead": "额头", "glabella": "眉间", "temple": "太阳穴",
    "eyeArea": "眼周", "midface": "中脸", "cheek": "脸颊", "perioral": "口周",
    "jawline": "下颌线", "neck": "颈部",
}


def esc(value) -> str:
    return html.escape(str(value)) if value is not None else ""


def field(label: str, value, mono: bool = False) -> str:
    if not value:
        return ""
    cls = ' class="mono"' if mono else ""
    return f"<div class='row'><div class='k'>{esc(label)}</div><div class='v'{cls}>{esc(value)}</div></div>"


def render_move(move: dict, index: int) -> str:
    source = move.get("source", {})
    movement = move.get("movement", {})

    anchors = []
    for key, label in (("startAnchor", "起点"), ("endAnchor", "终点")):
        if movement.get(key):
            anchors.append(f"{label} {movement[key]}")
    for a in movement.get("focusAnchors", []):
        anchors.append(f"区域 {a}")

    stop = source.get("stopSignalsZh")

    return f"""
<article class="move">
  <header>
    <div class="id">{esc(move['id'])}</div>
    <div class="titles">
      <div class="zh">{esc(source.get('titleZh', ''))}</div>
      <div class="en">{esc(move.get('title', ''))}</div>
    </div>
    <div class="verdict">
      <label><input type="checkbox"> 通过</label>
      <label><input type="checkbox"> 需修改</label>
      <label><input type="checkbox"> 不通过</label>
    </div>
  </header>

  <section class="src">
    <h4>专业文档原文（审这一段）</h4>
    {field("起始姿势", source.get("startingPositionZh"))}
    {field("操作", source.get("instructionZh"))}
    {field("时长", source.get("durationZh"))}
    {field("力度", source.get("intensityZh"))}
    {field("停止/禁忌信号", stop) if stop else
     "<div class='row warn'><div class='k'>停止/禁忌信号</div><div class='v'>原文未给出 —— 需要补</div></div>"}
    {field("使用建议", source.get("usageZh"))}
    {field("证据说明", source.get("evidenceZh"))}
    {field("研究备注", source.get("researchNoteZh"))}
    {field("出处", source.get("documentRef"), mono=True)}
  </section>

  <section class="en">
    <h4>用户会看到的英文（译文，请复核措辞是否走样）</h4>
    {field("屏幕提示", move.get("shortCue"))}
    {field("语音", move.get("voiceCue"))}
    {field("安全提示", move.get("safetyNote"))}
  </section>

  <section class="meta">
    <h4>工程侧参数（仅供参考，不需要您判断）</h4>
    <div class="chips">
      <span>区域：{esc(REGION_ZH.get(move.get('region'), move.get('region')))}</span>
      <span>默认时长：{esc(move.get('defaultDurationSeconds'))}s</span>
      <span>力度：{esc(INTENSITY_ZH.get(move.get('intensity'), move.get('intensity')))}</span>
      <span>工具：{esc(TOOL_ZH.get(move.get('requiresTool'), move.get('requiresTool')))}</span>
      <span>路径：{esc(movement.get('pathType'))}</span>
      {"<span>" + esc("；".join(anchors)) + "</span>" if anchors else ""}
    </div>
    <div class="ev">证据等级：{esc(EVIDENCE_ZH.get(move.get('evidenceLevel'), move.get('evidenceLevel')))}</div>
  </section>

  <section class="note">
    <h4>专家批注</h4>
    <div class="lines"></div>
  </section>
</article>
"""


def main() -> int:
    try:
        moves = json.loads((CONTENT / "moves.json").read_text(encoding="utf-8"))["moves"]
        routines = json.loads((CONTENT / "routines.json").read_text(encoding="utf-8"))["routines"]
        meta = json.loads((CONTENT / "content_meta.json").read_text(encoding="utf-8"))
    except (OSError, KeyError, json.JSONDecodeError) as exc:
        print(f"读取内容失败：{exc}")
        return 1

    moves = sorted(moves, key=lambda m: m["id"])

    # 每个动作被哪些 routine 用到 —— 专家判断风险时需要知道使用频率。
    usage: dict[str, list[str]] = {}
    for routine in routines:
        for ref in routine.get("steps", []):
            usage.setdefault(ref["move"], []).append(routine["id"])

    usage_rows = "".join(
        f"<tr><td class='mono'>{esc(m['id'])}</td><td>{esc(m.get('source', {}).get('titleZh', ''))}</td>"
        f"<td>{len(usage.get(m['id'], []))} 次</td>"
        f"<td>{esc('、'.join(sorted(set(usage.get(m['id'], [])))) or '暂未使用')}</td></tr>"
        for m in moves
    )

    today = datetime.date.today().isoformat()
    body = "".join(render_move(m, i) for i, m in enumerate(moves))

    document = f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>动作审阅表 · Expert Gate</title>
<style>
  body {{ margin: 0 auto; padding: 30px 22px 80px; max-width: 62rem;
         font: 15px/1.7 -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
         color: #1b1b1e; background: #fff; }}
  h1 {{ font-size: 1.7rem; margin: 0 0 .3rem; }}
  .sub {{ color: #6a6a70; margin: 0 0 1.6rem; font-size: .92rem; }}
  .banner {{ border: 2px solid #d97706; background: #fffbeb; border-radius: 10px;
             padding: 14px 16px; margin-bottom: 26px; }}
  .banner b {{ color: #b45309; }}
  table {{ border-collapse: collapse; width: 100%; font-size: .86rem; margin-bottom: 34px; }}
  th, td {{ border: 1px solid #e2e2e6; padding: 5px 8px; text-align: left; }}
  th {{ background: #f6f6f8; }}
  .mono {{ font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .88em; }}
  .move {{ border: 1px solid #dcdce2; border-radius: 12px; padding: 0 0 16px;
           margin-bottom: 26px; page-break-inside: avoid; }}
  .move > header {{ display: flex; align-items: flex-start; gap: 14px;
                    padding: 13px 16px; background: #f6f6f8;
                    border-bottom: 1px solid #dcdce2; border-radius: 12px 12px 0 0; }}
  .id {{ font-family: ui-monospace, monospace; font-weight: 700; font-size: 1rem; }}
  .titles {{ flex: 1; }}
  .titles .zh {{ font-weight: 600; }}
  .titles .en {{ color: #6a6a70; font-size: .88rem; }}
  .verdict {{ display: flex; gap: 12px; font-size: .84rem; white-space: nowrap; }}
  .move section {{ padding: 10px 16px 2px; }}
  .move h4 {{ font-size: .8rem; margin: 6px 0 8px; color: #6a6a70;
              text-transform: none; font-weight: 600; }}
  .row {{ display: flex; gap: 12px; margin-bottom: 5px; align-items: baseline; }}
  .row .k {{ flex: none; width: 7.5rem; color: #6a6a70; font-size: .84rem; }}
  .row .v {{ flex: 1; }}
  .row.warn .v {{ color: #b45309; font-weight: 600; }}
  section.src {{ background: #fcfcfd; }}
  section.en {{ border-top: 1px dashed #e2e2e6; }}
  .chips {{ display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 5px; }}
  .chips span {{ background: #f0f0f3; border-radius: 20px; padding: 2px 10px; font-size: .8rem; }}
  .ev {{ font-size: .82rem; color: #6a6a70; }}
  .lines {{ height: 4.6rem; border: 1px dashed #c9c9d0; border-radius: 6px; }}
  @media print {{
    body {{ padding: 0; max-width: none; }}
    .move {{ break-inside: avoid; }}
  }}
</style>
</head>
<body>

<h1>动作审阅表 · Expert Gate</h1>
<p class="sub">内容版本 {esc(meta.get('contentVersion'))} · 当前状态 {esc(meta.get('reviewStatus'))} · 导出于 {today}</p>

<div class="banner">
  <p><b>请您审的是这些：</b></p>
  <ol>
    <li><b>安全边界</b> —— 停止/禁忌信号写全了吗？力度描述会不会被误解成用力？
        有没有哪个动作对特定人群（皮肤破损、术后、TMJ 疼痛、孕期等）应当排除？</li>
    <li><b>位置与操作</b> —— 起始姿势与操作描述是否准确、可执行？</li>
    <li><b>译文有没有走样</b> —— 英文是用户实际看到的文字。
        安全相关的措辞经翻译最容易失真，所以中文原文与英文并排放在一起。</li>
  </ol>
  <p><b>不需要您判断的：</b>动作有没有效。我们<b>不会</b>对外做任何功效表述，
     证据等级只用于内部排优先级与风险边界，不会出现在给用户看的文案里。</p>
  <p><b>现状：</b>全部 {len(moves)} 个动作均标为 <span class="mono">draft</span>，
     未经您确认之前不会发布，代码里有测试强制拦住这一点。</p>
</div>

<h2 style="font-size:1.05rem">使用情况一览</h2>
<table>
  <tr><th>编号</th><th>动作</th><th>被使用</th><th>出现在</th></tr>
  {usage_rows}
</table>
<p class="sub">「暂未使用」不代表被淘汰 —— Evening 与 Quick Ritual 尚未编排，
   那几个动作是留给它们的。</p>

{body}

<p class="sub">共 {len(moves)} 个动作。审阅结果请标在每条右上角，
   修改意见写在「专家批注」栏。</p>

</body>
</html>
"""

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(document, encoding="utf-8")

    missing_stop = [m["id"] for m in moves if not m.get("source", {}).get("stopSignalsZh")]

    print(f"已生成 {OUTPUT.relative_to(ROOT)}")
    print(f"  {len(moves)} 个动作，{OUTPUT.stat().st_size // 1024} KB，单文件、无外部依赖")
    if missing_stop:
        print(f"  ⚠️ {len(missing_stop)} 个动作没有中文停止信号，表里已标红：{', '.join(missing_stop)}")
    print()
    print("  发给专家的方式：直接发这个 HTML 文件，双击就能看；或者用浏览器打印成 PDF。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
