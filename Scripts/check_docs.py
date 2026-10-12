#!/usr/bin/env python3
"""Check repository documentation for broken local Markdown links."""

from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parent.parent
LINK = re.compile(r"\]\(([^\s)]+)(?:\s+\"[^\"]*\")?\)")


def main() -> int:
    documents = sorted(ROOT.glob("*.md")) + sorted((ROOT / "Docs").rglob("*.md"))
    documents += sorted((ROOT / ".github").rglob("*.md"))
    errors = []
    for document in documents:
        # Preserve third-party source material without imposing our documentation rules.
        if "Licenses" in document.parts:
            continue
        for number, line in enumerate(document.read_text().splitlines(), start=1):
            for target in LINK.findall(line):
                url = urlsplit(target.strip("<>"))
                if url.scheme or url.netloc or not url.path:
                    continue
                path = document.parent / unquote(url.path)
                if not path.exists():
                    errors.append(f"{document.relative_to(ROOT)}:{number}: missing {target}")
    for error in errors:
        print(error, file=sys.stderr)
    if not errors:
        print(f"Local documentation links passed ({len(documents)} files).")
    return bool(errors)


if __name__ == "__main__":
    sys.exit(main())
