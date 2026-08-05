# ==============================================================================
# PCOS — One-Click Spin-Up Script for Windows (PowerShell)
# Usage: .\spinup.ps1
# ==============================================================================

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

Write-Header "PCOS (Personal Cloud OS) -- One-Click Spin-Up"

# 1. Verify Docker Desktop / Docker Engine is running
Write-Info "Step 1: Checking Docker availability..."
try {
    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Docker engine is not responding."
    }
    Write-Ok "Docker engine is running."
} catch {
    Write-Err "Docker is not running or not accessible."
    Write-Warn "Please launch Docker Desktop and try running .\spinup.ps1 again."
    exit 1
}

# 2. Check and provision .env file with secure secrets
Write-Info "Step 2: Checking environment configuration (.env)..."
$envPath = Join-Path $PSScriptRoot ".env"
$envExamplePath = Join-Path $PSScriptRoot ".env.example"

if (-not (Test-Path $envPath)) {
    if (Test-Path $envExamplePath) {
        Copy-Item $envExamplePath $envPath
        Write-Ok "Created .env from .env.example"
        
        # Generate random secure passwords
        $bytes = New-Object byte[] 32
        (New-Object Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes)
        $jwtSecret = [System.BitConverter]::ToString($bytes) -replace '-',''
        
        $passBytes = New-Object byte[] 16
        (New-Object Security.Cryptography.RNGCryptoServiceProvider).GetBytes($passBytes)
        $dbPass = [System.BitConverter]::ToString($passBytes) -replace '-',''

        (Get-Content $envPath) -replace 'CHANGE-ME-TO-A-SECURE-RANDOM-STRING.*', $jwtSecret `
                               -replace 'change-me-to-a-strong-database-password', $dbPass | Set-Content $envPath
        Write-Ok "Generated unique secure JWT secret and database password."
    } else {
        Write-Err ".env.example not found!"
        exit 1
    }
} else {
    Write-Ok ".env file is present."
}

# 3. Clean up ephemeral platform symlinks to prevent Docker context issues
Write-Info "Step 3: Checking build context..."
$ephemeralPath = Join-Path $PSScriptRoot "frontend\windows\flutter\ephemeral"
if (Test-Path $ephemeralPath) {
    Remove-Item -Recurse -Force $ephemeralPath -ErrorAction SilentlyContinue
    Write-Ok "Cleaned ephemeral Flutter symlinks."
}

# 4. Launch Docker Compose Stack
Write-Info "Step 4: Launching Docker Compose stack (13 services)..."
try {
    docker compose up -d --build
    if ($LASTEXITCODE -ne 0) {
        throw "Docker compose failed with exit code $LASTEXITCODE"
    }
    Write-Ok "Docker Compose workloads launched."
} catch {
    Write-Err "Failed to start Docker Compose stack: $_"
    exit 1
}

# 5. Wait for Backend Health
Write-Info "Step 5: Waiting for backend services to initialize..."
$maxRetries = 30
$healthy = $false

for ($i = 1; $i -le $maxRetries; $i++) {
    try {
        $resp = Invoke-RestMethod -Uri "http://localhost/health" -TimeoutSec 2 -ErrorAction Stop
        if ($resp.status -eq "healthy") {
            $healthy = $true
            break
        }
    } catch {
        # Retrying...
    }
    Start-Sleep -Seconds 2
    Write-Host "." -NoNewline -ForegroundColor Gray
}
Write-Host ""

if ($healthy) {
    Write-Ok "PCOS Backend is healthy and responding!"
} else {
    Write-Warn "Backend is taking longer to start. Check status with: docker compose ps"
}

# 6. Display Service Access Summary
Write-Header "PCOS Stack is LIVE & Ready!"

Write-Host "  * Web Frontend:      " -NoNewline; Write-Host "http://localhost" -ForegroundColor Yellow
Write-Host "  * Setup Wizard:      " -NoNewline; Write-Host "http://localhost/#/setup" -ForegroundColor Yellow
Write-Host "  * REST API Backend:  " -NoNewline; Write-Host "http://localhost/health" -ForegroundColor Yellow
Write-Host "  * API Explorer:      " -NoNewline; Write-Host "http://localhost/#/admin/api" -ForegroundColor Yellow
Write-Host "  * PCOS Doctor:       " -NoNewline; Write-Host "http://localhost/#/doctor" -ForegroundColor Yellow
Write-Host "  * Duplicate Finder:  " -NoNewline; Write-Host "http://localhost/#/duplicates" -ForegroundColor Yellow
Write-Host "  * Grafana Dashboard: " -NoNewline; Write-Host "http://localhost:3001" -ForegroundColor Yellow -NoNewline; Write-Host "  (admin / admin)" -ForegroundColor Gray
Write-Host "  * Prometheus:        " -NoNewline; Write-Host "http://localhost:9090" -ForegroundColor Yellow

Write-Host "`nTo shut down all services, run: " -NoNewline
Write-Host ".\bringdown.ps1`n" -ForegroundColor Cyan
