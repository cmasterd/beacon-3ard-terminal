# Beacon 3A-R3D Terminals

A pair of browser-based interfaces for running a Beacon 3A-R3D salvage scenario:

- **Terminal gateway** (`index.html`): choose the Player or Warden interface.
- **Player briefing** (`player_beacon_blueprint.html`): explore station sectors, search for items and logs, unlock keypads, and make the final escape or destruction choice.
- **Warden terminal** (`warden_beacon_master.html`): monitor player progress, control selected station overrides, send emergency broadcasts to the player terminal, and unlock audio and video logs.
- **Audio & video archive** (`archive.html`): lists audio logs and video logs; each is locked until the Warden unlocks it, and the player terminal alerts when one is released. "Leaving Gateway" (audio log #06) is public: it is always unlocked, has no Warden control, and triggers no alert. The other logs are Warden-locked placeholders expecting `audio/log-01.mp3` to `audio/log-05.mp3` and `video/log-01.mp4` to `video/log-03.mp4`. Add real files and edit `ARCHIVE` in both the archive and Warden pages (ids and titles must match).

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
- Audio & video archive: <http://localhost:8000/archive.html>

The pages use Tailwind CSS and fonts from CDNs, so an internet connection is needed for those visual assets. The game itself is implemented in the HTML files and does not require a build step.

## Progress and reset

Progress is saved in the browser and shared between both terminals on the same origin. Use the reset control in the Warden terminal to clear station progress, archive unlocks, alert memory and any active broadcast (it asks for confirmation).

An emergency broadcast (typed or preset) appears as a red banner on the player terminal until the player dismisses it or the Warden clears it. Browser storage is local to that browser profile; it is not synchronized between devices.
