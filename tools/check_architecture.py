#!/usr/bin/env python3
"""架构约束检查器 + 轻量 Swift 静态检查。

存在的理由有两个：

1. ARCHITECTURE.md 里那些「必须如此」的约束（Core 不许依赖 ARKit、
   只有一个文件允许出现 landmark 编号、领域模型里不许有对错判断）
   如果只写在文档里，迟早会被改掉。这里把它们变成可执行的检查。

2. 这台开发机没有 Swift 工具链。以下几类错误在 Mac 上会直接编译失败，
   但用纯文本分析就能提前抓到，省一轮 Mac 上的往返：
   - `@objc` 方法所在的类没继承 NSObject
   - 用了高于部署目标的 API
   - 花括号/圆括号不配对

它不是编译器，抓不到类型错误。但它抓到的每一条都是真错。

用法:
    python tools/check_architecture.py
退出码 0 = 无 error。
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CORE = ROOT / "Packages" / "FaceRitualCore" / "Sources" / "FaceRitualCore"
APP = ROOT / "App"

issues: list[tuple[str, str, str]] = []


def error(where: str, message: str) -> None:
    issues.append(("error", where, message))


def warn(where: str, message: str) -> None:
    issues.append(("warning", where, message))


def rel(path: pathlib.Path) -> str:
    return str(path.relative_to(ROOT)).replace("\\", "/")


def swift_files(base: pathlib.Path) -> list[pathlib.Path]:
    return sorted(base.rglob("*.swift"))


def strip_comments_and_strings(text: str) -> str:
    """去掉注释与字符串字面量，保留行数与括号结构。

    必须逐字符单遍扫描，不能用几个 re.sub 串起来。
    之前那版先剥注释再剥字符串，于是 `URL(string: "https://…")` 里的 `//`
    被当成行注释，把同一行后面的 `)` 一起吃掉 —— 括号配对检查就误报了。
    任何含 URL 的字符串都会触发。
    """
    out: list[str] = []
    index = 0
    length = len(text)

    while index < length:
        char = text[index]

        # 块注释（Swift 允许嵌套）
        if text.startswith("/*", index):
            depth = 1
            index += 2
            out.append("  ")
            while index < length and depth > 0:
                if text.startswith("/*", index):
                    depth += 1
                    out.append("  ")
                    index += 2
                elif text.startswith("*/", index):
                    depth -= 1
                    out.append("  ")
                    index += 2
                else:
                    out.append("\n" if text[index] == "\n" else " ")
                    index += 1
            continue

        # 行注释
        if text.startswith("//", index):
            while index < length and text[index] != "\n":
                out.append(" ")
                index += 1
            continue

        # 多行字符串
        if text.startswith('"""', index):
            out.append("   ")
            index += 3
            while index < length and not text.startswith('"""', index):
                out.append("\n" if text[index] == "\n" else " ")
                index += 1
            out.append("   ")
            index += 3
            continue

        # 单行字符串
        if char == '"':
            out.append(" ")
            index += 1
            while index < length and text[index] != '"':
                if text[index] == "\\" and index + 1 < length:
                    out.append("  ")
                    index += 2
                    continue
                out.append("\n" if text[index] == "\n" else " ")
                index += 1
            out.append(" ")
            index += 1
            continue

        out.append(char)
        index += 1

    return "".join(out)


def find_unterminated_string_literals(text: str) -> list[int]:
    """找出跨越了换行的单行字符串字面量，返回它们的起始行号。

    Swift 的单行字面量**不能包含裸换行** —— 那是编译错误
    （error: unterminated string literal）。

    加这条是因为它真的发生过：用 bash heredoc 生成 Swift 代码时，
    `\\n` 被写成了真正的换行，于是 `Text("...\\n\\n...")` 变成了跨三行的
    未闭合字面量。括号配对那条规则没发现 —— 扫描器把后面的内容
    一路当成字符串吞掉，括号数恰好还是平的。Mac 上一编译就炸，
    一次 CI 往返 7 分钟。
    """
    bad: list[int] = []
    index = 0
    length = len(text)
    line = 1

    while index < length:
        char = text[index]

        if char == "\n":
            line += 1
            index += 1
            continue

        if text.startswith("/*", index):
            depth = 1
            index += 2
            while index < length and depth > 0:
                if text.startswith("/*", index):
                    depth += 1
                    index += 2
                elif text.startswith("*/", index):
                    depth -= 1
                    index += 2
                else:
                    if text[index] == "\n":
                        line += 1
                    index += 1
            continue

        if text.startswith("//", index):
            while index < length and text[index] != "\n":
                index += 1
            continue

        # 多行字面量：允许换行，跳过整段
        if text.startswith('"""', index):
            index += 3
            while index < length and not text.startswith('"""', index):
                if text[index] == "\n":
                    line += 1
                index += 1
            index += 3
            continue

        if char == '"':
            start_line = line
            index += 1
            closed = False
            while index < length:
                if text[index] == "\\" and index + 1 < length:
                    # 行尾续行符（多行字面量里才合法，这里遇到就当普通转义）
                    if text[index + 1] == "\n":
                        line += 1
                    index += 2
                    continue
                if text[index] == '"':
                    closed = True
                    index += 1
                    break
                if text[index] == "\n":
                    break          # 裸换行 —— 字面量没闭合
                index += 1
            if not closed:
                bad.append(start_line)
            continue

        index += 1

    return bad


def check_string_literals_are_terminated() -> None:
    for base in (CORE, APP):
        for path in swift_files(base):
            text = path.read_text(encoding="utf-8")
            for lineno in find_unterminated_string_literals(text):
                error(
                    f"{rel(path)}:{lineno}",
                    "单行字符串字面量没有闭合就换行了。Swift 会编译失败"
                    "（unterminated string literal）。"
                    "需要多行文本请用 \"\"\" 三引号字面量。",
                )


# ---------------------------------------------------------------------------
# 1. Core 不得依赖任何 Apple 平台框架
# ---------------------------------------------------------------------------
FORBIDDEN_CORE_IMPORTS = {
    "ARKit", "Vision", "CoreML", "UIKit", "SwiftUI", "AVFoundation",
    "SceneKit", "Metal", "CoreImage", "QuartzCore", "AppKit", "StoreKit",
    "UserNotifications", "CoreGraphics", "Combine",
}


def check_core_isolation() -> None:
    """ARCHITECTURE.md §0：业务层不绑定 provider —— 靠这条编译期隔离保证。"""
    for path in swift_files(CORE):
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            match = re.match(r"\s*import\s+([A-Za-z_][A-Za-z0-9_]*)", line)
            if not match:
                continue
            module = match.group(1)
            if module in FORBIDDEN_CORE_IMPORTS:
                error(
                    f"{rel(path)}:{lineno}",
                    f"FaceRitualCore 不得 import {module} —— 它必须保持平台无关"
                    f"（ARCHITECTURE.md §0）",
                )


# ---------------------------------------------------------------------------
# 2. 只有一个文件允许出现稠密 landmark 编号
# ---------------------------------------------------------------------------
LANDMARK_INDEX_ALLOWLIST = {"App/FaceRitual/FaceAR/Providers/DenseLandmarkLayout.swift"}


def check_landmark_index_containment() -> None:
    """规格 §15：业务层不得依赖某个 landmark provider 的编号。

    检查手段：找 `.imageLeft(` / `.imageRight(` 这类布局槽位语法，
    以及形如 `Array(36...41)` 的编号区间。真正的编号表只应存在于允许清单里。
    """
    pattern = re.compile(r"\b(?:imageLeft|imageRight)\s*\(|Array\(\s*\d+\s*\.\.\.\s*\d+\s*\)")
    for base in (CORE, APP):
        for path in swift_files(base):
            if rel(path) in LANDMARK_INDEX_ALLOWLIST:
                continue
            if "Tests" in rel(path):
                continue
            body = strip_comments_and_strings(path.read_text(encoding="utf-8"))
            for lineno, line in enumerate(body.splitlines(), 1):
                if pattern.search(line):
                    error(
                        f"{rel(path)}:{lineno}",
                        "landmark 编号只允许出现在 DenseLandmarkLayout.swift",
                    )


# ---------------------------------------------------------------------------
# 3. 领域模型里不得出现「做对/做错」判断
# ---------------------------------------------------------------------------
VERDICT_WORDS = re.compile(
    r"\b(isCorrect|isIncorrect|correctness|isWrong|accuracyScore|"
    r"movementScore|performanceScore|isPerformedCorrectly)\b"
)


def check_no_correctness_verdict() -> None:
    """规格 §10：MVP 不承诺实时纠错，领域模型里根本不该有这个概念。"""
    for base in (CORE, APP):
        for path in swift_files(base):
            body = strip_comments_and_strings(path.read_text(encoding="utf-8"))
            for lineno, line in enumerate(body.splitlines(), 1):
                if VERDICT_WORDS.search(line):
                    error(
                        f"{rel(path)}:{lineno}",
                        "领域模型不得包含「做对/做错」判断（规格 §10）。"
                        "如确需实验性纠错，走 MovementSpec.trackingSupport 并逐动作验证。",
                    )


# ---------------------------------------------------------------------------
# 4. @objc 方法所在的类必须继承 NSObject
# ---------------------------------------------------------------------------
CLASS_DECL = re.compile(r"^\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+)?(?:final\s+)?class\s+(\w+)\s*(?::\s*([^{]+))?")


def check_objc_requires_nsobject() -> None:
    """这条在 Mac 上会直接编译失败：
    'method cannot be marked @objc because its class is not @objc compatible'。
    CADisplayLink(target:selector:) 是最常见的触发点。
    """
    for base in (CORE, APP):
        for path in swift_files(base):
            lines = path.read_text(encoding="utf-8").splitlines()
            current_class: str | None = None
            current_inherits: list[str] = []
            class_indent = 0

            for lineno, line in enumerate(lines, 1):
                decl = CLASS_DECL.match(line)
                if decl:
                    current_class = decl.group(1)
                    current_inherits = [
                        part.strip() for part in (decl.group(2) or "").split(",") if part.strip()
                    ]
                    class_indent = len(line) - len(line.lstrip())
                    continue

                if current_class and line.strip() and not line.startswith(" " * (class_indent + 1)):
                    # 缩进回到类声明层级或更外层 → 认为已经离开这个类
                    if not line.strip().startswith("}"):
                        current_class = None

                if "@objc" in line and current_class:
                    # NSObject 或任何以 NS/UI/AV/CA 开头的 ObjC 基类都算合格
                    ok = any(
                        base_name == "NSObject" or base_name.startswith(("NS", "UI", "AV", "CA", "SK", "MK"))
                        for base_name in current_inherits
                    )
                    if not ok:
                        error(
                            f"{rel(path)}:{lineno}",
                            f"类 {current_class} 用了 @objc 但没继承 NSObject —— Mac 上会直接编译失败。"
                            f"当前继承: {current_inherits or '(无)'}",
                        )


# ---------------------------------------------------------------------------
# 5. API 可用性 vs 部署目标
# ---------------------------------------------------------------------------
# 这些 API 需要的最低 iOS 版本。只列我们实际用到、且容易踩的。
API_MIN_IOS = {
    r"\.topBarTrailing\b": 17,
    r"\.topBarLeading\b": 17,
    r"MainActor\.assumeIsolated\b": 17,
    r"ContentUnavailableView\b": 17,
    r"@Observable\b": 17,
    r"\.scrollContentBackground\b": 16,
    r"NavigationStack\b": 16,
    r"\.contentTransition\b": 16,
}

# onChange 的双参数版是 iOS 17；单参数版在 17 起废弃。单独处理。
ONCHANGE_TWO_PARAM = re.compile(r"\.onChange\s*\(\s*of:[^)]*\)\s*\{\s*[^,{}]+,\s*[^,{}]+\s+in")


def deployment_target() -> int:
    text = (ROOT / "project.yml").read_text(encoding="utf-8")
    match = re.search(r'IPHONEOS_DEPLOYMENT_TARGET:\s*"?(\d+)', text)
    return int(match.group(1)) if match else 0


def check_api_availability() -> None:
    target = deployment_target()
    if target == 0:
        warn("project.yml", "读不到 IPHONEOS_DEPLOYMENT_TARGET，跳过 API 可用性检查")
        return

    for path in swift_files(APP):
        body = strip_comments_and_strings(path.read_text(encoding="utf-8"))
        for lineno, line in enumerate(body.splitlines(), 1):
            for pattern, min_ios in API_MIN_IOS.items():
                if re.search(pattern, line) and min_ios > target:
                    error(
                        f"{rel(path)}:{lineno}",
                        f"{pattern.strip('\\b')} 需要 iOS {min_ios}，"
                        f"但部署目标是 iOS {target}",
                    )
            if ONCHANGE_TWO_PARAM.search(line) and target < 17:
                error(
                    f"{rel(path)}:{lineno}",
                    f"onChange 的双参数闭包需要 iOS 17，但部署目标是 iOS {target}。"
                    f"改用单参数版或提高部署目标。",
                )

    # 反向检查：目标 >= 17 时不该再用已废弃的单参数 onChange
    if target >= 17:
        single = re.compile(r"\.onChange\s*\(\s*of:[^)]*\)\s*\{\s*[A-Za-z_][\w]*\s+in")
        for path in swift_files(APP):
            body = strip_comments_and_strings(path.read_text(encoding="utf-8"))
            for lineno, line in enumerate(body.splitlines(), 1):
                if single.search(line) and not ONCHANGE_TWO_PARAM.search(line):
                    warn(f"{rel(path)}:{lineno}", "onChange 单参数版在 iOS 17 起已废弃")


# ---------------------------------------------------------------------------
# 6. 括号配对
# ---------------------------------------------------------------------------
def check_bracket_balance() -> None:
    for base in (CORE, APP):
        for path in swift_files(base):
            body = strip_comments_and_strings(path.read_text(encoding="utf-8"))
            for opener, closer, name in (("{", "}", "花括号"), ("(", ")", "圆括号"), ("[", "]", "方括号")):
                delta = body.count(opener) - body.count(closer)
                if delta != 0:
                    error(
                        rel(path),
                        f"{name}不配对：{opener} 比 {closer} 多 {delta} 个"
                        if delta > 0
                        else f"{name}不配对：{closer} 比 {opener} 多 {-delta} 个",
                    )


# ---------------------------------------------------------------------------
# 7. 动作内容不得硬编码进 Swift
# ---------------------------------------------------------------------------
def check_no_hardcoded_content() -> None:
    """Owner 指令：不能把任何测试动作硬编码进 UI 或业务逻辑。

    检查手段：内容 JSON 里的 routine / step id 不应出现在 Swift 源码里
    （测试与示意图布局除外 —— 它们本来就要引用具体 id）。
    """
    import json

    content_dir = CORE / "Resources"
    routines = json.loads((content_dir / "routines.json").read_text(encoding="utf-8"))
    moves = json.loads((content_dir / "moves.json").read_text(encoding="utf-8"))
    ids = set()
    for move in moves["moves"]:
        ids.add(move["id"])
    for routine in routines["routines"]:
        ids.add(routine["id"])
        # routine 现在只写引用，step id 由 ContentAssembler 合成 —— 这里复刻同一规则。
        for index, ref in enumerate(routine["steps"]):
            ids.add(f"{routine['id']}_{index + 1:02d}_{ref['move']}")

    allow = {
        "Packages/FaceRitualCore/Tests",       # 测试当然要引用具体 id
        "App/FaceRitualTests",
    }
    for base in (CORE, APP):
        for path in swift_files(base):
            relpath = rel(path)
            if any(relpath.startswith(prefix) for prefix in allow):
                continue
            text = path.read_text(encoding="utf-8")
            for content_id in ids:
                if f'"{content_id}"' in text:
                    error(
                        relpath,
                        f"内容 id {content_id!r} 被硬编码进了 Swift。"
                        f"动作内容必须只存在于 Resources/*.json。",
                    )


# ---------------------------------------------------------------------------
# 8. 用户可见界面不得出现中文字面量
# ---------------------------------------------------------------------------
# 只有团队自己看的界面，中文更省事。其余一律走 AppCopy。
DEV_ONLY_SURFACES = (
    "App/FaceRitual/Features/Debug/",
    "App/FaceRitual/Features/Settings/SettingsView.swift",
    "App/FaceRitual/FaceAR/",          # provider 诊断信息，只在 Debug 图层显示
    "App/FaceRitual/Platform/",        # 平台适配层，无直出文案
    "App/FaceRitualTests/",            # 测试断言消息是写给我们自己看的
    "App/FaceRitualUITests/",          # 同上
)

CHINESE_LITERAL = re.compile(r'"[^"\n]*[一-鿿][^"\n]*"')


def check_user_facing_copy_is_english() -> None:
    """规格 §3 / §14：目标用户是欧美用户，主流程要用他们看得懂的语言。

    用户可见界面里的中文字面量一律视为漏改 —— 文案统一放 `AppCopy`，
    这样 Owner 与法务审文案（规格 §19）只需要看一个文件。
    """
    for path in swift_files(APP):
        relative = rel(path)
        if any(relative.startswith(prefix) for prefix in DEV_ONLY_SURFACES):
            continue

        # `#if DEBUG` 里的字符串不会进发布包，是给我们自己看的构建期提醒。
        # 不识别它的话，一条 DEBUG 警告就会被当成漏改的用户文案。
        debug_depth = 0

        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            stripped = line.strip()

            if re.match(r"#if\s+DEBUG\b", stripped):
                debug_depth += 1
                continue
            if debug_depth > 0:
                # #else 之后的分支是会发布的，重新开始检查
                if stripped.startswith("#else"):
                    debug_depth -= 1
                    continue
                if stripped.startswith("#endif"):
                    debug_depth -= 1
                    continue
                continue

            if stripped.startswith("//") or stripped.startswith("*"):
                continue
            for match in CHINESE_LITERAL.finditer(line):
                error(
                    f"{relative}:{lineno}",
                    f"用户可见界面出现中文字面量 {match.group(0)[:40]} —— 应改为 AppCopy 常量",
                )


# ---------------------------------------------------------------------------
# 9. 纯图标按钮必须有无障碍标签
# ---------------------------------------------------------------------------
def check_icon_buttons_have_accessibility_labels() -> None:
    """只有图标、没有文字的按钮，VoiceOver 只会念一句「按钮」。

    播放器的暂停 / 上一步 / 下一步 / 关闭全是这种，
    不给标签等于视障用户完全没法用 —— 这不是加分项，是能不能用的问题。

    判据：`Button` 之后的窗口内出现 `Image(systemName:`，
    但没有 `Text(` / `Label(` / `.accessibilityLabel(`。
    """
    # 用大括号配对确定按钮的真实范围，而不是固定窗口。
    # 窗口太窄会漏掉挂在后面的修饰符，太宽会串到相邻控件的 Text 上 —— 两头都不对。
    satisfied = (".accessibilityLabel(", ".accessibilityElement(", "Text(", "Label(")

    for path in swift_files(APP):
        lines = strip_comments_and_strings(path.read_text(encoding="utf-8")).splitlines()
        original = path.read_text(encoding="utf-8").splitlines()

        for index, line in enumerate(lines):
            if re.search(r"\bButton\s*[({]", line) is None:
                continue
            # 带文字的构造（Button("Close") { … }）直接跳过。
            # 注意此处用原文：字符串已被 strip 掉，只能靠 AppCopy. 前缀判断。
            if re.search(r'Button\s*\(\s*(?:"|AppCopy\.)', original[index]):
                continue

            # 从 Button 起按大括号深度走到闭包结束
            depth = 0
            end = index
            for cursor in range(index, min(len(lines), index + 60)):
                depth += lines[cursor].count("{") - lines[cursor].count("}")
                end = cursor
                if cursor > index and depth <= 0:
                    break

            # 闭包结束后紧跟的修饰符链（以 "." 开头的行）也算按钮的一部分。
            # 链中间可能夹注释 —— 注释已被 strip 成空行，要跳过而不是就此停下。
            tail = end + 1
            while tail < len(lines):
                stripped = lines[tail].strip()
                if stripped == "" or stripped.startswith("."):
                    tail += 1
                    continue
                break

            region = original[index:tail]
            if any("Image(systemName:" in item for item in region) is False:
                continue
            if any(any(token in item for token in satisfied) for item in region):
                continue

            error(
                f"{rel(path)}:{index + 1}",
                "纯图标按钮缺少 .accessibilityLabel —— VoiceOver 只会念「按钮」，用户无法操作",
            )


# ---------------------------------------------------------------------------
# 10. 隐私承诺必须是代码事实
# ---------------------------------------------------------------------------
# 摄像头权限文案对用户说「画面留在设备上，什么都不会被上传」。
# 那句话一旦写出去就是承诺 —— 这里把它锁成可验证的前提。
NETWORK_APIS = re.compile(
    r"\b(URLSession|URLRequest|NSURLConnection|NWConnection|NWBrowser|"
    r"CFReadStream|WKWebView|dataTask|downloadTask|uploadTask)\b"
    r"|^\s*import\s+(Network|CFNetwork)\b"
)

# StoreKit 走 Apple 自己的通道处理支付，不经手摄像头或用户内容，因此不在此列。
NETWORK_ALLOWLIST = ("App/FaceRitual/Platform/StoreKitEntitlementService.swift",)


def check_privacy_claim_holds() -> None:
    """规格 §4「端侧优先」+ 摄像头权限文案里的隐私承诺。

    如果哪天有人加了网络请求，这条会失败并指回那句文案 ——
    要么改代码，要么改承诺，但不能让两者不一致。
    """
    for base in (CORE, APP):
        for path in swift_files(base):
            relative = rel(path)
            if relative.startswith(NETWORK_ALLOWLIST) or "Tests" in relative:
                continue
            body = strip_comments_and_strings(path.read_text(encoding="utf-8"))
            for lineno, line in enumerate(body.splitlines(), 1):
                if NETWORK_APIS.search(line):
                    error(
                        f"{relative}:{lineno}",
                        "出现了联网 API，但摄像头权限文案对用户承诺「画面留在设备上，"
                        "什么都不会被上传」。要么去掉网络调用，要么先改 "
                        "AppCopy.cameraNeededMessage 与 project.yml 的 NSCameraUsageDescription。",
                    )


# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# 11. 网站文案不得出现功效表述
# ---------------------------------------------------------------------------
# 规格 §20 与 Sprint 3 §1：工程侧不得创造医学 / 美容 / 护理功效。
#
# 这条规则针对的是 site/ 下的对外文案。营销文案天然会往「承诺」上滑 ——
# 尤其是以后要在这个站上写文章引流的时候。靠自觉拦不住，所以做成检查。
#
# 例外：明确标了 data-claims-disclaimer 的区块可以出现这些词，
# 因为「我们不声称能提升紧致」这句话本身必须能写出来。
CLAIM_WORDS = [
    # 外观改变
    "anti-aging", "antiaging", "anti-ageing", "younger", "youthful", "rejuvenat",
    "wrinkle", "fine lines", "sagging", "firmer", "firming", "tighten", "tightening",
    "lifted", "lifting", "slimmer", "slimming", "snatched", "contour", "sculpted",
    "plump", "smoother skin", "glow up",
    # 生理声称
    "de-puff", "depuff", "puffiness", "detox", "drain", "circulation",
    "collagen", "boost", "rejuvenate", "metabolis",
    # 结果承诺
    "results in", "visible results", "proven to", "clinically", "scientifically proven",
    "guaranteed", "transform your face", "reverse",
]


def check_site_copy_has_no_efficacy_claims() -> None:
    site = ROOT / "site"
    if not site.exists():
        return

    for path in sorted(site.glob("*.html")):
        text = path.read_text(encoding="utf-8")

        # 去掉 HTML 注释（里面写的是给我们自己看的约束说明，本来就会提到这些词）
        text = re.sub(r"<!--.*?-->", " ", text, flags=re.S)
        # 去掉 <style>/<script>
        text = re.sub(r"<(style|script)\b.*?</\1>", " ", text, flags=re.S | re.I)
        # 去掉标了 data-claims-disclaimer 的区块 —— 免责声明必须能提到这些词
        text = re.sub(
            r"<(\w+)[^>]*\bdata-claims-disclaimer\b.*?</\1>", " ", text, flags=re.S | re.I
        )

        lowered = text.lower()
        for word in CLAIM_WORDS:
            index = lowered.find(word)
            if index < 0:
                continue
            snippet = " ".join(text[max(0, index - 60): index + 60].split())
            error(
                rel(path),
                f"对外文案出现功效词 {word!r}：…{snippet}…\n"
                f"           规格 §20 不允许自行创造功效表述。"
                f"确实需要写「我们**不**声称 X」时，把那段包进 "
                f"<div data-claims-disclaimer> 里。",
            )


def check_release_uses_real_purchases() -> None:
    """Release 构建不得使用 Mock 订阅。

    Mock 的行为是「点一下直接解锁」。如果它进了 Release 包，
    用户点订阅会拿到 Premium 而**不产生任何收入**，而且
    这种错误不会崩、不会报警、测试也照样过 —— 只有收入报表上看得出来。

    检查方式：`MockEntitlementService` 在 App 装配处只能出现在 `#if DEBUG` 里。
    """
    target = APP / "FaceRitual" / "App" / "AppEnvironment.swift"
    if not target.exists():
        error("App/FaceRitual/App/AppEnvironment.swift", "找不到 App 装配文件，无法确认订阅实现")
        return

    debug_depth = 0
    for lineno, line in enumerate(target.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if re.match(r"#if\s+DEBUG\b", stripped):
            debug_depth += 1
            continue
        if stripped.startswith("#endif"):
            debug_depth = max(0, debug_depth - 1)
            continue
        # `#if !DEBUG` 的分支里出现 Mock 才是真问题，这里一并按非 DEBUG 处理。
        if re.match(r"#if\s+!\s*DEBUG\b", stripped):
            debug_depth = 0
            continue
        if stripped.startswith("//"):
            continue
        if "MockEntitlementService" in stripped and debug_depth == 0:
            error(
                f"{rel(target)}:{lineno}",
                "Release 路径上用到了 MockEntitlementService。"
                "它的行为是「点一下直接解锁」—— 进了发布包就是"
                "用户点订阅拿到 Premium 但不产生任何收入，而且不会崩也不会报警。"
                "请把它放进 #if DEBUG。",
            )


def main() -> int:
    print("架构与静态检查\n")

    checks = [
        ("Core 平台隔离", check_core_isolation),
        ("landmark 编号收敛", check_landmark_index_containment),
        ("无对错判断（规格 §10）", check_no_correctness_verdict),
        ("@objc 需 NSObject", check_objc_requires_nsobject),
        ("API 可用性 vs 部署目标", check_api_availability),
        ("括号配对", check_bracket_balance),
        ("字符串字面量闭合", check_string_literals_are_terminated),
        ("动作内容零硬编码", check_no_hardcoded_content),
        ("用户面文案为英文", check_user_facing_copy_is_english),
        ("纯图标按钮有无障碍标签", check_icon_buttons_have_accessibility_labels),
        ("隐私承诺与代码一致", check_privacy_claim_holds),
        ("网站文案无功效表述", check_site_copy_has_no_efficacy_claims),
        ("Release 使用真实订阅", check_release_uses_real_purchases),
    ]

    for name, check in checks:
        before = len(issues)
        check()
        added = len(issues) - before
        status = "OK" if added == 0 else f"{added} 个问题"
        print(f"  [{status:>8}] {name}")

    errors = [i for i in issues if i[0] == "error"]
    warnings = [i for i in issues if i[0] == "warning"]

    if issues:
        print()
        for severity, where, message in issues:
            print(f"  [{severity}] {where}\n           {message}")

    core_count = len(swift_files(CORE))
    app_count = len(swift_files(APP))
    print(f"\n已检查 {core_count + app_count} 个 Swift 文件（Core {core_count} / App {app_count}）")
    print(f"errors={len(errors)} warnings={len(warnings)}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
