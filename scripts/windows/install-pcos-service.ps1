<#
.SYNOPSIS
    PCOS Windows Plug-and-Play Storage Installer & Service Configurator
.DESCRIPTION
    Installs PCOS Node Agent as an always-on Windows background service/startup task.
    Safely discovers fixed and external USB drives, configures local storage pools without
    formatting, performs one-touch pairing with the Cloudflare Edge Control Plane, and
    auto-starts with Windows.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install-pcos-service.ps1
    powershell -ExecutionPolicy Bypass -File .\install-pcos-service.ps1 -PairingCode 123456
    powershell -ExecutionPolicy Bypass -File .\install-pcos-service.ps1 -StoragePath "D:\PCOS" -NonInteractive
#>

[CmdletBinding()]
param(
    [string]$ServerUrl = "https://pcos-control-plane.dayashimoga.workers.dev",
    [string]$PairingCode = "",
    [string]$StoragePath = "",
    [switch]$NonInteractive,
    [switch]$SkipEnrollment
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   [PCOS] Personal Cloud Operating System (v1.8.0)" -ForegroundColor Cyan
Write-Host "       Windows Plug-and-Play Storage Node Installer" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Detect Fixed & External USB Volumes Safely
Write-Host "[1/5] Detecting connected drives and storage volumes..." -ForegroundColor Yellow
$volumes = Get-Volume | Where-Object { $_.DriveLetter -ne $null -and $_.DriveType -in @("Fixed", "Removable") -and $_.Size -gt 0 }

Write-Host "Found $($volumes.Count) available volume(s):" -ForegroundColor Green
$idx = 1
foreach ($vol in $volumes) {
    $sizeGb = [math]::Round($vol.Size / 1GB, 1)
    $freeGb = [math]::Round($vol.SizeRemaining / 1GB, 1)
    Write-Host "  [$idx] Drive $($vol.DriveLetter): [$($vol.FileSystemLabel)] ($freeGb GB free of $sizeGb GB, $($vol.DriveType))" -ForegroundColor Gray
    $idx++
}

# Select target drive
if (-not $StoragePath) {
    if (-not $NonInteractive -and $volumes.Count -gt 1) {
        Write-Host ""
        Write-Host "Choose storage drive for your personal cloud (default: recommend largest non-C drive):" -ForegroundColor Cyan
        $choice = Read-Host "Enter drive number [1-$($volumes.Count)] or press Enter for automatic recommendation"
        if ($choice -match '^\d+$' -and [int]$choice -ge 1 -and [int]$choice -le $volumes.Count) {
            $chosenVol = $volumes[[int]$choice - 1]
            $StoragePath = "$($chosenVol.DriveLetter):\PCOS"
        }
    }

    if (-not $StoragePath) {
        # Prefer D:\ or E:\ or largest non-C volume if available
        $selectedVol = $volumes | Where-Object { $_.DriveLetter -ne "C" } | Sort-Object SizeRemaining -Descending | Select-Object -First 1
        if (-not $selectedVol) {
            $selectedVol = $volumes | Where-Object { $_.DriveLetter -eq "C" } | Select-Object -First 1
        }

        if ($selectedVol -and $selectedVol.DriveLetter -ne "C") {
            $StoragePath = "$($selectedVol.DriveLetter):\PCOS"
        } else {
            $StoragePath = "$env:USERPROFILE\PCOS"
        }
    }
}

Write-Host ""
Write-Host "Target Storage Directory: $StoragePath" -ForegroundColor Cyan
Write-Host "Safety Guarantee: PCOS will NEVER format or delete existing data." -ForegroundColor Green

if (-not (Test-Path $StoragePath)) {
    New-Item -ItemType Directory -Path $StoragePath -Force | Out-Null
    Write-Host "Created storage root directory: $StoragePath" -ForegroundColor Gray
}

# 2. Locate or Build Agent Binary
Write-Host ""
Write-Host "[2/5] Preparing PCOS Node Agent binary..." -ForegroundColor Yellow
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$binCandidates = @(
    "$repoRoot\target\release\pcos-agent.exe",
    "$repoRoot\target\debug\pcos-agent.exe",
    "$env:LOCALAPPDATA\PCOS\pcos-agent.exe",
    "$repoRoot\target\release\pcos_agent.exe",
    "$repoRoot\target\debug\pcos_agent.exe"
)

$agentExe = $binCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $agentExe) {
    Write-Host "Building pcos-agent binary via cargo..." -ForegroundColor Gray
    Push-Location "$repoRoot\agent"
    cargo build --release
    Pop-Location
    $agentExe = "$repoRoot\target\release\pcos-agent.exe"
}

# Copy to PCOS application directory
$pcosAppData = "$env:LOCALAPPDATA\PCOS"
if (-not (Test-Path $pcosAppData)) {
    New-Item -ItemType Directory -Path $pcosAppData -Force | Out-Null
}
Copy-Item $agentExe "$pcosAppData\pcos-agent.exe" -Force
$installedExe = "$pcosAppData\pcos-agent.exe"
Write-Host "Installed agent binary to: $installedExe" -ForegroundColor Green

# 3. Pairing / Enrollment
Write-Host ""
Write-Host "[3/5] Device Pairing & Authentication..." -ForegroundColor Yellow

$configPath = "$pcosAppData\agent.toml"

if (-not $PairingCode -and -not $NonInteractive -and -not $SkipEnrollment) {
    Write-Host "Open PCOS in your browser or phone -> Devices -> 'Pair Device' (or QR code)." -ForegroundColor Cyan
    $userCode = Read-Host "Enter 6-digit pairing code (or press Enter to configure manually)"
    if ($userCode.Trim()) {
        $PairingCode = $userCode.Trim()
    }
}

if ($PairingCode) {
    try {
        & "$installedExe" --config "$configPath" enroll "$PairingCode" --server "$ServerUrl"
        Write-Host "Device successfully enrolled and authenticated!" -ForegroundColor Green
    } catch {
        Write-Warning "Enrollment encountered an issue: $_. Proceeding with configuration..."
    }
} else {
    Write-Host "Skipping online enrollment step. Node can pair anytime via: pcos-agent enroll <code>" -ForegroundColor Gray
}

# 4. Write Configuration
Write-Host ""
Write-Host "[4/5] Writing node configuration..." -ForegroundColor Yellow

# Detect drive letter of storage path for allowed_disks
$storageDrive = ""
if ($StoragePath -match '^([A-Za-z]):') {
    $storageDrive = $Matches[1].ToUpper() + ":"
}

$tomlLines = @(
    "server_url = `"$ServerUrl`"",
    "data_dir = `"$($pcosAppData.Replace('\', '/'))`"",
    "sync_folders = [`"$($StoragePath.Replace('\', '/'))`"]",
    "sync_interval_secs = 30",
    "allowed_disks = [`"$storageDrive`"]",
    "excluded_disks = []",
    "ignore_patterns = [`"*.tmp`", `"*.swp`", `".git/**`", `"node_modules/**`", `"target/**`", `".DS_Store`", `"Thumbs.db`"]"
)

# Preserve existing auth_token and device_id if already present
if (Test-Path $configPath) {
    $existingContent = Get-Content $configPath -Raw
    if ($existingContent -match 'auth_token\s*=\s*"([^"]+)"') {
        $tomlLines += "auth_token = `"$($Matches[1])`""
    }
    if ($existingContent -match 'device_id\s*=\s*"([^"]+)"') {
        $tomlLines += "device_id = `"$($Matches[1])`""
    }
    if ($existingContent -match 'user_id\s*=\s*"([^"]+)"') {
        $tomlLines += "user_id = `"$($Matches[1])`""
    }
}

Set-Content -Path $configPath -Value ($tomlLines -join "`n") -Encoding UTF8
Write-Host "Configuration saved to: $configPath" -ForegroundColor Gray

# Also write JSON config for backward-compatibility
$configJson = @{
    server_url = $ServerUrl
    storage_path = $StoragePath
    data_dir = $pcosAppData
    sync_folders = @($StoragePath)
    allowed_disks = @($storageDrive)
} | ConvertTo-Json
Set-Content -Path "$pcosAppData\config.json" -Value $configJson -Encoding UTF8

# 5. Register Windows Background Auto-Start Task
Write-Host ""
Write-Host "[5/5] Registering Windows background startup task..." -ForegroundColor Yellow
$taskName = "PCOSNodeAgent"

# Stop and remove existing task if present
try {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
} catch {}

$action = New-ScheduledTaskAction -Execute $installedExe -Argument "--config `"$configPath`" --daemon" -WorkingDirectory $pcosAppData
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "PCOS Personal Cloud Outbound Node Agent" | Out-Null
Write-Host "Registered scheduled startup task: $taskName" -ForegroundColor Green

# Launch Agent Immediately
Start-ScheduledTask -TaskName $taskName
Write-Host "Launched PCOS Node Agent in background." -ForegroundColor Green

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "PCOS Windows Storage Node is INSTALLED and ACTIVE!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Storage Pool:       $StoragePath" -ForegroundColor White
Write-Host "Control Plane:      $ServerUrl" -ForegroundColor White
Write-Host "Status:             Running in background (Auto-Starts with Windows)" -ForegroundColor White
Write-Host "Configuration:      $configPath" -ForegroundColor White
Write-Host ""
Write-Host "To view real-time node diagnostics anytime:" -ForegroundColor Cyan
Write-Host "  $installedExe doctor" -ForegroundColor White
Write-Host ""
Write-Host "To re-pair or connect another device:" -ForegroundColor Cyan
Write-Host "  $installedExe enroll <6-digit-code>" -ForegroundColor White
Write-Host ""

