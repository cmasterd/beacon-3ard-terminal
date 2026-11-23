'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const context = { window: {} };
vm.createContext(context);
for (const file of ['builder-validation.js', 'scenario-package.js']) {
    vm.runInContext(fs.readFileSync(path.join(__dirname, '..', file), 'utf8'), context, { filename: file });
    if (file === 'builder-validation.js') context.BUILDER_VALIDATION = context.window.BUILDER_VALIDATION;
}

function scenario() {
    return {
        title: ' Ghost Ship ', partyNodeId: 'bridge', hunterNodeId: 'bridge', stress: 2,
        worldFlags: { zpmInstalled: false, coreUnlocked: false, virusAwakened: true, lockdown: false, workersProvoked: false },
        inventory: [{ id: 'key', name: 'Key', isHeavy: false, installTargetNodeId: '' }],
        clocks: [{ id: 'clock', label: 'Danger', current: 3, max: 10, step: 1, unit: 'TICKS' }],
        nodes: [{
            id: 'bridge', level: '1', name: 'Hidden bridge', x: 1, y: 2,
            status: 'LOCKED', description: 'Secret sector', isLocked: true,
            requiredItemId: 'key', keypadCode: '1234', cautiousTick: 1, rushedRisk: 20,
            connections: ['bridge'], items: [],
            logs: [{ id: 'log', title: 'Secret log', author: 'Crew', stress: 1, body: 'Hidden message' }],
            extraSecret: 'not supported'
        }],
        extraSecret: 'not supported'
    };
}

test('creates a private versioned definition and only public catalog metadata', () => {
    const source = scenario();
    const result = context.window.SCENARIO_PACKAGE.makePackage(source);
    assert.deepEqual(JSON.parse(JSON.stringify(result.catalog)), { title: 'Ghost Ship', description: '' });
    assert.equal(result.definition.format, 'vad-scenario');
    assert.equal(result.definition.version, 1);
    assert.equal(result.definition.nodes[0].keypadCode, '1234');
    assert.equal(result.definition.nodes[0].logs[0].body, 'Hidden message');
    assert.equal(result.definition.initialState.inventory[0].id, 'key');
    assert.equal(result.definition.initialState.clocks[0].current, 3);
    assert.equal(result.definition.initialState.worldFlags.virusAwakened, true);
    assert.equal(JSON.stringify(result.catalog).includes('Secret'), false);
    assert.equal(JSON.stringify(result).includes('not supported'), false);
    source.nodes[0].connections.push('mutated');
    source.inventory[0].name = 'Changed';
    assert.equal(result.definition.nodes[0].connections.length, 1);
    assert.equal(result.definition.initialState.inventory[0].name, 'Key');
});

test('rejects invalid scenarios and invalid public titles', () => {
    const make = context.window.SCENARIO_PACKAGE.makePackage;
    assert.throws(() => make({ ...scenario(), nodes: [] }), /at least one room/);
    assert.throws(() => make({ ...scenario(), title: '  ' }), /title/);
    assert.throws(() => make({ ...scenario(), title: 'a'.repeat(121) }), /title/);
});

test('imports an exported package and rejects invalid definitions', () => {
    const api = context.window.SCENARIO_PACKAGE;
    const original = scenario();
    const data = api.makePackage(original);
    data.catalog.description = 'A derelict vessel';
    const restored = api.readPackage(JSON.parse(JSON.stringify(data)));
    assert.equal(restored.title, 'Ghost Ship');
    assert.equal(api.makePackage(restored).catalog.description, 'A derelict vessel');
    assert.equal(restored.nodes[0].keypadCode, '1234');
    assert.equal(restored.nodes[0].logs[0].body, 'Hidden message');
    assert.equal(restored.inventory[0].name, 'Key');
    assert.equal(restored.clocks[0].current, 3);
    assert.throws(() => api.readPackage({ ...data, definition: { ...data.definition, version: 2 } }), /unsupported/);
    assert.throws(() => api.readPackage({ ...data, definition: { ...data.definition, nodes: [] } }), /at least one room/);
});
