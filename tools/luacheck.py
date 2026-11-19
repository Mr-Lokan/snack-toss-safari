"""Crude Lua sanity check: block keywords vs 'end' and bracket balance.

python -I luacheck.py <file.lua> ...
"""
import re
import sys

KEYWORD = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def strip(src):
    """Return source with comments and string contents removed."""
    out, i, n = [], 0, len(src)
    while i < n:
        if src.startswith("--", i):
            m = re.match(r"--\[(=*)\[", src[i:])
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, i)
                assert j != -1, "unterminated block comment"
                out.append("\n" * src.count("\n", i, j))
                i = j + len(close)
            else:
                j = src.find("\n", i)
                i = n if j == -1 else j
            continue
        m = re.match(r"\[(=*)\[", src[i:])
        if m:
            close = "]" + m.group(1) + "]"
            j = src.find(close, i)
            assert j != -1, "unterminated long string"
            out.append('""' + "\n" * src.count("\n", i, j))
            i = j + len(close)
            continue
        c = src[i]
        if c in "\"'":
            j = i + 1
            while src[j] != c:
                assert src[j] != "\n", f"unterminated string at line {src.count(chr(10), 0, i) + 1}"
                j += 2 if src[j] == "\\" else 1
            out.append('""')
            i = j + 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def check(path):
    src = open(path, encoding="utf-8").read()
    code = strip(src)
    stack = []
    line = 1
    pos = 0
    for m in re.finditer(r"[A-Za-z_][A-Za-z0-9_]*|[()\[\]{}]|\n", code):
        tok = m.group(0)
        if tok == "\n":
            line += 1
            continue
        # skip field access like foo.end / foo:do
        prev = code[m.start() - 1] if m.start() else ""
        if prev in ".:" and KEYWORD.fullmatch(tok):
            continue
        if tok in ("function", "if", "do", "repeat", "(", "[", "{"):
            stack.append((tok, line))
        elif tok in ("end", "until", ")", "]", "}"):
            want = {"end": ("function", "if", "do"), "until": ("repeat",), ")": ("(",), "]": ("[",), "}": ("{",)}[tok]
            assert stack, f"{path}:{line}: unexpected '{tok}'"
            top, top_line = stack.pop()
            assert top in want, f"{path}:{line}: '{tok}' closes '{top}' from line {top_line}"
    assert not stack, f"{path}: unclosed {stack[-1]}"
    # 'for'/'while' must be followed by 'do' on the same statement: count them
    fors = len(re.findall(r"\b(for|while)\b", code))
    dos = len(re.findall(r"\bdo\b", code))
    assert dos >= fors, f"{path}: {fors} for/while but {dos} do"
    ifs = len(re.findall(r"(?<![.:])\b(if|elseif)\b", code))
    thens = len(re.findall(r"\bthen\b", code))
    assert ifs == thens, f"{path}: {ifs} if/elseif but {thens} then"
    print(f"ok  {path}")


for p in sys.argv[1:]:
    try:
        check(p)
    except AssertionError as e:
        print(f"ERR {p}: {e}")
