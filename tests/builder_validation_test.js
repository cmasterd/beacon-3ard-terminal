const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const listeners = {};
const status = { hidden: true, textContent: '' };
const values = new Map();
let allowReplacement = false;
const context = {
    window: { addEventListener: (event, listener) => { listeners[event] = listener; } },
    document: { getElementById: () => status },
    localStorage: {
        getItem: key => values.has(key) ? values.get(key) : null,
        setItem: (key, value) => values.set(key, value)
    },
    console: { error() {} },
    confirm: () => allowReplacement
};
vm.createContext(context);
for (const file of ['builder-validation.js', 'builder-storage.js']) {
    vm.runInContext(fs.readFileSync(file, 'utf8'), context, { filename: file });
}

const { ship, scenario } = context.window.BUILDER_VALIDATION;
const item = { id: 'item_1', name: 'Key', isHeavy: false, installTargetNodeId: '' };
const room = { id: 'r1', type: 'Bridge', name: 'Bridge', status: 'ONLINE', span: 2, notes: '' };
const vessel = {
    name: 'Ship', shipClass: 'Courier', transponder: 'AB', redAlert: false,
    hullCurrent: 1, hullMax: 1, armor: 0, thrusters: 1, jumpRating: 1, fuelCurrent: 1,
    fuelMax: 1, crewCurrent: 1, crewMax: 1, credits: 10, monthlyUpkeep: 0, totalDebt: 0,
    daysUntilDue: 1, rooms: [room], weapons: [], cargo: [], logs: []
};
const node = {
    id: 'node_1', level: '01', name: 'Start', x: 0, y: 0, status: 'ONLINE',
    description: '', isLocked: false, requiredItemId: '', keypadCode: '', cautiousTick: 1,
    rushedRisk: 20, connections: [], items: [item], logs: []
};
const adventure = {
    title: 'Scenario', partyNodeId: 'node_1', hunterNodeId: 'node_1', stress: 0,
    worldFlags: { zpmInstalled: false, coreUnlocked: false, virusAwakened: false, lockdown: false, workersProvoked: false },
    inventory: [], clocks: [], nodes: [node]
};
ship(vessel);
scenario(adventure);
assert.throws(() => ship({ name: 'incomplete', rooms: [] }), /ship\.shipClass/);
assert.throws(() => ship({ ...vessel, rooms: [{ ...room, id: "x');evil()" }] }), /valid identifier/);
assert.throws(() => scenario({ ...adventure, nodes: [] }), /at least one room/);
assert.throws(() => scenario({ ...adventure, nodes: [{ ...node, connections: ['missing'] }] }), /existing rooms/);

const storage = context.window.createBuilderStorage('test', ship, () => vessel);
values.set('test', '{"broken":true}');
assert.equal(storage.load(), vessel);
storage.save(vessel);
assert.equal(values.get('test'), '{"broken":true}', 'invalid stored data must not be overwritten');
assert.equal(storage.confirmImport(), false);
allowReplacement = true;
assert.equal(storage.confirmImport(), true);
storage.save(vessel);
assert.equal(JSON.parse(values.get('test')).name, 'Ship');
listeners.storage({ key: 'test' });
storage.save({ ...vessel, name: 'stale' });
assert.equal(JSON.parse(values.get('test')).name, 'Ship', 'a stale tab must not overwrite changes');
assert.match(status.textContent, /another tab/);
console.log('Builder validation and storage tests passed.');
