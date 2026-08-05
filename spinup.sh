#!/usr/bin/env bash
# ==============================================================================
# PCOS — One-Click Spin-Up Script for Linux, macOS & Cloud Servers (Bash)
# Usage: ./spinup.sh
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

clear 2>/dev/null || true
write_header "PCOS (Personal Cloud OS) -- Universal One-Click Spin-Up"

# 1. Check Docker & Docker Compose
write_info "Step 1: Checking Docker availability..."
if ! command -v docker &> /dev/null; then
    write_err "Docker is not installed! Please install Docker before running this script."
    exit 1
fi

if ! docker info &> /dev/null; then
    write_err "Docker daemon is not running or current user lacks permissions."
    write_warn "Try running: sudo ./spinup.sh"
    exit 1
fi
write_ok "Docker engine is running."

# 2. Check and provision .env configuration
write_info "Step 2: Checking environment configuration (.env)..."
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ENV_PATH="$SCRIPT_DIR/.env"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"

if [ ! -f "$ENV_PATH" ]; then
    if [ -f "$ENV_EXAMPLE" ]; then
        cp "$ENV_EXAMPLE" "$ENV_PATH"
        write_ok "Created .env from .env.example"
        
        # Generate random secrets
        JWT_SECRET=$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | xxd -p)
        DB_PASS=$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | xxd -p)
        
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/CHANGE-ME-TO-A-SECURE-RANDOM-STRING.*/$JWT_SECRET/" "$ENV_PATH"
            sed -i '' "s/change-me-to-a-strong-database-password/$DB_PASS/" "$ENV_PATH"
        else
            sed -i "s/CHANGE-ME-TO-A-SECURE-RANDOM-STRING.*/$JWT_SECRET/" "$ENV_PATH"
            sed -i "s/change-me-to-a-strong-database-password/$DB_PASS/" "$ENV_PATH"
        fi
        write_ok "Generated unique secure JWT secret and database password."
    else
        write_err ".env.example not found!"
        exit 1
    fi
else
    write_ok ".env file is present."
fi

# 3. Clean Flutter ephemeral build context if present
write_info "Step 3: Checking build context..."
rm -rf "$SCRIPT_DIR/frontend/windows/flutter/ephemeral" 2>/dev/null || true
write_ok "Build context verified."

# 4. Launch Docker Compose Stack
write_info "Step 4: Launching Docker Compose stack (13 services)..."
if docker compose version &> /dev/null; then
    docker compose up -d --build
else
    docker-compose up -d --build
fi
write_ok "Docker Compose workloads launched."

# 5. Wait for Backend Health Response
write_info "Step 5: Waiting for backend services to initialize..."
HEALTHY=false
for i in {1..30}; do
    if curl -s -f http://localhost/health | grep -q "healthy"; then
        HEALTHY=true
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

if [ "$HEALTHY" = true ]; then
    write_ok "PCOS Backend is healthy and responding!"
else
    write_warn "Backend is initializing. Check status with: docker compose ps"
fi

# Determine Server IP for Mobile Access
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || ipconfig getifaddr en0 2>/dev/null || echo "your-server-ip")

# 6. Access Summary
write_header "PCOS Stack is LIVE & Ready!"
echo -e "  * Web Frontend:      ${YELLOW}http://localhost${NC} (or http://${SERVER_IP})"
echo -e "  * Mobile Server URL: ${YELLOW}http://${SERVER_IP}${NC}"
echo -e "  * Setup Wizard:      ${YELLOW}http://localhost/#/setup${NC}"
echo -e "  * REST API Backend:  ${YELLOW}http://localhost/health${NC}"
echo -e "  * API Explorer:      ${YELLOW}http://localhost/#/admin/api${NC}"
echo -e "  * PCOS Doctor:       ${YELLOW}http://localhost/#/doctor${NC}"
echo -e "  * Duplicate Finder:  ${YELLOW}http://localhost/#/duplicates${NC}"
echo -e "  * Grafana Dashboard: ${YELLOW}http://localhost:3001${NC}  (admin / admin)"
echo -e "  * Prometheus:        ${YELLOW}http://localhost:9090${NC}"
echo -e "\nTo shut down all services, run: ${CYAN}./bringdown.sh${NC}\n"
