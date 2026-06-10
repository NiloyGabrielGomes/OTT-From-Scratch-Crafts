# ============================================================
#  OTT Streaming Pipeline - Startup Script (Multi-Input)
#  Starts MediaMTX (relay) + FFmpeg (encode) + Nginx (serve)
#
#  Each component runs independently:
#    MediaMTX - RTMP relay only, no encoding
#    FFmpeg   - connects to MediaMTX as client, transcodes + HLS
#    Nginx    - serves HLS files over HTTP
# ============================================================

# --- Configuration ---
$MEDIAMTX_PATH = "C:\tools\mediamtx_v1.19.0_windows_amd64"
$NGINX_PATH    = "C:\tools\nginx-1.30.2"
$PROJECT_DIR   = "$PSScriptRoot"
$MTX_CONFIG    = "$PROJECT_DIR\mediamtx.yml"

# Detect LAN IP for remote access URLs
$LAN_IP = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
    Select-Object -First 1 -ExpandProperty IPAddress)
if (-not $LAN_IP) { $LAN_IP = "localhost" }

# --- Stream definitions ---
# Each stream: name, RTMP URL on MediaMTX, video bitrate, output directory
$STREAMS = @(
    @{
        Name      = "cam1"
        RtmpUrl   = "rtmp://localhost:1935/live/cam1"
        Bitrate   = "2500k"
        Bufsize   = "5000k"
    },
    @{
        Name      = "cam2"
        RtmpUrl   = "rtmp://localhost:1935/live/cam2"
        Bitrate   = "1500k"
        Bufsize   = "3000k"
    },
    @{
        Name      = "screen"
        RtmpUrl   = "rtmp://localhost:1935/live/screen"
        Bitrate   = "4000k"
        Bufsize   = "8000k"
    }
)

# --- Colors ---
function Write-Step($msg)  { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-OK($msg)    { Write-Host "   $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "   $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "   $msg" -ForegroundColor Red }

# ============================================================
#  Pre-flight checks
# ============================================================
Write-Host "`n========================================" -ForegroundColor White
Write-Host "  OTT Streaming Pipeline - Multi-Input" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor White

# Check MediaMTX
Write-Step "Checking MediaMTX"
$mtxExe = "$MEDIAMTX_PATH\mediamtx.exe"
if (Test-Path $mtxExe) {
    Write-OK "Found at $MEDIAMTX_PATH"
} else {
    Write-Err "MediaMTX not found at $MEDIAMTX_PATH"
    Write-Err "Download from https://github.com/bluenviron/mediamtx/releases"
    exit 1
}

# Check project config
Write-Step "Checking MediaMTX config"
if (Test-Path $MTX_CONFIG) {
    Write-OK "Using project config: $MTX_CONFIG"
} else {
    Write-Err "Config not found at $MTX_CONFIG"
    exit 1
}

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
    $projectNginxConf = "$PROJECT_DIR\nginx.conf"
    $activeNginxConf  = "$NGINX_PATH\conf\nginx.conf"
    if (Test-Path $projectNginxConf) {
        Copy-Item $projectNginxConf $activeNginxConf -Force
        Write-OK "Deployed project nginx.conf"
    }
} else {
    Write-Warn "Nginx not found at $NGINX_PATH - HLS will not be served"
    $NGINX_PATH = $null
}

# ============================================================
#  Prepare HLS directories
# ============================================================
Write-Step "Preparing HLS directories"
foreach ($stream in $STREAMS) {
    $dir = "$PROJECT_DIR\hls\$($stream.Name)"
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-OK "Created hls\$($stream.Name)"
    }
    $old = Get-ChildItem "$dir\*.ts" -ErrorAction SilentlyContinue
    if ($old) {
        Remove-Item "$dir\*.ts" -Force
        Write-OK "Cleaned $($old.Count) old segment(s) from hls\$($stream.Name)"
    }
}

# ============================================================
#  Start Nginx
# ============================================================
if ($NGINX_PATH) {
    Write-Step "Starting Nginx"
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
            Write-Err "Nginx failed to start. Check config: $nginxExe -t"
        }
    }
    Write-OK "Viewer: http://${LAN_IP}/viewer/"
}

# ============================================================
#  Start MediaMTX
# ============================================================
Write-Step "Starting MediaMTX (RTMP relay)"
$mtxArgs = @("`"$MTX_CONFIG`"")
$mtxProc = Start-Process -FilePath $mtxExe -ArgumentList $mtxArgs -WorkingDirectory $MEDIAMTX_PATH -PassThru -WindowStyle Normal
Start-Sleep -Seconds 2
if (!$mtxProc.HasExited) {
    Write-OK "MediaMTX started (PID $($mtxProc.Id))"
} else {
    Write-Err "MediaMTX failed to start. Check config at $MTX_CONFIG"
    exit 1
}

Write-Host ""
Write-Host "  RTMP relay:   rtmp://0.0.0.0:1935/live/{name}" -ForegroundColor White
Write-Host "  REST API:     http://${LAN_IP}:9999/v3/paths/list" -ForegroundColor White

# ============================================================
#  Start FFmpeg instances (one per stream)
# ============================================================
Write-Step "Starting FFmpeg instances"
foreach ($stream in $STREAMS) {
    $name    = $stream.Name
    $rtmpUrl = $stream.RtmpUrl
    $bitrate = $stream.Bitrate
    $bufsize = $stream.Bufsize
    $outDir  = "$PROJECT_DIR\hls\$name"
    $playlist = "$outDir\stream.m3u8"
    $segPattern = "$outDir\stream%03d.ts"

    # FFmpeg connects to MediaMTX as a client (no -listen flag)
    $ffmpegArgs = @(
        "-i", $rtmpUrl,
        "-c:v", "libx264",
        "-preset", "veryfast",
        "-tune", "zerolatency",
        "-b:v", $bitrate,
        "-maxrate", $bitrate,
        "-bufsize", $bufsize,
        "-g", "60",
        "-keyint_min", "60",
        "-sc_threshold", "0",
        "-c:a", "aac",
        "-b:a", "128k",
        "-ar", "48000",
        "-f", "hls",
        "-hls_time", "4",
        "-hls_list_size", "5",
        "-hls_flags", "delete_segments",
        "-hls_segment_filename", $segPattern,
        $playlist
    )

    # Start FFmpeg in a new window so each stream has its own terminal
    $argString = $ffmpegArgs -join " "
    Start-Process -FilePath "ffmpeg" -ArgumentList $ffmpegArgs -WindowStyle Normal
    Write-OK "FFmpeg for $name -> hls\$name\stream.m3u8"
}

# ============================================================
#  Print summary
# ============================================================
Write-Host ""
Write-Host "========================================" -ForegroundColor White
Write-Host "  Pipeline is running" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor White
Write-Host ""
Write-Host "  OBS streams (push to MediaMTX):" -ForegroundColor Yellow
foreach ($stream in $STREAMS) {
    Write-Host "    $($stream.Name):  rtmp://${LAN_IP}:1935/live/$($stream.Name)" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "  HLS output (served by Nginx):" -ForegroundColor Yellow
foreach ($stream in $STREAMS) {
    Write-Host "    $($stream.Name):  http://${LAN_IP}/hls/$($stream.Name)/stream.m3u8" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "  Stream status:  http://${LAN_IP}:9999/v3/paths/list" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Stop with:  .\stop-stream.ps1" -ForegroundColor Cyan
Write-Host ""
