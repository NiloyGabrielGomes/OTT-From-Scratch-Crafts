// ============================================================
//  WHEP Client — WebRTC playback from MediaMTX
// ============================================================
class WHEPClient {
  constructor(endpoint, videoElement, statsCallback) {
    this.endpoint = endpoint;
    this.videoElement = videoElement;
    this.statsCallback = statsCallback;
    this.pc = null;
    this.state = 'disconnected'; // disconnected | connecting | connected | error
    this.statsInterval = null;
    this.prevStats = null;
  }

  async connect(codec = 'vp8') {
    if (this.pc) this.close();

    this.state = 'connecting';
    this.pc = new RTCPeerConnection({
      iceServers: [{ urls: 'stun:stun.l.google.com:19302' }]
    });

    // Handle incoming tracks
    this.pc.ontrack = (event) => {
      this.videoElement.srcObject = event.streams[0];
      this.state = 'connected';
      this.videoElement.closest('.stream-cell')?.classList.add('live');
      this.startStats();
    };

    // Connection state changes
    this.pc.onconnectionstatechange = () => {
      const state = this.pc.connectionState;
      if (state === 'connected') {
        this.state = 'connected';
      } else if (state === 'failed' || state === 'disconnected') {
        this.state = 'error';
        this.stopStats();
      }
      this.statsCallback?.({ type: 'state', state: this.state });
    };

    try {
      // Add transceivers for receiving media
      this.pc.addTransceiver('video', { direction: 'recvonly' });
      this.pc.addTransceiver('audio', { direction: 'recvonly' });

      // Create offer
      const offer = await this.pc.createOffer();
      await this.pc.setLocalDescription(offer);

      // Send to WHEP endpoint
      const url = `${this.endpoint}/whep`;
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/sdp',
          'Accept': 'application/sdp'
        },
        body: offer.sdp
      });

      if (!response.ok) {
        throw new Error(`WHEP error: ${response.status} ${response.statusText}`);
      }

      const answerSdp = await response.text();
      await this.pc.setRemoteDescription(
        new RTCSessionDescription({ type: 'answer', sdp: answerSdp })
      );

      this.state = 'connected';
      this.startStats();
      return true;
    } catch (err) {
      this.state = 'error';
      console.error('WHEP connection failed:', err);
      this.statsCallback?.({ type: 'error', message: err.message });
      return false;
    }
  }

  startStats() {
    this.stopStats();
    this.statsInterval = setInterval(async () => {
      if (!this.pc || this.pc.connectionState !== 'connected') return;
      try {
        const stats = await this.pc.getStats();
        let bitrate = 0, fps = 0, width = 0, height = 0, packetsLost = 0, packetsReceived = 0;

        stats.forEach(report => {
          if (report.type === 'inbound-rtp' && report.kind === 'video') {
            // Bitrate calculation (bits per second)
            if (this.prevStats && this.prevStats.has(report.id)) {
              const prev = this.prevStats.get(report.id);
              const duration = (report.timestamp - prev.timestamp) / 1000;
              if (duration > 0) {
                bitrate = ((report.bytesReceived - prev.bytesReceived) * 8) / duration / 1000; // kbps
              }
            }
            fps = report.framesPerSecond || 0;
            width = report.frameWidth || 0;
            height = report.frameHeight || 0;
            packetsLost = report.packetsLost || 0;
            packetsReceived = report.packetsReceived || 0;
          }
        });

        // Store for next calculation
        this.prevStats = new Map();
        stats.forEach(report => {
          if (report.type === 'inbound-rtp' && report.kind === 'video') {
            this.prevStats.set(report.id, {
              bytesReceived: report.bytesReceived,
              timestamp: report.timestamp
            });
          }
        });

        // Get round-trip time from candidate pair
        let rtt = 0;
        stats.forEach(report => {
          if (report.type === 'candidate-pair' && report.state === 'succeeded') {
            rtt = (report.currentRoundTripTime || 0) * 1000; // ms
          }
        });

        const lossRate = (packetsLost + packetsReceived) > 0
          ? (packetsLost / (packetsLost + packetsReceived)) * 100
          : 0;

        this.statsCallback?.({
          type: 'stats',
          bitrate: Math.round(bitrate),
          fps: Math.round(fps),
          resolution: `${width}x${height}`,
          packetLoss: lossRate.toFixed(1),
          rtt: Math.round(rtt)
        });
      } catch (err) {
        // Stats collection failed silently
      }
    }, 1000);
  }

  stopStats() {
    if (this.statsInterval) {
      clearInterval(this.statsInterval);
      this.statsInterval = null;
    }
  }

  close() {
    this.stopStats();
    if (this.pc) {
      this.pc.close();
      this.pc = null;
    }
    this.state = 'disconnected';
    this.videoElement.srcObject = null;
  }
}

// ============================================================
//  Monitor App
// ============================================================
const MONITOR_PORT = 8889;
const streams = new Map(); // streamName → { client, elements }
let inputsData = null;

// Build WHEP endpoint URL
function getWHEPEndpoint(streamName) {
  const host = window.location.hostname;
  return `http://${host}:${MONITOR_PORT}/live/${streamName}`;
}

// Create a stream cell element (uses Pico's <article> card)
function createStreamCell(streamName, label) {
  const cell = document.createElement('article');
  cell.className = 'stream-cell';
  cell.id = `cell-${streamName}`;
  cell.innerHTML = `
    <div class="cell-header">
      <div class="stream-name">
        <span class="status-dot offline" id="dot-${streamName}"></span>
        <span>${label}</span>
      </div>
      <span class="connection-state" id="state-${streamName}">disconnected</span>
    </div>
    <div class="video-container">
      <video id="video-${streamName}" autoplay muted playsinline></video>
      <div class="video-overlay" id="overlay-${streamName}">Waiting for stream...</div>
    </div>
    <div class="stats-bar" id="stats-${streamName}">
      <span class="stat-item"><span class="label">BITRATE</span> <span class="value" id="bitrate-${streamName}">--</span> kbps</span>
      <span class="stat-item"><span class="label">FPS</span> <span class="value" id="fps-${streamName}">--</span></span>
      <span class="stat-item"><span class="label">RES</span> <span class="value" id="res-${streamName}">--</span></span>
      <span class="stat-item"><span class="label">LOSS</span> <span class="value" id="loss-${streamName}">--</span>%</span>
      <span class="stat-item"><span class="label">RTT</span> <span class="value" id="rtt-${streamName}">--</span>ms</span>
    </div>
    <div class="cell-controls">
      <button class="outline" onclick="toggleMute('${streamName}')" id="mute-${streamName}" title="Mute/Unmute">&#128263;</button>
      <button class="outline" onclick="snapshot('${streamName}')" title="Snapshot">&#128247;</button>
      <button class="outline" onclick="toggleFullscreen('${streamName}')" title="Fullscreen">&#9974;</button>
      <button class="outline" onclick="reconnect('${streamName}')" title="Reconnect">&#8635;</button>
    </div>
  `;
  return cell;
}

// Auto-reconnect streams that disconnect
setInterval(() => {
  for (const [name, data] of streams.entries()) {
    if (data.client && data.client.state === 'error') {
      console.log(`Auto-reconnecting ${name}...`);
      reconnect(name);
    }
  }
}, 10000);

// Start on load
window.addEventListener('DOMContentLoaded', init);
