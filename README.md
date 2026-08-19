# RNG: ARMORY

**Medieval co-op wave survival / village defense**, built in Roblox.

Hold a walled village against waves that come up the road from the wilds beyond
the gate. Fight on the ground, on the wall-walk and at the choke point; recover
between waves; go back out for the boss.

> ### This design is not locked
>
> The game is being built **iteratively**. Systems, enemies, wave structure,
> objectives, progression, map areas and bosses are all still being decided,
> and the direction has already changed once — the project began as an RNG
> equipment RPG, and much of what exists was built for that shape.
>
> **The latest instruction wins.** When something new is asked for, adapt the
> existing game around it rather than rebuilding. Keep what works. These
> documents describe the *current* state and the *current* direction, not a
> finished specification, and they are expected to change as the game does.

---

## Where the game stands

The **world is finished to a good standard** and reads as a defense map
already: one gate, a curtain wall you can stand on, and a hostile zone with a
road running out of it.

The **systems are the rough half**, and several were built for the original RNG
loop. They still work; how much of each survives the new direction is open.

| System | State |
|---|---|
| World | Walled village and a rebuilt hostile zone, both on voxel terrain. 14,174 parts, 223 light sources |
| Combat | 6 enemy types, aggro/chase/attack/leash AI, crits, modifier effects |
| Enemy spawning | Attribute-driven — any part with an `EnemyId` becomes a spawner |
| Data & saving | DataStore with session locking, retry/backoff, autosave, shutdown flush |
| RNG rolling | 39 items, 8 rarities, 10 modifiers, luck, pity, multiplier chains — all server-side |
| Inventory | Unlimited, stacking, 8 filters, search, equip/unequip, sell, lock, compare |
| Equipment | 7 slots, aggregate stats, Power, visible weapon models, auto-equip on upgrade |
| Atmosphere | Fog and ambient blended by player position, village vs wilds |
| Anti-exploit | Server decides every outcome; token-bucket limits on all remotes |

**Not built yet:** waves themselves, the boss fight, objectives, defenses,
progression, audio, monetization.

**Open questions the new direction raises**, none of them decided: rolling
probably works better as a between-wave reward than as the main activity; zone
travel and zone gates may not survive at all; the village needs somewhere for
players to actually stand and hold.

---

## The world

Everything sits under `Workspace.World`. Ground is voxel Terrain throughout;
structures, props and vegetation are Parts.

```
Village/                        9,910 parts   <- the thing you defend
  Fortifications/  2,941  the defensive line - see below
  Foliage/         2,896  trees, shrubs, ground cover, outer treeline
  Town/            1,699  tavern, general store, bakery, blacksmith, 7 houses
  Yards/             920  fenced plots, vegetable beds, clutter
  Castle/            538  bailey, gatehouse, keep with corner turrets
  Lamps/             304  16 lantern posts along the paved ways
  Market/            266  six stalls ringing the well
  Outbuildings/      213  stable, barn, woodshed, granary
  Plaza/             132  the well, with a lantern on its roof ridge
  VillageSpawn            hidden spawn behind the well
  _WallLine  _WallTowers  _WallGate    the wall geometry - do not delete
  _PathRoutes  _PathMask  the ONLY record of the road network - do not delete

StarterZone/                    4,264 parts   <- where they come from
  Vegetation/      2,204  forest by chapter, dead trees on the battlefield
  Structures/      1,215  goblin camp and outpost, 3 watchtowers, battlefield
                          trench works and ruins, slime pond, boss arena,
                          the gate to Zone 2
  Props/             739  boulders, fallen logs, stumps
  Lights/            165  21 torch posts, 4 junction cairns, glowing fungus
  EnemySpawns/        14  attribute-driven markers
```

14,174 parts in the world, 223 light sources, roughly 489,000 voxel cells.

---

## The walls, and getting onto them

Rebuilt from scratch for players to fight from — the previous walls were
scenery you could only look at.

```
Fortifications/     2,941 parts
  Towers/           1,100   9 drum towers, each open through at walk level
  Curtain/            783   62 bays, walk at y = 28.8, merlons to 34.4
  WallStairs/         483   7 flights up from inside the village
  Gatehouse/          311   twin-tower gate, barrel-vaulted passage
  WallLighting/       199   62 wall torches and tower beacons
  Guardhouse/          65   kept from the earlier build
```

The circuit is continuous: every tower carries a `Tower_WalkFloor` through it
at walk height, so a player can run the full 1,907-stud perimeter without
dropping off. Each tower also has an internal stair up to its deck.

**The wall line is stored, not derived.** `_WallLine` holds 62 ordered joint
points, `_WallTowers` the 9 tower centres, `_WallGate` the gate. Anything that
attaches to the wall must read these — the wall is a curve, and treating it as
a circle or a rectangle has broken geometry repeatedly.

Stair spec, if you rebuild them: 22 treads, 2.6 run, 1.30 rise (27°), 8.0
studs of clear walking width, offset 8.7 studs inboard of the wall line, rail
outboard of the treads at 13.5. Flights are placed by bearing roughly every
51°, clear of every tower, the gatehouse and the castle.

---

## Zone 1 — the wilds

Rebuilt from scratch on voxel Terrain. It runs south from the gate to
`z = -500`, and it is the natural source of any attack on the village.

| | |
|---|---|
| Perimeter | Rock cliffs, tall on the west, a ravine on the east flank, a ridge closing the south — the world is sealed all round |
| Route network | A walkable spine from the gate to the arena, plus spurs to each combat space. **Nothing steeper than 26°** |
| Goblin territory | Palisaded camp and a smaller outpost on a raised plateau, with watchtowers |
| Battlefield | Scarred ground, 14 craters, 4 trenches with boarded revetments and firing steps, ruins, an abandoned siege engine |
| Slime hollow | A single slime pond filling the sunken ground, shoreline cut by the terrain contour |
| Boss arena | A bowl with a 12-pillar ring, braziers and the Goblin King's dais |
| Zone 2 gate | Ruined coursed masonry set into the south ridge, carrying `RequiresPower = 1200` |

Spawn markers: **Slime x4, Goblin x3, Wolf x3, GoblinWarrior x2,
EliteGoblin x1**, plus a `BossSpawn` carrying `BossId = "GoblinKing"`.

Verified on completion: zero holes over 5,625 samples, zero floating parts,
every `EnemyId` resolving in `EnemyConfig`.

---

## The ground, the roads and the grass

**Ground is voxel Terrain everywhere, and so are the roads.** The old
`Ground_Pasture` Part disc and the 763-part `Paths` folder are both gone. Roads
are painted into the terrain as `Cobblestone`, dirt lanes as
`Sandstone`/`Ground`. That makes z-fighting structurally impossible — there is
no second surface to fight with.

Village terrain is held **dead flat at `y = 0.10`** under every part that meets
the ground, using a mask built from their real footprints; hills appear only in
the open ring between the town and the curtain wall.

**Only `Grass` and `LeafyGrass` grow blades**, so everywhere people walk is
painted bare on purpose. Roughly 70% of the village floor is green, 27% trodden
earth, 3% paved.

`_PathRoutes` and `_PathMask` on the Village folder are the only surviving
record of the road network. **Do not delete them.** `_PathRoutes` is
`kind|width|name|x,z;x,z;...` where `C` is a cobbled way and `D` a dirt lane —
and the `Market` entry is stored with **width 0**, which silently paints
nothing unless you substitute a real width.

---

## Lighting and air

**Lighting is fixed at dusk** (`ClockTime 18.1`). There are 223 light sources:
window glow, 16 village lantern posts, the well lantern, 62 wall torches, tower
beacons, gate braziers, and in the zone 21 torch posts, 4 junction cairns, camp
fires, arena braziers and glowing fungus.

**Fog is not static.** `AtmosphereController` blends fog and ambient by player
position across `BoundaryZ = -10`, so the wilds read heavier than the village.
Tune `AtmosphereConfig`, never `Lighting` directly.

Two traps documented in that config: an `Atmosphere` object **overrides legacy
`FogStart`/`FogEnd` entirely**, and the controller adopts an existing
`Atmosphere` rather than adding a second, because two of them fight.

The Wilds profile was retuned after measurement. The authored
`Density 0.72 / Offset 0.40` hid everything past about 40 studs, which would
have made enemies invisible at `CombatController`'s 95-stud reach. It is now
`0.62 / 0.10` — `Offset` is the dial that pulls fog toward the camera, so
lowering it buys back the near field while keeping distance thick.

---

## The world lives in the cloud, not in the repo

**Read this before you go looking for a save button.**

This is a **Team Create place** (place `76196845987264`, group-owned). Both
collaborators edit the same live `Workspace` and see each other's changes
immediately. Roblox holds the version history, and every earlier version is
recoverable from the Creator Dashboard or File → Open from Roblox. **That is
the first resort if the world is destroyed**, not the repo.

`RNGArmory.rbxl` here is a **backup snapshot**, not the source of truth and not
a sync mechanism. Refresh it before anything destructive, around a large
structural job, and at milestones — **not after every world change**.

To refresh: File → **Download a Copy** (a cloud-opened place has no "Save to
File As"), overwrite `RNGArmory.rbxl`, commit. The file is binary: it restores
perfectly, does not diff, and cannot be merged.

`tools/BuildWorld.luau` is legacy and would destroy the current world; it
carries a warning banner. `tools/RestoreGround.luau` is its safe counterpart —
it only adds missing floors and never wipes.

---

## Architecture in short

The server decides everything that matters — RNG, currency, inventory, damage,
rewards. The client requests and displays; it never determines an outcome.
Anything a designer might reasonably want to tune lives in
`src/shared/Config/`, not in gameplay code. Full detail in [CLAUDE.md](CLAUDE.md).

```
src/shared/   -> ReplicatedStorage      10 configs, shared modules, remote manifest
src/server/   -> ServerScriptService    8 services
src/client/   -> StarterPlayerScripts   7 controllers
tools/        -> not synced             one-off world scripts
RNGArmory.rbxl                          backup snapshot of the world
```

**The world and the combat system meet at exactly one place: attributes.**
`EnemyService` walks every descendant of `Workspace.World` and spawns from any
`BasePart` carrying an `EnemyId` string attribute, reading `MaxAlive` and
`Radius` alongside it. Nothing is matched by name and no folder path is
hardcoded — so a zone can be torn down and rebuilt freely, and **wave spawners
are a change to *when* it spawns rather than *how***. A typo'd `EnemyId` fails
silently. See CLAUDE.md, "The enemy spawn contract".

---

## Setting up a machine

One-time. Windows instructions; macOS differs where noted.

### 1. Clone

```bash
git clone https://github.com/cinnamon73/Rojo-.git
```

### 2. Install the toolchain

Install [Rokit](https://github.com/rojo-rbx/rokit/releases), then from the
project folder:

```bash
rokit install
```

That reads `rokit.toml` and installs the pinned Rojo version (7.7.0). If it
refuses because the tool is untrusted, run `rokit trust rojo-rbx/rojo` first.

### 3. Install the Rojo Studio plugin

In Studio: **Toolbox → Creator Store → Plugins → search Rojo → Install**
(publisher `rojo-rbx`).

Do **not** use `rojo plugin install`. It looks up a
`HKCU\Software\Roblox\RobloxStudio\ContentFolder` registry value that current
Studio builds no longer write, and fails with a misleading "Roblox might not be
installed".

### 4. Enable Studio as an MCP server

In Studio: **Assistant → … → Manage MCP Servers → Enable Studio as MCP server**.

`.mcp.json` already points Claude Code at the launcher via
`%LOCALAPPDATA%\Roblox\mcp.bat`, so Windows machines need no further config —
just restart Claude Code so it picks the server up. On macOS the path is
`/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP` and `.mcp.json` needs
editing to match.

### 5. Open the world

Open the Team Create place from Studio's home screen. `RNGArmory.rbxl` in this
folder is only a backup snapshot — see "The world lives in the cloud" above.

### 6. Sync and play

Run this from the project folder — Rokit resolves the tool from `rokit.toml`,
so it fails from anywhere else:

```bash
rojo serve
```

Click **Connect** in the Rojo panel, then press Play.

---

## Daily workflow

```bash
git pull
```

…work…

World edits need no step here — the place is Team Create and your geometry is
already shared and already versioned by Roblox. Refresh `RNGArmory.rbxl` only
at a milestone or before something destructive.

```bash
git add -A && git commit -m "what changed" && git push
```

**Pull before you start and push when you finish.** Two people work on this repo
and git will not merge Studio's world for you — but it does not have to, because
the world does not live here.

**Only one person can Rojo-sync at a time.** The plugin claims a lock at
`ServerStorage.__Rojo_SessionLock`; if the other side holds it you get *"Could
not sync because user 'X' is already syncing"*. Delete that ObjectValue and
press Connect to take it over. It does not remove anyone from Team Create.

---

## Manual steps still outstanding

These cannot be done from code. Nothing breaks without them — the affected
features stay inert rather than erroring — but they are required before launch.

- [ ] **Set `Lighting.Technology` to `Future`** in Properties. Scripts cannot
      set it; it needs elevated permission, and the command bar cannot even
      read it. Until it is set, all **223** light sources glow but do not
      properly light the surfaces around them. This is the single biggest
      visual win available and takes one click.
- [ ] **Enable Studio Access to API Services** — Game Settings → Security.
      Without it every DataStore call fails.
- [ ] **Create gamepasses and developer products** on the Creator Dashboard and
      paste their ids into `src/shared/Config/MonetizationConfig.luau`. Every id
      is `0` today, which reads as inactive — nothing is granted, nothing errors.
- [ ] **Upload audio and icons**, then fill in
      `src/shared/Config/AssetConfig.luau`. Ids of `0` make the helpers return
      `nil` and callers no-op, so the game is silent rather than broken.

---

## Troubleshooting

**Rojo says it cannot find the tool.** You are not in the project folder. Rokit
resolves tools from `rokit.toml`, so it must be run from here.

**Rojo connects but changes never appear.** Check Plugins → Manage Plugins →
Rojo has script injection permission. Denying it silently blocks updates to
*existing* scripts while still allowing new ones, which presents as a partial
sync rather than an error.

**"Could not load your save data" on every rejoin in Studio.** A stale session
lock. Studio uses a stable job id and a 20-second lock timeout so this should
clear itself within a minute; if it persists the DataStore is genuinely
unreachable.

**Enemies spawn but never move.** They only step while at least one player is in
the server, and they leash back to their marker if pulled too far.

**The village looks flat and washed out.** `Lighting.Technology` is not set to
`Future`. See the manual steps above.

**Play-testing a change did nothing.** Rojo syncs to the Edit datamodel. A play
session started before the sync landed is running the old code — stop, confirm
the change is in Edit, and start again.
