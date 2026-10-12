# [YOUR GAME NAME]

An open-world superhero game for Roblox, set in the small town of **Rushville**.
Players get a power ring, explore the town and take on missions solo or with a partner.
It is *inspired by* the HBO series *Lanterns*. All names, art, text and designs in this
project are original. It uses no DC logos, the comic oath, character names or actor
likenesses.

The game name is a placeholder in `src/shared/Config/Game.luau`.

**Status: Milestone 0 (Foundation).** This milestone covers the project setup, networking,
config, saving, input, and the Rushville map blockout with its districts, spawns, mission
markers and boundary. Ring powers come in Milestone 1.

---

## 1. One-time setup

You need **Roblox Studio** and a terminal: PowerShell on Windows, Terminal on macOS.

1. **Install Rokit**, the toolchain manager. It installs the exact tool versions this
   project pins in `rokit.toml`.
   - Windows (PowerShell):
     ```powershell
     Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
     ```
   - macOS / Linux:
     ```bash
     curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
     ```
   Close and reopen the terminal afterwards.
2. **Install the project tools.** From the project folder, run:
   ```bash
   rokit install
   ```
   Answer "yes" when it asks to trust each tool. This installs Rojo, luau-lsp, selene, StyLua
   and Lune.
3. **Install the Rojo plugin into Studio.** Close Studio first, then run:
   ```bash
   rojo plugin install
   ```
   The plugin version matches the CLI version from `rokit.toml`.
4. *(Optional, recommended)* Install **VS Code** with these extensions: *Rojo*
   (evaera.vscode-rojo), *Luau Language Server* (JohnnyMorganz.luau-lsp), *Selene*
   (Kampfkarren.selene-vscode) and *StyLua* (JohnnyMorganz.stylua).

## 2. Connecting the project to Studio

1. In the project folder, start the Rojo server and leave it running:
   ```bash
   rojo serve
   ```
   It prints `Rojo server listening on port 34872`.
2. Open Studio and create a new place: **File → New**, then pick **Baseplate**.
3. **Delete the template's `Workspace.Baseplate` and `Workspace.SpawnLocation`.** The town's
   ground sits exactly at Y = 0, so the template baseplate would flicker against it, and its
   spawn would compete with the game's own spawn. If you forget, the game disables stray
   spawns at runtime and prints a warning about the baseplate.
4. Open the **Plugins** tab, click **Rojo**, then **Connect** (the defaults are `localhost` /
   `34872`).
   The code appears in:
   - `ReplicatedStorage.Shared`: shared config, types, remotes and utilities
   - `ServerScriptService.Server`: server services and the map builder
   - `StarterPlayer.StarterPlayerScripts.Client`: client controllers and UI

   From now on, every file you save on disk syncs into Studio live.
5. **Enable saving** if you want to test progress across sessions. Publish the place with
   **File → Publish to Roblox**, then turn on **Game Settings → Security → Enable Studio
   Access to API Services**.
   Without this, the game still runs on in-memory data and shows a "Saving is unavailable"
   notice.
6. Press **Play** (F5).

> Rojo syncs code only. The map, and any models you add in Studio, live in your place
> file, so **save the place** in Studio as usual.

## 3. Testing Milestone 0

Do these checks in order. The Output window should show `[WorldService] Built the blockout
map in … ms` and `[Server] Initialised services in … ms`, with no red errors.

| # | Do this | You should see |
|---|---------|----------------|
| 1 | Press Play | You spawn at the **south end of the highway**, by the railroad. A **"Rail Yard"** banner appears and a welcome message: *"Welcome to Rushville…"* the first time, or *"Welcome back… Session N"* later. |
| 2 | Walk north up Main St to the crossroads | A **"Downtown"** banner, then the toast *"New area discovered: Downtown (2/7)"*. |
| 3 | Press **M** (keyboard), **D-pad Up** (controller), or tap the **Map** button (phone) | The **Districts panel**: discovered districts with a check mark, undiscovered ones as "???", your current one marked *You are here*, and "Discovered X / 7". Close it with M, B (controller) or the **Close** button. |
| 4 | Visit the Farmstead, North Fields, Elm & Oak, South Fields | Each one shows its banner and a discovery toast. The panel updates live. |
| 5 | Walk into the **Sheriff's Office** (door faces Center Street) | A front office with desks and a case board. Through the back doorway is the glowing green **ring battery**, where players will recharge in Milestone 1. |
| 6 | Walk into the **Diner** and the **Grain Elevator** | The Diner has a counter, stools and booths. The Grain Elevator is derelict: go through the gap in its fence, inside the broken north opening, and up the ramps. |
| 7 | Find the **crime scene** in the south wheat field | A trampled circle with evidence markers and tape posts. |
| 8 | Reset your character (**Esc → Reset Character**) in a district you've discovered | You respawn at the nearest respawn point of a district you've discovered, not back on the highway. |
| 9 | **Stop**, then **Play** again (with saving enabled, step 2.5) | *"Welcome back… Session 2"*, and the panel still lists your districts. |
| 10 | **Boundary.** While playing, switch the command bar to the **Server** context (Test tab → Current: Server) and run `game.Players:GetPlayers()[1].Character:PivotTo(CFrame.new(2350, 5, 0))` | Back on the client: a **"Signal fading"** warning with an amber edge glow, and a gentle push back toward town. You can't walk past X = 2500. |
| 11 | Same, but `CFrame.new(2800, 5, 0)` (as if an exploiter teleported) | Within about a second the server puts you back inside the boundary and logs a warning in Output. |
| 12 | **Mobile.** Test tab → **Device** → pick a phone, then Play | The UI scales down, and the round **Map** button sits on the right, clear of the jump button. |
| 13 | **Mission markers** | Green discs with labels such as `Story_CaseHQ` at the story and side-mission spots. The labels only show in Studio. Missions attach to them in Milestone 3. |

**Seeing the district zones.** Set `DebugShowZonesInStudio = true` in
`src/shared/Config/World.luau` and press Play. Each district's invisible volume is drawn as a
coloured translucent box.

## 4. The map

The map is built **from code** (`src/server/Map/`) to match the Rushville layout PDF:
1000 × 700 studs, origin at Main St × Center St, +X east, +Z south.

- **Automatic.** If `Workspace` has no `Map` folder when the server starts, the blockout is
  built (about 0.1 s).
- **Baking it into your place.** Do this so you can edit it and swap in real models. In edit
  mode (not playing), open **View → Command Bar** and run:
  ```lua
  require(game.ServerScriptService.Server.Map.MapBuilder).Build(workspace)
  ```
  Then save the place. From then on, the game uses your saved map exactly as it is.
  To regenerate it, run `...Build(workspace, { Replace = true })`. **This deletes your edits
  to the map**, so only do it on purpose.
- **Exporting as a model file.** `lune run tests/export-map` writes
  `build/RushvilleMap.rbxm`, which you can drag into Studio.

**Layout in Workspace**

```
Map
├─ Rushville
│  ├─ Ground
│  ├─ Roads          Main St, Center Street, County Road, Elm Ave, Oak St, Railroad, sidewalks, signs
│  ├─ Downtown       General Store, Diner, Sheriff's Office (case HQ + ring battery), Hardware,
│  │                 Bar, Motel, Post Office, Church, Gas Station
│  ├─ Farmstead      Farmhouse, Barn, Silos A–C, north cornfield
│  ├─ NorthFields    Water Tower, north-east wheat field
│  ├─ Residential    10 houses, the Calloway Home
│  ├─ SouthFields    South wheat field, the crime scene
│  └─ RailYard       Derelict Grain Elevator, south corn strips, rail siding
├─ OuterRing         Farmland, farmsteads and roads out to the edge of the world
├─ Zones             Invisible district volumes (one or more per district)
├─ Spawns            The main SpawnLocation + one respawn point per district
└─ MissionMarkers    Mission start markers (always streamed to every client)
```

**Replacing blockout parts with real models.**
- Every building, field and landmark is a `Model` tagged `Blockout`. Its `PrimaryPart` is an
  invisible `Footprint` box with the exact size and position from the build table. Line your
  real model up with the footprint, then delete the blockout model.
- Gameplay never looks things up by name. It uses tags, so keep these objects, or move their
  tags and attributes onto your replacements:
  - the parts in `Zones`, `Spawns` and `MissionMarkers`
  - the battery's `Core` part, tagged `RingBatterySpot`, in the Sheriff's Office

  The tag and attribute names are in `src/shared/Util/Tags.luau`.

**Changes from the PDF:**
- The Farmhouse, Barn and silos moved 35 studs west, so the silos no longer run into the
  General Store.
- "Stewart Home" is now the **Calloway Home**, an original name.
- The Grain Elevator is the abandoned site for secrets.
- An outer ring of farmland extends the world to ±2,500 studs for flying room. Past the soft
  boundary, players are warned and pushed back.

## 5. Project layout & architecture

```
default.project.json   Rojo mapping (src/shared, src/server, src/client)
rokit.toml             pinned toolchain
scripts/check.sh       quality gate
tests/                 offline Lune tests (utilities + the map contract)
src/shared/            → ReplicatedStorage.Shared
  Config/              ALL tunable numbers and player-facing text
  Types.luau           shared types (save format, districts, input)
  Net.luau             typed remote wrappers: validation + per-player rate limits
  Remotes.luau         EVERY client↔server message, declared once
  Util/                Signal, Validate, RateLimiter, Zones, Boundary, Tags
src/server/            → ServerScriptService.Server
  init.server.luau     starts services in order (Init, then Start)
  Services/            DataService, WorldService, ZoneService, SpawnService, BoundaryService
  Map/                 map data (MapLayout) and builders
  Vendor/ProfileStore  session-locked saving (third-party, Apache-2.0)
src/client/            → StarterPlayerScripts.Client
  init.client.luau     starts controllers in order
  Controllers/         Hud, Input, Notification, Profile, Zone, DistrictsPanel, Boundary
  UI/                  small UI building helpers
```

**Rules the code follows**
- **The server is in charge.** Clients only send requests. The server checks every argument
  (`Util/Validate`) and rate-limits every remote per player (`Config/Net.luau`), and decides
  everything that matters: data, discovery, rewards. Too many malformed messages get the
  sender kicked.
- **Tuning lives in `src/shared/Config`.** That covers speeds, timings, boundary size, UI
  sizes, colours and text, so you can balance without digging through code. Map geometry
  lives in `src/server/Map/MapLayout.luau`.
- **One Service per system** on the server and **one Controller per system** on the client.
  Each has `Init` (wire up, never yields) and `Start` (may yield).
- **Saving uses ProfileStore** with session locking, so two servers can never write the same
  save. If a save can't load, the player is asked to rejoin rather than playing on blank
  data. If the DataStore fails mid-session, players are told and progress is kept until it
  recovers.
- **Input.** Every action is defined once in `Config/Input.luau` for keyboard, gamepad and
  touch. On phones and tablets, actions get on-screen buttons.

**Adding a remote:** declare it in `src/shared/Remotes.luau` with one validator per argument,
and add a rate limit in `Config/Net.luau`.

## 6. Quality checks

```bash
./scripts/check.sh
```

On Windows, run it from Git Bash. It does five things:
- builds the place with Rojo
- type-checks every script in **strict** mode with luau-lsp
- lints with selene
- checks formatting with StyLua (run `stylua src` to fix formatting)
- runs the offline tests with `lune run tests/run`

The tests check the utilities and the whole map against the PDF build table: positions,
sizes, overlaps, zones, spawns, markers and walk-in interiors.

## Third-party code

- [ProfileStore](https://github.com/MadStudioRoblox/ProfileStore) by loleris, Apache License 2.0.
  The license is in `licenses/ProfileStore-LICENSE.txt`.
