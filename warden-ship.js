(function () {
    'use strict';
    window.setupWardenShip = function () {
        if (!GAME_STORAGE.online || GAME_STORAGE.role !== 'warden') return;
        const panel = document.createElement('section');
        panel.className = 'my-4 p-4 bg-black border border-emerald-800 rounded space-y-3';
        const heading = document.createElement('h2');
        heading.className = 'font-orbitron text-emerald-300 font-bold';
        heading.textContent = 'SHARED SHIP & REQUISITIONS';
        const description = document.createElement('p');
        description.className = 'text-sm text-gray-400';
        description.textContent = 'Publish a Shipyard JSON export or the ship saved in this browser. Players can see all published ship data. Approvals are manual: update the ship in Shipyard and publish it again when ready.';
        const shipStatus = document.createElement('p');
        shipStatus.className = 'text-sm text-emerald-300';
        const feedback = document.createElement('p');
        feedback.setAttribute('role', 'status');
        feedback.className = 'text-sm text-amber-300';
        const controls = document.createElement('div');
        controls.className = 'flex flex-wrap gap-3 items-center';
        const local = document.createElement('button');
        local.type = 'button';
        local.textContent = 'PUBLISH LOCAL SHIPYARD SHIP';
        local.className = 'px-3 py-2 border border-emerald-700 text-emerald-300';
        const label = document.createElement('label');
        label.textContent = 'PUBLISH SHIP JSON ';
        label.className = 'px-3 py-2 border border-emerald-700 text-emerald-300';
        const file = document.createElement('input');
        file.type = 'file';
        file.accept = '.json,application/json';
        file.setAttribute('aria-label', 'Publish Shipyard JSON');
        label.append(file);
        const clear = document.createElement('button');
        clear.type = 'button';
        clear.textContent = 'CLEAR DECIDED REQUESTS';
        clear.className = 'px-3 py-2 border border-rose-700 text-rose-300';
        const list = document.createElement('div');
        list.className = 'space-y-2';
        controls.append(local, label, clear);
        panel.append(heading, description, shipStatus, controls, feedback, list);
        document.querySelector('main').before(panel);

        async function publish(data) {
            BUILDER_VALIDATION.ship(data);
            if (!confirm('Publish this ship to all players in this session? This replaces the previously published ship.')) return;
            await GAME_STORAGE.publishShip(data);
            feedback.textContent = 'Ship published to this session.';
        }
        local.addEventListener('click', async () => {
            local.disabled = true;
            try {
                const raw = localStorage.getItem('mothership_shipyard_os_v1');
                if (!raw) throw new Error('No Shipyard ship is saved in this browser. Export JSON from Shipyard on another device instead.');
                await publish(JSON.parse(raw));
            } catch (error) { feedback.textContent = 'Could not publish ship: ' + error.message; }
            finally { local.disabled = false; }
        });
        file.addEventListener('change', async () => {
            const selected = file.files[0];
            if (!selected) return;
            file.disabled = true;
            try { await publish(JSON.parse(await selected.text())); }
            catch (error) { feedback.textContent = 'Could not publish ship: ' + error.message; }
            finally { file.disabled = false; file.value = ''; }
        });
        clear.addEventListener('click', async () => {
            if (!confirm('Clear all approved and rejected requests? Pending requests will remain.')) return;
            clear.disabled = true;
            try { await GAME_STORAGE.clearDecidedShipRequests(); feedback.textContent = 'Decided requests cleared.'; }
            catch (error) { feedback.textContent = 'Could not clear requests: ' + error.message; }
            finally { clear.disabled = false; }
        });
        function render() {
            const info = GAME_STORAGE.info;
            if (!info) return;
            if (!Array.isArray(info.ship_requests) || !Object.prototype.hasOwnProperty.call(info, 'ship')) {
                shipStatus.textContent = 'Update the Supabase schema to enable the shared ship and requisitions.';
                local.disabled = file.disabled = clear.disabled = true;
                list.replaceChildren();
                return;
            }
            local.disabled = file.disabled = clear.disabled = false;
            shipStatus.textContent = info.ship ? `PUBLISHED SHIP: ${info.ship.name}` : 'NO SHIP PUBLISHED';
            list.replaceChildren();
            if (!info.ship_requests.length) {
                list.textContent = 'No ship requests.';
                return;
            }
            for (const request of info.ship_requests) {
                const row = document.createElement('div');
                row.className = 'p-2 border border-emerald-900 flex flex-wrap gap-2 items-center text-sm';
                const text = document.createElement('span');
                text.textContent = `GROUP ${request.group} — ${SHIP_REQUEST_ITEMS[request.item] || request.item} × ${request.quantity} — ${request.status.toUpperCase()} — ${new Date(request.created_at).toLocaleString()}`;
                row.append(text);
                if (request.status === 'pending') {
                    for (const decision of ['approved', 'rejected']) {
                        const button = document.createElement('button');
                        button.type = 'button';
                        button.className = 'px-2 py-1 border border-emerald-700 text-emerald-300';
                        button.textContent = decision === 'approved' ? 'APPROVE' : 'REJECT';
                        button.addEventListener('click', async () => {
                            row.querySelectorAll('button').forEach(b => { b.disabled = true; });
                            try {
                                await GAME_STORAGE.decideShipRequest(request.id, decision);
                                feedback.textContent = decision === 'approved'
                                    ? 'Approved. Handle the purchase manually; republish the ship after updating it.'
                                    : 'Request rejected.';
                            } catch (error) {
                                feedback.textContent = 'Could not confirm decision: ' + error.message + '. Check the request status before retrying.';
                                row.querySelectorAll('button').forEach(b => { b.disabled = false; });
                            }
                        });
                        row.append(button);
                    }
                }
                list.append(row);
            }
        }
        window.addEventListener('beacon-sync', render);
        render();
    };
})();
