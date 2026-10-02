#!/usr/bin/env bash
# ==============================================================================
# PCOS — One-Click Teardown Script for Linux, macOS & Cloud Servers (Bash)
# Usage: ./bringdown.sh [--purge]
# ==============================================================================

set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

write_header() {
    echo -e "\n${CYAN}======================================================================${NC}"
    echo -e "  ${WHITE}$1${NC}"
    echo -e "${CYAN}======================================================================${NC}\n"
}

write_ok()   { echo -e "${GREEN}[OK]    $1${NC}"; }
write_info() { echo -e "${CYAN}[INFO]  $1${NC}"; }
write_warn() { echo -e "${YELLOW}[WARN]  $1${NC}"; }
write_err()  { echo -e "${RED}[FAIL]  $1${NC}"; }

PURGE=false
if [[ "$1" == "--purge" || "$1" == "-v" ]]; then
    PURGE=true
fi

clear 2>/dev/null || true
write_header "PCOS (Personal Cloud OS) -- Universal Teardown"

write_info "Step 1: Detecting container runtime (Docker or Podman)..."
RUNTIME=""
COMPOSE_CMD=""

if command -v docker &> /dev/null && docker info &> /dev/null; then
    RUNTIME="docker"
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    fi
elif command -v podman &> /dev/null && podman info &> /dev/null; then
    RUNTIME="podman"
    if podman compose version &> /dev/null; then
        COMPOSE_CMD="podman compose"
    elif command -v podman-compose &> /dev/null; then
        COMPOSE_CMD="podman-compose"
    fi
fi

if [ -z "$RUNTIME" ] || [ -z "$COMPOSE_CMD" ]; then
    write_err "Neither Docker nor Podman is accessible."
    exit 1
fi
write_ok "Container runtime detected: $RUNTIME ($COMPOSE_CMD)"

if [ "$PURGE" = true ]; then
    write_warn "Step 2: Stopping containers and PURGING all data volumes..."
    $COMPOSE_CMD --profile full down -v
else
    write_info "Step 2: Stopping container services (preserving data volumes)..."
    $COMPOSE_CMD --profile full down
fi

write_ok "All PCOS container services stopped."
write_header "PCOS Teardown Complete"

if [ "$PURGE" = true ]; then
    echo -e "  * All database and file storage volumes PURGED."
else
    echo -e "  * Data preserved in $RUNTIME volumes. Run ./spinup.sh to start again."
fi
echo ""
