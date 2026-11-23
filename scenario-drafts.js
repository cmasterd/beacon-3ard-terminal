(function () {
    'use strict';
    const status = document.getElementById('draft-status');
    const select = document.getElementById('draft-select');
    const file = document.getElementById('draft-file');
    const save = document.getElementById('draft-save');
    const retry = document.getElementById('draft-retry');
    const discard = document.getElementById('draft-discard');
    const refresh = document.getElementById('draft-refresh');
    const download = document.getElementById('draft-download');
    let drafts = [];
    let pending = null;
    let busy = false;

    function controls() {
        save.disabled = busy || !!pending;
        select.disabled = busy || !!pending;
        file.disabled = busy || !!pending;
        refresh.disabled = busy || !!pending;
        download.disabled = busy || !!pending || !select.value;
        retry.hidden = !pending;
        discard.hidden = !pending;
        retry.disabled = busy;
        discard.disabled = busy;
    }

    async function list() {
        const client = await BEACON_ONLINE.getClient();
        const session = await client.auth.getSession();
        if (session.error) throw session.error;
        if (!session.data.session) throw new Error('Sign in with your Warden account first');
        const result = await BEACON_ONLINE.rpc('game_list_my_drafts', {});
        if (!Array.isArray(result)) throw new Error('Invalid draft list returned by server');
        drafts = result;
        const selected = select.value;
        select.replaceChildren(new Option('NEW DRAFT', ''));
        for (const draft of drafts) select.add(new Option(`${draft.title} — version ${draft.version}`, draft.id));
        if (drafts.some(draft => draft.id === selected)) select.value = selected;
    }

    async function reload() {
        busy = true;
        controls();
        try {
            await list();
            status.textContent = 'Private drafts loaded.';
        } catch (error) {
            status.textContent = 'Could not load drafts: ' + error.message;
        } finally {
            busy = false;
            controls();
        }
    }

    async function send() {
        if (!pending || busy) return;
        busy = true;
        controls();
        status.textContent = 'Saving private draft...';
        try {
            const result = await BEACON_ONLINE.rpc('game_save_draft', pending);
            if (!result || result.game_id !== pending.p_game_id || result.version_id !== pending.p_version_id
                || result.version !== pending.p_expected_version + 1) throw new Error('Invalid save confirmation');
            const savedId = pending.p_game_id;
            pending = null;
            file.value = '';
            try {
                await list();
                select.value = savedId;
                status.textContent = `Private draft saved as version ${result.version}. It is not published.`;
            } catch (error) {
                status.textContent = `Version ${result.version} saved, but the draft list could not be refreshed: ${error.message}`;
            }
        } catch (error) {
            status.textContent = 'Save not confirmed: ' + error.message + '. Retry the same save, or check the draft list before discarding.';
        } finally {
            busy = false;
            controls();
        }
    }

    save.addEventListener('click', async () => {
        if (busy || pending) return;
        if (!file.files.length) { status.textContent = 'Choose a game package first.'; return; }
        busy = true;
        controls();
        try {
            const text = await file.files[0].text();
            if (new TextEncoder().encode(text).length > 1048576) throw new Error('Package exceeds 1 MiB');
            const data = JSON.parse(text);
            if (!data || !data.catalog || !data.definition || data.definition.format !== 'vad-scenario'
                || data.definition.version !== 1) throw new Error('Choose a version 1 scenario game package');
            const draft = drafts.find(entry => entry.id === select.value);
            if (select.value && !draft) throw new Error('Selected draft is no longer available; refresh');
            pending = {
                p_game_id: draft ? draft.id : crypto.randomUUID(),
                p_version_id: crypto.randomUUID(),
                p_expected_version: draft ? draft.version : 0,
                p_package: data
            };
        } catch (error) {
            status.textContent = 'Could not prepare package: ' + error.message;
        } finally {
            busy = false;
            controls();
        }
        if (pending) await send();
    });
    retry.addEventListener('click', send);
    discard.addEventListener('click', () => {
        if (!pending || busy || !confirm('The save may have succeeded. Discard its retry and refresh the draft list?')) return;
        pending = null;
        reload();
    });
    refresh.addEventListener('click', reload);
    select.addEventListener('change', controls);
    download.addEventListener('click', async () => {
        if (!select.value || busy || pending) return;
        busy = true;
        controls();
        try {
            const result = await BEACON_ONLINE.rpc('game_read_draft', { p_game_id: select.value });
            if (!result || !result.package) throw new Error('Invalid draft returned by server');
            const blob = new Blob([JSON.stringify(result.package, null, 2)], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = `private_scenario_v${result.version}.json`;
            document.body.append(a);
            a.click();
            a.remove();
            URL.revokeObjectURL(url);
            status.textContent = 'Private package downloaded. Keep it away from players.';
        } catch (error) {
            status.textContent = 'Could not download draft: ' + error.message;
        } finally {
            busy = false;
            controls();
        }
    });
    window.addEventListener('beforeunload', event => {
        if (!pending) return;
        event.preventDefault();
        event.returnValue = '';
    });
    reload();
})();
