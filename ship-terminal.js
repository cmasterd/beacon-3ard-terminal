(function () {
    'use strict';
    const message = document.getElementById('connection-message');
    const content = document.getElementById('ship-content');
    const group = document.getElementById('request-group');
    const item = document.getElementById('request-item');
    const quantity = document.getElementById('request-quantity');
    const status = document.getElementById('request-message');
    const submit = document.getElementById('request-submit');
    const discard = document.getElementById('request-discard');
    let pending = null;
    let sending = false;
    for (const [id, label] of Object.entries(SHIP_REQUEST_ITEMS)) item.add(new Option(label, id));

    function render() {
        const info = GAME_STORAGE.info;
        if (!info) return;
        if (!Array.isArray(info.ship_requests) || !Object.prototype.hasOwnProperty.call(info, 'ship')) {
            message.textContent = 'The Warden must update the Supabase schema before the online ship terminal is available.';
            content.hidden = true;
            return;
        }
        content.hidden = false;
        group.replaceChildren();
        for (let n = 1; n <= 4; n++) if (info.groups[n]) group.add(new Option(`GROUP ${n}`, String(n), false, n === GAME_STORAGE.group));
        const details = document.getElementById('ship-details');
        details.replaceChildren();
        if (!info.ship) {
            details.textContent = 'The Warden has not published a ship yet.';
        } else {
            try {
                BUILDER_VALIDATION.ship(info.ship);
                const ship = info.ship;
                const title = document.createElement('h3');
                title.textContent = `${ship.name} // ${ship.shipClass} // ${ship.transponder}`;
                const stats = document.createElement('p');
                stats.textContent = `HULL ${ship.hullCurrent}/${ship.hullMax} | ARMOR ${ship.armor} | THRUST ${ship.thrusters} | JUMP ${ship.jumpRating} | FUEL ${ship.fuelCurrent}/${ship.fuelMax} | CREW ${ship.crewCurrent}/${ship.crewMax} | CREDITS ${ship.credits} | DEBT ${ship.totalDebt} | ${ship.redAlert ? 'RED ALERT' : 'NORMAL STATUS'}`;
                details.append(title, stats);
                for (const [heading, entries] of [
                    ['DECK', ship.rooms.map(room => `${room.name} (${room.status}) — ${room.notes}`)],
                    ['WEAPONS', ship.weapons.map(weapon => `${weapon.name} — ${weapon.damage}, ${weapon.range} (${weapon.status})`)],
                    ['CARGO', ship.cargo],
                    ['SHIP LOGS', ship.logs.map(log => `${log.title} (${log.date}): ${log.body}`)]
                ]) {
                    const h = document.createElement('h4');
                    h.textContent = heading;
                    const ul = document.createElement('ul');
                    if (!entries.length) {
                        const li = document.createElement('li');
                        li.textContent = 'None';
                        ul.append(li);
                    }
                    for (const entry of entries) {
                        const li = document.createElement('li');
                        li.textContent = entry;
                        ul.append(li);
                    }
                    details.append(h, ul);
                }
            } catch (error) {
                details.textContent = 'Cannot display the published ship: ' + error.message;
            }
        }
        submit.disabled = sending || (!info.ship && !pending);
        const history = document.getElementById('request-history');
        history.replaceChildren();
        if (!info.ship_requests.length) history.textContent = 'No requests yet.';
        for (const request of info.ship_requests) {
            const p = document.createElement('p');
            p.textContent = `GROUP ${request.group} — ${SHIP_REQUEST_ITEMS[request.item] || request.item} × ${request.quantity} — ${request.status.toUpperCase()} — ${new Date(request.created_at).toLocaleString()}`;
            history.append(p);
        }
    }

    group.addEventListener('change', () => {
        GAME_STORAGE.selectGroup(Number(group.value));
        render();
    });
    document.getElementById('request-form').addEventListener('submit', async event => {
        event.preventDefault();
        if (!pending) pending = { id: crypto.randomUUID(), item: item.value, quantity: Number(quantity.value),
            group: GAME_STORAGE.group, epoch: GAME_STORAGE.info.reset_epoch };
        sending = true;
        group.disabled = item.disabled = quantity.disabled = submit.disabled = true;
        discard.disabled = true;
        status.textContent = 'Sending request...';
        try {
            await GAME_STORAGE.requestShipItem(pending.item, pending.quantity, pending.id, pending.group, pending.epoch);
            pending = null;
            status.textContent = 'Request sent to the Warden.';
        } catch (error) {
            status.textContent = 'Could not confirm the request: ' + error.message + '. Retry with the same request; keep this tab open.';
        } finally {
            sending = false;
            group.disabled = item.disabled = quantity.disabled = !!pending;
            discard.disabled = false;
            discard.hidden = !pending;
            submit.disabled = !pending && !GAME_STORAGE.info.ship;
            submit.textContent = pending ? 'RETRY REQUEST' : 'SEND REQUEST';
        }
    });
    discard.addEventListener('click', () => {
        if (!confirm('The Warden may already have received this request. Discard the retry and check request history before sending a new one?')) return;
        pending = null;
        group.disabled = item.disabled = quantity.disabled = false;
        discard.hidden = true;
        submit.textContent = 'SEND REQUEST';
        status.textContent = 'Retry discarded. Check the request history before submitting again.';
        render();
    });
    window.addEventListener('beforeunload', event => {
        if (!pending) return;
        event.preventDefault();
        event.returnValue = '';
    });
    window.onload = async () => {
        try {
            await BEACON_ONLINE.start();
            if (!GAME_STORAGE.online || GAME_STORAGE.role !== 'player') {
                message.textContent = 'Join a Beacon online player session from the Beacon gateway first. The local Shipyard terminal remains available under Builders.';
                return;
            }
            message.textContent = 'Connected to the shared player session. Ship changes are published by the Warden.';
            content.hidden = false;
            window.addEventListener('beacon-sync', render);
            render();
        } catch (error) { BEACON_ONLINE.showStartupError(error); }
    };
})();
