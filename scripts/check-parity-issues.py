#!/usr/bin/env python3
"""Fails if a `planned` item in docs/feature-parity.md names no issue.

An item that is planned but carried by no issue is invisible on the project
board and only shows up at release time (LAY-10 was added after the phase
issues had been created and had no issue for a week). Every planned row must
therefore name the issue that implements it as "Planned in #180". Other
issue numbers in a row (often closed issues of earlier parts) do not count.
Runs in CI and needs no network, so it cannot check that the issue is still
open; the implement-issue skill covers that when an issue is closed.
"""

import pathlib
import re
import sys

PARITY_DOC = pathlib.Path(__file__).resolve().parent.parent / "docs" / "feature-parity.md"
ROW = re.compile(r"^\| ([A-Z]+-\d+) \|")
ISSUE = re.compile(r"Planned in #\d+")


def main() -> int:
    missing = []
    for number, line in enumerate(PARITY_DOC.read_text(encoding="utf-8").splitlines(), 1):
        match = ROW.match(line)
        if not match:
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        # Only feature rows end with a status; other tables (defects) do not.
        if cells[-1] != "planned":
            continue
        if not ISSUE.search(line):
            missing.append(f"docs/feature-parity.md:{number}: {match.group(1)}")

    if missing:
        print("These planned parity items name no issue. Add \"Planned in #N\" with")
        print("the open issue that implements each one, or create that issue:")
        print("\n".join(missing))
        return 1
    print("Every planned parity item names an issue.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
