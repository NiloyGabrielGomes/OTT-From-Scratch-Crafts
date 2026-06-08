# ============================================================
#  OTT Streaming Pipeline — Startup Script
#  Starts FFmpeg (RTMP listener + HLS packager) and Nginx
# ============================================================

# --- Configuration (edit as needed) ---
$RTMP_PORT       = 1935
$RTMP_APP        = "live"
$RTMP_KEY        = "stream"
$VIDEO_BITRATE   = "2500k"
$AUDIO_BITRATE   = "128k"
$HLS_SEGMENT_TIME = 4          # seconds per segment
$HLS_LIST_SIZE   = 5           # segments to keep in playlist
$OUTPUT_DIR      = "$PSScriptRoot\hls"
$NGINX_PATH      = "C:\nginx"  # adjust if Nginx is elsewhere

# --- Derived ---
$RTMP_URL = "rtmp://0.0.0.0:${RTMP_PORT}/${RTMP_APP}/${RTMP_KEY}"
$PLAYLIST = "$OUTPUT_DIR\stream.m3u8"
$SEGMENT_PATTERN = "$OUTPUT_DIR\stream%03d.ts"

# --- Colors ---
function Write-Step($msg)  { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)    { Write-Host "   $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "   $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "   $msg" -ForegroundColor Red }

# ============================================================
#  Pre-flight checks
# ============================================================
Write-Host "`n========================================" -ForegroundColor White
Write-Host "  OTT Streaming Pipeline — Startup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor White

# Check FFmpeg
Write-Step "Checking FFmpeg"
try {
    $ffmpegVersion = & ffmpeg -version 2>&1 | Select-Object -First 1
    Write-OK "Found: $ffmpegVersion"
} catch {
    Write-Err "FFmpeg not found. Install from https://www.gyan.dev/ffmpeg/builds/ and add to PATH."
    exit 1
}

# Check Nginx
Write-Step "Checking Nginx"
$nginxExe = "$NGINX_PATH\nginx.exe"
if (Test-Path $nginxExe) {
    Write-OK "Found at $NGINX_PATH"
} else {
    Write-Warn "Nginx not found at $NGINX_PATH — skipping Nginx startup."
    Write-Warn "Set `$NGINX_PATH in this script or install Nginx from https://nginx.org/en/download.html"
    $NGINX_PATH = $null
}

