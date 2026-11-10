(function () {
    'use strict';

    const PROJECT_URL = 'https://erzvykheeffibzadmset.supabase.co';
    const PUBLIC_KEY = 'sb_publishable_tJAMHG90WUI2SNMYDXIFqQ_YeiQtXe9';
    const CONFIG_KEY = 'beacon_online_tab_v1';
    const ROOM_KEY = 'vad_shared_station_state_v14';
    const STATUS_KEY = 'vad_ship_status_v1';
    const LOG_KEY = 'vad_session_log_v1';
    const NOTES_KEY = 'vad_warden_notes_v1';
    const FOCUS_KEY = 'vad_player_focus_v1';
    const PUBLIC_KEYS = [ROOM_KEY, STATUS_KEY, 'vad_hazards_v1', 'vad_audio_archive_v1',
        'vad_video_archive_v1', 'vad_text_archive_v1', 'vad_broadcast_v1', 'vad_countdown_v1'];
    const PRIVATE_KEYS = [LOG_KEY, NOTES_KEY];
    let config = null;
    let client;
    let snapshot = {};
    let info = null;
    let lastEpoch = null;
    let pending = [];
    let writeRevision = 0;
    let flushing = false;
    let pollRunning = false;
    let banner;
    let targetSection = null;
    let configError = null;

    function validConfig(value) {
        return value && typeof value.code === 'string' && /^[a-f0-9]{64}$/.test(value.code) &&
            (value.role === 'warden' || (value.role === 'player' && Number.isInteger(value.group) &&
                value.group >= 1 && value.group <= 4));
    }

    const hash = new URLSearchParams(location.hash.slice(1));
    if (hash.has('beacon_session')) {
        const code = hash.get('beacon_session');
        const role = hash.get('role');
        const group = Number(hash.get('group') || 1);
        const proposed = { code, role, group: role === 'player' ? group : null };
        if (!validConfig(proposed)) {
            configError = new Error('Invalid online session link');
        } else {
            config = proposed;
            targetSection = hash.get('section');
            sessionStorage.setItem(CONFIG_KEY, JSON.stringify(config));
            history.replaceState(null, '', location.pathname + location.search);
        }
    } else {
        const saved = sessionStorage.getItem(CONFIG_KEY);
        if (saved) {
            try {
                config = JSON.parse(saved);
                if (!validConfig(config)) throw new Error('Malformed session');
            } catch (error) { config = null; configError = new Error('Invalid saved online session: ' + error.message); }
        }
    }

    function sdk() {
        if (window.supabase) return Promise.resolve(window.supabase);
        return new Promise((resolve, reject) => {
            const script = document.createElement('script');
            script.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js';
            script.onload = () => window.supabase ? resolve(window.supabase) : reject(new Error('Supabase library did not load'));
            script.onerror = () => reject(new Error('Could not load the Supabase library. Check your internet connection.'));
            document.head.append(script);
        });
    }

    async function getClient() {
        if (!client) client = (await sdk()).createClient(PROJECT_URL, PUBLIC_KEY);
        return client;
    }

    async function rpc(name, args) {
        const result = await (await getClient()).rpc(name, args);
        if (result.error) throw new Error(result.error.message);
        return result.data;
    }

    function params() { return { p_code: config.code, p_group: config.group }; }
    function localKey(key) {
        if (!config || key === 'vad_sound_v1') return key;
        return 'beacon_local_' + config.code + '_' + (config.role === 'player' ? 'player' : 'warden') + '_' + key;
    }
    function isRemote(key) {
        return config && (PUBLIC_KEYS.includes(key) || (config.role === 'warden' && PRIVATE_KEYS.includes(key)));
    }
    function serialized(value) { return value === undefined ? null : typeof value === 'string' ? value : JSON.stringify(value); }

    function setBanner(message, error) {
        if (!banner) return;
        banner.textContent = message;
        banner.style.background = error ? '#7f1d1d' : '#083344';
    }

    function enqueue(name, args, includeEpoch = true) {
        writeRevision++;
        pending.push({ name, args: includeEpoch ? { ...args, p_epoch: info.reset_epoch } : args });
        setBanner('ONLINE: SAVING CHANGES...', false);
        flush();
    }

    async function flush() {
        if (flushing || !pending.length) return;
        flushing = true;
        try {
            while (pending.length) {
                await rpc(pending[0].name, pending[0].args);
                pending.shift();
            }
            await refresh();
        } catch (error) {
            if (pending.length) {
                setBanner('ONLINE SYNC FAILED: ' + error.message + ' — changes are pending in this tab; do not close it. Retrying...', true);
                const discard = document.createElement('button');
                discard.type = 'button';
                discard.style.cssText = 'margin-left:1rem;text-decoration:underline';
                discard.textContent = 'DISCARD PENDING CHANGES AND RELOAD';
                discard.onclick = () => {
                    if (!confirm('Discard all unsent changes in this tab and reload the latest session?')) return;
                    pending = [];
                    location.reload();
                };
                banner.append(discard);
                setTimeout(flush, 5000);
            } else setBanner('ONLINE CONNECTION LOST: ' + error.message + ' — retrying', true);
            console.error('Online sync failed:', error);
        } finally {
            flushing = false;
        }
    }

    function roomChanges(previous, next) {
        const changes = {};
        Object.keys(next).forEach(room => {
            const fields = {};
            Object.keys(next[room]).forEach(field => {
                if (!previous[room] || previous[room][field] !== next[room][field]) fields[field] = next[room][field];
            });
            if (Object.keys(fields).length) changes[room] = fields;
        });
        return changes;
    }

    const storage = {
        get online() { return !!config || !!configError; },
        get role() { return config && config.role; },
        get group() { return config && config.group; },
        get info() { return info; },
        getItem(key) {
            if (isRemote(key)) return serialized(snapshot[key]);
            return localStorage.getItem(localKey(key));
        },
        setItem(key, value, baseValue) {
            value = String(value);
            if (!isRemote(key)) {
                if (config && key === FOCUS_KEY && config.role === 'player') {
                    const room = String(JSON.parse(value).room);
                    info.presence[config.group] = { room, time: Date.now() };
                    enqueue('beacon_focus', { ...params(), p_room: room }, false);
                } else {
                    localStorage.setItem(localKey(key), value);
                }
                return;
            }
            if (key === LOG_KEY) throw new Error('Use logEvent to append online log entries');
            const previous = key === STATUS_KEY
                ? (snapshot[key] || { oxygen: 100, power: 0, hull: 100, comms: 0 })
                : snapshot[key];
            const next = key === NOTES_KEY ? value : JSON.parse(value);
            let change = next;
            if (key === ROOM_KEY) {
                const base = baseValue ? JSON.parse(baseValue) : previous || {};
                change = roomChanges(base, next);
                snapshot[key] = { ...previous };
                Object.keys(change).forEach(room => {
                    snapshot[key][room] = { ...snapshot[key][room], ...change[room] };
                });
            } else if (key === STATUS_KEY) {
                change = {};
                Object.keys(next).forEach(field => {
                    if (!previous || previous[field] !== next[field]) change[field] = next[field];
                });
                snapshot[key] = { ...previous, ...change };
            } else snapshot[key] = next;
            if ((key === ROOM_KEY || key === STATUS_KEY) && !Object.keys(change).length) return;
            enqueue('beacon_update', { ...params(), p_key: key, p_value: change });
        },
        removeItem(key) {
            if (!isRemote(key)) { localStorage.removeItem(localKey(key)); return; }
            delete snapshot[key];
            if (key === LOG_KEY) enqueue('beacon_clear_log', { p_code: config.code });
            else enqueue('beacon_update', { ...params(), p_key: key, p_value: null });
        },
        keys() {
            if (!config) return Object.keys(localStorage);
            const localPrefix = 'beacon_local_' + config.code + '_' + (config.role === 'player' ? 'player' : 'warden') + '_';
            return [...new Set([...Object.keys(snapshot), ...Object.keys(localStorage)
                .filter(key => key.startsWith(localPrefix)).map(key => key.slice(localPrefix.length))])];
        },
        logEvent(source, text) {
            if (!config) return false;
            enqueue('beacon_log', { ...params(), p_source: source, p_message: String(text), p_event_id: crypto.randomUUID() });
            return true;
        },
        link(page, role, group) {
            const url = new URL(page, location.href);
            const section = url.hash.slice(1);
            const options = { beacon_session: config.code, role };
            if (group) options.group = String(group);
            if (section) options.section = section;
            url.hash = new URLSearchParams(options).toString();
            return url.href;
        },
        async setGroup(group, enabled) {
            await rpc('beacon_set_group', { p_code: config.code, p_group: group, p_enabled: enabled });
            await refresh();
        },
        selectGroup(group) {
            if (!config || config.role !== 'player' || !info || !info.groups[group]) {
                throw new Error('That group is not enabled by the Warden');
            }
            config.group = group;
            sessionStorage.setItem(CONFIG_KEY, JSON.stringify(config));
            updateArchiveLinks();
            setBanner('ONLINE: CONNECTED — GROUP ' + group, false);
        },
        async waitForSync() {
            while (pending.length || flushing) {
                await new Promise(resolve => setTimeout(resolve, 100));
            }
        },
        async syncNow() {
            for (;;) {
                await this.waitForSync();
                while (pollRunning) await new Promise(resolve => setTimeout(resolve, 100));
                const revision = writeRevision;
                await refresh();
                if (!pending.length && revision === writeRevision) return;
            }
        },
        async restore(entries) {
            if (!config || config.role !== 'warden') throw new Error('Warden access required');
            await this.waitForSync();
            const data = {};
            for (const [key, value] of entries) {
                if (!PUBLIC_KEYS.includes(key) && !PRIVATE_KEYS.includes(key)) continue;
                try { data[key] = key === NOTES_KEY ? value : JSON.parse(value); }
                catch (error) { throw new Error('Invalid backup entry ' + key + ': ' + error.message); }
            }
            await rpc('beacon_restore', { p_code: config.code, p_data: data });
            for (const [key, value] of entries) {
                if (!PUBLIC_KEYS.includes(key) && !PRIVATE_KEYS.includes(key) && key !== FOCUS_KEY) {
                    localStorage.setItem(localKey(key), value);
                }
            }
        },
        async reset() {
            if (!config || config.role !== 'warden') throw new Error('Warden access required');
            await this.waitForSync();
            await rpc('beacon_reset', { p_code: config.code });
        }
    };

    async function refresh() {
        if (pollRunning || pending.length) return;
        pollRunning = true;
        const revision = writeRevision;
        try {
            const result = await rpc('beacon_read_session', params());
            if (pending.length || revision !== writeRevision) return;
            const epochKey = localKey('reset_epoch');
            const oldEpoch = localStorage.getItem(epochKey);
            if (oldEpoch !== null && oldEpoch !== String(result.reset_epoch)) {
                ['vad_audio_notified_v1', 'vad_video_notified_v1', 'vad_text_notified_v1',
                    'vad_broadcast_seen_v1', 'vad_text_revealed_v1'].forEach(key => localStorage.removeItem(localKey(key)));
            }
            if (lastEpoch !== null && lastEpoch !== result.reset_epoch) window.dispatchEvent(new Event('beacon-reset'));
            lastEpoch = result.reset_epoch;
            localStorage.setItem(epochKey, String(result.reset_epoch));
            info = result;
            info.receivedAt = Date.now();
            snapshot = { ...result.shared, ...result.private };
            if (config.role === 'player' && !info.groups[config.group]) {
                config.group = 1;
                sessionStorage.setItem(CONFIG_KEY, JSON.stringify(config));
                updateArchiveLinks();
                window.dispatchEvent(new Event('beacon-group-disabled'));
            }
            setBanner('ONLINE: CONNECTED' + (config.group ? ' — GROUP ' + config.group : ''), false);
            window.dispatchEvent(new Event('beacon-sync'));
        } finally {
            pollRunning = false;
        }
    }

    function updateArchiveLinks() {
        document.querySelectorAll('a[data-beacon-archive]').forEach(link => {
            link.href = storage.link(link.dataset.beaconArchive, 'player', config.group || 1);
        });
    }

    async function start() {
        if (configError) throw configError;
        if (!config) return;
        banner = document.createElement('div');
        banner.setAttribute('role', 'status');
        banner.style.cssText = 'position:fixed;bottom:0;left:0;right:0;z-index:300;padding:6px;color:white;font:14px monospace;text-align:center';
        document.body.append(banner);
        if (config.role === 'player') {
            const exit = document.createElement('button');
            exit.type = 'button';
            exit.textContent = 'LEAVE ONLINE';
            exit.style.cssText = 'position:fixed;bottom:2rem;right:1rem;z-index:301;padding:6px;background:#083344;color:white;border:1px solid #22d3ee';
            exit.addEventListener('click', () => {
                if (pending.length && !confirm('Discard all unsent changes and leave the online session?')) return;
                pending = [];
                sessionStorage.removeItem(CONFIG_KEY);
                location.href = 'index.html';
            });
            document.body.append(exit);
        }
        window.addEventListener('beforeunload', event => {
            if (!pending.length) return;
            event.preventDefault();
            event.returnValue = '';
        });
        setBanner('ONLINE: CONNECTING...', false);
        if (config.role === 'warden') {
            const opened = await rpc('beacon_open_warden', {});
            if (opened.code !== config.code) throw new Error('This Warden session does not belong to the signed-in user');
        }
        await refresh();
        document.querySelectorAll('a[href^="archive.html"]').forEach(link => {
            link.dataset.beaconArchive = link.getAttribute('href');
        });
        updateArchiveLinks();
        if (targetSection) {
            const target = document.getElementById(targetSection);
            if (target) target.scrollIntoView();
        }
        setInterval(async () => {
            try { await refresh(); }
            catch (error) {
                setBanner('ONLINE CONNECTION LOST: ' + error.message + ' — retrying', true);
                console.error('Online refresh failed:', error);
            }
        }, 2000);
    }

    function showStartupError(error) {
        console.error('Online startup failed:', error);
        const panel = document.createElement('div');
        panel.style.cssText = 'position:fixed;inset:0;z-index:500;background:#100;display:flex;align-items:center;justify-content:center;padding:2rem;color:white;font:16px monospace';
        const content = document.createElement('div');
        const message = document.createElement('p');
        message.textContent = 'ONLINE CONNECTION FAILED: ' + error.message;
        const retry = document.createElement('button');
        retry.textContent = 'RETRY';
        retry.onclick = () => location.reload();
        const exit = document.createElement('button');
        exit.textContent = 'RETURN TO GATEWAY';
        exit.style.marginLeft = '1rem';
        exit.onclick = () => { sessionStorage.removeItem(CONFIG_KEY); location.href = 'index.html'; };
        content.append(message, retry, exit);
        panel.append(content);
        document.body.append(panel);
    }

    window.GAME_STORAGE = storage;
    window.BEACON_ONLINE = {
        start, showStartupError, getClient, rpc, link: storage.link,
        clear: () => sessionStorage.removeItem(CONFIG_KEY),
        async signOut() {
            const result = await (await getClient()).auth.signOut();
            if (result.error) throw new Error(result.error.message);
        }
    };
})();
