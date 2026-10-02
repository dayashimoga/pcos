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

# 1. Verify Docker or Podman availability
Write-Info "Step 1: Detecting container runtime (Docker or Podman)..."
$runtime = $null
$composeCmd = $null

if (Get-Command docker -ErrorAction SilentlyContinue) {
    try {
        $null = docker info 2>&1
        if ($LASTEXITCODE -eq 0) {
            $runtime = "docker"
            $composeCmd = "docker compose"
        }
    } catch {}
}

if (-not $runtime -and (Get-Command podman -ErrorAction SilentlyContinue)) {
    try {
        $null = podman info 2>&1
        if ($LASTEXITCODE -eq 0) {
            $runtime = "podman"
            try {
                $null = podman compose version 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $composeCmd = "podman compose"
                }
            } catch {}

            if (-not $composeCmd -and (Get-Command podman-compose -ErrorAction SilentlyContinue)) {
                $composeCmd = "podman-compose"
            }
        }
    } catch {}
}

if (-not $runtime -or -not $composeCmd) {
    Write-Err "Neither Docker nor Podman is accessible."
    exit 1
}

Write-Ok "Container runtime detected: $runtime ($composeCmd)"

# 2. Shut down Container Compose Stack
if ($PurgeVolumes) {
    Write-Warn "Step 2: Stopping all containers and PURGING persistent data volumes..."
    if ($composeCmd -eq "docker compose") {
        docker compose --profile full down -v --remove-orphans
    } elseif ($composeCmd -eq "podman compose") {
        podman compose --profile full down -v
    } else {
        podman-compose --profile full down -v
    }
} else {
    Write-Info "Step 2: Stopping all container services (preserving data volumes)..."
    if ($composeCmd -eq "docker compose") {
        docker compose --profile full down --remove-orphans
    } elseif ($composeCmd -eq "podman compose") {
        podman compose --profile full down
    } else {
        podman-compose --profile full down
    }
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
    Write-Host "  * Data preserved in $runtime volumes. Run .\spinup.ps1 to start again." -ForegroundColor Green
}
Write-Host ""
