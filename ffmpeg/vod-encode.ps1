# ============================================================
#  FFmpeg VOD HLS Encoder
#
#  Encodes a video file into HLS VOD segments (.ts + .m3u8)
#
#  Usage:  .\vod-encode.ps1 -InputVideo "videos/ad/my-ad.mp4" -OutputDir "hls/ad"
# ============================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$InputVideo,

    [Parameter(Mandatory=$true)]
    [string]$OutputDir
)

$SCRIPT_DIR  = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_DIR = Split-Path -Parent $SCRIPT_DIR

# Resolve paths relative to project root
if (![IO.Path]::IsPathRooted($InputVideo)) {
    $InputVideo = Join-Path $PROJECT_DIR $InputVideo
}
if (![IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir = Join-Path $PROJECT_DIR $OutputDir
}

# Validate input
if (!(Test-Path $InputVideo)) {
    Write-Error "Input video not found: $InputVideo"
    exit 1
}

# Create output directory
if (!(Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$playlist   = Join-Path $OutputDir "index.m3u8"
$segPattern = Join-Path $OutputDir "seg_%03d.ts"

Write-Host ">> Encoding VOD HLS" -ForegroundColor Cyan
Write-Host "   Input:  $InputVideo" -ForegroundColor Gray
Write-Host "   Output: $playlist" -ForegroundColor Gray

# --- FFmpeg args ---
$ffmpegArgs = @(
    "-i", $InputVideo,
    "-c:v", "libx264",
    "-preset", "fast",
    "-g", "60",
    "-keyint_min", "60",
    "-sc_threshold", "0",
    "-c:a", "aac",
    "-b:a", "128k",
    "-ar", "48000",
    "-f", "hls",
    "-hls_time", "4",
    "-hls_list_size", "0",
    "-hls_segment_type", "mpegts",
    "-hls_segment_filename", $segPattern,
    $playlist
)

& ffmpeg @ffmpegArgs

if ($LASTEXITCODE -eq 0) {
    $segCount = (Get-ChildItem "$OutputDir\*.ts").Count
    Write-Host ">> Done. $segCount segments created." -ForegroundColor Green
} else {
    Write-Error "FFmpeg exited with code $LASTEXITCODE"
    exit 1
}
