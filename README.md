# VAD Terminal Network

The main gateway offers a game library, local creator prototypes and shared terminals. The library's first game is Beacon 3A-R3D:

- **Main gateway** (`index.html`): access the game library, builders and shared terminals.
- **Game library** (`library.html`) and **Beacon gateway** (`beacon.html`): choose Beacon and its Player, Warden, Archive or Shop interface.
- **Player briefing** (`player_beacon_blueprint.html`): explore station sectors, search for items and logs, unlock keypads, and make the final escape or destruction choice.
- **Warden terminal** (`warden_beacon_master.html`): monitor player progress, control selected station overrides, send emergency broadcasts and run a countdown timer on the player terminal, and unlock audio, video and text logs.
- **Audio, video & text archive** (`archive.html`): lists audio, video and text logs; each is locked until the Warden unlocks it, and the player terminal alerts when one is released. "Leaving Gateway" (audio log #06) is public: it is always unlocked, has no Warden control, and triggers no alert. The other logs are Warden-locked placeholders expecting `audio/log-01.mp3` to `audio/log-05.mp3` and `video/log-01.mp4` to `video/log-03.mp4`. Text logs (emails, manifests, reports) need no files: write each entry's `body` directly in `logs.js`.

## Builders and shared shop

The **Builders** page offers two local prototypes. Scenario Builder edits and previews a scenario in one page, with mechanics currently specific to Beacon 3A-R3D. Shipyard Builder edits a ship and provides a ship terminal and shop. Neither is connected to Beacon's online session. They save one project each in this browser on this origin. Export JSON regularly to back up or transfer your project; imported files replace the current project. Exports include current simulation progress, not just the starting design. Projects are not automatically published to the Game Library.

The Shop Terminal is available under **Shared Terminals** and from the Beacon gateway. It opens Shipyard directly in shop mode and uses the same locally saved ship and credits as Shipyard. Its purchases are not shared across devices and do not update Beacon's online session. If the same project changes in another tab, saving pauses to avoid overwriting it: export any unsaved work and reload to see the latest copy.

Invalid imports are rejected without replacing the project. Storage errors and invalid saved data are shown on the page; a damaged saved project is not overwritten automatically. A valid imported backup can replace it.

### Preparing a scenario package

Scenario Builder's **Export Game Package** creates a versioned JSON package for the future publishing workflow. It does not publish a game or create a playable session. The `catalog` contains the public title and an initially empty description; the `definition` contains the private scenario, including sector details, items, logs, keypad codes and starting state. Treat the entire exported file as private and do not share it with players. Existing **Export JSON** remains the builder's backup format; game packages cannot currently be imported into the builder.

The package records the current simulation state as the starting state, including party and hunter locations, inventory, clocks and flags. Reset or adjust the simulation before exporting if necessary. It uses format `vad-scenario`, version `1`; only explicitly supported fields are included. The eventual server must keep the definition private and reveal sector details, items and logs through approval-controlled player views. The package is a foundation, not a generic runtime: Beacon-specific simulation mechanics have not yet been generalized.

### Game-aware foundation (in development)

`supabase/game_foundation.sql` is an experimental, additive database migration intended to be run **after** `supabase/schema.sql`. It registers Beacon as a game and links existing and newly created Beacon sessions to game-session records without copying or changing their codes, credentials, progress, notes, ships or requests. It also provides private storage for versioned game definitions, separate session state and group inventories, and a model that can associate multiple named sessions with a game. Public catalog results include only published game metadata, not definitions; a Warden's session list contains only that account's session metadata.

This is a foundation, not a finished game-publishing feature: the Scenario Builder cannot publish games, create new playable sessions, or keep secrets private during online play yet. Beacon still uses its existing terminals and one legacy session per Warden. No new scenario runtime or rule engine is exposed by this migration. Test it in an isolated database and back up the live project before applying it; do not apply it to production until the remaining features are ready.

### Shared online ship and requisitions

The Warden can publish a Shipyard ship from the current browser or upload an exported Shipyard JSON file in the online Warden terminal's **Shared Ship & Requisitions** panel. This replaces the published snapshot. All players in the session can view every field of that snapshot, including ship logs and cargo, so do not publish Warden-only information. The online ship terminal is accessible from the Beacon player code form or the online player terminal. Players select an enabled group and request ship upgrades, fuel or repairs; the Warden sees the requesting group and can approve or reject each request. Request history is visible to players.

Approval is **manual**: it does not deduct credits, perform a purchase or change the shared ship. The Warden handles the purchase in Shipyard or another way, then republishes the updated ship. The Shipyard shop remains local and is not the shared ship itself. Requests and their decisions persist across devices, station resets and backup restores, as does the published ship. They are not included in the existing Beacon backup export; separately export the ship from Shipyard. The Warden can clear decided requests to make room; pending requests are retained. The session holds up to 200 requests. An uncertain submission can be retried with the same identifier while its tab remains open; check the history before creating a replacement.

## Editing logs

All log content (titles, descriptions, file paths, text bodies, `public` flags) lives in one file, `logs.js`. The archive, Warden and player pages all read it, so edit it once. Add real media files to `audio/` and `video/` and update the `src` paths there.

`audio/log-01.mp3` to `log-05.mp3` are generated placeholders: Windows text-to-speech plus ffmpeg effects. The Dr. Vane scripts are in `tools/make-audio.ps1` (Windows PowerShell, needs ffmpeg on the PATH). Edit them and re-run `powershell -ExecutionPolicy Bypass -File tools\make-audio.ps1`, or overwrite the mp3s with real recordings.

In local mode the pages share scenario progress through the browser's `localStorage`. Open them in the same browser and serve them from the same origin. Online mode can also synchronize an independent session across devices through Supabase.

## Player action approvals

Selecting a sector is unrestricted, but **Explore**, **Search**, and **Access Logs** send a request to the Warden in both local and online games. The Warden sees pending requests in **Player Action Requests** and can approve or reject each one. Approval immediately applies the action; rejection leaves progress unchanged and the player can request it again. The player terminal shows the latest request for the current sector, including the requesting group online. Only one equivalent request can be pending at a time. If an action becomes unavailable before approval, the Warden can reject the stale request.

Sector 7B still requires engine power or the Warden's visibility override, but plugging in the engine no longer automatically explores it: exploration also requires approval. These sector actions are separate from the Warden's archive unlock controls.

For local approval, use a browser with Web Locks support and a secure origin such as `localhost` or HTTPS. Both terminals must use the same browser profile and origin; local mode is not a security boundary. Online approval works across devices and browsers using the shared session. A reset or backup restore clears the request queue, so players must submit new requests afterward. Backups do not include request history. If a submission cannot be confirmed, keep its tab open and use **Retry** or **Discard** after checking its status.

## Online sessions and split groups

The Warden signs in through **Online Warden Login** in the Warden Overwatch tile using the account created in the Supabase project. Share the player link or session code with everyone, including the shared table touchscreen. Players can enter the code in the Player Briefing tile to join. After a successful connection the browser remembers that session, so opening the online player terminal again needs no code; enter a new one to switch sessions or use **Forget Saved Session** to remove it. Local player and Warden terminals remain available from the same tiles.

Group 1 is always enabled; turn groups 2, 3 and 4 on when the party splits. Each newly enabled or re-enabled group starts at Group 1's current sector, or sector 1 if Group 1 hasn't selected a sector yet. Players select an enabled group on any player device, then select a sector to move that group's marker. Multiple devices can control the same group; the last sector selection wins. Disabling a group hides its marker and returns any affected player device to Group 1.

Station progress, hazards, status, broadcasts, countdown and archive unlocks are shared. Numbered coloured markers on both maps show active groups' last selected sectors. They remain visible when players switch groups or disconnect; they are not device-presence indicators. The archive follows the player's session when opened from their terminal. Sound and each device's alert/reveal history remain local. Online updates are polled about every two seconds.

The status banner reports pending or failed writes. If the connection fails, keep the tab open while it retries; unsent changes are not guaranteed to survive closing the tab. A failed write can be discarded explicitly using the banner's reload control. Resetting or restoring the session rejects writes from before the reset; affected devices must discard stale pending changes and reload. Online reset is Warden-only and preserves Warden notes and group settings. Backup export and restore work from the online Warden terminal; importing a local backup replaces the online session.

The five-character session code and player link grant access: share them only with your players. The short code is easier to guess and does not provide strong protection against unauthorized joining; anyone who discovers it can act as a player in any enabled group. The browser saves the session credential after joining, so don't use a shared or public device unless you intend to leave access available there. The Warden login and database permissions protect online Warden-only controls and notes, but not the scenario content itself: the static website, its Warden page, codes and log contents remain public.

### Supabase setup

1. Create a Supabase project and manually create an email/password Warden user in **Authentication → Users**. Confirm that user. Consider disabling public user sign-ups in Authentication settings while keeping email/password sign-in enabled.
2. In the Supabase **SQL Editor**, run the complete contents of [`supabase/schema.sql`](supabase/schema.sql). It creates private tables with row-level security and functions that authorize player and Warden access. Re-running it preserves existing sessions.
3. `online.js` is configured with this project's URL and publishable key. These are public client configuration, not administrative credentials. Never put a database password, secret key or service-role key in the site or backup.
4. Open the gateway, select **Game Library → Beacon 3A-R3D → Online Warden Login**, sign in, and share the player link or session code. Enable additional groups as needed. The online station starts separately from local progress; use Backup & Restore to import an existing local backup if desired.

An internet connection is required. Supabase can pause an inactive free project; restore it from its dashboard before play if needed. The Warden's **Exit Online Session** signs out on that browser. Each Warden account has one persistent online station.

When deploying action approvals, update the schema and the player and Warden pages together. Older player pages are not compatible with the approval-enforcing schema; the new pages require the updated schema.

## Run locally

From the project directory, start a local static web server:

```powershell
py -m http.server 8000
```

Then open the gateway in your browser and choose a terminal:

- Gateway: <http://localhost:8000/>
- Game library: <http://localhost:8000/library.html>
- Beacon gateway: <http://localhost:8000/beacon.html>
- Builders: <http://localhost:8000/builders.html>
- Shared terminals: <http://localhost:8000/terminals.html>
- Player: <http://localhost:8000/player_beacon_blueprint.html>
- Warden: <http://localhost:8000/warden_beacon_master.html>
- Audio, video & text archive: <http://localhost:8000/archive.html>

The pages use Tailwind CSS and fonts from CDNs, so an internet connection is needed for those visual assets. The game itself is implemented in the HTML files and does not require a build step.

Run the focused builder validation and storage tests with `node tests\builder_validation_test.js`.

## Progress and reset

In local mode, progress is saved in the browser and shared between terminals on the same origin. Use the reset control in the Warden terminal to clear station progress, archive unlocks, alert memory, any active broadcast and the countdown (it asks for confirmation).

An emergency broadcast (typed or preset) appears as a red banner on the player terminal until the player dismisses it or the Warden clears it.

The Warden can start, pause, resume and clear a labelled countdown (for example "SELF-DESTRUCT"); the player terminal shows a live clock in the bottom-left and flags when time expires.

The Warden has a **Ship Status Board** with Oxygen, Power, Hull and Comms sliders (0-100%, with -10/+10 buttons) and one-click presets (hull breach, power failure, life support failing, blackout, all clear). The player terminal shows them as a strip under the header: amber below 60%, red and pulsing below 30%. When a gauge drops below 25% the player terminal sounds the alarm and glitches the screen. Power and Comms start at 0% (Oxygen and Hull at 100%); plugging the Sovereign Engine into sector 07 sets Power to 100%, and the player's "Reset Blueprint" sets it back to 0%. "Reset to defaults" restores all four starting values.

In a room's detail panel the Warden can set a **Sector Hazard** (vacuum, fire, radiation, toxic gas, xeno contact, power surge). That sector pulses red with a warning tag on both maps, and the player sees a hazard banner when viewing it. Players see the marker even for undiscovered sectors, so set hazards when you want them revealed.

The player terminal opens with a login screen once per browser tab: a rotating laser-style VAD logo and a **LOGIN** button. Pressing it runs a slow boot sequence (about 8 seconds, with a SKIP button) before the terminal appears; the login click also counts as the click browsers need before audio can play. The screen briefly glitches on broadcasts, log unlocks and countdown expiry, and locked archive entries flicker. Both effects honour the system "reduce motion" setting.

The player terminal has a **SOUND** button (header). When on, it plays a chime when a log unlocks, an alarm for broadcasts and a siren when the countdown expires. Browsers only allow audio after a click, so press the button (or click anywhere on the page) once after each page load. The sound setting stays local to the browser profile.

The player terminal has a **FULLSCREEN** button (or press `F`) for a cleaner view on the second monitor.

Unlocked text logs show an **Open Document** button on the archive page. It opens a popup (close with the button, `Esc` or a click outside) where the text types itself out the first time it is opened (click the text to skip); afterwards, and with "reduce motion", it appears at once.

In local mode the Warden schematic shows a **players-here marker** on the selected sector. In online mode it shows numbered markers for active groups, as described above. A Warden station reset returns the local marker or every enabled online group marker to sector 01; enabled group settings stay unchanged.

## Warden session log, notes and backup

The Warden terminal records a timestamped **Session Log** of player actions (sector movement, explore, search, keypad attempts, engine, escape, self-destruct) and Warden actions (broadcasts, unlocks, hazards, status changes, countdown, resets), with Copy and Clear buttons. New online player entries include the group selected when the action was performed; older entries and local-mode entries remain labelled PLAYER. Switching groups or selecting the same sector again does not record a move. A station reset clears the log. **Warden Notes** is a private scratchpad that autosaves and survives a station reset.

**Backup & Restore** downloads all game state (progress, unlocks, status, hazards, log, notes) as a JSON file, and can restore it later; restoring replaces current state and reloads the page. Sound preference is not included.

## Warden access code

The local Warden terminal opens with a keypad. The code is `1337` (change `WARDEN_CODE` in `warden_beacon_master.html`). It stays unlocked for the rest of that browser tab. This is a client-side gate to keep players out of the GM view; anyone who reads the page source can see the code. Online Warden control instead requires the Supabase email/password login.

## Hosting (GitHub Pages)

The site is published with GitHub Pages at <https://cmasterd.github.io/beacon-3ard-terminal/index.html> and updates when `master` is pushed. Everything in the repo is public, including the Warden page, its master keypad codes and the `1337` access code, so players who find the URL or read the page source can spoil the game. Static hosting alone does not sync devices; online mode uses the separately configured Supabase project.
