#!/usr/bin/env python3
"""对 validate_content.py 做反向验证：故意写坏内容，确认每条规则真的会报错。

存在的理由：一条从不触发的检查比没有检查更糟 —— 它给人「已经验过了」的错觉。
这个脚本把内容 JSON 复制到临时目录，逐条注入缺陷，跑一遍校验器，
检查它是否报出了预期的错误。任何一条没报出来，就说明那条规则已经失效。

新增校验规则时，请在 CASES 里同时加一条对应的破坏用例。

用法:
    python tools/check_validator_teeth.py
退出码 0 = 每条规则都还有牙齿。
"""

from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
RESOURCES = "Packages/FaceRitualCore/Sources/FaceRitualCore/Resources"
SRC = ROOT / RESOURCES
DOCS = ("anchors.json", "moves.json", "routines.json", "content_meta.json")

CASES: list[tuple[str, object, str]] = []


def case(name: str, expect: str):
    """注册一条破坏用例。expect 是期望在输出里出现的错误片段。"""

    def decorate(fn):
        CASES.append((name, fn, expect))
        return fn

    return decorate


def move(docs: dict, move_id: str) -> dict:
    return next(m for m in docs["moves.json"]["moves"] if m["id"] == move_id)


# ---------------------------------------------------------------------------
# 破坏用例
# ---------------------------------------------------------------------------
@case("工具动作被允许进 morning", "不能依赖工具")
def _(docs):
    move(docs, "GM-19")["allowedRoutineTypes"] = ["morning", "quick"]


@case("morning routine 里塞了只允许 quick 的动作", "却出现在 morning routine 里")
def _(docs):
    docs["routines.json"]["routines"][0]["steps"][0]["move"] = "GM-19"


@case("tap 既无 focusAnchors 也无 startAnchor", "pathType=tap 需要 focusAnchors")
def _(docs):
    movement = move(docs, "GM-15")["movement"]
    movement.pop("focusAnchors", None)
    movement.pop("startAnchor", None)


@case("focusAnchors 指向不存在的 anchor", "focusAnchors 引用了不存在的 anchor")
def _(docs):
    move(docs, "GM-15")["movement"]["focusAnchors"] = ["nowhere_left"]


@case("allowedRoutineTypes 为空", "allowedRoutineTypes 为空")
def _(docs):
    move(docs, "GM-02")["allowedRoutineTypes"] = []


@case("未知 intensity", "未知 intensity")
def _(docs):
    move(docs, "GM-02")["intensity"] = "crushing"


@case("动作缺中文原文标题", "缺少 source.titleZh")
def _(docs):
    del move(docs, "GM-02")["source"]["titleZh"]


@case("routine 引用不存在的动作", "引用了动作库里不存在的动作")
def _(docs):
    docs["routines.json"]["routines"][0]["steps"][0]["move"] = "GM-99"


@case("schemaVersion 回退", "schemaVersion 应为")
def _(docs):
    docs["content_meta.json"]["schemaVersion"] = 1


@case("未知 pathType", "未知 pathType")
def _(docs):
    move(docs, "GM-02")["movement"]["pathType"] = "spiral"


@case("defaultDurationSeconds 为 0", "defaultDurationSeconds 必须 > 0")
def _(docs):
    move(docs, "GM-02")["defaultDurationSeconds"] = 0


@case("line 缺 endAnchor", "需要同时提供 startAnchor 与 endAnchor")
def _(docs):
    del move(docs, "GM-02")["movement"]["endAnchor"]


@case("anchor 引用不存在的 landmark", "未知 landmark")
def _(docs):
    docs["anchors.json"]["anchors"][0]["rule"] = {"type": "landmark", "id": "thirdEye"}


@case("morning routine 被标为 premium", "不得标记为 premium")
def _(docs):
    docs["routines.json"]["routines"][0]["isPremium"] = True


@case("没有任何免费 Morning Core", "缺少免费的 Morning Core")
def _(docs):
    for routine in docs["routines.json"]["routines"]:
        routine["type"] = "quick"


# ---------------------------------------------------------------------------
def run_case(mutate) -> tuple[int, str]:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="fr_teeth_"))
    try:
        resources = tmp / RESOURCES
        resources.parent.mkdir(parents=True)
        shutil.copytree(SRC, resources)
        (tmp / "tools").mkdir()
        shutil.copy(ROOT / "tools" / "validate_content.py", tmp / "tools" / "validate_content.py")

        docs = {name: json.loads((resources / name).read_text(encoding="utf-8")) for name in DOCS}
        mutate(docs)
        for name, doc in docs.items():
            (resources / name).write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")

        proc = subprocess.run(
            [sys.executable, str(tmp / "tools" / "validate_content.py")],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=dict(os.environ, PYTHONIOENCODING="utf-8"),
        )
        return proc.returncode, (proc.stdout or "") + (proc.stderr or "")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main() -> int:
    # 先确认未经破坏的内容包本身是干净的，否则下面的判断全都不可信。
    baseline = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "validate_content.py")],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=dict(os.environ, PYTHONIOENCODING="utf-8"),
    )
    if baseline.returncode != 0:
        print("基线就不干净：当前内容包本身有 error，先修好再谈规则有没有牙齿。")
        print(baseline.stdout)
        return 1

    print(f"反向验证 {len(CASES)} 条校验规则（每条注入一个缺陷，看校验器是否报错）\n")
    failed = 0
    for name, mutate, expect in CASES:
        code, output = run_case(mutate)
        ok = code == 1 and expect in output
        print(("  PASS  " if ok else "  FAIL  ") + name)
        if not ok:
            failed += 1
            print(f"        期望输出里包含: {expect}")
            print(f"        实际退出码: {code}")
            for line in output.splitlines():
                if "[error]" in line:
                    print("        " + line.strip())

    print(f"\n{len(CASES) - failed}/{len(CASES)} 条规则确认有效")
    if failed:
        print("有规则失效了 —— 它不会拦住任何东西，等于不存在。")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
