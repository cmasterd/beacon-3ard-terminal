(function () {
    'use strict';
    window.setupActionApprovals = function () {
        const panel = document.createElement('section');
        panel.className = 'my-4 p-4 bg-black border border-amber-700 rounded space-y-3';
        const title = document.createElement('h2');
        title.className = 'font-orbitron text-amber-300 font-bold';
        title.textContent = 'PLAYER ACTION REQUESTS';
        const text = document.createElement('p');
        text.className = 'text-sm text-gray-400';
        text.textContent = 'Approve or reject exploration, searches and log access. Approving immediately applies the action.';
        const status = document.createElement('p');
        status.className = 'text-sm text-amber-300';
        status.setAttribute('role', 'status');
        const list = document.createElement('div');
        list.className = 'space-y-2';
        panel.append(title, text, status, list);
        document.querySelector('main').before(panel);
        let signature = '';
        let busy = false;
        function render() {
            if (busy) return;
            try {
                const requests = ACTION_APPROVAL.list().filter(r => r.status === 'pending');
                const next = JSON.stringify(requests);
                if (next === signature) return;
                signature = next;
                list.replaceChildren();
                if (!requests.length) { list.textContent = 'No pending requests.'; return; }
                for (const request of requests) {
                    const row = document.createElement('div');
                    row.className = 'flex flex-wrap gap-2 items-center p-2 border border-amber-900';
                    const label = document.createElement('span');
                    label.textContent = `${request.group ? `GROUP ${request.group}` : 'PLAYER'} — ${ACTION_APPROVAL.labels[request.action]} — SECTOR ${request.room.toUpperCase()}`;
                    row.append(label);
                    for (const approve of [true, false]) {
                        const button = document.createElement('button');
                        button.type = 'button';
                        button.className = 'px-3 py-2 border border-amber-600 text-amber-200';
                        button.textContent = approve ? 'APPROVE' : 'REJECT';
                        button.addEventListener('click', async () => {
                            busy = true;
                            row.querySelectorAll('button').forEach(b => { b.disabled = true; });
                            try {
                                await ACTION_APPROVAL.decide(request.id, approve);
                                status.textContent = approve ? 'Action approved and applied.' : 'Request rejected.';
                            } catch (error) {
                                status.textContent = 'Could not decide request: ' + error.message + '. If the action is no longer available, reject the request.';
                            } finally {
                                busy = false;
                                signature = '';
                                render();
                            }
                        });
                        row.append(button);
                    }
                    list.append(row);
                }
            } catch (error) {
                signature = '';
                status.textContent = 'Requests unavailable: ' + error.message;
                list.replaceChildren();
            }
        }
        window.addEventListener('beacon-sync', render);
        window.addEventListener('storage', render);
        setInterval(render, 1000);
        render();
    };
})();
