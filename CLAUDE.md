# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an OTT (Over-The-Top) streaming platform built from scratch as a learning bootcamp. The project progresses through 6 chapters, each building on the last: live HLS streaming (Ch1), low-latency WebRTC monitoring (Ch2), on-demand VOD with pre-roll ads (Ch3), mid-stream ad insertion (Ch4), scale architecture document (Ch5), and AWS media services rebuild (Ch6).

## Environment

- **Claude Code runs in:** Ubuntu WSL2 terminal
- **Project code lives on:** Windows filesystem (`E:\Streaming Service Project\OTT-From-Scratch-Crafts`)
- **WSL path:** `/mnt/e/Streaming Service Project/OTT-From-Scratch-Crafts`
- **Tools (OBS, FFmpeg, Nginx, MediaMTX) are installed on Windows**, not WSL
- All media tool commands (ffmpeg, nginx) should use **Windows PowerShell syntax** (backtick line continuation, `dir` instead of `ls`)
- OBS Studio is a Windows GUI application — configure via its settings UI, not CLI
- **PowerShell scripts must be ASCII-safe** — no em dashes, curly quotes, or non-ASCII characters

## Architecture — Chapters 1+2+3 Pipeline

```
[OBS/Source] → [RTMP] → [MediaMTX (relay)]
                              ├─→ [WebRTC (WHEP)] → [Browser Monitor]   ← Chapter 2 (low-latency)
                              ├─→ [FFmpeg] → [HLS] → [Nginx] → [Browser Viewer]  ← Chapter 1
                              └─→ [Recording] → [fMP4 files] → [videos/]  ← Chapter 3 (VOD source)
```

- **MediaMTX** acts as the RTMP relay server on port 1935. It receives RTMP streams from multiple sources (OBS instances) and triggers FFmpeg per-input via `runOnReady` hooks. Also serves WebRTC on port 8889 for low-latency monitoring. Records streams to disk via built-in recording feature.
- **FFmpeg** is NOT started directly. MediaMTX calls `ffmpeg/ffmpeg-start.ps1 -StreamName <name>` when a stream is published. FFmpeg reads from MediaMTX and writes HLS segments to `hls/<streamName>/`.
- **Nginx** serves the HLS directory, the viewer page, the monitor page, the VOD library, and `inputs.json` over HTTP. Uses `server_name _` to accept requests on any IP (LAN access). Config lives at `config/nginx.conf` and is auto-deployed to Nginx's install directory by `start-stream.ps1`.
- **inputs.json** is the single source of truth for all stream configurations (bitrate, codec settings, labels).
- **HLS.js** in the browser fetches the manifest and segments via HTTP. The viewer has stream selector tabs (live) and a VOD library (on-demand).
- **WebRTC Monitor** (`monitor/index.html`) uses WHEP protocol to pull streams from MediaMTX with <1s latency. Multi-view dashboard for director/producer monitoring.

**Why re-encode instead of pass-through (`-c:v copy`)?** HLS segments must start on keyframes. By re-encoding with `-g 60 -keyint_min 60 -sc_threshold 0`, we guarantee keyframes align with segment boundaries. Pass-through would require OBS to emit perfectly-aligned keyframes, which is unreliable.

**Why MediaMTX instead of FFmpeg listening directly?** With multiple inputs (cam1, cam2, screen), each needs its own FFmpeg instance. MediaMTX acts as a central RTMP relay that triggers per-stream FFmpeg processes only when a source publishes (`runOnReady`), avoiding the chicken-and-egg problem of FFmpeg starting before OBS connects.

## VOD & SSAI (Chapter 3)

On-demand video with server-side ad insertion (SSAI) pre-roll:

```
videos/
├── ad/*.mp4              # ad source video(s)
└── live/cam1/*.mp4       # recorded content from MediaMTX

        ↓ ffmpeg/vod-generate.ps1

vod/
├── catalog.json           # video library metadata (served to viewer)
├── _shared/ad/            # ad HLS segments (encoded once, reused)
├── <video-id>/
│   ├── index.m3u8         # master playlist: ad segments → discontinuity → content segments
│   └── content/           # content HLS segments
```

- **SSAI over CSAI:** Ad stitched server-side into manifest. Player sees one continuous stream. Ad blockers cannot skip. Server has full control.
- **Master playlist pattern:** Per-video `index.m3u8` references shared ad segments + video-specific content segments with `#EXT-X-DISCONTINUITY` between them. Same pattern used by AWS MediaTailor.
- **`ffmpeg/vod-encode.ps1`** — encodes a single video into HLS VOD segments (`-hls_list_size 0` for VOD mode, all segments kept).
- **`ffmpeg/vod-generate.ps1`** — orchestrator: encodes ad + all content videos, generates master playlists and `catalog.json`.
- **`catalog.json`** — served by Nginx at `/vod/catalog.json`, consumed by the viewer's VOD library UI.

## Folder Structure

```
project root/
├── start-stream.ps1            # starts MediaMTX + Nginx (NOT FFmpeg)
├── stop-stream.ps1             # stops all processes
├── start-stream.bat            # convenience launcher → start-stream.ps1
├── inputs.json                 # stream definitions (single source of truth)
├── mediamtx.yml                # MediaMTX relay config (RTMP + WebRTC + recording)
├── auto.crt / auto.key         # self-signed TLS certs for HTTPS
├── ffmpeg/
│   ├── ffmpeg-start.ps1        # FFmpeg live encoder (called by MediaMTX)
│   ├── ffmpeg-start.bat        # batch wrapper for MediaMTX runOnReady
│   ├── vod-encode.ps1          # FFmpeg VOD HLS encoder (single video → segments)
│   └── vod-generate.ps1        # orchestrator: encodes all + master playlists + catalog
├── config/
│   └── nginx.conf              # Nginx config (HLS, monitor, VOD, CORS, caching)
├── viewer/
│   ├── index.html              # viewer page — Live + VOD tabs (Pico CSS)
│   ├── styles.css              # minimal custom CSS overrides
│   └── app.js                  # HLS.js live player + VOD library + player
├── monitor/
│   ├── index.html              # WebRTC multi-view monitor dashboard (Ch2)
│   ├── styles.css              # Pico CSS overrides
│   └── app.js                  # WHEP client + stats
├── hls/                        # HLS live output (auto-generated, gitignored)
├── videos/                     # recorded streams + ad video (gitignored)
│   ├── ad/                     #   ad source video(s)
│   └── live/cam1/              #   MediaMTX recordings (fMP4)
├── vod/                        # VOD HLS output (generated, gitignored)
└── claude-contexts/            # bootcamp reference docs
```

## Key Config: inputs.json

All stream settings are defined in `inputs.json` (project root). This file is:
- Read by `ffmpeg/ffmpeg-start.ps1` to configure each FFmpeg instance
- Read by `start-stream.ps1` for startup summary display
- Served by Nginx at `/inputs.json` for the viewer's stream selector

To add a new stream: add an entry to `inputs.json` and a corresponding `paths` block in `mediamtx.yml`.

## Key Config: mediamtx.yml

MediaMTX is configured in `mediamtx.yml` (project root). Key points:
- **RTMP:** Port 1935 for receiving streams from OBS
- **WebRTC:** Port 8889 for low-latency monitoring (WHEP protocol)
- **Recording:** `record: yes` with `recordFormat: fmp4` saves streams to `videos/` automatically
- `runOnReady` fires when OBS publishes to that path (NOT `runOnPublish` — that doesn't exist)
- `runOnReadyRestart: yes` restarts FFmpeg if it crashes while the stream is still active
- Paths call PowerShell directly: `powershell -ExecutionPolicy Bypass -File "...\ffmpeg\ffmpeg-start.ps1" cam1`
- FFmpeg receives SIGINT when OBS disconnects (MediaMTX sends it automatically)
- **WebRTC codec:** Default VP8 for lowest latency, configurable via monitor UI

## Operational Scripts

- `start-stream.ps1` — Starts MediaMTX + Nginx. Reads `inputs.json` for summary. Detects LAN IP for remote access URLs. Deploys `config/nginx.conf` to Nginx install directory.
- `stop-stream.ps1` — Stops FFmpeg, MediaMTX, and Nginx.
- `ffmpeg/ffmpeg-start.ps1` — FFmpeg live encoder. Called by MediaMTX, not by user. Takes `-StreamName` param, reads `inputs.json` for settings.
- `ffmpeg/vod-encode.ps1` — Encodes a video into HLS VOD segments. Takes `-InputVideo` and `-OutputDir` params.
- `ffmpeg/vod-generate.ps1` — Generates VOD master playlists and `catalog.json` from `videos/` folder. Run manually after recording content.
- `start-stream.bat` — Double-click convenience launcher for `start-stream.ps1`.

## LAN Access

The pipeline supports LAN access for office network streaming/viewing:
- `start-stream.ps1` detects the machine's LAN IP via `Get-NetIPAddress`
- Nginx uses `server_name _` to accept requests on any IP
- OBS sources on other machines stream to `rtmp://<LAN_IP>:1935/live/<streamName>`
- Viewers access via `http://<LAN_IP>/viewer/`
- Monitor access via `http://<LAN_IP>/monitor/` (WebRTC, <1s latency)
- VOD library via `http://<LAN_IP>/viewer/` (VOD tab)
- Self-signed TLS certs (`auto.crt` / `auto.key`) are available for HTTPS if needed
- Windows Firewall rules needed: OTT Nginx HTTP (80), OTT MediaMTX RTMP (1935), OTT MediaMTX WebRTC Signaling (8889), OTT MediaMTX WebRTC Media (8888), OTT MediaMTX API (9999)

## Key FFmpeg Flags

- `-listen 1` — act as RTMP server (wait for MediaMTX to connect)
- `-g 60 -keyint_min 60` — keyframe every 60 frames (2s at 30fps), aligns with 4s segments
- `-sc_threshold 0` — disable scene-change keyframe insertion (breaks HLS alignment)
- `-tune zerolatency` — disable look-ahead buffering for live streaming
- `-hls_time 4` — 4-second segments
- `-hls_flags delete_segments+append_list` — auto-delete old `.ts` files, append mode (live)
- `-hls_list_size 0` — keep all segments (VOD mode)

## Key Reference Documents

- `claude-contexts/ott-bootcamp-task.md` — Full bootcamp task brief (all 6 chapters, checkpoints)
- `claude-contexts/ott-bootcamp-context.md` — Detailed architectural guidance for Chapters 1-2, setup instructions, tracing guide, and checkpoint Q&A
- `claude-contexts/plan.md` — Current implementation plan (Chapter 3: VOD with SSAI)

## Git Conventions

- PR template at `.github/pull_request_template.md` — use it for all PRs
- Issue templates exist for bugs, features, and tasks in `.github/ISSUE_TEMPLATE/`
- Link issues in PRs with `Fixes #n` syntax
