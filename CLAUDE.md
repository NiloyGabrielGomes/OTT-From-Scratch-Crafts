# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an OTT (Over-The-Top) streaming platform built from scratch as a learning bootcamp. The project progresses through 6 chapters, each building on the last: live HLS streaming (Ch1), low-latency WebRTC monitoring (Ch2), on-demand VOD with pre-roll ads (Ch3), mid-stream ad insertion (Ch4), scale architecture document (Ch5), and AWS media services rebuild (Ch6).

## Environment

- **Claude Code runs in:** Ubuntu WSL2 terminal
- **Project code lives on:** Windows filesystem (`E:\Streaming Service Project\OTT-From-Scratch-Crafts`)
- **WSL path:** `/mnt/e/Streaming Service Project/OTT-From-Scratch-Crafts`
- **Tools (OBS, FFmpeg, Nginx) are installed on Windows**, not WSL
- All media tool commands (ffmpeg, nginx) should use **Windows PowerShell syntax** (backtick line continuation, `dir` instead of `ls`)
- OBS Studio is a Windows GUI application — configure via its settings UI, not CLI

## Architecture — Chapter 1 Pipeline

```
[OBS] → [RTMP] → [FFmpeg (receive + re-encode + HLS package)] → [HLS files on disk] → [Nginx] → [Browser / HLS.js]
```

- OBS handles scene composition and light H.264/AAC encoding, streams via RTMP to `rtmp://localhost:1935/live/stream`
- FFmpeg listens on RTMP port 1935 (`-listen 1`), re-encodes with HLS-optimized settings (`libx264`, keyframe every 60 frames, `-sc_threshold 0`), and writes HLS segments (`.m3u8` + `.ts`) to disk
- Nginx serves the HLS directory with correct MIME types and caches segments for concurrent viewers
- HLS.js in the browser fetches the manifest and segments via HTTP

**Why re-encode instead of pass-through (`-c:v copy`)?** HLS segments must start on keyframes. By re-encoding with `-g 60 -keyint_min 60 -sc_threshold 0`, we guarantee keyframes align with segment boundaries. Pass-through would require OBS to emit perfectly-aligned keyframes, which is unreliable.

## Operational Scripts

- `start-stream.ps1` — Starts FFmpeg (RTMP listener + HLS packager) and Nginx. All FFmpeg config is in one place (bitrate, segment time, keyframe interval).
- `stop-stream.ps1` — Stops FFmpeg and Nginx cleanly.
- `start-stream.bat` — Double-click launcher for `start-stream.ps1`.
- `nginx.conf` — Standalone Nginx config (must be copied to `C:\nginx\conf\nginx.conf`).
- `viewer/index.html` — HLS.js viewer page.
- `hls/` — HLS output directory (segments auto-deleted by FFmpeg, gitignored).

## Key FFmpeg Flags

The FFmpeg command uses these flags for HLS-optimized encoding:
- `-listen 1` — act as RTMP server (wait for OBS to connect)
- `-g 60 -keyint_min 60` — keyframe every 60 frames (2s at 30fps), aligns with 4s segments
- `-sc_threshold 0` — disable scene-change keyframe insertion (breaks HLS alignment)
- `-tune zerolatency` — disable look-ahead buffering for live streaming
- `-hls_time 4` — 4-second segments
- `-hls_flags delete_segments` — auto-delete old `.ts` files from disk

## Key Reference Documents

- `claude-contexts/ott-bootcamp-task.md` — Full bootcamp task brief (all 6 chapters, checkpoints)
- `claude-contexts/ott-bootcamp-context.md` — Detailed architectural guidance for Chapters 1-2, setup instructions, tracing guide, and checkpoint Q&A
- `claude-contexts/plan.md` — Current implementation plan (Chapter 1 OBS variant)

## Git Conventions

- PR template at `.github/pull_request_template.md` — use it for all PRs
- Issue templates exist for bugs, features, and tasks in `.github/ISSUE_TEMPLATE/`
- Link issues in PRs with `Fixes #n` syntax
