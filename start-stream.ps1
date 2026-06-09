# ============================================================
#  OTT Streaming Pipeline - Startup Script
#  Starts FFmpeg (RTMP listener + HLS packager) and Nginx
# ============================================================

# --- Configuration (edit as needed) ---
$RTMP_PORT        = 1935
$RTMP_APP         = "live"
$RTMP_KEY         = "stream"
$VIDEO_BITRATE    = "2500k"
$AUDIO_BITRATE    = "128k"
$HLS_SEGMENT_TIME = 4          # seconds per segment
$HLS_LIST_SIZE    = 5          # segments to keep in playlist
$OUTPUT_DIR       = "$PSScriptRoot\hls"
$NGINX_PATH       = "C:\tools\nginx-1.30.2"  # adjust if Nginx is elsewhere

# --- Derived ---
$RTMP_URL        = "rtmp://0.0.0.0:${RTMP_PORT}/${RTMP_APP}/${RTMP_KEY}"
$PLAYLIST        = "$OUTPUT_DIR\stream.m3u8"
$SEGMENT_PATTERN = "$OUTPUT_DIR\stream%03d.ts"
$VIDEO_BUFSIZE   = "{0}k" -f (([int]($VIDEO_BITRATE -replace '[^0-9]', '')) * 2)

# --- Colors ---
function Write-Step($msg) { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-OK($msg) { Write-Host "   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "   $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "   $msg" -ForegroundColor Red }

# ============================================================
#  Pre-flight checks
# ============================================================
Write-Host "`n========================================" -ForegroundColor White
Write-Host "  OTT Streaming Pipeline - Startup" -ForegroundColor Cyan
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
    $projectNginxConf = Join-Path $PSScriptRoot "nginx.conf"
    $activeNginxConf = Join-Path $NGINX_PATH "conf\nginx.conf"
    if (Test-Path $projectNginxConf) {
        Copy-Item $projectNginxConf $activeNginxConf -Force
        Write-OK "Deployed project nginx.conf to $activeNginxConf"
    } else {
        Write-Warn "Project nginx.conf not found at $projectNginxConf"
    }
} else {
    Write-Warn "Nginx not found at $NGINX_PATH - skipping Nginx startup."
    Write-Warn "Set `$NGINX_PATH in this script or install Nginx from https://nginx.org/en/download.html"
    $NGINX_PATH = $null
}

# ============================================================
#  Prepare HLS output directory
# ============================================================
Write-Step "Preparing HLS output directory"

if (Test-Path $OUTPUT_DIR) {
    # Clean old segments
    $oldFiles = Get-ChildItem "$OUTPUT_DIR\*.ts" -ErrorAction SilentlyContinue
    if ($oldFiles) {
        Remove-Item "$OUTPUT_DIR\*.ts" -Force
        Write-OK "Cleaned $($oldFiles.Count) old segment(s)"
    } else {
        Write-OK "No old segments to clean"
    }
} else {
    New-Item -ItemType Directory -Path $OUTPUT_DIR -Force | Out-Null
    Write-OK "Created $OUTPUT_DIR"
}

# ============================================================
#  Start Nginx (if available)
# ============================================================
if ($NGINX_PATH) {
    Write-Step "Starting Nginx"

    # Check if already running
    $existing = Get-Process nginx -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Warn "Nginx already running (PID $($existing.Id)) - reloading config"
        & $nginxExe -s reload
    } else {
        Start-Process -FilePath $nginxExe -WorkingDirectory $NGINX_PATH -WindowStyle Normal
        Start-Sleep -Seconds 1
        $proc = Get-Process nginx -ErrorAction SilentlyContinue
        if ($proc) {
            Write-OK "Nginx started (PID $($proc.Id))"
        } else {
            Write-Err "Nginx failed to start. Check config with: $nginxExe -t"
        }
    }

    Write-OK "Viewer page: http://localhost/viewer/"
    Write-OK "Stream URL:  http://localhost/hls/stream.m3u8"
}

# ============================================================
#  Start FFmpeg
# ============================================================
Write-Step "Starting FFmpeg (RTMP listener + HLS packager)"
Write-Host ""
Write-Host "  Listening on:  rtmp://0.0.0.0:${RTMP_PORT}/${RTMP_APP}/${RTMP_KEY}" -ForegroundColor White
Write-Host "  Video:         libx264, $VIDEO_BITRATE, keyframe every 2s" -ForegroundColor White
Write-Host "  Audio:         AAC, $AUDIO_BITRATE" -ForegroundColor White
Write-Host "  HLS:           ${HLS_SEGMENT_TIME}s segments, ${HLS_LIST_SIZE} in playlist" -ForegroundColor White
Write-Host "  Output:        $PLAYLIST" -ForegroundColor White
Write-Host ""
Write-Host "  Start OBS and stream to: rtmp://localhost:${RTMP_PORT}/${RTMP_APP}" -ForegroundColor Yellow
Write-Host "  Press Ctrl+C to stop`n" -ForegroundColor Yellow

# Build FFmpeg arguments
$ffmpegArgs = @(
    "-listen", "1",
    "-i", $RTMP_URL,
    # Video encoding
    "-c:v", "libx264",
    "-preset", "veryfast",
    "-tune", "zerolatency",
    "-b:v", $VIDEO_BITRATE,
    "-maxrate", $VIDEO_BITRATE,
    "-bufsize", $VIDEO_BUFSIZE,
    "-g", "60",
    "-keyint_min", "60",
    "-sc_threshold", "0",
    # Audio encoding
    "-c:a", "aac",
    "-b:a", $AUDIO_BITRATE,
    "-ar", "48000",
    # HLS output
    "-f", "hls",
    "-hls_time", $HLS_SEGMENT_TIME.ToString(),
    "-hls_list_size", $HLS_LIST_SIZE.ToString(),
    "-hls_flags", "delete_segments",
    "-hls_segment_filename", $SEGMENT_PATTERN,
    $PLAYLIST
)

# Run FFmpeg (this blocks until Ctrl+C)
& ffmpeg @ffmpegArgs
