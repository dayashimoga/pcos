<#
.SYNOPSIS
    PCOS Windows Zero-Config Plug-and-Play Storage Installer & Service Configurator
.DESCRIPTION
    Installs PCOS Node Agent as an always-on Windows background service/startup task.
    Safely discovers fixed and external USB drives, configures local storage pools without
    formatting, and connects outbound to the PCOS Edge Control Plane.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install-pcos-service.ps1
#>

[CmdletBinding()]
param(
    [string]$ServerUrl = "https://pcos-control-plane.dayashimoga.workers.dev",
    [string]$StoragePath = "",
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   ☁ PCOS - Personal Cloud Operating System" -ForegroundColor Cyan
Write-Host "       Windows Plug-and-Play Storage Installer" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Detect Fixed & External USB Volumes Safely
Write-Host "[1/5] Detecting connected drives and storage volumes..." -ForegroundColor Yellow
$volumes = Get-Volume | Where-Object { $_.DriveLetter -ne $null -and $_.DriveType -in @("Fixed", "Removable") -and $_.Size -gt 0 }

Write-Host "Found $($volumes.Count) available volume(s):" -ForegroundColor Green
foreach ($vol in $volumes) {
    $sizeGb = [math]::Round($vol.Size / 1GB, 1)
    $freeGb = [math]::Round($vol.SizeRemaining / 1GB, 1)
    Write-Host "  - Drive $($vol.DriveLetter): [$($vol.FileSystemLabel)] ($freeGb GB free of $sizeGb GB, $($vol.DriveType))" -ForegroundColor Gray
}

# Select target drive
if (-not $StoragePath) {
    # Prefer D:\ or E:\ or largest non-C volume if available
    $selectedVol = $volumes | Where-Object { $_.DriveLetter -ne "C" } | Sort-Object SizeRemaining -Descending | Select-Object -First 1
    if (-not $selectedVol) {
        $selectedVol = $volumes | Where-Object { $_.DriveLetter -eq "C" } | Select-Object -First 1
    }

    if ($selectedVol -and $selectedVol.DriveLetter -ne "C") {
        $StoragePath = "$($selectedVol.DriveLetter):\PCOS"
    } else {
        $StoragePath = "$env:USERPROFILE\PCOS_Storage"
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
    "$repoRoot\target\release\pcos_agent.exe",
    "$repoRoot\target\debug\pcos_agent.exe",
    "$env:LOCALAPPDATA\PCOS\pcos_agent.exe"
)

$agentExe = $binCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $agentExe) {
    Write-Host "Building pcos_agent binary via cargo..." -ForegroundColor Gray
    Push-Location "$repoRoot\agent"
    cargo build --release
    Pop-Location
    $agentExe = "$repoRoot\target\release\pcos_agent.exe"
}

# Copy to PCOS application directory
$pcosAppData = "$env:LOCALAPPDATA\PCOS"
if (-not (Test-Path $pcosAppData)) {
    New-Item -ItemType Directory -Path $pcosAppData -Force | Out-Null
}
Copy-Item $agentExe "$pcosAppData\pcos_agent.exe" -Force
$installedExe = "$pcosAppData\pcos_agent.exe"
Write-Host "Installed agent binary to: $installedExe" -ForegroundColor Green

# 3. Write Safe Configuration
Write-Host ""
Write-Host "[3/5] Writing node configuration..." -ForegroundColor Yellow
$configJson = @{
    server_url = $ServerUrl
    storage_path = $StoragePath
    auto_start = $true
    lan_discovery = $true
} | ConvertTo-Json

$configPath = "$pcosAppData\config.json"
Set-Content -Path $configPath -Value $configJson -Encoding UTF8
Write-Host "Configuration saved to: $configPath" -ForegroundColor Gray

# 4. Register Windows Background Auto-Start Task
Write-Host ""
Write-Host "[4/5] Registering Windows background startup task..." -ForegroundColor Yellow
$taskName = "PCOSNodeAgent"

# Remove existing if present
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction -Execute $installedExe -Argument "--config `"$configPath`"" -WorkingDirectory $pcosAppData
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "PCOS Personal Cloud Outbound Node Agent" | Out-Null
Write-Host "Registered scheduled startup task: $taskName" -ForegroundColor Green

# 5. Start Agent Immediately
Write-Host ""
Write-Host "[5/5] Launching PCOS Node Agent in background..." -ForegroundColor Yellow
Start-ScheduledTask -TaskName $taskName

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "🎉 PCOS Windows Storage Node is INSTALLED and ACTIVE!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Storage Pool:       $StoragePath" -ForegroundColor White
Write-Host "Control Plane:      $ServerUrl" -ForegroundColor White
Write-Host "Status:             Running in background (Auto-Starts with Windows)" -ForegroundColor White
Write-Host ""
Write-Host "NEXT STEP: Open your PCOS Web / Mobile App -> Go to 'Devices' -> Scan QR / Pair." -ForegroundColor Cyan
Write-Host ""
