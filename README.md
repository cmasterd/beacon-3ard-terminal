# Beacon 3A-R3D Terminals

A pair of browser-based interfaces for running a Beacon 3A-R3D salvage scenario:

- **Terminal gateway** (`index.html`): choose the Player or Warden interface.
- **Player briefing** (`player_beacon_blueprint.html`): explore station sectors, search for items and logs, unlock keypads, and make the final escape or destruction choice.
- **Warden terminal** (`warden_beacon_master.html`): monitor player progress, control selected station overrides, send emergency broadcasts and run a countdown timer on the player terminal, and unlock audio, video and text logs.
- **Audio, video & text archive** (`archive.html`): lists audio, video and text logs; each is locked until the Warden unlocks it, and the player terminal alerts when one is released. "Leaving Gateway" (audio log #06) is public: it is always unlocked, has no Warden control, and triggers no alert. The other logs are Warden-locked placeholders expecting `audio/log-01.mp3` to `audio/log-05.mp3` and `video/log-01.mp4` to `video/log-03.mp4`. Text logs (emails, manifests, reports) need no files: write each entry's `body` directly in `logs.js`.

## Editing logs

All log content (titles, descriptions, file paths, text bodies, `public` flags) lives in one file, `logs.js`. The archive, Warden and player pages all read it, so edit it once. Add real media files to `audio/` and `video/` and update the `src` paths there.

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
- Audio, video & text archive: <http://localhost:8000/archive.html>

The pages use Tailwind CSS and fonts from CDNs, so an internet connection is needed for those visual assets. The game itself is implemented in the HTML files and does not require a build step.

## Progress and reset

Progress is saved in the browser and shared between both terminals on the same origin. Use the reset control in the Warden terminal to clear station progress, archive unlocks, alert memory, any active broadcast and the countdown (it asks for confirmation).

An emergency broadcast (typed or preset) appears as a red banner on the player terminal until the player dismisses it or the Warden clears it.

The Warden can start, pause, resume and clear a labelled countdown (for example "SELF-DESTRUCT"); the player terminal shows a live clock in the bottom-left and flags when time expires.

The Warden has a **Ship Status Board** with Oxygen, Power, Hull and Comms sliders (0-100%, with -10/+10 buttons) and one-click presets (hull breach, power failure, life support failing, blackout, all clear). The player terminal shows them as a strip under the header: amber below 60%, red and pulsing below 30%. When a gauge drops below 25% the player terminal sounds the alarm and glitches the screen. Power and Comms start at 0% (Oxygen and Hull at 100%); plugging the Sovereign Engine into sector 07 sets Power to 100%, and the player's "Reset Blueprint" sets it back to 0%. "Reset to defaults" restores all four starting values.

In a room's detail panel the Warden can set a **Sector Hazard** (vacuum, fire, radiation, toxic gas, xeno contact, power surge). That sector pulses red with a warning tag on both maps, and the player sees a hazard banner when viewing it. Players see the marker even for undiscovered sectors, so set hazards when you want them revealed.

The player terminal plays a short boot-up sequence once per browser tab (click or press a key to skip). The screen briefly glitches on broadcasts, log unlocks and countdown expiry, and locked archive entries flicker. Both effects honour the system "reduce motion" setting.

The player terminal has a **SOUND** button (header). When on, it plays a chime when a log unlocks, an alarm for broadcasts and a siren when the countdown expires. Browsers only allow audio after a click, so press the button (or click anywhere on the page) once after each page load. Browser storage is local to that browser profile; it is not synchronized between devices.

The player terminal has a **FULLSCREEN** button (or press `F`) for a cleaner view on the second monitor.

Text logs in the archive type themselves out the first time they are shown (click to skip); afterwards, and with "reduce motion", they appear at once.

## Warden session log, notes and backup

The Warden terminal records a timestamped **Session Log** of player actions (explore, search, keypad attempts, engine, escape, self-destruct) and Warden actions (broadcasts, unlocks, hazards, status changes, countdown, resets), with Copy and Clear buttons. A station reset clears the log. **Warden Notes** is a private scratchpad that autosaves and survives a station reset.

**Backup & Restore** downloads all game state (progress, unlocks, status, hazards, log, notes) as a JSON file, and can restore it later; restoring replaces current state and reloads the page. Sound preference is not included.

## Warden access code

The Warden terminal opens with a keypad. The code is `1337` (change `WARDEN_CODE` in `warden_beacon_master.html`). It stays unlocked for the rest of that browser tab. This is a client-side gate to keep players out of the GM view; anyone who reads the page source can see the code.

## Hosting (GitHub Pages)

The site is published with GitHub Pages at <https://cmasterd.github.io/beacon-3ard-terminal/index.html> and updates when `master` is pushed. Everything in the repo is public, including the Warden page, its master keypad codes and the `1337` access code, so players who find the URL or read the page source can spoil the game. Share only the player link with players. Static hosting also does not sync devices: the player and Warden terminals must be open in the same browser (same origin), as described above.
