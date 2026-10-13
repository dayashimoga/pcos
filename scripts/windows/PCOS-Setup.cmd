@echo off
title PCOS Storage Node Setup Wizard
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0PCOS-Setup-GUI.ps1"
