'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

function setup() {
    const values = new Map();
    const localStorage = {
        getItem(key) { return values.has(key) ? values.get(key) : null; },
        setItem(key, value) { values.set(key, String(value)); },
        removeItem(key) { values.delete(key); }
    };
    const station = {
        RESET_KEY: 'reset',
        LOG_KEY: 'log',
        logEvent(source, message) {
            const log = JSON.parse(localStorage.getItem('log') || '[]');
            log.push({ source, message });
            localStorage.setItem('log', JSON.stringify(log));
        }
    };
    localStorage.setItem('vad_shared_station_state_v14', JSON.stringify({
        '2': { unlocked: true, explored: false, searched: false, logUnlocked: false },
        '7b': { unlocked: true, explored: false, enginePowered: false, wardenAllow7bVis: false }
    }));
    const context = {
        window: {}, localStorage, STATION: station, GAME_STORAGE: { online: false },
        navigator: { locks: { request(name, callback) { return Promise.resolve().then(callback); } } }
    };
    vm.runInNewContext(fs.readFileSync(path.join(__dirname, '..', 'action-approval.js'), 'utf8'), context);
    return { approval: context.window.ACTION_APPROVAL, localStorage };
}

test('local requests require approval and reject duplicates', async () => {
    const { approval, localStorage } = setup();
    const request = { id: 'one', room: '2', action: 'explore', epoch: null };
    await approval.submit(request);
    await approval.submit(request);
    await assert.rejects(approval.submit({ ...request, id: 'two' }), /already pending/);
    assert.equal(JSON.parse(localStorage.getItem('vad_shared_station_state_v14'))['2'].explored, false);
    await approval.decide('one', true);
    await approval.decide('one', true);
    assert.equal(JSON.parse(localStorage.getItem('vad_shared_station_state_v14'))['2'].explored, true);
    assert.equal(JSON.parse(localStorage.getItem('log')).length, 1);
    await assert.rejects(approval.decide('one', false), /already decided/);
});

test('failed local approval restores state and log and can be retried', async () => {
    const { approval, localStorage } = setup();
    await approval.submit({ id: 'one', room: '2', action: 'explore', epoch: null });
    const setItem = localStorage.setItem;
    let injected = false;
    localStorage.setItem = function (key, value) {
        if (key === approval.KEY && !injected) {
            injected = true;
            throw new Error('injected failure');
        }
        return setItem.call(this, key, value);
    };
    await assert.rejects(approval.decide('one', true), /changes rolled back/);
    assert.equal(JSON.parse(localStorage.getItem('vad_shared_station_state_v14'))['2'].explored, false);
    assert.equal(localStorage.getItem('log'), null);
    assert.equal(approval.list()[0].status, 'pending');
    await approval.decide('one', true);
    assert.equal(approval.list()[0].status, 'approved');
});

test('rejects invalid prerequisites and stale requests', async () => {
    const { approval, localStorage } = setup();
    await assert.rejects(approval.submit({ id: 'one', room: '2', action: 'search', epoch: null }), /unavailable/);
    await assert.rejects(approval.submit({ id: 'two', room: '7b', action: 'explore', epoch: null }), /unavailable/);
    localStorage.setItem('reset', 'new');
    await assert.rejects(approval.submit({ id: 'three', room: '2', action: 'explore', epoch: null }), /reset/);
});
