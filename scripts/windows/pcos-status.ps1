<#
.SYNOPSIS
    PCOS Node Status & Quick Controller
#>

$installedExe = "$env:LOCALAPPDATA\PCOS\pcos-agent.exe"
$configPath = "$env:LOCALAPPDATA\PCOS\agent.toml"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   [PCOS] Storage Node Controller & Status" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Check Background Task
$task = Get-ScheduledTask -TaskName "PCOSNodeAgent" -ErrorAction SilentlyContinue
if ($task) {
    Write-Host "Service Task Status : $($task.State)" -ForegroundColor Green
} else {
    Write-Host "Service Task Status : Not registered" -ForegroundColor Yellow
}

# 2. Check Process
$proc = Get-Process pcos-agent, pcos_agent -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host "Process State       : Running (PID: $($proc.Id -join ', '))" -ForegroundColor Green
    Write-Host "Memory Usage        : $([math]::Round(($proc | Measure-Object WorkingSet64 -Sum).Sum / 1MB, 1)) MB" -ForegroundColor Gray
} else {
    Write-Host "Process State       : Stopped" -ForegroundColor Yellow
}

# 3. Check Configuration
if (Test-Path $configPath) {
    Write-Host "Configuration       : $configPath" -ForegroundColor Gray
    Get-Content $configPath | Where-Object { $_ -match '^(server_url|sync_folders|allowed_disks|device_id)' } | ForEach-Object {
        Write-Host "  $_" -ForegroundColor DarkGray
    }
}

# 4. Diagnostics check if binary exists
if (Test-Path $installedExe) {
    Write-Host ""
    Write-Host "Quick Actions:" -ForegroundColor Cyan
    Write-Host "  1. View full diagnostics (doctor)" -ForegroundColor White
    Write-Host "  2. Restart background agent" -ForegroundColor White
    Write-Host "  3. Open PCOS Web App" -ForegroundColor White
    Write-Host "  4. Exit" -ForegroundColor White
    Write-Host ""
    $choice = Read-Host "Select action [1-4]"
    switch ($choice) {
        "1" { & "$installedExe" --config "$configPath" doctor }
        "2" {
            Stop-ScheduledTask -TaskName "PCOSNodeAgent" -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            Start-ScheduledTask -TaskName "PCOSNodeAgent"
            Write-Host "Service restarted." -ForegroundColor Green
        }
        "3" { Start-Process "https://pcos-control-plane.dayashimoga.workers.dev" }
        default {}
    }
}
