(function () {
    'use strict';

    function fail(path, expected) { throw new Error(`${path}: expected ${expected}`); }
    function object(value, path) {
        if (!value || typeof value !== 'object' || Array.isArray(value)) fail(path, 'an object');
    }
    function fields(value, path, types) {
        object(value, path);
        for (const [key, type] of Object.entries(types)) {
            if (typeof value[key] !== type || (type === 'number' && !Number.isFinite(value[key]))) {
                fail(`${path}.${key}`, type);
            }
        }
    }
    function array(value, path, check) {
        if (!Array.isArray(value)) fail(path, 'an array');
        value.forEach((entry, index) => check(entry, `${path}[${index}]`));
    }
    function id(value, path) {
        if (typeof value !== 'string' || !/^[a-zA-Z0-9_-]+$/.test(value)) fail(path, 'a valid identifier');
    }
    function unique(values, path) {
        if (new Set(values).size !== values.length) fail(path, 'unique identifiers');
    }
    function oneOf(value, choices, path) {
        if (!choices.includes(value)) fail(path, choices.join(', '));
    }

    function ship(data) {
        fields(data, 'ship', {
            name: 'string', shipClass: 'string', transponder: 'string', redAlert: 'boolean',
            hullCurrent: 'number', hullMax: 'number', armor: 'number', thrusters: 'number',
            jumpRating: 'number', fuelCurrent: 'number', fuelMax: 'number',
            crewCurrent: 'number', crewMax: 'number', credits: 'number', monthlyUpkeep: 'number',
            totalDebt: 'number', daysUntilDue: 'number'
        });
        array(data.rooms, 'ship.rooms', (room, path) => {
            fields(room, path, { id: 'string', type: 'string', name: 'string', status: 'string', span: 'number', notes: 'string' });
            id(room.id, `${path}.id`);
            oneOf(room.status, ['ONLINE', 'DAMAGED', 'OFFLINE'], `${path}.status`);
            oneOf(room.span, [1, 2, 4], `${path}.span`);
        });
        unique(data.rooms.map(room => room.id), 'ship.rooms');
        array(data.weapons, 'ship.weapons', (weapon, path) => {
            fields(weapon, path, { id: 'string', name: 'string', damage: 'string', range: 'string', status: 'string' });
            id(weapon.id, `${path}.id`);
            oneOf(weapon.status, ['ONLINE', 'DAMAGED', 'OFFLINE'], `${path}.status`);
        });
        array(data.cargo, 'ship.cargo', (entry, path) => {
            if (typeof entry !== 'string') fail(path, 'string');
        });
        array(data.logs, 'ship.logs', (log, path) => {
            fields(log, path, { id: 'string', title: 'string', date: 'string', body: 'string' });
            id(log.id, `${path}.id`);
        });
    }

    function scenario(data) {
        fields(data, 'scenario', { title: 'string', partyNodeId: 'string', hunterNodeId: 'string', stress: 'number' });
        fields(data.worldFlags, 'scenario.worldFlags', {
            zpmInstalled: 'boolean', coreUnlocked: 'boolean', virusAwakened: 'boolean',
            lockdown: 'boolean', workersProvoked: 'boolean'
        });
        function item(entry, path) {
            fields(entry, path, { id: 'string', name: 'string', isHeavy: 'boolean', installTargetNodeId: 'string' });
            id(entry.id, `${path}.id`);
            if (entry.installTargetNodeId) id(entry.installTargetNodeId, `${path}.installTargetNodeId`);
        }
        array(data.inventory, 'scenario.inventory', item);
        array(data.clocks, 'scenario.clocks', (clock, path) => {
            fields(clock, path, { id: 'string', label: 'string', current: 'number', max: 'number', step: 'number', unit: 'string' });
            id(clock.id, `${path}.id`);
            if (clock.max <= 0 || clock.step <= 0) fail(path, 'positive clock maximum and step');
            oneOf(clock.unit, ['TICKS', '%'], `${path}.unit`);
        });
        unique(data.clocks.map(clock => clock.id), 'scenario.clocks');
        array(data.nodes, 'scenario.nodes', (node, path) => {
            fields(node, path, {
                id: 'string', level: 'string', name: 'string', x: 'number', y: 'number',
                status: 'string', description: 'string', isLocked: 'boolean', requiredItemId: 'string',
                keypadCode: 'string', cautiousTick: 'number', rushedRisk: 'number'
            });
            id(node.id, `${path}.id`);
            oneOf(node.status, ['ONLINE', 'OFFLINE', 'LOCKED', 'BREACHED'], `${path}.status`);
            array(node.connections, `${path}.connections`, id);
            array(node.items, `${path}.items`, item);
            array(node.logs, `${path}.logs`, (log, logPath) => {
                fields(log, logPath, { id: 'string', title: 'string', author: 'string', stress: 'number', body: 'string' });
                id(log.id, `${logPath}.id`);
            });
        });
        if (!data.nodes.length) fail('scenario.nodes', 'at least one room');
        const ids = data.nodes.map(node => node.id);
        unique(ids, 'scenario.nodes');
        if (!ids.includes(data.partyNodeId) || !ids.includes(data.hunterNodeId)) fail('scenario', 'existing party and hunter rooms');
        data.nodes.forEach(node => {
            if (node.connections.some(target => !ids.includes(target))) fail(`scenario.nodes.${node.id}.connections`, 'existing rooms');
        });
    }

    window.BUILDER_VALIDATION = { ship, scenario };
})();
