@echo off
chcp 65001 >nul
title Mandala Studio
cd /d "%~dp0"

echo.
echo  ========================================
echo   Mandala Studio
echo  ========================================
echo.
echo  Starting local server...
echo  (Leave this window open while you use the app.)
echo  Close this window to stop the server.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Mandala.ps1"
if errorlevel 1 (
  echo.
  echo  Could not start. On Windows 10/11 PowerShell is required.
  echo  Try right-click Start-Mandala.ps1 -^> Run with PowerShell
  echo.
  pause
)
