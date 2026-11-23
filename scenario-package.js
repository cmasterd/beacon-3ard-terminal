(function () {
    'use strict';

    function makePackage(scenario) {
        BUILDER_VALIDATION.scenario(scenario);
        const title = scenario.title.trim();
        if (!title || title.length > 120) throw new Error('Scenario title must contain 1 to 120 characters');

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
        return { catalog: { title, description: '' }, definition };
    }

    window.SCENARIO_PACKAGE = { makePackage };
})();
