# OTT Streaming Platform — From Scratch

A hands-on project building an OTT (Over-The-Top) streaming platform from the ground up. This project progresses through 6 chapters, each building on the last.

---

## Chapter 1 — "We Need to Go Live"

### Architecture

```
┌──────────┐    RTMP     ┌──────────┐    HLS (.m3u8 + .ts)    ┌──────────┐    HTTP    ┌──────────┐
│  Source  │ ──────────► │  FFmpeg  │ ──────────────────────► │  Nginx   │ ─────────► │ Browser  │
│ (eg. OBS)│  port 1935  │(encoder) │     writes to disk      │ (cache)  │            │ (HLS.js) │
└──────────┘             └──────────┘                         └──────────┘            └──────────┘
  scenes,                  re-encode                              serve               fetch + play
  camera,                  + HLS package                          segments            via MSE
  overlays
```

**Why this shape?** Each component does one job. OBS handles the creative side (scenes, camera, overlays). FFmpeg handles the technical side (encoding, HLS segmentation). Nginx handles delivery (caching, concurrent viewers). This mirrors how real broadcast studios work — production and encoding are separate systems connected by a standard protocol (RTMP).

### Components

| Component | Role | Runs on |
|-----------|------|---------|
| **Source->RTMP** | Video source + scene composition. Sends RTMP to FFmpeg. | Windows GUI |
| **FFmpeg+HLS** | Receives RTMP, re-encodes with HLS-optimized settings, writes `.m3u8` + `.ts` segments to disk. | Windows CLI |
| **Nginx** | Serves HLS files over HTTP with correct MIME types. Caches segments so concurrent viewers don't multiply disk reads. | Windows |
| **HLS.js** | JavaScript library in the browser that fetches the `.m3u8` playlist, downloads segments, and feeds them to a `<video>` element. | Browser |

### Key Decisions

**Why re-encode in FFmpeg instead of `-c:v copy` (pass-through)?**
Sources (eg. OBS) does a preliminary encode, but FFmpeg needs control over keyframe placement for HLS. HLS segments must start on keyframes — if keyframes don't align with segment boundaries, you get playback glitches. By re-encoding with `-g 60 -keyint_min 60 -sc_threshold 0`, we guarantee a keyframe every 60 frames (2 seconds at 30fps), perfectly aligned with our 4-second segment duration. The `-sc_threshold 0` flag prevents the encoder from inserting extra keyframes on scene changes, which would break the alignment.

**Why does HLS have 15–30 seconds of latency?**
The player pre-buffers 3–5 segments before starting playback as protection against network hiccups. Each segment is 4 seconds long. This is a feature, not a bug — it makes HLS robust for broadcast. The tradeoff is latency. (Chapter 2 addresses this with WebRTC for sub-second latency.)

**Why Nginx instead of a Python dev server?**
Python's `http.server` is single-threaded — multiple viewers would queue up. Nginx handles concurrent connections efficiently and serves cached segments without hitting the filesystem for every request. It's the standard way to front HLS output.

### Pipeline Walkthrough

```
1. OBS captures camera/screen, composites scenes, encodes lightly, sends RTMP
                         │
                         ▼
2. FFmpeg listens on rtmp://0.0.0.0:1935/live/stream
   receives the RTMP stream, re-encodes with HLS-optimized settings
   keyframe every 60 frames, 4-second segments
                         │
                         ▼
3. FFmpeg writes hls/stream.m3u8 (playlist) + hls/stream001.ts, stream002.ts, ... (segments)
   old segments are deleted as they leave the rolling playlist window
                         │
                         ▼
4. Nginx serves the hls/ directory on http://localhost/hls/
   correct MIME types (application/vnd.apple.mpegurl for .m3u8, video/mp2t for .ts)
   caches segments for concurrent viewers
                         │
                         ▼
5. Browser loads viewer/index.html
   HLS.js fetches stream.m3u8, reads the segment list
   downloads .ts segments, feeds them to <video> via Media Source Extensions
   polls the playlist every ~4 seconds for new segments
```

### Setup

#### Manual Start (step by step)

```powershell
# Terminal 1 — Start FFmpeg
mkdir hls -Force
ffmpeg -listen 1 -i rtmp://0.0.0.0:1935/live/stream `
  -c:v libx264 -preset veryfast -tune zerolatency `
  -b:v 2500k -maxrate 2500k -bufsize 5000k `
  -g 60 -keyint_min 60 -sc_threshold 0 `
  -c:a aac -b:a 128k -ar 48000 `
  -f hls -hls_time 4 -hls_list_size 5 -hls_flags delete_segments `
  -hls_segment_filename hls/stream%03d.ts `
  hls/stream.m3u8

# Terminal 2 — Start Nginx
cd C:\nginx
start nginx

# OBS — Start Streaming to rtmp://localhost:1935/live

# Browser — Open http://localhost/viewer/
```

### Verifying the Pipeline

| Hop | What to check | Where |
|-----|--------------|-------|
| **Source → Encode** | OBS shows "Live" with bitrate graph moving | OBS status bar |
| **Encode → Package** | FFmpeg terminal shows `fps=30`, `speed=1.00x`, `time` incrementing | FFmpeg terminal |
| **Package → Disk** | `dir hls\` shows `.ts` files appearing every ~4s | PowerShell |
| **Disk → Cache** | `http://localhost/hls/stream.m3u8` returns playlist text, not a download | Browser |
| **Cache → Player** | DevTools (F12) → Network shows periodic `.m3u8` + `.ts` fetches | Browser |
| **Concurrent viewers** | Open 3 tabs — all play simultaneously | Browser |

### Project Structure

```
.
├── start-stream.ps1       # Startup script (FFmpeg + Nginx)
├── start-stream.bat       # Double-click launcher
├── stop-stream.ps1        # Shutdown script
├── nginx.conf             # Nginx config (HLS serving)
├── hls/                   # HLS output (gitignored)
│   ├── stream.m3u8        #   playlist (rolling window)
│   └── stream001.ts       #   segment files (auto-deleted)
└── viewer/
    └── index.html         # HLS.js viewer page
```

### FFmpeg Flags Reference

| Flag | Purpose |
|------|---------|
| `-listen 1` | Act as RTMP server (wait for incoming connections) |
| `-c:v libx264` | H.264 video encoder |
| `-preset veryfast` | Encoding speed (faster = less CPU, slightly lower quality) |
| `-tune zerolatency` | Disable look-ahead buffering — essential for live |
| `-b:v 2500k` | Target video bitrate |
| `-maxrate 2500k -bufsize 5000k` | CBR-like constraint, caps bitrate spikes |
| `-g 60 -keyint_min 60` | Keyframe every 60 frames (2s at 30fps) |
| `-sc_threshold 0` | No extra keyframes on scene changes (breaks HLS alignment) |
| `-c:a aac -b:a 128k` | AAC audio at 128kbps |
| `-f hls` | Output format: HLS |
| `-hls_time 4` | 4-second segments |
| `-hls_list_size 5` | Keep 5 segments in playlist |
| `-hls_flags delete_segments` | Delete old `.ts` files from disk |

---

## Roadmap

| Chapter | Topic | Status |
|---------|-------|--------|
| 1 | Live HLS streaming with OBS + FFmpeg | ✅ Done |
| 2 | Low-latency WebRTC monitoring feed | Planned |
| 3 | On-demand VOD with pre-roll ads | Planned |
| 4 | Mid-stream ad insertion | Planned |
| 5 | Scale architecture document (100k users) | Planned |
| 6 | AWS Media Services rebuild | Planned |
