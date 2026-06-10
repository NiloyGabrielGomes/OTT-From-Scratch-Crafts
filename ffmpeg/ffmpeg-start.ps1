# ============================================================
#  FFmpeg HLS Launcher (called by MediaMTX runOnPublish)
#
#  Usage:  .\ffmpeg-start.ps1 -StreamName cam1
#
#  MediaMTX calls this when OBS starts publishing.
#  Reads stream config from inputs.json and starts FFmpeg.
#  MediaMTX terminates this process (and its FFmpeg child)
#  when OBS disconnects.
# ============================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$StreamName
)

$PROJECT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$INPUTS_FILE = Join-Path $PROJECT_DIR "inputs.json"

# --- Load config ---
if (!(Test-Path $INPUTS_FILE)) {
    Write-Error "inputs.json not found at $INPUTS_FILE"
    exit 1
}

$config = Get-Content $INPUTS_FILE -Raw | ConvertFrom-Json
$input  = $config.inputs | Where-Object { $_.name -eq $StreamName }

if (!$input) {
    Write-Error "Stream '$StreamName' not found in inputs.json"
    exit 1
}

# --- Build paths ---
$rtmpUrl    = "$($config.rtmpServer)/$StreamName"
$outDir     = Join-Path $PROJECT_DIR "hls\$StreamName"
$playlist   = Join-Path $outDir "stream.m3u8"
$segPattern = Join-Path $outDir "stream%03d.ts"

# Create output directory if needed
if (!(Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

# --- Build FFmpeg args ---
$ffmpegArgs = @(
    "-i", $rtmpUrl,
    "-c:v", "libx264",
    "-preset", "veryfast",
    "-tune", "zerolatency",
    "-b:v", $input.videoBitrate,
    "-maxrate", $input.videoBitrate,
    "-bufsize", $input.bufsize,
    "-g", "60",
    "-keyint_min", "60",
    "-sc_threshold", "0",
    "-c:a", "aac",
    "-b:a", $input.audioBitrate,
    "-ar", "48000",
    "-f", "hls",
    "-hls_time", "4",
    "-hls_list_size", "5",
    "-hls_flags", "delete_segments",
    "-hls_segment_filename", $segPattern,
    $playlist
)

Write-Host ">> FFmpeg starting for '$StreamName'" -ForegroundColor Cyan
Write-Host "   Input:  $rtmpUrl" -ForegroundColor Gray
Write-Host "   Output: $playlist" -ForegroundColor Gray

# --- Run FFmpeg (blocking) ---
# This process stays alive until MediaMTX terminates it (OBS disconnects)
& ffmpeg @ffmpegArgs
