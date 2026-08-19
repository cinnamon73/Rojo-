# RNG: ARMORY

A Roblox RPG built around an RNG equipment system.

> Roll for equipment → Equip better gear → Fight enemies → Earn currency →
> Upgrade → Unlock new zones → Better loot → Repeat

**Status: playable vertical slice in a finished-looking world.** The full loop
runs end to end — roll, reveal, equip, walk out of the village, fight, earn XP
and coins, level up, roll better. The systems are unpolished; the world is not.
[ROADMAP.md](ROADMAP.md) has what is left.

---

## What works today

| System | State |
|---|---|
| Data & saving | DataStore with session locking, retry/backoff, autosave, shutdown flush |
| RNG rolling | 39 items, 8 rarities, 10 modifiers, luck, pity — all server-side |
| Roll reveal | Decelerating reel, rarity-tiered presentation, auto-roll with stop condition |
| Inventory | Grid, 8 filters, search, equip/unequip, sell, lock, stat comparison |
| Equipment | 7 slots, aggregate stats, Power, visible weapon models |
| Combat | 6 enemy types, aggro/chase/attack/leash AI, crits, modifier effects |
| World | Walled village with castle, market, 11 buildings, lit at dusk. ~14,000 parts. Zone 1 awaiting rebuild |
| Characters | Standard R15 body for everyone; head, face, hair and accessories preserved |
| Anti-exploit | Server decides every outcome; token-bucket limits on all remotes |

**Not built yet:** the boss, quests, daily rewards, shop, monetization, audio.

---

## The world

Everything sits under `Workspace.World`.

```
Village/
  Fortifications/   curtain wall (62 bays), 9 drum watch towers, gatehouse,
                    gate hoardings, 62 wall torches, gate lighting
  Castle/           bailey, gatehouse, keep with corner turrets, inner ward
  Town/             tavern, general store, bakery, blacksmith, 7 houses
  Outbuildings/     stable, barn, woodshed, granary along the gate road
  Market/           six stalls ringing the well
  Paths/            organic cobbled ways and dirt tracks, one flat surface
  Yards/            fenced plots, vegetable beds and clutter per building
  Foliage/          141 trees, 233 shrubs, ground cover
  Lamps/            13 lantern posts
StarterZone/        hunting grounds, slime pit, goblin camps, boss arena
                    — being rebuilt from scratch, see ROADMAP Phase 5b
```

**Zone 1 is the next big job.** `StarterZone` was built in an early pass and
never got the village treatment, so it is visibly the roughest part of the
game — and it is where players spend their combat time. The rebuild puts it on
**Roblox voxel Terrain** for genuine hills, ravines and craters, the first use
of Terrain in this project; structures, props and vegetation stay as Parts. The
village is read-only while that work runs. ROADMAP Phase 5b carries the layout,
the ~6,000 part budget and the five review checkpoints.

**The path system is a single flat surface.** Every path tile sits at exactly
`y = 0.30` with no overlaps, which is what makes z-fighting structurally
impossible rather than something to keep suppressing. If you edit paths, keep
that invariant — vary colour and material, never height.

**Lighting is fixed at dusk** (`ClockTime 18.1`) with atmosphere, bloom and a
warm shift. There are ~190 light sources: window glow, lanterns, wall torches,
tower beacons and gate braziers. Arrow loops glow but deliberately cast no
light — there are 169 of them and lighting them all would wreck performance.

---

## The world lives in the cloud, not in the repo

**Read this before you go looking for a save button.**

This is a **Team Create place** on Roblox's cloud (place `76196845987264`,
owned by a group). Both collaborators are in the same edit session and see the
same `Workspace`. World edits propagate immediately — there is nothing to sync
by hand, nothing to merge, and no way for your geometry to be stranded on your
own machine.

Roblox keeps the version history. The place is on **version 125** at the time
of writing, and every earlier version is recoverable from the Creator Dashboard
or File → Open from Roblox. **That is the first resort if something destroys
the world**, not the repo.

### So what is `RNGArmory.rbxl` for?

A **backup snapshot**, and nothing more. It is a restore point pinned to a
commit, so a given revision of the code can be paired with the world that
matched it. It is not how the world is shared and it is not the source of
truth.

Refresh it when a snapshot is actually worth having:

- before running anything destructive — `tools/BuildWorld.luau` would wipe the
  world outright
- before and after a large structural job, such as the Phase 5b Zone 1 rebuild
- at a milestone worth being able to return to

There is no need to re-save it after every prop you move. Earlier revisions of
this document said there was; that was wrong, and it was written before anyone
checked whether the place was Team Create.

To refresh it: **File → Download a Copy** (a cloud-opened place has no "Save to
File As"), overwrite `RNGArmory.rbxl` in this repo folder, commit. The file is
binary — it restores perfectly but does not diff, and two snapshots of the same
world cannot be merged. That is fine for a backup and is the reason it is not
used for collaboration.

`tools/BuildWorld.luau` is kept only as a record of the *original* village. It
carries a warning banner. Do not run it — it would destroy the current world.
`tools/RestoreGround.luau` is its safe counterpart: it only adds missing
floors and never wipes, so it is safe to run twice.

---

## Architecture in short

The server decides everything that matters — RNG, currency, inventory, damage,
rewards. The client requests and displays; it never determines an outcome.
Anything a designer might reasonably want to tune lives in
`src/shared/Config/`, not in gameplay code. Full detail in [CLAUDE.md](CLAUDE.md).

```
src/shared/   → ReplicatedStorage      config, shared modules, remote manifest
src/server/   → ServerScriptService    authoritative game systems
src/client/   → StarterPlayerScripts   UI and input
tools/        → not synced             one-off scripts
RNGArmory.rbxl                         the world (Workspace geometry)
```

**The world and the combat system meet at exactly one place: attributes.**
`EnemyService` walks every descendant of `Workspace.World` and spawns from any
`BasePart` carrying an `EnemyId` string attribute, reading `MaxAlive` and
`Radius` alongside it. Nothing is matched by name and no folder path is
hardcoded — which means a zone can be torn down and rebuilt freely, but a
typo'd `EnemyId` fails silently. See CLAUDE.md, "The enemy spawn contract".

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

Open **`RNGArmory.rbxl`** from this folder in Studio. That is the world.

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
      read it. Until it is set, the ~190 light sources glow but do not properly
      light the surfaces around them. This is the single biggest visual win
      available and takes one click.
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
