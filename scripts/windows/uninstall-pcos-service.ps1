<#
.SYNOPSIS
    PCOS Windows Service & Agent Clean Uninstaller
.DESCRIPTION
    Stops running PCOS Agent background task, unregisters the startup schedule,
    and cleanly uninstalls binaries while leaving user storage files intact.
#>

$ErrorActionPreference = "SilentlyContinue"

Write-Host "Stopping and unregistering PCOS Node Agent..." -ForegroundColor Yellow

# 1. Stop and remove scheduled task
Stop-ScheduledTask -TaskName "PCOSNodeAgent"
Unregister-ScheduledTask -TaskName "PCOSNodeAgent" -Confirm:$false

# 2. Stop running processes
Get-Process pcos_agent -ErrorAction SilentlyContinue | Stop-Process -Force

# 3. Clean up binaries (preserve storage data!)
$pcosAppData = "$env:LOCALAPPDATA\PCOS"
if (Test-Path "$pcosAppData\pcos_agent.exe") {
    Remove-Item "$pcosAppData\pcos_agent.exe" -Force
}

Write-Host "PCOS background agent has been cleanly uninstalled." -ForegroundColor Green
Write-Host "Note: Your personal storage files on disk were PRESERVED." -ForegroundColor Gray
