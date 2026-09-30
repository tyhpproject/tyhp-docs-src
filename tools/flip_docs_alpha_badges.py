#!/usr/bin/env python3
"""Flip content/ frontmatter state for stories <= 16.5; prepend not-in-alpha banners."""
from __future__ import annotations

import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1] / "content"
CUTOFF = 16.5

STUB_FILES = {
    "cli_languageServer.md",
    "cli_sourcemapGeneration.md",
    "cli_xdebugProxy.md",
    "cli_tyhpdefGeneration.md",
    "tyhp_3100_internalModifier.md",
    "tyhp_3300_nullConditionalAssignment.md",
    "tyhp_3400_newTypeConstraint.md",
    "tyhp_3500_genericDefaults.md",
}

BANNER = """:::warning Not in this alpha
This feature is **not included** in Tyhp 805.0.0-alpha.1 (roadmap Tier 2/3). The rest of this page describes the planned design. Do not expect these commands or syntax to work yet.
:::

"""

STORY_RE = re.compile(r"^  story: ['\"]([^'\"]+)['\"]\s*$", re.M)
STATE_RE = re.compile(r"^  state: \S+\s*$", re.M)
FM_RE = re.compile(r"\A---\n.*?\n---\n", re.S)


def story_value(raw: str) -> float | None:
    try:
        return float(raw)
    except ValueError:
        return None


def flip_state(text: str) -> str:
    m = STORY_RE.search(text)
    if not m:
        return text
    val = story_value(m.group(1))
    if val is None or val > CUTOFF:
        return text
    return STATE_RE.sub("  state: complete", text, count=1)


def prepend_banner(text: str) -> str:
    if "Not in this alpha" in text:
        return text
    m = FM_RE.match(text)
    if not m:
        return BANNER + text
    return m.group(0) + "\n" + BANNER + text[m.end() :]


def main() -> None:
    for path in sorted(ROOT.glob("*.md")):
        original = path.read_text()
        updated = flip_state(original)
        if path.name in STUB_FILES:
            updated = prepend_banner(updated)
        if updated != original:
            path.write_text(updated)
            print(path.name)


if __name__ == "__main__":
    main()
