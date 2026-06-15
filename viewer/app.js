// ============================================================
//  Stream Viewer — Live + VOD
// ============================================================

// === DOM refs ===
const video         = document.getElementById('video');
const status        = document.getElementById('status');
const tabsDiv       = document.getElementById('tabs');
const infoDiv       = document.getElementById('info');
const modeTabs      = document.querySelectorAll('.mode-tab');
const liveSection   = document.getElementById('live-section');
const vodSection    = document.getElementById('vod-section');
const vodVideo      = document.getElementById('vod-video');
const vodStatus     = document.getElementById('vod-status');
const vodInfo       = document.getElementById('vod-info');
const vodGrid       = document.getElementById('vod-grid');
const vodEmpty      = document.getElementById('vod-empty');
const vodPlayerArea = document.getElementById('vod-player-area');
const vodLibrary    = document.getElementById('vod-library');
const vodBack       = document.getElementById('vod-back');

// === State ===
let hls       = null;
let streams   = [];
let active    = null;
let vodHls    = null;
let vodCatalog = [];

// === Mode switching ===
function switchMode(mode) {
    modeTabs.forEach(t => t.classList.toggle('active', t.dataset.mode === mode));
    liveSection.classList.toggle('hidden', mode !== 'live');
    vodSection.classList.toggle('hidden', mode !== 'vod');

    if (mode === 'vod' && hls) {
        hls.destroy();
        hls = null;
        active = null;
    }
    if (mode === 'live') {
        vodVideo.pause();
        vodVideo.src = '';
    }
}

modeTabs.forEach(t => {
    t.addEventListener('click', () => switchMode(t.dataset.mode));
});

// === VOD ===
function setVodStatus(text, cls) {
    vodStatus.textContent = text;
    vodStatus.className = 'status-bar ' + cls;
}

vodBack.addEventListener('click', (e) => {
    e.preventDefault();
    if (vodHls) { vodHls.destroy(); vodHls = null; }
    vodVideo.pause();
    vodVideo.src = '';
    vodPlayerArea.classList.add('hidden');
    vodLibrary.classList.remove('hidden');
    setVodStatus('', '');
    vodInfo.textContent = '';
});

function playVod(videoId) {
    const entry = vodCatalog.find(v => v.id === videoId);
    if (!entry) return;

    vodLibrary.classList.add('hidden');
    vodPlayerArea.classList.remove('hidden');
    vodInfo.textContent = entry.title;

    if (vodHls) { vodHls.destroy(); vodHls = null; }
    setVodStatus('Loading...', 'loading');

    const url = entry.playlist;

    if (Hls.isSupported()) {
        vodHls = new Hls();
        vodHls.loadSource(url);
        vodHls.attachMedia(vodVideo);

        vodHls.on(Hls.Events.MANIFEST_PARSED, () => {
            setVodStatus('Playing', 'vod');
            vodVideo.play().catch(() => {});
        });

        vodHls.on(Hls.Events.ERROR, (_, data) => {
            if (data.fatal) {
                setVodStatus('Error loading video', 'error');
                console.error('VOD HLS fatal error:', data);
            }
        });

    } else if (vodVideo.canPlayType('application/vnd.apple.mpegurl')) {
        vodVideo.src = url;
        vodVideo.addEventListener('loadedmetadata', () => {
            setVodStatus('Playing', 'vod');
            vodVideo.play().catch(() => {});
        });
    } else {
        setVodStatus('HLS not supported in this browser', 'error');
    }
}

async function initVod() {
    try {
        const resp = await fetch('/vod/catalog.json');
        const data = await resp.json();
        vodCatalog = data.videos || [];

        if (!vodCatalog.length) {
            vodEmpty.classList.remove('hidden');
            return;
        }

        vodCatalog.forEach(v => {
            const card = document.createElement('article');
            card.className = 'vod-card';
            card.innerHTML = `
                <div class="vod-thumb">&#127916;</div>
                <footer>
                    <strong>${v.title}</strong><br>
                    <small>${v.duration || 'Unknown duration'}</small>
                </footer>
            `;
            card.addEventListener('click', () => playVod(v.id));
            vodGrid.appendChild(card);
        });

    } catch (e) {
        vodEmpty.classList.remove('hidden');
    }
}

// === Init ===
initLive();
initVod();
