// ============================================================
//  Stream Viewer - Live + VOD
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
let vodCatalog = [];
let adVideoUrl = null;

// === Mode switching ===
function switchMode(mode) {
    modeTabs.forEach(function(t) {
        t.classList.toggle('active', t.dataset.mode === mode);
    });
    liveSection.classList.toggle('hidden', mode !== 'live');
    vodSection.classList.toggle('hidden', mode !== 'vod');

    if (mode === 'vod' && hls) {
        hls.destroy();
        hls = null;
        active = null;
    }
    if (mode === 'live') {
        vodVideo.pause();
        vodVideo.removeAttribute('src');
        vodVideo.load();
    }
}

modeTabs.forEach(function(t) {
    t.addEventListener('click', function() { switchMode(t.dataset.mode); });
});

// === Live stream ===
function setStatus(text, cls) {
    status.textContent = text;
    status.className = 'status-bar ' + cls;
}

function streamUrl(name) {
    return '/hls/' + name + '/stream.m3u8';
}

function switchStream(name) {
    if (active === name) return;
    active = name;

    document.querySelectorAll('.stream-tab').forEach(function(t) {
        t.classList.toggle('active', t.dataset.name === name);
    });

    var s = streams.find(function(x) { return x.name === name; });
    infoDiv.textContent = s
        ? s.label + ' - video: ' + s.videoBitrate + ', audio: ' + s.audioBitrate
        : '';

    if (hls) { hls.destroy(); hls = null; }

    var url = streamUrl(name);
    setStatus('Connecting...', 'loading');

    if (typeof Hls !== 'undefined' && Hls.isSupported()) {
        hls = new Hls({
            liveSyncDurationCount: 3,
            liveMaxLatencyDurationCount: 6,
        });
        hls.loadSource(url);
        hls.attachMedia(video);

        hls.on(Hls.Events.MANIFEST_PARSED, function() {
            setStatus('LIVE', 'live');
            video.play().catch(function() {});
        });

        hls.on(Hls.Events.ERROR, function(_, data) {
            if (data.fatal) {
                setStatus('Stream offline - is OBS streaming?', 'error');
                console.error('HLS fatal error:', data);
            }
        });

        hls.on(Hls.Events.FRAG_LOADED, function() {
            setStatus('LIVE', 'live');
        });

    } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
        video.src = url;
        video.addEventListener('loadedmetadata', function() {
            setStatus('LIVE', 'live');
            video.play().catch(function() {});
        });
    } else {
        setStatus('HLS not supported in this browser', 'error');
    }
}

async function initLive() {
    try {
        var resp = await fetch('/inputs.json');
        if (!resp.ok) {
            throw new Error('HTTP ' + resp.status + ' while loading /inputs.json');
        }
        var data = await resp.json();
        streams = data.inputs || [];

        if (!streams.length) {
            setStatus('No streams configured in inputs.json', 'error');
            return;
        }

        streams.forEach(function(s) {
            var btn = document.createElement('button');
            btn.className = 'stream-tab';
            btn.dataset.name = s.name;
            btn.textContent = s.label || s.name;
            btn.addEventListener('click', function() { switchStream(s.name); });
            tabsDiv.appendChild(btn);
        });

        switchStream(streams[0].name);

    } catch (e) {
        setStatus('Failed to load /inputs.json - is Nginx running?', 'error');
        console.error(e);
    }
}

// === VOD ===
function setVodStatus(text, cls) {
    vodStatus.textContent = text;
    vodStatus.className = 'status-bar ' + cls;
}

vodBack.addEventListener('click', function(e) {
    e.preventDefault();
    vodVideo.pause();
    vodVideo.removeAttribute('src');
    vodVideo.load();
    vodPlayerArea.classList.add('hidden');
    vodLibrary.classList.remove('hidden');
    setVodStatus('', '');
    vodInfo.textContent = '';
});

function playVod(videoId) {
    var entry = vodCatalog.find(function(v) { return v.id === videoId; });
    if (!entry) return;

    vodLibrary.classList.add('hidden');
    vodPlayerArea.classList.remove('hidden');
    vodInfo.textContent = entry.title;

    // Play ad first, then content
    setVodStatus('Playing ad...', 'ad');
    vodVideo.src = adVideoUrl;
    vodVideo.play().catch(function() {});

    vodVideo.onended = function() {
        // Check if we just finished the ad
        if (vodVideo.src.indexOf('ad/') !== -1) {
            setVodStatus('Playing', 'vod');
            vodVideo.src = entry.url;
            vodVideo.play().catch(function() {});
            vodVideo.onended = function() {
                setVodStatus('Finished', 'vod');
            };
        }
    };
}

async function initVod() {
    try {
        var resp = await fetch('/videos/catalog.json');
        if (!resp.ok) return;
        var data = await resp.json();
        vodCatalog = data.videos || [];
        adVideoUrl = data.ad || null;

        if (!vodCatalog.length || !adVideoUrl) {
            vodEmpty.classList.remove('hidden');
            return;
        }

        vodCatalog.forEach(function(v) {
            var card = document.createElement('article');
            card.className = 'vod-card';
            card.innerHTML =
                '<div class="vod-thumb">&#127916;</div>' +
                '<footer>' +
                '<strong>' + v.title + '</strong><br>' +
                '<small>' + (v.duration || '') + '</small>' +
                '</footer>';
            card.addEventListener('click', function() { playVod(v.id); });
            vodGrid.appendChild(card);
        });

    } catch (e) {
        vodEmpty.classList.remove('hidden');
    }
}

// === Init ===
initLive();
initVod();
