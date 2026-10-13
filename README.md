# [YOUR GAME NAME]

An open-world superhero game for Roblox, set in the small town of **Rushville**.
Players get a power ring, explore the town and take on missions solo or with a partner.
It is *inspired by* the HBO series *Lanterns*. All names, art, text and designs in this
project are original. It uses no DC logos, the comic oath, character names or actor
likenesses.

The game name is a placeholder in `src/shared/Config/Game.luau`.

**Status: Milestone 1 (Ring Powers).** The power ring: flight with banking and a boost, the
energy beam, the shield bubble and three hard-light constructs (wall, hammer, cage), the
willpower and ring-charge meters, the oath moment that recharges the ring at the battery in
the Sheriff's Office, and a training yard of practice targets. Every power works on
keyboard and mouse, gamepad and touch.

Milestone 0 (Foundation) is complete: project setup, networking, config, saving, input, and
the Rushville map blockout with its districts, spawns, mission markers and boundary.

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

   **If the installer stops with `curl: (56) ... error: 403`:** the script first asks
   GitHub's API for the latest version, and GitHub only allows about 60 anonymous API
   calls per hour per network. Download Rokit directly instead, which makes no API call.
   On macOS, run `uname -m` first: `arm64` means Apple Silicon, `x86_64` means Intel.
   ```bash
   cd ~/Downloads
   # Apple Silicon (arm64):
   curl -fL -o rokit.zip https://github.com/rojo-rbx/rokit/releases/download/v1.2.0/rokit-1.2.0-macos-aarch64.zip
   # Intel (x86_64) instead:
   # curl -fL -o rokit.zip https://github.com/rojo-rbx/rokit/releases/download/v1.2.0/rokit-1.2.0-macos-x86_64.zip
   unzip -o rokit.zip
   ./rokit self-install
   ```
   On Windows, download `rokit-1.2.0-windows-x86_64.zip` from the
   [Rokit releases page](https://github.com/rojo-rbx/rokit/releases), unzip it and run
   `.\rokit.exe self-install`.

   If `rokit install` (step 2) also fails with 403, give Rokit a GitHub token so it isn't
   rate limited. Create one at <https://github.com/settings/tokens>; a classic token with
   no scopes ticked is enough. Then run `rokit authenticate github --token YOUR_TOKEN`.
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

## 3. Controls

The crosshair sits in the middle of the screen; every power aims at it. While you fly, fire
or cast, the camera moves over your right shoulder and, on PC, the mouse locks to the
middle of the screen so moving it steers. The mouse unlocks while the Districts panel or
the Roblox menu is open.

| Action | PC (keyboard + mouse) | Gamepad | Touch |
|---|---|---|---|
| Take off / land | **F** | **Y** | **Fly** button (reads **Land** while flying) |
| Fly | **W A S D**; the mouse steers, and W flies where you look | Left stick; the right stick turns the camera | Thumbstick; drag the right side of the screen to look |
| Climb / dive | **Space** / **Left Ctrl** or **C**. Holding dive near the ground lands. | **A** / **B** | **Up** / **Down** buttons (only while flying). The jump button also climbs. |
| Boost | Hold **Left Shift** | Click **L3** to switch it on, again to switch it off | **Boost** switches it on (it then reads **Cruise**) and off. It also ends after a moment without moving. |
| Energy beam | Hold **left mouse button** | Hold **R2** | Hold **Beam**; drag that finger to aim while firing |
| Shield bubble | **Q** (toggle) | **L2** (toggle) | **Shield** (toggle) |
| Cast the selected construct | **R** | **X** | **Cast** (labelled with the selected construct) |
| Choose a construct | **1** / **2** / **3** cast Wall / Hammer / Cage at once and select it | **R1** / **L1**: next / previous | **Swap**: next |
| Recharge at the ring battery | Hold **E** at the battery | Hold **D-pad Right** | Tap and hold the prompt |
| Districts panel | **M** | **D-pad Up** (**B** closes it) | **Map** |

Key bindings live in `src/shared/Config/Input.luau`; the touch button layout and its
measurements are described at the top of that file.

## 4. Testing Milestone 1

Press Play. The Output should show `[Server] [YOUR GAME NAME] 0.2.0 · Milestone 1` and
`[Server] Initialised services in … ms`, with no red errors. Do these checks in order.

| # | Do this | You should see |
|---|---------|----------------|
| 1 | Look at the bottom of the screen | The ring HUD: a **WILLPOWER** bar, **RING 100%**, and five slots (Beam, Shield, Wall, Hammer, Cage) with their keys. A green ring glows on your right hand. |
| 2 | From the spawn, walk east (to your right as you face up the highway) to the fenced **PRACTICE RANGE** | Five **Practice Targets**, each with a name and health bar, behind a white firing line. |
| 3 | **Fly.** Press F | A green burst at your feet, you lift off, the camera slides over your right shoulder and the crosshair appears. W flies where you look; within about 15° of the horizon you fly level. Turn hard and the body **banks** into the turn. Space and Ctrl climb and dive. A dive brakes into a skim just above the ground; holding Ctrl there lands. F lands anywhere. |
| 4 | **Boost.** Hold Shift while flying | Speed surges, the field of view widens, light streaks rush past the screen edges and your trails brighten. Willpower drains while boosting and starts refilling about 1 s after you let go. When willpower runs low the boost ends by itself (you keep flying). |
| 5 | **Beam.** Stand at the firing line and hold the left mouse button on a target | A green beam from your ring to the crosshair, sparks where it hits, damage numbers over the target, which rocks on its stand and loses health. Willpower drains while firing. A defeated target tips over, sinks into the ground, and a new one rises about 4 s later. |
| 6 | **Shield.** Press Q | A green bubble around you; willpower drains while it is up. Firing or casting now says *"You can't do that right now"*. Press Q again: the bubble drops and the Shield slot shows a short cooldown. |
| 7 | **Wall.** Press 1 aiming at the ground a few studs ahead | A glowing panel builds up from the ground, facing you, and blocks your path. It shatters after about 10 s. Casting again straight away says *"Wall is recharging"*. |
| 8 | **Hammer.** Press 2 aiming between two targets | A giant hammer swings down; a shockwave and dust; damage numbers on every target within its radius. |
| 9 | **Cage.** Press 3 aiming at a target | Bars snap shut around it for a few seconds and it barely rocks when hit. Aimed at empty ground: *"Nothing to trap there"*, and nothing is spent. |
| 10 | **Willpower.** Use powers back to back until the bar is nearly empty | Powers are refused with *"Not enough willpower"* (and a fizzle sound once one is set). Below the notch on the bar it dims: constructs are weaker there. Stop for a moment and it refills. |
| 11 | **Weaker constructs.** Hit a target with the hammer at full willpower, then drain willpower with the beam to just above 30 and hammer again | The first hit shows **70**; the weak one less (about 50). A weak wall also has less health (select `Workspace.Constructs.Wall` in the Explorer: its `MaxHealth` attribute is 300 at full strength) and vanishes sooner. |
| 12 | **Ring charge.** Every power wears the charge down slowly. For a quick test, set `ChargePerSecond = 10` under `Beam` in `src/shared/Config/Powers.luau` and fire the beam (pausing whenever willpower runs out) until the meter reaches 0. **Put the value back to 0.2 afterwards.** | At 20 %: *"Ring charge low…"*. At 0: *"Your ring has gone dark…"*, sparks and smoke from the ring as its light dies, you land if you were flying, every power says *"Out of ring charge"*, and the HUD meter turns red with *"Recharge at the Sheriff's Office"*. Charge is saved: stopping and playing again does not refill it. |
| 13 | **The oath.** Go to the Sheriff's Office (Downtown, north side of Center Street east of Main St), through to the back room, and hold E on **Recharge ring** at the glowing battery | You stop, face the battery and raise your ring. Letterbox bars slide in, the camera pushes in on a cinematic shot, the four oath lines appear one by one, and the charge meter fills over 8 s. It ends with a green flash, *"Ring fully charged."* and the HUD back. Willpower is full again too. |
| 14 | **Interrupted oath.** Start it again and reset your character (Esc → Reset Character) halfway | *"The oath was interrupted."* The charge filled so far is kept. After respawning, the camera, HUD and controls are back to normal. |
| 15 | **Clean respawn.** Fly with the shield up while firing, then reset | The new character walks normally: no leftover bubble, beam, trails or locked camera. |
| 16 | **Mobile.** Test tab → Device → pick a phone, then Play | Fly, Beam, Shield, Cast and Swap buttons sit bottom-right, left of the jump button. Up, Down and Boost appear while flying, Fly reads Land, Boost reads Cruise while on. Holding Beam and dragging aims. The compact HUD sits top-left. During the oath every button and the thumbstick hide, and come back afterwards. |
| 17 | **Gamepad.** Connect a real controller (Studio cannot emulate one) | The HUD shows controller glyphs. Y flies, R2 fires, L2 shields, X casts, R1/L1 swap, L3 toggles boost, A/B climb and dive. With the Districts panel open, B only closes it. D-pad Right recharges at the battery. |
| 18 | **Two players.** Test tab → Clients and Servers → 2 players | Each player sees the other's flight trails, beam, shield glow, constructs and the battery flare. |

## 5. Testing Milestone 0

Do these checks in order. The Output window should show `[WorldService] Built the blockout
map in … ms`, the game name and version from `Config/Game.luau`, and `[Server] Initialised
services in … ms`, with no red errors.

| # | Do this | You should see |
|---|---------|----------------|
| 1 | Press Play | You spawn at the **south end of the highway**, by the railroad. A **"Rail Yard"** banner appears and a welcome message: *"Welcome to Rushville…"* the first time, or *"Welcome back… Session N"* later. |
| 2 | Walk north up Main St to the crossroads | A **"Downtown"** banner, then the toast *"New area discovered: Downtown (2/7)"*. |
| 3 | Press **M** (keyboard), **D-pad Up** (controller), or tap the **Map** button (phone) | The **Districts panel**: discovered districts with a check mark, undiscovered ones as "???", your current one marked *You are here*, and "Discovered X / 7". Close it with M, B (controller) or the **Close** button. |
| 4 | Visit the Farmstead, North Fields, Elm & Oak, South Fields | Each one shows its banner and a discovery toast. The panel updates live. |
| 5 | Walk into the **Sheriff's Office** (door faces Center Street) | A front office with desks and a case board. Through the back doorway is the glowing green **ring battery**, where players recharge their ring (Milestone 1, test 13). |
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

## 6. The map

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
  **A map baked before Milestone 1 has no training yard** (and so no practice targets):
  rebuild it as below, or delete `Workspace.Map` so the game builds the current one.
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
│  └─ RailYard       Derelict Grain Elevator, south corn strips, rail siding, Training Yard
├─ OuterRing         Farmland, farmsteads and roads out to the edge of the world
├─ Zones             Invisible district volumes (one or more per district)
├─ Spawns            The main SpawnLocation + one respawn point per district
└─ MissionMarkers    Mission start markers (always streamed to every client)
```

While the game runs, the server also keeps `Workspace.Constructs` (every hard-light
construct) and `Workspace.TrainingDummies` (the practice targets); each client draws its
effects in `Workspace.RingEffects`.

**Replacing blockout parts with real models.**
- Every building, field and landmark is a `Model` tagged `Blockout`. Its `PrimaryPart` is an
  invisible `Footprint` box with the exact size and position from the build table. Line your
  real model up with the footprint, then delete the blockout model.
- Gameplay never looks things up by name. It uses tags, so keep these objects, or move their
  tags and attributes onto your replacements:
  - the parts in `Zones`, `Spawns` and `MissionMarkers`
  - the battery's `Core` part, tagged `RingBatterySpot`, in the Sheriff's Office
  - the invisible `TrainingDummySpot` parts in the Training Yard (a practice target stands
    on each one, facing its front)

  The tag and attribute names are in `src/shared/Util/Tags.luau`.

**Changes from the PDF:**
- The Farmhouse, Barn and silos moved 35 studs west, so the silos no longer run into the
  General Store.
- "Stewart Home" is now the **Calloway Home**, an original name.
- The Grain Elevator is the abandoned site for secrets.
- An outer ring of farmland extends the world to ±2,500 studs for flying room. Past the soft
  boundary, players are warned and pushed back.

## 7. Sounds and animations

Every power has sound and animation hooks in **`src/shared/Config/Assets.luau`**. They ship
empty, because audio and animations must be uploaded to (or owned by) your own account or
group before a game may use them. An empty entry is skipped silently, so nothing breaks
while they are blank.

To add one, upload it in Studio (or take one from the Creator Store), copy its asset id, and
paste it as `"rbxassetid://<id>"`:

```lua
Takeoff = "rbxassetid://1234567890",
```

| Hook | When it plays |
|---|---|
| Sounds: `Takeoff`, `FlightLoop`, `BoostStart`, `Land` | Taking off; looped while flying (its pitch rises with speed); a boost kicking in; landing |
| `BeamLoop`, `BeamImpact` | Looped while a beam fires; where it hits |
| `ShieldUp`, `ShieldDown` | The bubble rising and dropping |
| `WallSpawn`, `WallShatter`, `HammerSwing`, `HammerImpact`, `CageClose`, `CageRelease` | The constructs |
| `PowerRejected`, `RingDepleted` | A refused power (a short fizzle); the ring running out of charge |
| `OathChoir`, `OathComplete`, `BatteryFlare` | During the oath; when it completes (the reciting player); the battery flaring (everyone nearby) |
| Animations: `FlyIdle`, `FlyForward` | Looped while flying, blended by speed |
| `BeamPose`, `ConstructCast` | Arm raised while firing; a short gesture when casting |
| `OathPose` | The ring raised toward the battery. Without it, the server raises the arm by turning the shoulder joint. |

`SoundVolume` and the roll-off distances for 3D sounds are in the same file. Animations
must belong to the place's owner (you or your group) and suit the avatar type (R15 by
default).

## 8. Project layout & architecture

```
default.project.json   Rojo mapping (src/shared, src/server, src/client)
rokit.toml             pinned toolchain
scripts/check.sh       quality gate
tests/                 offline Lune tests (utilities + the map contract)
src/shared/            → ReplicatedStorage.Shared
  Config/              ALL tunable numbers and player-facing text
  Types.luau           shared types (save format, districts, input, powers)
  Net.luau             typed remote wrappers: validation + per-player rate limits
  Remotes.luau         EVERY client↔server message, declared once
  Util/                Signal, Validate, RateLimiter, Zones, Boundary, Tags
src/server/            → ServerScriptService.Server
  init.server.luau     starts services in order (Init, then Start)
  Services/            DataService, WorldService, ZoneService, SpawnService, BoundaryService,
                       RingService (willpower, charge, cooldowns), CombatService (targets,
                       damage), FlightService, PowerService (beam, shield, constructs),
                       BatteryService (the oath), DummyService (practice targets)
  Map/                 map data (MapLayout) and builders (incl. the Training Yard)
  Vendor/ProfileStore  session-locked saving (third-party, Apache-2.0)
src/client/            → StarterPlayerScripts.Client
  init.client.luau     starts controllers in order
  Controllers/         Hud, Input, Notification, Profile, Zone, DistrictsPanel, Boundary,
                       Camera (combat camera, aiming), Ring, Flight, Sound, VFX, Power,
                       RingHud, Oath
  VFX/                 effect builders: beams, one-shot effects, trails, hit numbers
  UI/                  small UI building helpers
```

**Rules the code follows**
- **The server is in charge.** Clients only send requests. The server checks every argument
  (`Util/Validate`) and rate-limits every remote per player (`Config/Net.luau`), and decides
  everything that matters: data, discovery, rewards. Too many malformed messages get the
  sender kicked.
- **Ring powers are server-authoritative.** The client takes off, draws its beam and
  refuses an obviously impossible power at once, for feel, but the server decides who may
  fly, what every power costs, what it hits, its cooldowns and what is saved
  (`RingService` is the one authority over willpower, charge and cooldowns). It mirrors
  that state to each player as attributes (`Util/Tags.luau`) that the HUD and effects read.
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

## 9. Quality checks

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
