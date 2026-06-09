# ============================================================
#  OTT Streaming Pipeline - Stop Script
# ============================================================

$NGINX_PATH = "C:\tools\nginx-1.30.2"

function Write-Step($msg) { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-OK($msg) { Write-Host "   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "   $msg" -ForegroundColor Yellow }

Write-Host "`n========================================" -ForegroundColor White
Write-Host "  OTT Streaming Pipeline - Shutdown" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor White

# Stop FFmpeg
Write-Step "Stopping FFmpeg"
$ffmpeg = Get-Process ffmpeg -ErrorAction SilentlyContinue
if ($ffmpeg) {
    Stop-Process -Id $ffmpeg.Id -Force
    Write-OK "FFmpeg stopped (was PID $($ffmpeg.Id))"
} else {
    Write-Warn "FFmpeg not running"
}

# Stop Nginx
Write-Step "Stopping Nginx"
$nginx = Get-Process nginx -ErrorAction SilentlyContinue
if ($nginx) {
    $nginxExe = Join-Path $NGINX_PATH "nginx.exe"
    if (Test-Path $nginxExe) {
        & $nginxExe -s stop 2>$null
    }

    Start-Sleep -Seconds 1
    $still = Get-Process nginx -ErrorAction SilentlyContinue
    if ($still) {
        Stop-Process -Name nginx -Force
        Write-OK "Nginx force-stopped"
    } else {
        Write-OK "Nginx stopped gracefully"
    }
} else {
    Write-Warn "Nginx not running"
}

Write-Host "`nPipeline shut down.`n" -ForegroundColor Green
