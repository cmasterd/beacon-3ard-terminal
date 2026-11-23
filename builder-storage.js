(function () {
    'use strict';
    window.createBuilderStorage = function (key, validate, makeDefault) {
        const status = document.getElementById('builder-storage-status');
        let blocked = false;
        function warn(message) {
            status.textContent = message;
            status.hidden = false;
            console.error(message);
        }
        window.addEventListener('storage', event => {
            if (event.key === key || event.key === null) {
                blocked = true;
                warn('This project changed in another tab. Changes here will not be saved. Export your work, then reload to see the latest version.');
            }
        });
        return {
            load() {
                try {
                    const saved = localStorage.getItem(key);
                    if (saved !== null) {
                        const data = JSON.parse(saved);
                        validate(data);
                        return data;
                    }
                } catch (error) {
                    blocked = true;
                    warn('Could not load the saved project: ' + error.message + '. It has not been overwritten. Import a valid backup to replace it, or export the displayed default.');
                }
                return makeDefault();
            },
            save(data) {
                if (blocked) return;
                try {
                    validate(data);
                    localStorage.setItem(key, JSON.stringify(data));
                } catch (error) {
                    blocked = true;
                    warn('Could not save this project: ' + error.message + '. Export your work as JSON to avoid losing it.');
                }
            },
            confirmImport() {
                if (blocked && !confirm('Saving is paused. Replace the saved project with this imported backup?')) return false;
                blocked = false;
                status.hidden = true;
                return true;
            },
            error(message) { warn(message); }
        };
    };
})();
