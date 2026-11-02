# Beacon 3A-R3D Terminals

A pair of browser-based interfaces for running a Beacon 3A-R3D salvage scenario:

- **Terminal gateway** (`index.html`): choose the Player or Warden interface.
- **Player briefing** (`player_beacon_blueprint.html`): explore station sectors, search for items and logs, unlock keypads, and make the final escape or destruction choice.
- **Warden terminal** (`warden_beacon_master.html`): monitor player progress, control selected station overrides, and unlock audio logs.
- **Audio archive** (`audio_archive.html`): lists five audio logs; each is locked until the Warden unlocks it. Logs currently use placeholder titles, descriptions, and audio paths (`audio/log-01.mp3` to `audio/log-05.mp3`). Add the real files to an `audio/` folder and edit `AUDIO_LOGS` in both the archive and Warden pages.

Both pages share scenario progress through the browser's `localStorage`. Open them in the same browser and serve them from the same origin to keep the terminals synchronized.

## Run locally

From the project directory, start a local static web server:

```powershell
py -m http.server 8000
```

Then open the gateway in your browser and choose a terminal:

- Gateway: <http://localhost:8000/>
- Player: <http://localhost:8000/player_beacon_blueprint.html>
- Warden: <http://localhost:8000/warden_beacon_master.html>
- Audio archive: <http://localhost:8000/audio_archive.html>

The pages use Tailwind CSS and fonts from CDNs, so an internet connection is needed for those visual assets. The game itself is implemented in the HTML files and does not require a build step.

## Progress and reset

Progress is saved in the browser and shared between both terminals on the same origin. Use the reset control in the Warden terminal to clear station progress. Browser storage is local to that browser profile; it is not synchronized between devices.
