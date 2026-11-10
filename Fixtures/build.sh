#!/usr/bin/env bash
# Rebuilds the fixture PDFs (and, with --video, the test video).
# Run from anywhere: ./Fixtures/build.sh [--video]
# Needs pdfLaTeX with Beamer (TeX Live) and latexmk; --video needs ffmpeg.
set -euo pipefail

cd "$(dirname "$0")"

# Fixed timestamps make the PDFs reproducible (2026-01-01 00:00:00 UTC).
export SOURCE_DATE_EPOCH=1767225600
export FORCE_SOURCE_DATE=1
export TZ=UTC

if [[ "${1:-}" == "--video" ]]; then
  # 4 s test pattern with a quiet 440 Hz tone, 320x180, 15 fps.
  # Generated, so there are no licensing questions. No metadata.
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "testsrc2=size=320x180:rate=15:duration=4" \
    -f lavfi -i "sine=frequency=440:sample_rate=22050:duration=4" \
    -filter:a "volume=0.2" \
    -c:v libx264 -preset veryslow -crf 30 -pix_fmt yuv420p -threads 1 \
    -c:a aac -b:a 32k -ac 1 \
    -map_metadata -1 -fflags +bitexact -flags:v +bitexact -flags:a +bitexact \
    -movflags +faststart \
    media/test-pattern.mp4
fi

for tex in *.tex; do
  latexmk -g -pdf -interaction=nonstopmode -halt-on-error -quiet "$tex"
done
latexmk -c -quiet
rm -f ./*.nav ./*.snm ./*.vrb
