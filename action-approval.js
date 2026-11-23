(function () {
    'use strict';
    const KEY = 'vad_action_requests_v1';
    const STATE_KEY = 'vad_shared_station_state_v14';
    const LOCK = 'beacon-local-actions-v1';
    const fields = { explore: 'explored', search: 'searched', log: 'logUnlocked' };
    const labels = { explore: 'Explore', search: 'Search', log: 'Access logs' };
    function readRequests() {
        const raw = localStorage.getItem(KEY);
        const requests = raw === null ? [] : JSON.parse(raw);
        if (!Array.isArray(requests)) throw new Error('Invalid local request list');
        return requests;
    }
    function validate(state, room, action) {
        const field = fields[action];
        const st = state && state[room];
        if (!field || !st || !st.unlocked || (room === '7b' && !st.enginePowered && !st.wardenAllow7bVis)
            || (action !== 'explore' && !st.explored) || st[field]) throw new Error('Action is unavailable or already completed');
    }
    function withLock(fn) {
        if (!navigator.locks) throw new Error('Local approval requires browser Web Locks support and a secure origin (localhost or HTTPS)');
        return navigator.locks.request(LOCK, fn);
    }
    async function submit(request) {
        if (GAME_STORAGE.online) return GAME_STORAGE.requestAction(request.room, request.action, request.id, request.epoch, request.group);
        return withLock(() => {
            if (request.epoch !== localStorage.getItem(STATION.RESET_KEY)) throw new Error('Station was reset; discard this request');
            const requests = readRequests();
            if (requests.some(r => r.id === request.id)) return;
            validate(JSON.parse(localStorage.getItem(STATE_KEY)), request.room, request.action);
            if (requests.some(r => r.status === 'pending' && r.room === request.room && r.action === request.action)) throw new Error('An equivalent request is already pending');
            const retained = requests.length >= 300 ? requests.filter(r => r.status === 'pending') : requests;
            if (retained.length >= 300) throw new Error('Request queue is full');
            retained.push({ ...request, status: 'pending', time: Date.now() });
            localStorage.setItem(KEY, JSON.stringify(retained));
        });
    }
    async function decide(id, approve) {
        if (GAME_STORAGE.online) return GAME_STORAGE.decideAction(id, approve);
        return withLock(() => {
            const requests = readRequests();
            const request = requests.find(r => r.id === id);
            if (!request) throw new Error('Request not found');
            const decision = approve ? 'approved' : 'rejected';
            if (request.status !== 'pending') {
                if (request.status === decision) return;
                throw new Error('Request already decided');
            }
            if (approve) {
                const oldState = localStorage.getItem(STATE_KEY);
                const oldLog = localStorage.getItem(STATION.LOG_KEY);
                const state = JSON.parse(oldState);
                validate(state, request.room, request.action);
                state[request.room][fields[request.action]] = true;
                try {
                    localStorage.setItem(STATE_KEY, JSON.stringify(state));
                    STATION.logEvent('PLAYER', `${{ explore: 'Explored sector', search: 'Searched sector', log: 'Accessed data log: sector' }[request.action]} ${request.room}`);
                    request.status = decision;
                    localStorage.setItem(KEY, JSON.stringify(requests));
                } catch (error) {
                    try {
                        if (oldState === null) localStorage.removeItem(STATE_KEY);
                        else localStorage.setItem(STATE_KEY, oldState);
                        if (oldLog === null) localStorage.removeItem(STATION.LOG_KEY);
                        else localStorage.setItem(STATION.LOG_KEY, oldLog);
                    } catch (rollbackError) {
                        throw new Error('Approval failed and recovery failed; check station state and log: ' + error.message + '; ' + rollbackError.message);
                    }
                    throw new Error('Approval failed; changes rolled back: ' + error.message);
                }
                return;
            }
            request.status = decision;
            localStorage.setItem(KEY, JSON.stringify(requests));
        });
    }
    function list() {
        if (GAME_STORAGE.online) {
            if (!GAME_STORAGE.info || !Array.isArray(GAME_STORAGE.info.action_requests)) throw new Error('Update the Supabase schema to enable action approvals');
            return GAME_STORAGE.info.action_requests;
        }
        return readRequests();
    }
    window.ACTION_APPROVAL = { KEY, labels, list, submit, decide, withLock };
})();
