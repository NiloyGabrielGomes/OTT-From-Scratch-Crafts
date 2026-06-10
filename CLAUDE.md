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

## Architecture — Chapter 1 Pipeline (Multi-Input)

```
[OBS/Source] → [RTMP] → [MediaMTX (relay)] → [runOnReady hook] → [FFmpeg (re-encode + HLS)] → [Nginx] → [Browser/HLS.js]
```

- **MediaMTX** acts as the RTMP relay server on port 1935. It receives RTMP streams from multiple sources (OBS instances) and triggers FFmpeg per-input via `runOnReady` hooks.
- **FFmpeg** is NOT started directly. MediaMTX calls `ffmpeg/ffmpeg-start.ps1 -StreamName <name>` when a stream is published. FFmpeg reads from MediaMTX and writes HLS segments to `hls/<streamName>/`.
- **Nginx** serves the HLS directory, the viewer page, and `inputs.json` over HTTP. Uses `server_name _` to accept requests on any IP (LAN access). Config lives at `config/nginx.conf` and is auto-deployed to Nginx's install directory by `start-stream.ps1`.
- **inputs.json** is the single source of truth for all stream configurations (bitrate, codec settings, labels).
- **HLS.js** in the browser fetches the manifest and segments via HTTP. The viewer has stream selector tabs populated from `/inputs.json`.

**Why re-encode instead of pass-through (`-c:v copy`)?** HLS segments must start on keyframes. By re-encoding with `-g 60 -keyint_min 60 -sc_threshold 0`, we guarantee keyframes align with segment boundaries. Pass-through would require OBS to emit perfectly-aligned keyframes, which is unreliable.

**Why MediaMTX instead of FFmpeg listening directly?** With multiple inputs (cam1, cam2, screen), each needs its own FFmpeg instance. MediaMTX acts as a central RTMP relay that triggers per-stream FFmpeg processes only when a source publishes (`runOnReady`), avoiding the chicken-and-egg problem of FFmpeg starting before OBS connects.

## Folder Structure

```
project root/
├── start-stream.ps1            # starts MediaMTX + Nginx (NOT FFmpeg)
├── stop-stream.ps1             # stops all processes
├── start-stream.bat            # convenience launcher → start-stream.ps1
├── inputs.json                 # stream definitions (single source of truth)
├── mediamtx.yml                # MediaMTX relay config with runOnReady hooks
├── auto.crt / auto.key         # self-signed TLS certs for HTTPS
├── ffmpeg/
│   └── ffmpeg-start.ps1        # FFmpeg encoder (called by MediaMTX)
├── config/
│   └── nginx.conf              # Nginx config (HLS serving, CORS, caching)
├── viewer/
│   └── index.html              # HLS.js viewer with stream selector tabs
├── hls/                        # HLS output (auto-generated, gitignored)
│   ├── cam1/                   #   per-stream segments
│   ├── cam2/
│   └── screen/
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
- `runOnReady` fires when OBS publishes to that path (NOT `runOnPublish` — that doesn't exist)
- `runOnReadyRestart: yes` restarts FFmpeg if it crashes while the stream is still active
- Paths call PowerShell directly: `powershell -ExecutionPolicy Bypass -File "...\ffmpeg\ffmpeg-start.ps1" cam1`
- FFmpeg receives SIGINT when OBS disconnects (MediaMTX sends it automatically)

## Operational Scripts

- `start-stream.ps1` — Starts MediaMTX + Nginx. Reads `inputs.json` for summary. Detects LAN IP for remote access URLs. Deploys `config/nginx.conf` to Nginx install directory.
- `stop-stream.ps1` — Stops FFmpeg, MediaMTX, and Nginx.
- `ffmpeg/ffmpeg-start.ps1` — FFmpeg encoder. Called by MediaMTX, not by user. Takes `-StreamName` param, reads `inputs.json` for settings.
- `start-stream.bat` — Double-click convenience launcher for `start-stream.ps1`.

## LAN Access

The pipeline supports LAN access for office network streaming/viewing:
- `start-stream.ps1` detects the machine's LAN IP via `Get-NetIPAddress`
- Nginx uses `server_name _` to accept requests on any IP
- OBS sources on other machines stream to `rtmp://<LAN_IP>:1935/live/<streamName>`
- Viewers access via `http://<LAN_IP>/viewer/`
- Self-signed TLS certs (`auto.crt` / `auto.key`) are available for HTTPS if needed
- Windows Firewall rules needed for ports 80 (Nginx), 1935 (RTMP), 9999 (MediaMTX API)

## Key FFmpeg Flags

- `-listen 1` — act as RTMP server (wait for MediaMTX to connect)
- `-g 60 -keyint_min 60` — keyframe every 60 frames (2s at 30fps), aligns with 4s segments
- `-sc_threshold 0` — disable scene-change keyframe insertion (breaks HLS alignment)
- `-tune zerolatency` — disable look-ahead buffering for live streaming
- `-hls_time 4` — 4-second segments
- `-hls_flags delete_segments+append_list` — auto-delete old `.ts` files, append mode

## Key Reference Documents

- `claude-contexts/ott-bootcamp-task.md` — Full bootcamp task brief (all 6 chapters, checkpoints)
- `claude-contexts/ott-bootcamp-context.md` — Detailed architectural guidance for Chapters 1-2, setup instructions, tracing guide, and checkpoint Q&A
- `claude-contexts/plan.md` — Current implementation plan (Chapter 1 OBS variant)

## Git Conventions

- PR template at `.github/pull_request_template.md` — use it for all PRs
- Issue templates exist for bugs, features, and tasks in `.github/ISSUE_TEMPLATE/`
- Link issues in PRs with `Fixes #n` syntax
