@echo off
REM ============================================================
REM  Wrapper for MediaMTX runOnPublish
REM  Called as: ffmpeg-start.bat cam1
REM  Delegates to ffmpeg-start.ps1
REM ============================================================
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0ffmpeg-start.ps1" -StreamName %1
