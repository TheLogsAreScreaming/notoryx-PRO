#!/usr/bin/env python3
"""Lists places in lib/ worth checking for accessibility.

Matches text patterns only: a flagged line is a place to look, not a
confirmed bug, and an unflagged line isn't proof that anything works.

Usage: python3 tool/a11y_scan.py   (from the repository root)
"""
import pathlib
import re
import sys


def call_body(text, start):
    """Text of the call whose opening bracket is at or after start."""
    i = text.index("(", start)
    depth = 0
    quote = None
    j = i
    while j < len(text):
        c = text[j]
        if quote:
            if c == "\\":
                j += 1
            elif c == quote:
                quote = None
        elif c in "'\"":
            quote = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return text[i : j + 1]
        j += 1
    return text[i:]


# Generated translations aren't hand-written UI.
FILES = sorted(
    p for p in pathlib.Path("lib").rglob("*.dart")
    if "l10n" not in p.parts and not p.name.endswith(".g.dart")
)

LABELLED = re.compile(r"Semantics\(|\bText\(|tooltip:|semanticLabel:|labelText:")
CHECKS = [
    ("IconButton", re.compile(r"\bIconButton(?:\.\w+)?\("), re.compile(r"tooltip:")),
    (
        "FloatingActionButton",
        re.compile(r"\bFloatingActionButton(?:\.\w+)?\("),
        re.compile(r"tooltip:"),
    ),
    ("GestureDetector", re.compile(r"\bGestureDetector\("), LABELLED),
    ("InkWell", re.compile(r"\bInkWell\("), LABELLED),
    ("Image", re.compile(r"\bImage(?:\.\w+)?\("), re.compile(r"semanticLabel:")),
]
COUNTS = [
    ("Text scaling clamped or disabled", r"withClampedTextScaling|textScaleFactor:|textScaler: *TextScaler\.noScaling"),
    ("Reduce-motion checks", r"disableAnimations"),
    ("Bold-text checks", r"boldText"),
    ("TextOverflow.ellipsis", r"TextOverflow\.ellipsis"),
    ("FittedBox", r"\bFittedBox\("),
    ("Live regions", r"liveRegion:"),
    ("Text not translated", r"\bText\(\s*'[^']*[A-Za-z]"),
]


def main():
    found = {name: 0 for name, _, _ in CHECKS}
    flagged = []
    totals = {name: 0 for name, _ in COUNTS}
    for path in FILES:
        text = path.read_text(encoding="utf8")
        for name, opener, wanted in CHECKS:
            for m in opener.finditer(text):
                found[name] += 1
                before = text[max(0, m.start() - 160) : m.start()]
                body = call_body(text, m.start())
                if wanted.search(body):
                    continue
                if name in ("GestureDetector", "InkWell") and "Semantics(" in before:
                    continue
                line = text.count("\n", 0, m.start()) + 1
                flagged.append(f"{path}:{line}: {name}")
        for name, pattern in COUNTS:
            totals[name] += len(re.findall(pattern, text))
    print(f"Scanned {len(FILES)} files\n")
    for name, _, _ in CHECKS:
        to_review = sum(1 for f in flagged if f.endswith(": " + name))
        print(f"{name}: {found[name]} found, {to_review} to review")
    print()
    for name, _ in COUNTS:
        print(f"{name}: {totals[name]}")
    if flagged:
        print("\nTo review:")
        print("\n".join(flagged))
    return 0


if __name__ == "__main__":
    sys.exit(main())
