(function () {
    'use strict';
    const select = document.getElementById('draft-select');
    const name = document.getElementById('session-name');
    const create = document.getElementById('session-create');
    const retry = document.getElementById('session-retry');
    const discard = document.getElementById('session-discard');
    const refresh = document.getElementById('session-refresh');
    const status = document.getElementById('session-status');
    const list = document.getElementById('session-list');
    let pending = null;
    let busy = false;

    function controls() {
        create.disabled = busy || !!pending || !select.value;
        name.disabled = busy || !!pending;
        refresh.disabled = busy || !!pending;
        retry.hidden = !pending;
        discard.hidden = !pending;
        retry.disabled = busy;
        discard.disabled = busy;
    }

    async function load() {
        const client = await BEACON_ONLINE.getClient();
        const auth = await client.auth.getSession();
        if (auth.error) throw auth.error;
        if (!auth.data.session) throw new Error('Sign in with your Warden account first');
        const sessions = await BEACON_ONLINE.rpc('game_list_my_prepared_sessions', {});
        if (!Array.isArray(sessions)) throw new Error('Invalid session list returned by server');
        list.replaceChildren();
        if (!sessions.length) {
            const row = document.createElement('li');
            row.textContent = 'No prepared sessions.';
            list.append(row);
        }
        for (const session of sessions) {
            const row = document.createElement('li');
            row.textContent = `${session.name} — ${session.game_title} — version ${session.version}`;
            list.append(row);
        }
    }

    async function reload() {
        busy = true;
        controls();
        try {
            await load();
            status.textContent = 'Prepared sessions loaded. They are not playable yet.';
        } catch (error) {
            status.textContent = 'Could not load prepared sessions: ' + error.message;
        } finally {
            busy = false;
            controls();
        }
    }

    async function send() {
        if (busy || !pending) return;
        busy = true;
        controls();
        status.textContent = 'Preparing private session...';
        try {
            const result = await BEACON_ONLINE.rpc('game_prepare_session', pending);
            if (!result || result.session_id !== pending.p_session_id || result.game_id !== pending.p_game_id
                || result.version_id !== pending.p_version_id) throw new Error('Invalid session confirmation');
            pending = null;
            name.value = '';
            try {
                await load();
                status.textContent = 'Private session prepared. It is not playable yet.';
            } catch (error) {
                status.textContent = 'Session prepared, but the list could not be refreshed: ' + error.message;
            }
        } catch (error) {
            status.textContent = 'Preparation not confirmed: ' + error.message + '. Retry, or check the session list after discarding.';
        } finally {
            busy = false;
            controls();
        }
    }

    create.addEventListener('click', async () => {
        if (busy || pending || !select.value) return;
        const sessionName = name.value.trim();
        if (!sessionName || sessionName.length > 120) {
            status.textContent = 'Enter a session name of 1 to 120 characters.';
            return;
        }
        busy = true;
        controls();
        try {
            const option = select.selectedOptions[0];
            if (!option || !option.dataset.versionId) throw new Error('Draft unavailable; refresh the draft list');
            pending = { p_session_id: crypto.randomUUID(), p_game_id: option.value,
                p_version_id: option.dataset.versionId, p_name: sessionName };
        } catch (error) {
            status.textContent = 'Could not prepare session: ' + error.message;
        } finally {
            busy = false;
            controls();
        }
        if (pending) await send();
    });
    retry.addEventListener('click', send);
    discard.addEventListener('click', () => {
        if (!pending || busy || !confirm('The session may have been prepared. Discard its retry and refresh the list?')) return;
        pending = null;
        reload();
    });
    refresh.addEventListener('click', reload);
    select.addEventListener('change', controls);
    window.addEventListener('beforeunload', event => {
        if (!pending) return;
        event.preventDefault();
        event.returnValue = '';
    });
    reload();
})();
