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

