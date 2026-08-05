# ==============================================================================
# PCOS — One-Click Teardown Script for Windows (PowerShell)
# Usage: .\bringdown.ps1 [-PurgeVolumes]
# ==============================================================================

param (
    [switch]$PurgeVolumes
)

$ErrorActionPreference = "Stop"

function Write-Header ($text) {
    Write-Host "`n======================================================================" -ForegroundColor Cyan
    Write-Host "  $text" -ForegroundColor White
    Write-Host "======================================================================`n" -ForegroundColor Cyan
}

function Write-Ok   ($text) { Write-Host "[OK]    $text" -ForegroundColor Green }
function Write-Info ($text) { Write-Host "[INFO]  $text" -ForegroundColor Cyan }
function Write-Warn ($text) { Write-Host "[WARN]  $text" -ForegroundColor Yellow }
function Write-Err  ($text) { Write-Host "[FAIL]  $text" -ForegroundColor Red }

Write-Header "PCOS (Personal Cloud OS) -- One-Click Teardown"

# 1. Verify Docker availability
Write-Info "Step 1: Checking Docker availability..."
try {
    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Docker engine is not responding."
    }
    Write-Ok "Docker engine is running."
} catch {
    Write-Err "Docker is not running or not accessible."
    exit 1
}

# 2. Shut down Docker Compose Stack
if ($PurgeVolumes) {
    Write-Warn "Step 2: Stopping all containers and PURGING persistent data volumes..."
    docker compose down -v --remove-orphans
} else {
    Write-Info "Step 2: Stopping all container services (preserving data volumes)..."
    docker compose down --remove-orphans
}

if ($LASTEXITCODE -eq 0) {
    Write-Ok "All PCOS container services have been stopped."
} else {
    Write-Err "Failed to bring down containers completely."
}

Write-Header "PCOS Teardown Complete"
Write-Host "  * All container services stopped." -ForegroundColor White
if ($PurgeVolumes) {
    Write-Host "  * All database and file volumes purged." -ForegroundColor Yellow
} else {
    Write-Host "  * Data preserved in Docker volumes. Run .\spinup.ps1 to start again." -ForegroundColor Green
}
Write-Host ""
