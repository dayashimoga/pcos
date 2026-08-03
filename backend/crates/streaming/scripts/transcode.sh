#!/usr/bin/env bash
# PCOS Transcoder — generates HLS adaptive bitrate streams from video/audio files.
# Uses FFmpeg inside Docker — no local install needed.
# Usage: transcode <input_file> <output_dir> [profile]
# Profiles: adaptive (default), audio-only, thumbnail
set -euo pipefail

INPUT="$1"
OUTPUT_DIR="$2"
PROFILE="${3:-adaptive}"

if [ ! -f "$INPUT" ]; then
  echo "ERROR: Input file not found: $INPUT"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
BASENAME=$(basename "$INPUT" | sed 's/\.[^.]*$//')

echo "═══ PCOS Transcoder ═══"
echo "  Input:   $INPUT"
echo "  Output:  $OUTPUT_DIR"
echo "  Profile: $PROFILE"

case "$PROFILE" in
  adaptive)
    # HLS Adaptive Bitrate — 3 quality levels + audio
    echo "  Generating HLS adaptive streams..."

    # 360p (low bandwidth)
    ffmpeg -i "$INPUT" -y \
      -vf "scale=-2:360" -c:v libx264 -preset fast -crf 28 -maxrate 800k -bufsize 1200k \
      -c:a aac -b:a 96k -ac 2 \
      -f hls -hls_time 6 -hls_list_size 0 \
      -hls_segment_filename "$OUTPUT_DIR/${BASENAME}_360p_%03d.ts" \
      "$OUTPUT_DIR/${BASENAME}_360p.m3u8" 2>/dev/null

    # 720p (standard)
    ffmpeg -i "$INPUT" -y \
      -vf "scale=-2:720" -c:v libx264 -preset fast -crf 23 -maxrate 2500k -bufsize 5000k \
      -c:a aac -b:a 128k -ac 2 \
      -f hls -hls_time 6 -hls_list_size 0 \
      -hls_segment_filename "$OUTPUT_DIR/${BASENAME}_720p_%03d.ts" \
      "$OUTPUT_DIR/${BASENAME}_720p.m3u8" 2>/dev/null

    # 1080p (high quality)
    ffmpeg -i "$INPUT" -y \
      -vf "scale=-2:1080" -c:v libx264 -preset fast -crf 20 -maxrate 5000k -bufsize 10000k \
      -c:a aac -b:a 192k -ac 2 \
      -f hls -hls_time 6 -hls_list_size 0 \
      -hls_segment_filename "$OUTPUT_DIR/${BASENAME}_1080p_%03d.ts" \
      "$OUTPUT_DIR/${BASENAME}_1080p.m3u8" 2>/dev/null

    # Master playlist
    cat > "$OUTPUT_DIR/${BASENAME}.m3u8" <<EOF
#EXTM3U
#EXT-X-VERSION:3

#EXT-X-STREAM-INF:BANDWIDTH=896000,RESOLUTION=640x360
${BASENAME}_360p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2628000,RESOLUTION=1280x720
${BASENAME}_720p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5192000,RESOLUTION=1920x1080
${BASENAME}_1080p.m3u8
EOF

    echo "  ✓ HLS master playlist: $OUTPUT_DIR/${BASENAME}.m3u8"
    echo "  ✓ 3 quality levels: 360p, 720p, 1080p"
    ;;

  audio-only)
    # Audio extraction — HLS audio + MP3 fallback
    echo "  Extracting audio streams..."

    ffmpeg -i "$INPUT" -y \
      -vn -c:a aac -b:a 128k -ac 2 \
      -f hls -hls_time 10 -hls_list_size 0 \
      -hls_segment_filename "$OUTPUT_DIR/${BASENAME}_audio_%03d.ts" \
      "$OUTPUT_DIR/${BASENAME}_audio.m3u8" 2>/dev/null

    ffmpeg -i "$INPUT" -y \
      -vn -c:a libmp3lame -b:a 192k -ac 2 \
      "$OUTPUT_DIR/${BASENAME}.mp3" 2>/dev/null

    echo "  ✓ Audio HLS: $OUTPUT_DIR/${BASENAME}_audio.m3u8"
    echo "  ✓ MP3 fallback: $OUTPUT_DIR/${BASENAME}.mp3"
    ;;

  thumbnail)
    # Generate video thumbnails
    echo "  Generating thumbnails..."

    # Single thumbnail at 5s
    ffmpeg -i "$INPUT" -y -ss 5 -vframes 1 -vf "scale=320:-1" \
      "$OUTPUT_DIR/${BASENAME}_thumb.jpg" 2>/dev/null

    # Thumbnail sprite (one frame every 10s, max 60 frames)
    ffmpeg -i "$INPUT" -y -vf "fps=1/10,scale=160:-1,tile=10x6" \
      "$OUTPUT_DIR/${BASENAME}_sprite.jpg" 2>/dev/null

    echo "  ✓ Thumbnail: $OUTPUT_DIR/${BASENAME}_thumb.jpg"
    echo "  ✓ Sprite: $OUTPUT_DIR/${BASENAME}_sprite.jpg"
    ;;

  *)
    echo "Unknown profile: $PROFILE"
    echo "Available: adaptive, audio-only, thumbnail"
    exit 1
    ;;
esac

echo "  Done."
