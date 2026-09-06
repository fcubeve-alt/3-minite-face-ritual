#!/usr/bin/env python3
"""Swift 跨文件引用检查器（无编译器版）。

这台机器没有 Swift 工具链，59 个文件全靠手写。编译器能抓的类型错误抓不到，
但下面三类错误纯文本分析就能查，而且它们恰好是手写大量代码时最常犯的：

  1. 引用了不存在的枚举 case（改名后漏改调用点）
  2. 初始化器参数标签对不上（加/删/改参数后漏改调用点）
  3. 声明了协议一致性但没实现全部要求

它不是编译器。为了让报出来的每一条都值得看，宁可漏报也不误报：
  - 只检查**我们自己声明**的类型，不碰 Apple SDK
  - 解析不确定的地方一律跳过而不是猜
  - 每条规则都有对应的自测（--self-test）

已知盲区（漏报，不是误报）：
  - 字符串插值内部的引用查不到 —— strip_noise 会把整个字符串抹成空白
  - 带尾随闭包的调用跳过 init 标签检查（实参个数对不上，判不准）
  - 协议一致性只按名字比对，不比签名
  - 裸 `.someCase`（靠类型推断的）不查，只查带类型名的限定引用

用法:
    python tools/check_swift_refs.py
    python tools/check_swift_refs.py --self-test   # 用故意写错的代码验证检查器有效
"""

from __future__ import annotations

import pathlib
import re
import sys
from dataclasses import dataclass, field

# Windows 检出是 CRLF。下面用「行长 + 1」推算字符偏移，
# 不先归一化换行的话每行会差 1 个字符，match_paren 就会从错误的位置开始配对。
CRLF = "\r\n"
LF = "\n"

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE_DIRS = [
    ROOT / "Packages" / "FaceRitualCore" / "Sources",
    ROOT / "App",
]

issues: list[tuple[str, str, str]] = []


def error(where: str, message: str) -> None:
    issues.append(("error", where, message))


def rel(path: pathlib.Path) -> str:
    return str(path.relative_to(ROOT)).replace("\\", "/")


# ---------------------------------------------------------------------------
# 词法预处理
# ---------------------------------------------------------------------------
def strip_noise(text: str) -> str:
    """去掉注释与字符串字面量，但**保留行数与括号结构**。

    保留行数是为了报错时能指出行号；
    字符串换成等长空白是为了不让字符串里的括号干扰配对。
    """
    out = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        # 块注释
        if text.startswith("/*", i):
            depth = 1
            i += 2
            out.append("  ")
            while i < n and depth > 0:
                if text.startswith("/*", i):
                    depth += 1
                    out.append("  ")
                    i += 2
                elif text.startswith("*/", i):
                    depth -= 1
                    out.append("  ")
                    i += 2
                else:
                    out.append("\n" if text[i] == "\n" else " ")
                    i += 1
            continue
        # 行注释
        if text.startswith("//", i):
            while i < n and text[i] != "\n":
                out.append(" ")
                i += 1
            continue
        # 多行字符串
        if text.startswith('"""', i):
            out.append("   ")
            i += 3
            while i < n and not text.startswith('"""', i):
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
            out.append("   ")
            i += 3
            continue
        # 单行字符串（含插值 —— 插值里的括号一并抹掉，够用）
        if ch == '"':
            out.append(" ")
            i += 1
            while i < n and text[i] != '"':
                if text[i] == "\\" and i + 1 < n:
                    out.append("  ")
                    i += 2
                    continue
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
            out.append(" ")
            i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def match_paren(text: str, open_index: int) -> int:
    """返回与 text[open_index] 配对的右括号下标，找不到返回 -1。"""
    pairs = {"(": ")", "[": "]", "{": "}"}
    opener = text[open_index]
    closer = pairs[opener]
    depth = 0
    for i in range(open_index, len(text)):
        if text[i] in pairs:
            depth += 1
        elif text[i] in pairs.values():
            depth -= 1
            if depth == 0:
                return i if text[i] == closer else -1
    return -1


def split_top_level(text: str, separator: str = ",") -> list[str]:
    """按顶层分隔符切分，忽略括号内的分隔符。"""
    parts = []
    depth = 0
    current = []
    for ch in text:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        if ch == separator and depth == 0:
            parts.append("".join(current))
            current = []
        else:
            current.append(ch)
    if "".join(current).strip():
        parts.append("".join(current))
    return parts


# ---------------------------------------------------------------------------
# 声明抽取
# ---------------------------------------------------------------------------
@dataclass
class TypeInfo:
    name: str
    kind: str                                   # struct / class / enum / protocol / actor
    file: str = ""
    line: int = 0
    inherits: list[str] = field(default_factory=list)
    cases: set[str] = field(default_factory=set)          # 枚举 case
    members: set[str] = field(default_factory=set)        # func / var / let / 嵌套类型名
    inits: list[list[str]] = field(default_factory=list)  # 每个 init 的参数标签序列
    init_required: list[set[str]] = field(default_factory=list)  # 无默认值的标签
    requirements: set[str] = field(default_factory=set)   # 协议要求（仅 protocol）
    # 成员名 → [(文件, 行号, 种类)]，种类为 "func" / "property"。
    # members 是 set，同名会被吞掉，查重需要保留每一次声明。
    member_sites: dict = field(default_factory=dict)


DECL_RE = re.compile(
    r"^\s*(?:@[\w.()]+\s+)*"
    r"(?:public\s+|internal\s+|private\s+|fileprivate\s+|open\s+)?"
    r"(?:final\s+)?(?:indirect\s+)?"
    r"(struct|class|enum|protocol|actor|extension)\s+"
    r"([A-Z]\w*)"
    r"([^{]*)"
)

MEMBER_RE = re.compile(
    r"^\s*(?:@[\w.()]+\s+)*"
    r"(?:(?:public|internal|private|fileprivate|open)\s+)?"
    # private(set) / fileprivate(set) / internal(set)
    r"(?:(?:private|fileprivate|internal|public)\(set\)\s+)?"
    r"(?:(?:static|class|final|mutating|override|lazy|weak|unowned|nonisolated)\s+)*"
    r"(?:(func)\s+(\w+)|(var|let)\s+(\w+))"
)

CASE_RE = re.compile(r"^\s*(?:indirect\s+)?case\s+(.+)$")


def has_top_level_default(param: str) -> bool:
    """参数是否带默认值。

    不能用 split_top_level 的分段数来判断：字符串字面量已被 strip_noise 抹成空白，
    `version: String = "0.0.1"` 会变成 `version: String =        `，
    尾段全是空白会被 split 丢掉，于是「有默认值」被误判为没有。
    这里直接找顶层的赋值号，并排除 == != >= <= 这些比较运算。
    """
    depth = 0
    for index, ch in enumerate(param):
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == "=" and depth == 0:
            previous = param[index - 1] if index > 0 else " "
            following = param[index + 1] if index + 1 < len(param) else " "
            if previous in "=!<>" or following == "=":
                continue
            return True
    return False


def parse_init_labels(signature: str) -> tuple[list[str], set[str]]:
    """从 init 的参数列表文本里取出标签序列与「无默认值」的标签集合。"""
    labels: list[str] = []
    required: set[str] = set()
    for param in split_top_level(signature):
        param = param.strip()
        if not param:
            continue
        has_default = has_top_level_default(param)
        # 形式：  label name: Type = default   /   _ name: Type   /   name: Type
        head = param.split(":", 1)[0].strip()
        tokens = head.split()
        if not tokens:
            continue
        label = tokens[0]
        labels.append(label)
        if not has_default:
            required.add(label)
    return labels, required


def parse_file(path: pathlib.Path, types: dict[str, TypeInfo]) -> None:
    # 归一化换行：Windows 检出是 CRLF，而下面用「行长 + 1」推算字符偏移，
    # 不归一化的话每行差 1 个字符，match_paren 会从错误的位置开始配对。
    raw = path.read_text(encoding="utf-8").replace(CRLF, LF)
    text = strip_noise(raw)
    lines = text.splitlines()

    # (类型名, 声明所在缩进, 是否是 extension) 栈
    stack: list[tuple[str, int, bool]] = []
    conditional_depth = 0

    for lineno, line in enumerate(lines, 1):
        stripped = line.strip()
        if not stripped:
            continue
        indent = len(line) - len(line.lstrip())

        # 退栈：缩进回到或低于声明层，说明离开了那个类型
        while stack and indent <= stack[-1][1] and not stripped.startswith("}"):
            stack.pop()

        decl = DECL_RE.match(line)
        if decl:
            kind, name, tail = decl.group(1), decl.group(2), decl.group(3)
            if kind == "extension":
                info = types.setdefault(name, TypeInfo(name=name, kind="extension"))
            else:
                info = types.get(name)
                if info is None or info.kind == "extension":
                    info = TypeInfo(name=name, kind=kind)
                    types[name] = info
                info.kind = kind
                info.file = rel(path)
                info.line = lineno
            if ":" in tail:
                inherited = tail.split(":", 1)[1]
                inherited = inherited.split(" where ")[0]
                info.inherits.extend(
                    t.strip().split("<")[0] for t in split_top_level(inherited) if t.strip()
                )
            stack.append((name, indent, kind == "extension"))
            continue

        if not stack:
            continue
        owner_name, owner_indent, in_extension = stack[-1]
        owner = types[owner_name]
        # 只认「恰好比类型声明深一层」的成员。
        # 再深就是函数体里的局部变量了 —— 那些不是类型成员。
        is_direct_member = indent == owner_indent + 4

        # 枚举 case
        case_match = CASE_RE.match(line)
        if case_match and is_direct_member and owner.kind in ("enum", "extension"):
            body = case_match.group(1)
            # `case a, b, c` / `case a(Int)` / `case a = "x"`
            for piece in split_top_level(body):
                name = piece.strip().split("(")[0].split("=")[0].strip()
                if re.fullmatch(r"\w+", name):
                    owner.cases.add(name)
            continue

        # init
        init_match = re.match(r"^\s*(?:@\w+\s+)*(?:public\s+|internal\s+|private\s+|fileprivate\s+)?"
                              r"(?:convenience\s+|required\s+|override\s+)*init\??\s*(\()", line)
        if init_match and is_direct_member:
            start = line.index("(", init_match.start(1))
            absolute = sum(len(l) + 1 for l in lines[:lineno - 1]) + start
            end = match_paren(text, absolute)
            if end != -1:
                labels, required = parse_init_labels(text[absolute + 1:end])
                owner.inits.append(labels)
                owner.init_required.append(required)
            continue

        member = MEMBER_RE.match(line)
        if member and is_direct_member:
            name = member.group(2) or member.group(4)
            if name:
                owner.members.add(name)
                # 只在**没有条件编译**的地方记录：`#if DEBUG` 的两个分支里
                # 出现同名成员是合法的，记进去会误报。
                if conditional_depth == 0:
                    kind = "func" if member.group(1) else "property"
                    # 只留签名，去掉函数体与默认值 —— 重载的区别在参数表，
                    # 而复制粘贴出来的重复往往连函数体都不一样。
                    signature = " ".join(stripped.split("{")[0].split())
                    owner.member_sites.setdefault(name, []).append(
                        (rel(path), lineno, kind, signature)
                    )
                # 协议**本体**里的才是「要求」。
                # 写在 `extension SomeProtocol` 里的是默认实现 ——
                # 遵循者不需要再实现一遍，算成要求会大批误报。
                if owner.kind == "protocol" and not in_extension:
                    owner.requirements.add(name)


# ---------------------------------------------------------------------------
# 检查
# ---------------------------------------------------------------------------
def check_duplicate_members(types: dict[str, TypeInfo]) -> None:
    """同一个类型里重复声明同名**属性** —— Swift 直接编译失败。

    加这条是因为它真的发生过：给 ARGuidanceController 加 POC 访问器时，
    我写了一个和已有 `lockLossCount` 重名的属性。这类错误 Mac 上一编译就炸，
    在 Windows 上完全看不出来，一次 CI 往返 7 分钟。

    **只查属性（var / let），不查方法。** 第一版没区分，在干净的代码库上
    报了 6 个误报 —— 因为 Swift 里：
      - 方法可以重载：`decide(routine:level:)` 与 `decide(mode:routine:level:)`
      - 属性和方法可以同名：`let routines` 与 `func routines(ofType:)`
      - 委托方法天生成组同名：`speechSynthesizer(_:didFinish:)` / `(_:didCancel:)`
    一条会喊狼来了的规则比没有规则更糟，所以宁可缩小范围。

    同样只查**同一文件内**：跨文件 extension 之间重名也是错误，
    但那需要更完整的解析才能不误报。
    """
    for info in types.values():
        for name, sites in info.member_sites.items():
            properties: dict = {}
            for file, lineno, kind, _ in sites:
                if kind != "property":
                    continue
                properties.setdefault(file, []).append(lineno)
            for file, lines_ in properties.items():
                if len(lines_) > 1:
                    ordered = sorted(lines_)
                    error(
                        f"{file}:{ordered[1]}",
                        f"{info.name} 里重复声明了属性 {name!r}"
                        f"（另一处在第 {ordered[0]} 行）。Swift 会编译失败。",
                    )


def check_identical_declarations(types: dict[str, TypeInfo]) -> None:
    """同一个类型、同一个文件里出现**一模一样**的声明行 —— 几乎必然是复制粘贴事故。

    上一条规则（重复声明属性）刻意放过了方法，因为 Swift 允许重载。
    但重载的参数表一定不同，所以**声明行原文完全相同**就不是重载，是重复。

    加这条是因为我自己犯过：一个批量编辑脚本用「从 A 删到 B」的写法，
    而 B 在文件里出现在 A 之前，于是变成了插入 ——
    `private func safetyNote(_:)` 被复制成两份。
    Mac 上一编译就炸（invalid redeclaration），Windows 上完全看不出来。
    """
    for info in types.values():
        for name, sites in info.member_sites.items():
            by_line: dict = {}
            for file, lineno, _, text in sites:
                by_line.setdefault((file, text), []).append(lineno)
            for (file, text), lines_ in by_line.items():
                if len(lines_) > 1:
                    ordered = sorted(lines_)
                    error(
                        f"{file}:{ordered[1]}",
                        f"{info.name} 里出现了两处一模一样的声明 {name!r}"
                        f"（另一处在第 {ordered[0]} 行）：{text[:70]}"
                        f" —— 参数表相同就不是重载，Swift 会报 invalid redeclaration。",
                    )


def check_enum_case_references(types: dict[str, TypeInfo], files: list[pathlib.Path]) -> None:
    """`OurEnum.someCase` 里的 someCase 必须真的存在。

    只查**限定引用**（带类型名的），因为裸 `.foo` 的类型要靠推断，容易误报。
    """
    enums = {
        name: info for name, info in types.items()
        if info.kind == "enum" and (info.cases or info.members)
    }
    if not enums:
        return
    pattern = re.compile(r"\b(" + "|".join(re.escape(n) for n in enums) + r")\.(\w+)")

    for path in files:
        text = strip_noise(path.read_text(encoding="utf-8").replace(CRLF, LF))
        for lineno, line in enumerate(text.splitlines(), 1):
            for match in pattern.finditer(line):
                type_name, member = match.group(1), match.group(2)
                info = enums[type_name]
                known = info.cases | info.members | {
                    # Swift 为枚举自动合成的成员
                    "allCases", "rawValue", "init", "self", "Type", "some", "none",
                }
                if member not in known:
                    error(
                        f"{rel(path)}:{lineno}",
                        f"{type_name}.{member} 不存在。已知 case: {', '.join(sorted(info.cases)) or '(无)'}",
                    )


def check_initializer_labels(types: dict[str, TypeInfo], files: list[pathlib.Path]) -> None:
    """`OurType(...)` 的参数标签必须能对上某个已声明的 init。"""
    candidates = {
        name: info for name, info in types.items()
        if info.inits and info.kind in ("struct", "class", "actor")
    }
    if not candidates:
        return
    pattern = re.compile(r"(?<![\w.])(" + "|".join(re.escape(n) for n in candidates) + r")\s*\(")

    for path in files:
        text = strip_noise(path.read_text(encoding="utf-8").replace(CRLF, LF))
        offsets = [0]
        for line in text.splitlines(keepends=True):
            offsets.append(offsets[-1] + len(line))

        for match in pattern.finditer(text):
            type_name = match.group(1)
            open_index = text.index("(", match.end() - 1)
            close_index = match_paren(text, open_index)
            if close_index == -1:
                continue

            args = text[open_index + 1:close_index]
            call_labels = []
            for piece in split_top_level(args):
                piece = piece.strip()
                if not piece:
                    continue
                label_match = re.match(r"^(\w+)\s*:", piece)
                call_labels.append(label_match.group(1) if label_match else "_")

            info = candidates[type_name]
            # 尾随闭包会让实参少一个，无法可靠判断 —— 跳过。
            after = text[close_index + 1:close_index + 40].lstrip()
            if after.startswith("{"):
                continue

            if any(matches_init(call_labels, labels, required)
                   for labels, required in zip(info.inits, info.init_required)):
                continue

            lineno = next(i for i, off in enumerate(offsets) if off > open_index)
            expected = " | ".join("(" + ", ".join(l) + ")" for l in info.inits) or "(无)"
            error(
                f"{rel(path)}:{lineno}",
                f"{type_name}(...) 的参数标签 ({', '.join(call_labels) or '空'}) 对不上任何已声明的 init。"
                f" 已声明: {expected}",
            )


def matches_init(call: list[str], declared: list[str], required: set[str]) -> bool:
    """调用的标签序列必须是声明标签的子序列，且覆盖全部必填项。"""
    index = 0
    for label in call:
        while index < len(declared) and declared[index] != label:
            index += 1
        if index == len(declared):
            return False
        index += 1
    return required.issubset(set(call))


def check_protocol_conformance(types: dict[str, TypeInfo]) -> None:
    """声明了我们自己的协议，就必须把要求都实现掉（按名字查，不比签名）。"""
    protocols = {n: i for n, i in types.items() if i.kind == "protocol" and i.requirements}
    if not protocols:
        return

    for name, info in types.items():
        if info.kind not in ("struct", "class", "actor", "enum"):
            continue
        for parent in info.inherits:
            protocol = protocols.get(parent)
            if protocol is None:
                continue
            missing = protocol.requirements - info.members
            if missing:
                error(
                    f"{info.file}:{info.line}",
                    f"{name} 声明遵循 {parent}，但缺少: {', '.join(sorted(missing))}",
                )


# ---------------------------------------------------------------------------
def collect_files() -> list[pathlib.Path]:
    files: list[pathlib.Path] = []
    for base in SOURCE_DIRS:
        files.extend(sorted(base.rglob("*.swift")))
    return files


def run(files: list[pathlib.Path]) -> None:
    types: dict[str, TypeInfo] = {}
    for path in files:
        parse_file(path, types)

    check_enum_case_references(types, files)
    check_initializer_labels(types, files)
    check_protocol_conformance(types)
    check_duplicate_members(types)
    check_identical_declarations(types)


SELF_TEST_SOURCE = '''
enum Fruit {
    case apple
    case banana
}

protocol Greeter {
    func greet()
    var name: String { get }
}

struct Duplicated {
    var lockLossCount: Int { 0 }
    var other: Int { 1 }
    var lockLossCount: Int { 2 }
}

struct CopyPasted {
    private func safetyNote(_ note: String) -> Int { 0 }
    private func other() -> Int { 1 }
    private func safetyNote(_ note: String) -> Int { 2 }
    // 真正的重载不该被误报：参数表不同
    private func overloaded(a: Int) -> Int { 0 }
    private func overloaded(b: String) -> Int { 1 }
}

struct Person: Greeter {
    var name: String
    init(name: String, age: Int = 0) {
        self.name = name
    }
}

struct Caller {
    func run() {
        let a = Fruit.apple
        let b = Fruit.cherry
        let p = Person(name: "x")
        let q = Person(nickname: "x")
        _ = (a, b, p, q)
    }
}
'''


def self_test() -> int:
    """用故意写错的代码验证三条规则都会报错。"""
    import tempfile

    global issues
    with tempfile.TemporaryDirectory() as tmp:
        path = pathlib.Path(tmp) / "SelfTest.swift"
        path.write_text(SELF_TEST_SOURCE, encoding="utf-8")

        # 让 rel() 能处理临时目录
        global ROOT
        original_root = ROOT
        ROOT = pathlib.Path(tmp)
        issues = []
        run([path])
        ROOT = original_root

        found = {message for _, _, message in issues}
        expectations = {
            "枚举不存在的 case": any("Fruit.cherry" in m for m in found),
            "init 标签对不上": any("Person(...)" in m for m in found),
            "协议要求未实现": any("greet" in m for m in found),
            "重复声明属性": any("重复声明了属性" in m for m in found),
            "一模一样的声明": any("一模一样的声明" in m for m in found),
            "重载不误报": not any("overloaded" in m for m in found),
        }

        print("自测（用故意写错的代码验证检查器有效）:")
        for name, ok in expectations.items():
            print(f"  [{'命中' if ok else '漏报'}] {name}")
        for _, where, message in issues:
            print(f"    → {where}: {message}")

        return 0 if all(expectations.values()) else 1


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()

    files = collect_files()
    run(files)

    print("Swift 引用检查（枚举 case / init 标签 / 协议一致性）\n")
    for severity, where, message in issues:
        print(f"  [{severity}] {where}\n           {message}")
    if not issues:
        print("  无问题")
    print(f"\n已检查 {len(files)} 个 Swift 文件")
    print(f"errors={len(issues)}")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
