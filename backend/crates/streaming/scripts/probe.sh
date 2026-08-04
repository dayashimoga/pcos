#!/usr/bin/env bash
# PCOS Media Probe — extract metadata from video/audio files using ffprobe.
# Output: JSON with duration, resolution, codec, bitrate, etc.
# Usage: probe <input_file>
set -euo pipefail

INPUT="$1"
if [ ! -f "$INPUT" ]; then
  echo '{"error":"File not found"}'
  exit 1
fi

ffprobe -v quiet -print_format json -show_format -show_streams "$INPUT" 2>/dev/null
