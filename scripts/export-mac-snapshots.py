#!/usr/bin/env python3
"""Export the Mac snapshots from the MacSnapshots test run.

Reads ./build/MacSnapshots.xcresult and writes ./.pr-screenshots/mac/<name>.png.
Only PNGs that SlidePilot rendered itself are exported: they carry a
"SlidePilotSnapshot:<name>" PNG title (see WindowSnapshot.swift). Everything
else in the result bundle is ignored.

xcresulttool is not used because it writes to the system temp folder, which
the Claude Code sandbox blocks. The result bundle stores attachments as plain
files, so reading them directly is enough. Paths are fixed on purpose.
"""

from __future__ import annotations

import re
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESULT_DATA = ROOT / "build" / "MacSnapshots.xcresult" / "Data"
OUTPUT = ROOT / ".pr-screenshots" / "mac"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
MARKER = re.compile(r"SlidePilotSnapshot:(mac-[A-Za-z0-9-]{1,80})(?![A-Za-z0-9-])")


def snapshot_name(data: bytes) -> str | None:
    """Return the snapshot name from the PNG's text metadata, or None.

    ImageIO writes the PNG title as XMP (dc:title) into an iTXt chunk.
    """
    if not data.startswith(PNG_SIGNATURE):
        return None
    offset = len(PNG_SIGNATURE)
    while offset + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[offset:offset + 8])
        body = data[offset + 8:offset + 8 + length]
        offset += 12 + length
        if kind == b"IEND" or kind == b"IDAT":
            break
        if kind == b"tEXt":
            value = body.partition(b"\0")[2]
        elif kind == b"iTXt":
            _, _, rest = body.partition(b"\0")
            if len(rest) < 2:
                continue
            compressed, method = rest[0], rest[1]
            value = rest[2:].split(b"\0", 2)[-1]
            if compressed:
                if method != 0:
                    continue
                value = zlib.decompress(value)
        else:
            continue
        match = MARKER.search(value.decode("utf-8", "replace"))
        if match:
            return match.group(1)
    return None


def main() -> int:
    if not RESULT_DATA.is_dir():
        print(f"No result bundle at {RESULT_DATA.relative_to(ROOT)}. Run the MacSnapshots test plan first.")
        return 1
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for old in OUTPUT.glob("*.png"):
        old.unlink()

    exported = []
    for file in sorted(RESULT_DATA.iterdir()):
        if not file.is_file():
            continue
        with file.open("rb") as handle:
            if handle.read(len(PNG_SIGNATURE)) != PNG_SIGNATURE:
                continue
        data = file.read_bytes()
        name = snapshot_name(data)
        if name is None:
            continue
        (OUTPUT / f"{name}.png").write_bytes(data)
        exported.append(name)

    if not exported:
        print("No SlidePilot snapshots found in the result bundle.")
        return 1
    for name in sorted(exported):
        print(f"{OUTPUT.relative_to(ROOT)}/{name}.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
