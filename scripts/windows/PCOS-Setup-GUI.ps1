<#
.SYNOPSIS
    PCOS Windows Graphical Storage Node Installer & Pairing Wizard
.DESCRIPTION
    Consumer-friendly GUI setup for PCOS:
    Create Account -> Create Cloud -> Add Computer -> Install -> Pair -> Select Authorized Drives -> Done.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = "PCOS Storage Node — Windows Setup Wizard"
$form.Size = New-Object System.Drawing.Size(640, 620)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42) # Slate 900
$form.ForeColor = [System.Drawing.Color]::FromArgb(241, 245, 249)

# Header Panel
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Location = New-Object System.Drawing.Point(0, 0)
$headerPanel.Size = New-Object System.Drawing.Size(640, 90)
$headerPanel.BackColor = [System.Drawing.Color]::FromArgb(30, 41, 59) # Slate 800
$form.Controls.Add($headerPanel)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "☁ PCOS Personal Cloud Storage Node"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(129, 140, 248) # Indigo 400
$lblTitle.Location = New-Object System.Drawing.Point(24, 18)
$lblTitle.AutoSize = $true
$headerPanel.Controls.Add($lblTitle)

$lblSubtitle = New-Object System.Windows.Forms.Label
$lblSubtitle.Text = "Turn your computer's disks & USB storage into accessible personal cloud."
$lblSubtitle.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$lblSubtitle.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184) # Slate 400
$lblSubtitle.Location = New-Object System.Drawing.Point(26, 52)
$lblSubtitle.AutoSize = $true
$headerPanel.Controls.Add($lblSubtitle)

# Step 1: Pairing Code
$lblStep1 = New-Object System.Windows.Forms.Label
$lblStep1.Text = "Step 1: Enter 6-digit pairing code from PCOS Web/Mobile"
$lblStep1.Font = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold)
$lblStep1.ForeColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
$lblStep1.Location = New-Object System.Drawing.Point(24, 105)
$lblStep1.AutoSize = $true
$form.Controls.Add($lblStep1)

$txtCode = New-Object System.Windows.Forms.TextBox
$txtCode.Font = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
$txtCode.TextAlign = "Center"
$txtCode.Location = New-Object System.Drawing.Point(24, 135)
$txtCode.Size = New-Object System.Drawing.Size(220, 40)
$txtCode.BackColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
$txtCode.ForeColor = [System.Drawing.Color]::FromArgb(248, 250, 252)
$txtCode.MaxLength = 6
$form.Controls.Add($txtCode)

$btnOpenWeb = New-Object System.Windows.Forms.Button
$btnOpenWeb.Text = "Open PCOS Web (Get Code)"
$btnOpenWeb.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnOpenWeb.Location = New-Object System.Drawing.Point(260, 135)
$btnOpenWeb.Size = New-Object System.Drawing.Size(210, 38)
$btnOpenWeb.BackColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
$btnOpenWeb.ForeColor = [System.Drawing.Color]::White
$btnOpenWeb.FlatStyle = "Flat"
$btnOpenWeb.FlatAppearance.BorderSize = 0
$btnOpenWeb.Add_Click({
    Start-Process "https://pcos-control-plane.dayashimoga.workers.dev/#/devices"
})
$form.Controls.Add($btnOpenWeb)

# Step 2: Storage Selection
$lblStep2 = New-Object System.Windows.Forms.Label
$lblStep2.Text = "Step 2: Select drives and storage folder to authorize"
$lblStep2.Font = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold)
$lblStep2.ForeColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
$lblStep2.Location = New-Object System.Drawing.Point(24, 190)
$lblStep2.AutoSize = $true
$form.Controls.Add($lblStep2)

$listDrives = New-Object System.Windows.Forms.CheckedListBox
$listDrives.Location = New-Object System.Drawing.Point(24, 218)
$listDrives.Size = New-Object System.Drawing.Size(575, 110)
$listDrives.BackColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
$listDrives.ForeColor = [System.Drawing.Color]::FromArgb(241, 245, 249)
$listDrives.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$listDrives.BorderStyle = "FixedSingle"
$form.Controls.Add($listDrives)

# Enumerate actual physical drives
$volumes = Get-Volume | Where-Object { $_.DriveLetter -ne $null -and $_.DriveType -in @("Fixed", "Removable") -and $_.Size -gt 0 }
$defaultStoragePath = "$env:USERPROFILE\PCOS"
$idx = 0
$recommendedIdx = -1

foreach ($vol in $volumes) {
    $sizeGb = [math]::Round($vol.Size / 1GB, 1)
    $freeGb = [math]::Round($vol.SizeRemaining / 1GB, 1)
    $label = if ($vol.FileSystemLabel) { $vol.FileSystemLabel } else { "Local Disk" }
    $isNonC = ($vol.DriveLetter -ne "C")
    $itemText = "Drive $($vol.DriveLetter): [$label] - $freeGb GB free of $sizeGb GB ($($vol.DriveType))"
    if ($isNonC -and $recommendedIdx -eq -1) {
        $itemText += " ★ Recommended Storage"
        $recommendedIdx = $idx
        $defaultStoragePath = "$($vol.DriveLetter):\PCOS"
    }
    $listDrives.Items.Add($itemText) | Out-Null
    $idx++
}

# Auto-check recommended drive
if ($recommendedIdx -ge 0) {
    $listDrives.SetItemChecked($recommendedIdx, $true)
} elseif ($listDrives.Items.Count -gt 0) {
    $listDrives.SetItemChecked(0, $true)
}

$lblPath = New-Object System.Windows.Forms.Label
$lblPath.Text = "Target Storage Folder (Never formatted, safe to use):"
$lblPath.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblPath.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
$lblPath.Location = New-Object System.Drawing.Point(24, 335)
$lblPath.AutoSize = $true
$form.Controls.Add($lblPath)

$txtPath = New-Object System.Windows.Forms.TextBox
$txtPath.Text = $defaultStoragePath
$txtPath.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$txtPath.Location = New-Object System.Drawing.Point(24, 355)
$txtPath.Size = New-Object System.Drawing.Size(460, 28)
$txtPath.BackColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
$txtPath.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($txtPath)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "Browse..."
$btnBrowse.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$btnBrowse.Location = New-Object System.Drawing.Point(495, 354)
$btnBrowse.Size = New-Object System.Drawing.Size(104, 30)
$btnBrowse.BackColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
$btnBrowse.ForeColor = [System.Drawing.Color]::White
$btnBrowse.FlatStyle = "Flat"
$btnBrowse.FlatAppearance.BorderSize = 0
$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.SelectedPath = $txtPath.Text
    if ($dlg.ShowDialog() -eq "OK") {
        $txtPath.Text = $dlg.SelectedPath
    }
})
$form.Controls.Add($btnBrowse)

# Progress Bar & Status
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(24, 400)
$progressBar.Size = New-Object System.Drawing.Size(575, 12)
$progressBar.Visible = $false
$form.Controls.Add($progressBar)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Ready to install. No open ports, router setup, or manual config required."
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(148, 163, 184)
$lblStatus.Location = New-Object System.Drawing.Point(24, 420)
$lblStatus.Size = New-Object System.Drawing.Size(575, 45)
$form.Controls.Add($lblStatus)

# Action Buttons
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = "🚀 Install & Pair PCOS Node"
$btnInstall.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$btnInstall.Location = New-Object System.Drawing.Point(24, 480)
$btnInstall.Size = New-Object System.Drawing.Size(360, 48)
$btnInstall.BackColor = [System.Drawing.Color]::FromArgb(99, 102, 241) # Indigo 500
$btnInstall.ForeColor = [System.Drawing.Color]::White
$btnInstall.FlatStyle = "Flat"
$btnInstall.FlatAppearance.BorderSize = 0
$btnInstall.Cursor = [System.Windows.Forms.Cursors]::Hand

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Close"
$btnCancel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$btnCancel.Location = New-Object System.Drawing.Point(400, 480)
$btnCancel.Size = New-Object System.Drawing.Size(199, 48)
$btnCancel.BackColor = [System.Drawing.Color]::FromArgb(51, 65, 85)
$btnCancel.ForeColor = [System.Drawing.Color]::White
$btnCancel.FlatStyle = "Flat"
$btnCancel.FlatAppearance.BorderSize = 0
$btnCancel.Add_Click({ $form.Close() })

$btnInstall.Add_Click({
    $code = $txtCode.Text.Trim()
    if ($code.Length -ne 6 -or -not ($code -match '^\d{6}$')) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please enter a valid 6-digit numeric pairing code from your PCOS dashboard.",
            "Invalid Pairing Code",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    $btnInstall.Enabled = $false
    $progressBar.Visible = $true
    $progressBar.Value = 20
    $lblStatus.Text = "Installing PCOS Agent binary and configuring background service..."
    $form.Update()

    $targetStorage = $txtPath.Text.Trim()
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $installScript = Join-Path $scriptDir "install-pcos-service.ps1"

    try {
        $progressBar.Value = 40
        $lblStatus.Text = "Connecting and enrolling with Cloudflare Edge Control Plane..."
        $form.Update()

        $p = Start-Process powershell.exe -ArgumentList @(
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$installScript`"",
            "-PairingCode", "`"$code`"",
            "-StoragePath", "`"$targetStorage`"",
            "-NonInteractive"
        ) -PassThru -Wait -NoNewWindow

        $progressBar.Value = 100
        if ($p.ExitCode -eq 0) {
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(52, 211, 153) # Emerald 400
            $lblStatus.Text = "🎉 Node installed & paired successfully! Auto-starts with Windows."
            [System.Windows.Forms.MessageBox]::Show(
                "PCOS Storage Node is now active in the background and connected to your cloud.`n`nStorage Pool: $targetStorage",
                "Installation Successful",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            $btnInstall.Text = "✔ Installed & Active"
        } else {
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(248, 113, 113) # Red 400
            $lblStatus.Text = "Installation failed with exit code $($p.ExitCode). Check pairing code."
            $btnInstall.Enabled = $true
        }
    } catch {
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(248, 113, 113)
        $lblStatus.Text = "Error: $($_.Exception.Message)"
        $btnInstall.Enabled = $true
    }
})

$form.Controls.Add($btnInstall)
$form.Controls.Add($btnCancel)

$form.ShowDialog() | Out-Null
