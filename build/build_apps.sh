#!/usr/bin/env bash
# PCOS Native App Builder — Docker-only, no local SDK installs
# Builds Android APK/AAB, Linux bundle, and Web via Docker containers.
# Windows MSIX, macOS DMG, and iOS IPA require their respective OS runners (CI only).
#
# Usage: bash build/build_apps.sh [android|linux|web|all]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FRONTEND_DIR="$PROJECT_DIR/frontend"
ARTIFACTS_DIR="$PROJECT_DIR/build/artifacts"
BUILD_DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$ARTIFACTS_DIR"/{android,linux,web,windows,macos,ios}

TARGET="${1:-all}"

build_android() {
  echo "═══ Building Android APK/AAB ═══"
  docker build \
    -f "$SCRIPT_DIR/Dockerfile.android" \
    -t pcos-android:latest \
    "$FRONTEND_DIR" 2>&1 | tail -5

  # Extract artifacts
  CONTAINER_ID=$(docker create pcos-android:latest)
  docker cp "$CONTAINER_ID:/artifacts/apk/" "$ARTIFACTS_DIR/android/" 2>/dev/null || true
  docker cp "$CONTAINER_ID:/artifacts/aab/" "$ARTIFACTS_DIR/android/" 2>/dev/null || true
  docker rm "$CONTAINER_ID" > /dev/null

  echo "  ✓ Android artifacts → $ARTIFACTS_DIR/android/"
  ls -lh "$ARTIFACTS_DIR/android/"* 2>/dev/null || echo "  (build may have warnings — check Docker output)"
}

build_linux() {
  echo "═══ Building Linux Desktop ═══"
  docker build \
    -f "$SCRIPT_DIR/Dockerfile.linux" \
    -t pcos-linux:latest \
    "$FRONTEND_DIR" 2>&1 | tail -5

  CONTAINER_ID=$(docker create pcos-linux:latest)
  docker cp "$CONTAINER_ID:/artifacts/linux-bundle/" "$ARTIFACTS_DIR/linux/" 2>/dev/null || true
  docker cp "$CONTAINER_ID:/artifacts/AppDir/" "$ARTIFACTS_DIR/linux/AppDir/" 2>/dev/null || true
  docker rm "$CONTAINER_ID" > /dev/null

  echo "  ✓ Linux artifacts → $ARTIFACTS_DIR/linux/"
}

build_web() {
  echo "═══ Building Web (Production) ═══"
  docker build \
    -f "$SCRIPT_DIR/Dockerfile.web" \
    -t pcos-web:latest \
    "$FRONTEND_DIR" 2>&1 | tail -5

  # Extract web build
  CONTAINER_ID=$(docker create pcos-web:latest)
  docker cp "$CONTAINER_ID:/usr/share/nginx/html/" "$ARTIFACTS_DIR/web/" 2>/dev/null || true
  docker rm "$CONTAINER_ID" > /dev/null

  echo "  ✓ Web artifacts → $ARTIFACTS_DIR/web/"
}

echo "╔══════════════════════════════════════════╗"
echo "║   PCOS Native App Builder (Docker)       ║"
echo "║   Target: $TARGET                          "
echo "╚══════════════════════════════════════════╝"
echo ""

case "$TARGET" in
  android) build_android ;;
  linux)   build_linux ;;
  web)     build_web ;;
  all)
    build_android
    echo ""
    build_linux
    echo ""
    build_web
    ;;
  *)
    echo "Usage: $0 [android|linux|web|all]"
    echo ""
    echo "Platforms requiring native CI runners (not Docker-buildable on Linux):"
    echo "  windows  → GitHub Actions windows-latest runner"
    echo "  macos    → GitHub Actions macos-latest runner"
    echo "  ios      → GitHub Actions macos-latest runner + Xcode"
    exit 1
    ;;
esac

echo ""
echo "═══ Build Summary ═══"
echo "Artifacts directory: $ARTIFACTS_DIR"
find "$ARTIFACTS_DIR" -type f -name "*.apk" -o -name "*.aab" -o -name "*.html" 2>/dev/null | head -20
echo ""
echo "Done."
