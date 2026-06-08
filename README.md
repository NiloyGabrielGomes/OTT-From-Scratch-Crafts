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

