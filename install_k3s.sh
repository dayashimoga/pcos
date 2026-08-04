#!/usr/bin/env bash
# Usage: bash install_k3s.sh
# Automated installer for K3s & PCOS Kubernetes secure deployment.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/scripts/deploy_k3s.sh" "$@"
