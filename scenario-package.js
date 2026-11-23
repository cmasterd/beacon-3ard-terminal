(function () {
    'use strict';

    function makePackage(scenario) {
        BUILDER_VALIDATION.scenario(scenario);
        const title = scenario.title.trim();
        if (!title || title.length > 120) throw new Error('Scenario title must contain 1 to 120 characters');
        const description = scenario.catalogDescription === undefined ? '' : scenario.catalogDescription;
        if (typeof description !== 'string' || description.length > 2000) throw new Error('Catalog description must be text of at most 2000 characters');

        const item = value => ({
            id: value.id, name: value.name, isHeavy: value.isHeavy,
            installTargetNodeId: value.installTargetNodeId
        });
        const definition = {
            format: 'vad-scenario',
            version: 1,
            initialState: {
                partyNodeId: scenario.partyNodeId,
                hunterNodeId: scenario.hunterNodeId,
                stress: scenario.stress,
                worldFlags: {
                    zpmInstalled: scenario.worldFlags.zpmInstalled,
                    coreUnlocked: scenario.worldFlags.coreUnlocked,
                    virusAwakened: scenario.worldFlags.virusAwakened,
                    lockdown: scenario.worldFlags.lockdown,
                    workersProvoked: scenario.worldFlags.workersProvoked
                },
                inventory: scenario.inventory.map(item),
                clocks: scenario.clocks.map(clock => ({
                    id: clock.id, label: clock.label, current: clock.current,
                    max: clock.max, step: clock.step, unit: clock.unit
                }))
            },
            nodes: scenario.nodes.map(node => ({
                id: node.id, level: node.level, name: node.name, x: node.x, y: node.y,
                status: node.status, description: node.description, isLocked: node.isLocked,
                requiredItemId: node.requiredItemId, keypadCode: node.keypadCode,
                cautiousTick: node.cautiousTick, rushedRisk: node.rushedRisk,
                connections: [...node.connections],
                items: node.items.map(item),
                logs: node.logs.map(log => ({
                    id: log.id, title: log.title, author: log.author, stress: log.stress, body: log.body
                }))
            }))
        };
        return { catalog: { title, description }, definition };
    }

    function readPackage(data) {
        if (!data || typeof data !== 'object' || !data.catalog || typeof data.catalog.title !== 'string'
            || typeof data.catalog.description !== 'string' || !data.definition
            || data.definition.format !== 'vad-scenario' || data.definition.version !== 1
            || !data.definition.initialState || !Array.isArray(data.definition.nodes)) {
            throw new Error('Invalid or unsupported scenario game package');
        }
        const title = data.catalog.title.trim();
        if (!title || title.length > 120 || data.catalog.description.length > 2000) {
            throw new Error('Invalid catalog title or description');
        }
        const state = data.definition.initialState;
        const scenario = {
            title,
            catalogDescription: data.catalog.description,
            partyNodeId: state.partyNodeId,
            hunterNodeId: state.hunterNodeId,
            stress: state.stress,
            worldFlags: state.worldFlags,
            inventory: state.inventory,
            clocks: state.clocks,
            nodes: data.definition.nodes
        };
        BUILDER_VALIDATION.scenario(scenario);
        return scenario;
    }

    window.SCENARIO_PACKAGE = { makePackage, readPackage };
})();
