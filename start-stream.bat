@echo off
REM ============================================================
REM  OTT Streaming Pipeline — Quick Launcher
REM  Double-click to start FFmpeg + Nginx
REM ============================================================

echo.
echo  ========================================
echo   OTT Streaming Pipeline — Starting
echo  ========================================
echo.

REM Change to the script's own directory
cd /d "%~dp0"

REM Run the PowerShell startup script
powershell -ExecutionPolicy Bypass -File "start-stream.ps1"

pause
