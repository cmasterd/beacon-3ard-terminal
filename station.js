// Shared by the Warden and player pages: ship status gauges and sector hazards.
(function () {
    const HAZARD_KEY = 'vad_hazards_v1';
    const STATUS_KEY = 'vad_ship_status_v1';
    const LOG_KEY = 'vad_session_log_v1';
    const NOTES_KEY = 'vad_warden_notes_v1';
    const FOCUS_KEY = 'vad_player_focus_v1';
    const HAZARDS = ['VACUUM', 'FIRE', 'RADIATION', 'TOXIC GAS', 'XENO CONTACT', 'POWER SURGE'];
    const GAUGES = [
        { id: 'oxygen', label: 'OXYGEN', def: 100 },
        { id: 'power', label: 'POWER', def: 0 },
        { id: 'hull', label: 'HULL', def: 100 },
        { id: 'comms', label: 'COMMS', def: 0 }
    ];

    function readJson(key) {
        try {
            const parsed = JSON.parse(localStorage.getItem(key) || '{}');
            return parsed && typeof parsed === 'object' ? parsed : {};
        } catch (e) {
            return {};
        }
    }

    function readHazards() {
        const raw = readJson(HAZARD_KEY);
        const out = {};
        Object.keys(raw).forEach(room => { if (HAZARDS.includes(raw[room])) out[room] = raw[room]; });
        return out;
    }

    function readStatus() {
        const raw = readJson(STATUS_KEY);
        const out = {};
        GAUGES.forEach(g => {
            const v = raw[g.id] === undefined ? NaN : Number(raw[g.id]);
            out[g.id] = Number.isFinite(v) ? Math.max(0, Math.min(100, Math.round(v))) : g.def;
        });
        return out;
    }

    function writeStatus(status) {
        localStorage.setItem(STATUS_KEY, JSON.stringify(status));
    }

    function setHazard(room, hazard) {
        const hazards = readHazards();
        if (hazard) hazards[room] = hazard; else delete hazards[room];
        localStorage.setItem(HAZARD_KEY, JSON.stringify(hazards));
    }

    // Idempotent: safe to call on every poll. prefix is "node" (player) or "warden-node".
    function applyHazards(prefix) {
        const hazards = readHazards();
        document.querySelectorAll('.room-node').forEach(g => {
            if (!g.id.startsWith(prefix + '-')) return;
            const room = g.id.slice(prefix.length + 1);
            const hazard = hazards[room];
            const existing = g.querySelector('.hazard-tag');
            if (existing && (!hazard || existing.dataset.hazard !== hazard)) existing.remove();
            g.classList.toggle('hazard-node', !!hazard);
            if (!hazard || g.querySelector('.hazard-tag')) return;
            const rect = g.querySelector('rect');
            const tag = document.createElementNS('http://www.w3.org/2000/svg', 'text');
            tag.setAttribute('class', 'hazard-tag');
            tag.dataset.hazard = hazard;
            tag.setAttribute('x', Number(rect.getAttribute('x')) + Number(rect.getAttribute('width')) / 2);
            tag.setAttribute('y', Number(rect.getAttribute('y')) + Number(rect.getAttribute('height')) - 4);
            tag.setAttribute('text-anchor', 'middle');
            tag.setAttribute('font-size', '9');
            tag.setAttribute('font-weight', 'bold');
            tag.setAttribute('fill', '#f87171');
            tag.textContent = '\u26A0 ' + hazard;
            g.append(tag);
        });
    }

    const style = document.createElement('style');
    style.textContent = `
        @keyframes hazard-pulse { 0%, 100% { stroke-opacity: 1; } 50% { stroke-opacity: 0.25; } }
        .room-node.hazard-node rect { stroke: #ef4444 !important; stroke-width: 3; animation: hazard-pulse 1.2s infinite; }
        @media (prefers-reduced-motion: reduce) { .room-node.hazard-node rect { animation: none; } }
    `;
    document.head.append(style);

    function logEvent(source, text) {
        let log = [];
        try { log = JSON.parse(localStorage.getItem(LOG_KEY) || '[]'); } catch (e) { log = []; }
        if (!Array.isArray(log)) log = [];
        log.push({ t: Date.now(), s: source, m: String(text) });
        localStorage.setItem(LOG_KEY, JSON.stringify(log.slice(-300)));
    }

    function readLog() {
        try {
            const log = JSON.parse(localStorage.getItem(LOG_KEY) || '[]');
            return Array.isArray(log) ? log : [];
        } catch (e) {
            return [];
        }
    }

    window.STATION = { HAZARD_KEY, STATUS_KEY, LOG_KEY, NOTES_KEY, FOCUS_KEY, HAZARDS, GAUGES, readHazards, readStatus, writeStatus, setHazard, applyHazards, logEvent, readLog };
})();
