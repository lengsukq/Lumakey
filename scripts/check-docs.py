#!/usr/bin/env python3
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
INDEX = DOCS / "INDEX.md"

LINK_RE = re.compile(r"\[[^\]]+\]\(([^)#]+)(#[^)]+)?\)")
HEADING_RE = re.compile(r"^\s{0,3}#{1,6}\s+(.+?)\s*$")


def slugify(heading: str) -> str:
    clean = re.sub(r"[`*_~]", "", heading.strip().lower())
    clean = re.sub(r"[^\w\s\-\u4e00-\u9fff]", "", clean)
    return re.sub(r"\s+", "-", clean).strip("-")


def collect_anchors(md_path: Path) -> set[str]:
    anchors = set()
    for line in md_path.read_text(encoding="utf-8").splitlines():
        m = HEADING_RE.match(line)
        if m:
            anchors.add(slugify(m.group(1)))
    return anchors


def main() -> int:
    issues: list[str] = []
    md_files = [ROOT / "README.md", ROOT / "AGENTS.md", *sorted(DOCS.glob("*.md"))]
    anchor_cache = {p: collect_anchors(p) for p in md_files if p.exists()}

    index_text = INDEX.read_text(encoding="utf-8") if INDEX.exists() else ""
    for doc_file in sorted(DOCS.glob("*.md")):
        if doc_file.name == "INDEX.md":
            continue
        if f"({doc_file.name})" not in index_text:
            issues.append(f"docs/INDEX.md missing link to ({doc_file.name})")

    for md in md_files:
        if not md.exists():
            issues.append(f"Missing expected file: {md.relative_to(ROOT)}")
            continue
        for lineno, line in enumerate(md.read_text(encoding="utf-8").splitlines(), 1):
            for match in LINK_RE.finditer(line):
                target, anchor = match.group(1), match.group(2)
                if target.startswith(("http://", "https://", "mailto:", "lumakey://")):
                    continue
                resolved = (md.parent / target).resolve()
                if not resolved.exists():
                    issues.append(f"{md.relative_to(ROOT)}:{lineno} broken link -> {target}")
                    continue
                if anchor and resolved in anchor_cache:
                    slug = anchor.lstrip("#").lower()
                    if slug not in anchor_cache[resolved]:
                        issues.append(f"{md.relative_to(ROOT)}:{lineno} missing anchor #{slug} in {target}")

    for issue in issues:
        print(f"ISSUE: {issue}")
    print(f"Checked {len(md_files)} docs: {len(issues)} issue(s)")
    return 1 if issues else 0


if __name__ == "__main__":
    sys.exit(main())
