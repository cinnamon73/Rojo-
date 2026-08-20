# RNG: ARMORY — project context

Read this before making changes. It is written for Claude Code instances
working on this repo, and there are **two of us** — one per collaborator.
Coordination rules are at the bottom and they matter more than anything else
here.

## The direction, and how to treat it

**Medieval co-op wave survival / village defense.** Hold a walled village
against waves coming up the road from the wilds beyond the gate.

**This is not a locked design, and you must not treat it as one.** The project
began as an RNG equipment RPG and much of what exists was built for that shape.
The direction changed. It may change again.

Working rules, in priority order:

1. **Build what is asked for.** Not the adjacent thing you think would be
   better, and not a larger version of it.
2. **Keep what already works.** Preserve existing systems and geometry unless
   told explicitly to change or remove them.
3. **Adapt rather than rebuild.** A new feature means the smallest set of
   changes that makes it work while everything else keeps running. Do not tear
   down large parts of the game to accommodate an addition.
4. **The latest instruction wins.** When a new decision contradicts something
   written here, the new decision is right and this document is stale — update
   it.
5. **Small design calls are yours.** Quality, flow, performance, visuals,
   organisation. Suggest bigger ideas; do not implement them unasked.
6. **Keep the docs honest.** README, ROADMAP and this file are expected to
   change as the game does. They describe the current state, not a spec.

### What the pivot means for existing systems

Nothing below is decided. Recorded so neither instance assumes:

- **Rolling is GONE.** Both collaborators decided to remove it rather than
  demote it. RNGService, MultiplierConfig, RarityConfig, ItemConfig,
  ItemInstance, ModifierConfig, EquipmentService and the four roll/gear
  controllers are deleted. Do not reintroduce them — if a reward economy is
  wanted, design one for waves rather than restoring the old one.
- **Zone travel and zone gates** may not survive at all.
- **The village** has no defensive positions designed as such yet — the
  wall-walk exists, but nothing is placed for players to hold.
- **`EnemyService` already suits waves.** It is attribute-driven, so wave
  spawning is a change to *when* it spawns, not *how*.

## How code reaches the game

Two independent channels. Know which one you are using.

| Channel | Covers | How |
|---|---|---|
| **Rojo** | `ReplicatedStorage`, `ServerScriptService`, `StarterPlayerScripts` | Edit files in `src/`. `rojo serve` pushes to Studio. |
| **Studio MCP** | Everything else — `Workspace` geometry, live inspection, running Luau | `mcp__Roblox_Studio__*` tools against the live session |

**Rojo is authoritative for `src/`.** Anything you write into those three
services *inside Studio* gets overwritten on the next sync. Put Luau in `src/`.

**Workspace is NOT managed by Rojo, and it is NOT delivered by the repo.** This
is a **Team Create cloud place**. Both collaborators edit the same live
`Workspace` and see each other's changes immediately. Roblox holds the version
history — recoverable from the Creator Dashboard or File → Open from Roblox.
**That is the first resort if the world gets destroyed.**

`RNGArmory.rbxl` is a **backup snapshot**, not the source of truth. Refresh it
before anything destructive, around large structural jobs, and at milestones —
not after every change. File → **Download a Copy**, overwrite, commit. Binary:
restores perfectly, does not diff, cannot be merged.

[`tools/BuildWorld.luau`](tools/BuildWorld.luau) is legacy and would destroy the
current world. [`tools/RestoreGround.luau`](tools/RestoreGround.luau) only adds
missing floors and never wipes.

## The world as it stands

`Workspace.World` holds `Village` (9,758 parts) and `StarterZone` (4,583).
14,341 parts and 227 light sources in total; terrain is ~489,000 voxel cells.

**The fortifications were rebuilt from scratch for players to fight from**
(2,789 parts): 62 curtain bays with the walk at `y = 28.8` and merlons to
`34.4`, 9 drum towers open through at walk level, a twin-tower gatehouse, and
**7 stair flights** up from inside the village. The circuit is continuous — a
`Tower_WalkFloor` carries the walk through every tower, so the full 1,907-stud
perimeter is runnable.

**The wall geometry is stored on the Village folder, not derived.** `_WallLine`
(62 ordered joints), `_WallTowers` (9 centres), `_WallGate`. Anything attaching
to the wall must read them. Two warnings from experience: these StringValues
have been reverted by the other session mid-task, so **re-check `_WallTowers`
actually holds corrected values before trusting it**, and the wall is a *curve* —
treating it as a circle or a rectangle has broken geometry repeatedly.

**Ground is voxel Terrain everywhere, and so are the roads.** The old
`Ground_Pasture` Part disc and the 763-part `Paths` folder are both gone. Roads
are `Cobblestone` painted into terrain, dirt lanes `Sandstone`/`Ground`. That
makes z-fighting structurally impossible — there is no second surface.

Village terrain is **dead flat at `y = 0.10`** under every part that meets the
ground, held by a mask built from their real footprints. Hills only in the open
ring between town and curtain wall. **Rebuild that mask from live geometry
before re-sculpting**, or buildings end up on hillsides.

**`_PathRoutes` and `_PathMask` on the Village folder are the only record of the
road network.** The tiles they generated are deleted. Do not remove them.
Format is `kind|width|name|x,z;x,z;...`, `C` cobbled and `D` dirt — and the
`Market` entry is stored with **width 0**, which silently paints nothing unless
you substitute a real width.

**Zone 1 is complete.** Terrain landforms, a route network (nothing steeper than
26°), goblin camps and watchtowers, a scarred battlefield with trench works, a
slime pond, the boss arena, the Zone 2 gate, forest by chapter, and torch-post
lighting along the routes.

## Classes replaced equipment

A player's power is one string: `profile.Class`. There is no inventory, no
equipment slots, no rarity and no item instances. A class IS the loadout.

`ClassConfig` holds eight definitions — stats, weapon archetype and tint, one
ability, and an unlock gate. `ClassService` owns selection and pushes stats onto
the character. Anything that used to ask "what is this player wearing?" now asks
`ClassService.GetStats(profile)`, which returns the same shaped table
`EquipmentService.GetAggregateStats` did, so `CombatService`'s damage roll was
left alone.

| Tier | Classes |
|---|---|
| 1 | Archer, Swordsman |
| 2 | Berserker, Musketeer, Assassin |
| 3 | Paladin, Necromancer |
| Paid | King (gamepass) |

**There is no levelling and no unlock ladder.** Tiers are labels describing
complexity; every class is free except the King. Kills pay coins only —
`Progression`'s XP functions still exist but nothing calls them, and the HUD
shows a single coins pill.

**JOINING IS A MENU, AND SPAWNING IS EXPLICIT.** `ClassService.Start` sets
`Players.CharacterAutoLoads = false`. A joining player gets no character; the
client shows the full-screen class menu (banner + mannequin per class) and the
first `ClassSelectRequest` is what calls `LoadCharacter`. Consequences that
will bite anyone who forgets:

- **Nothing spawns players except ClassService.** A test script that waits for
  `player.Character` after join will wait forever unless a class is picked.
- **Respawn is manual too.** Auto-load off disables automatic respawn;
  ClassService's `Died` hook reinstates it (same class, no menu, 5s delay).
  Remove that hook and every death is permanent.

Things worth knowing before editing any of it:

- **Selection applies on the NEXT spawn**, never immediately. Re-statting a live
  character mid-wave desyncs its health bar, and swapping to Berserker to dodge
  a killing blow would be free.
- **`ApplyToCharacter` preserves the health RATIO.** Setting Health to MaxHealth
  on a stat refresh would be a free full heal — an exploit during a wave.
- **`ClassService.OwnsGamepass` returns false while unconfigured**, so King is
  unreachable until `MonetizationConfig` has real ids. That is correct, not a
  bug: an unconfigured pass should lock a class, not hand it out.
- **`ClassConfig.IsUnlocked(definition, ownsGamepass)`** — two arguments now.
  The old profile/level parameter is gone with the unlock ladder.
- **`CharacterService` does not know classes exist.** It fires `CharacterReady`
  and `ClassService` listens. Going the other way closes a require cycle,
  because `ClassService` already depends on `CharacterService`.
- **Weapon appearance comes from the class.** `WeaponModels.Build` now takes
  `(archetype, colour, material, name)` rather than an item instance.
- **Balance is unproven.** The numbers in `ClassConfig` have never been played.
  One deliberate departure from the brief is recorded in its header: Berserker's
  undying is on a 45s cooldown, not the "medium" it was specified as, because
  10s of immortality on a medium timer is over 50% uptime.

Abilities are **defined but not implemented** — `AbilityService` does not exist
yet. `AbilityRequest` is declared in the manifest and unhandled.

## The enemy spawn contract

This matters more than it looks: it is the only link between world geometry and
the combat system, and it is entirely attribute-driven.

`EnemyService.populate()` walks **every descendant of `Workspace.World`** and
picks up any `BasePart` carrying an `EnemyId` string attribute. Nothing is
matched by name, and no folder path is hardcoded.

| Attribute | Meaning |
|---|---|
| `EnemyId` | Required, string. Must match an id in `EnemyConfig`. |
| `MaxAlive` | How many live at this marker at once. Defaults to `2`. |
| `Radius` | Scatter radius around the marker. |

Three consequences:

- **Deleting and rebuilding a zone breaks nothing**, provided new markers carry
  the same attributes.
- **Wave spawning is a change to *when*, not *how*.** The discovery mechanism
  already does what a wave system needs.
- **A marker with a typo'd `EnemyId` fails silently.** `EnemyConfig.Get`
  returns nil and the marker is skipped with no warning.

Defined ids: `Slime`, `Goblin`, `Wolf`, `GoblinWarrior`, `EliteGoblin`,
`GoblinKing`. The boss marker is `BossSpawn` and carries `BossId`.

## Terrain, geometry and testing lessons

### Live-testing the game from the Studio command bar

Hard-won, all three verified this session:

- **The command bar has its OWN module cache.** `require`ing a server module
  from it during Play gives a FRESH instance whose internal state is empty —
  DataService.Get returns nil for loaded players, Select fails with
  ProfileNotLoaded. To exercise real systems, fire the real remotes from the
  CLIENT context instead: `Remotes.X:InvokeServer(...)` goes through NetGuard
  into the server's actual module instances.
- **The client/server toggle** (the monitor icon beside Stop) switches which
  context the command bar executes in. The Output's "All Contexts" dropdown is
  only a display filter.
- **An effect that exists is not an effect that reads.** Part-count polling
  proved VFX spawning and replicating while four consecutive screenshots showed
  nothing: 0.28-0.45s lifetimes are sub-perceptual in normal play. When
  something "does not work" visually, first check whether it is absent or
  merely too fast — the fixes are entirely different.


Every one of these cost real bugs. Several cost the same bug twice.

### Terrain

- **Occupancy is measured from the voxel CENTRE, not its bottom.**
  `occ = (h - voxelCentreY) / 4` puts the surface at `h`. The intuitive
  `(h - voxelBottom) / 4` puts it **exactly 2 studs too high, everywhere** —
  and because the error is uniform the terrain still looks plausible. It was
  only caught when village parts pinned at `y = 0.10` came out floating.
  Calibrate against a test strip rather than reasoning about it.
- **Raycasts do not see voxels written earlier in the same script.** Verify
  terrain in a *separate* call or every probe reports the pre-write state. This
  produced two phantom bug reports, including 41 imaginary holes.
- **Repeated carve passes drift.** Sampling "the surrounding ground" as a
  reference re-reads terrain a previous pass already lowered, so each run digs
  deeper. Derive carve depths from a deterministic height function, not from
  the current surface.
- **Only `Grass` and `LeafyGrass` grow blades.** Painting either under paving or
  against a wall pushes grass through it. Anywhere people walk is painted bare
  on purpose.
- **Terrain is not a `Part`** — it cannot be `Anchored` or `CastShadow`, the
  sole exception to that rule. **`Terrain.WaterColor` is global**, so terrain
  water cannot be slime-green in one place and blue in another.
- **A liquid surface should be a flat plane wider than its basin.** Let the
  terrain contour occlude it — that gives an organic shoreline for free. Do not
  try to match the outline with the part.

### Geometry

- **Pitched roofs — and stair rails, and every other sloped slab.** A slab at
  `z = s * run/2` takes rotation `s * pitch`, not `-s * pitch`.
  `CFrame.Angles(φ,0,0)` maps local Z to `(0, -sin φ, cos φ)`. Built off
  `CFrame.lookAt(p, p + ascentDirection)`, a rail wants **`+pitch`**. All eight
  stair rails went in inverted and crossed their own flights like an X — and it
  only showed from a 3/4 view, not from the side.
- **A long assembly following the curtain wall must be built on the wall's arc
  length, not on a chord.** Each stair flight is 57 studs; built along one
  segment's direction it splayed up to 12 studs away from the wall it was
  supposed to hug. Walk `_WallLine` by arc length and take the position and
  frame from the line at each step. Rebuilt that way the centreline holds to
  0.22 studs.
- **A polyline's tangent jumps at every joint — smooth it.** Taking the raw
  segment tangent gave a **15.6° yaw jump between two consecutive treads**, and
  the advance along the flight collapsed from 2.6 studs to 0.18, bunching the
  steps into a visible kink. Average the tangent over a window
  (`(posAt(s+9) - posAt(s-9)).Unit`) and the worst jump falls to 1.34°.
- **Rails, newels and copings belong OUTSIDE the walking strip.** Put them at
  `inset + width/2 + thickness/2`, never inside the tread width — a rail set
  1.6 studs into a 7-stud stair leaves 5.4, and a newel dropped on the
  centreline blocks the entrance outright. Also remember **the curtain's own
  plinth projects inward** and ate the inner 1.8 studs of the lower steps.
- **Alternating colours across many small parts reads as a glitch.** Twenty
  steps cycling four greys looked like corduroy / z-fighting. One stone colour
  with a thin lighter nosing on each tread reads as masonry.
- **Cylinders lie along local X.** A `Cylinder` needs a 90° roll about Z to
  stand upright. This is also how you make a flat disc.
- **Recovering a yaw from a LookVector is `atan2(-L.X, -L.Z)`**, not
  `atan2(L.X, L.Z)`. **For a part whose LENGTH runs along local X, spanning two
  points, the yaw is `atan2(-dz, dx)`.** Getting this wrong has now spun a
  building backwards twice and thrown a gateway lintel out sideways once.
- **Build assemblies as chains, not from a common origin.** Place each piece
  from the endpoint of the one it attaches to. Rotating a part moves its ends,
  so offsets guessed before the rotation never meet after it.
- **Rings of blocks on an arc need a depth stagger.** Voussoirs rotated about Z
  keep their faces parallel, so every block lands on one plane and they z-fight
  however narrow you make them. Size from measured neighbour spacing AND offset
  alternate blocks along their own normal.
- **Arches must spring from the measured top of their piers.** Guessing the
  spring height buries most of the arch and leaves a scattered row of stones.
- **Roof extents are not wall extents.** Roofs overhang by 8–13 studs here.
  Carving ground from a building's full extent deletes the paving its own door
  opens onto. Use the plinth.
- **Props positioned relative to a plinth top will float** if they stand off the
  plinth. Fixed three separate times.
- **Never move one member of an assembly on its own.** Shifting individual
  `Tower_Leg` parts out of a route corridor pulled the legs out from under their
  own deck. Move the whole thing or move nothing.
- **`Glass` takes its colour from the skybox.** It rendered green slime as blue
  water. Use `SmoothPlastic` with transparency when the colour must hold.

### Tests that lie

Eight separate false positives this project, and one of them was acted on and
broke working geometry. Assume your check is wrong before you assume the world
is.

- **A support test must use WORLD extents, not the part's own `Size`.** A
  rotated part's length may run along a different axis than `Size.X`. A search
  box built from local size missed both gate posts and reported a correctly
  built lintel as floating — which was then "fixed" by dropping it to the
  ground.
- **A floating test must measure the piece that touches the ground.** Testing
  every foliage part reported 869 of 1,010 tree parts as floating, because
  canopies are *meant* to be in the air. Testing trunks gave 0. Equally, the
  test must accept ground support — raycast down before flagging.
- **Rays that start inside geometry return nothing.** A downward ray from a part
  already embedded in its support reports no support. Use a volume query.
- **Coplanar-overlap tests over-report.** They count masses meeting flush inside
  a wall and treat a rolled cylinder as a box. Check a screenshot before acting
  on a large count.
- **A corridor-clearance probe counts the surfaces that define the corridor.**
  Sweeping an 8-stud stair with a 1.4-wide box reported 827 intrusions — every
  one was the box overlapping the wall face or the rail by about a tenth of a
  stud at the very edge of the span. Inset the probe, or measure the gap
  between the two bounding surfaces instead of hit-testing it.
- **A walkable-surface probe must stop at the end of the surface.** Sampling
  past the top landing reported a "25.8-stud jump" that was just the ray
  reaching the ground beyond the structure. Bound the sweep to the thing you
  are testing.
- **A staircase's own ascending mass reads as an obstruction** to any headroom
  check that looks forward and up. Exclude the flight's own steps.
- **`math.noise` can return outside ±0.5.** Using it as a 0–1 roll without
  clamping overflows array indices.

**Screenshot at player eye height before trusting any geometry change.** A
top-down view has hidden almost every bug above.

## Lighting and atmosphere

`Lighting` is fixed at dusk (`ClockTime 18.1`) in the Edit datamodel — that is
what the place saves. **`AtmosphereController` applies profiles at runtime**,
blending fog and ambient by player position across `AtmosphereConfig.BoundaryZ`.

Tune `AtmosphereConfig`, never `Lighting` directly. Two traps documented there:
an `Atmosphere` object **overrides legacy `FogStart`/`FogEnd` entirely**, and the
controller adopts an existing `Atmosphere` rather than adding a second, because
two of them fight.

**Fog must keep enemies visible at engagement range.** `CombatController`
targets to 95 studs and bows reach 90. The authored Wilds profile
(`Density 0.72 / Offset 0.40`) hid everything past ~40 studs and was retuned to
`0.62 / 0.10` after testing against reference blocks at 30/60/90/95 studs.
`Offset` is the dial that pulls fog toward the camera — lower it to buy back the
near field. Re-run that test if you retune.

## Layout

```
src/
├── shared/          → ReplicatedStorage
│   ├── Config/      Designer-tunable values. No magic numbers in services.
│   └── Modules/     Shared utilities, types, the remote manifest
├── server/          → ServerScriptService
│   └── Services/    8 services (Data, Enemy, Combat, RNG, Equipment, …)
└── client/          → StarterPlayerScripts
    └── Controllers/ 7 controllers (UI, Roll, Inventory, Combat, Gear, Atmosphere)
```

Rojo suffix conventions: `.server.luau` → `Script`, `.client.luau` →
`LocalScript`, bare `.luau` → `ModuleScript`.

## Conventions

- **The server decides everything that matters.** RNG, currency, inventory,
  damage, rewards, purchases. The client may *request*; it never *determines*.
  Treat every remote argument as hostile input.
- **Config over code.** Drop rates, stats, prices, enemy health, luck and pity
  live in `src/shared/Config/`. If a designer would plausibly want to change it,
  it does not belong in a service.
- **Remotes are declared in one place**: `src/shared/Modules/Remotes.luau`. Add
  an entry; the server builds instances from the manifest at runtime. Never
  create a remote instance ad hoc.
- **Never overwrite good data with empty data.** A failed profile load kicks the
  player rather than handing them a blank profile that would save over the real
  one. See `DataService`.
- Type annotations where they help. `--!strict` on modules that tolerate it.
- Small modules, clear names, comments only where the logic is non-obvious.

## Things that look done but are not

- **Waves do not exist.** Enemies spawn from static markers, not in waves.
- **The boss does not spawn.** The arena is built and `BossSpawn` carries
  `BossId = "GoblinKing"`; nothing reads it.
- **Both zone gates are decorative.** The village gate and the Zone 2 gate carry
  `RequiresPower = 1200`; nothing reads it, so players walk through.
- **Nothing spends coins.** Kills pay them; there is no sink.
- **`Skeleton` is an id in two registries** — a hostile in `EnemyConfig` (the
  barrow camp) and the Necromancer's summon in `MinionConfig`. They never look
  each other up, so nothing breaks, but a player fighting one while another
  fights beside them sees the same name twice. Worth renaming one.
- **Enemies and minions are primitive rigs.** Weapons have real shaped geometry;
  enemies and minions are assembled from blocks and do not animate.
- **No audio anywhere.** Every id in `AssetConfig` is `0`.
- **Buildings are shells** with no interiors, and the village has no NPCs.
- **Mobile is untested on hardware.**

## Outstanding manual steps

These cannot be done from code. Ask the user; do not work around them.

- [ ] **Set `Lighting.Technology` to `Future`.** Until then all 227 light
      sources glow but do not light the surfaces around them.
- [ ] **Enable Studio Access to API Services** — File → Game Settings →
      Security. Until this is on, every DataStore call fails.
- [ ] **Create gamepasses and developer products**, paste ids into
      `MonetizationConfig`.
- [ ] **Upload audio and icons**, fill in `AssetConfig`.

## Coordination between the two Claudes

The collaborators decided **both Claudes work on everything**. That makes
collisions likely, so:

1. **Pull before you start, push when you finish.** `git pull` then `git push`.
2. **Check the live DataModel before assuming.** The other instance may have
   already built what you are about to build, or moved it. Use
   `search_game_tree` and read `src/` first.
3. **Write idempotent bootstrap code.** Services should be safe to start twice
   and safe to run against a partially-built tree.
4. **Only one person can Rojo-sync at a time.** The plugin claims a lock — an
   `ObjectValue` at `ServerStorage.__Rojo_SessionLock` whose `Value` is the
   holder's `Player`. To take it over, delete that ObjectValue and press
   Connect. This does not remove anyone from Team Create and is not the same as
   evicting a collaborator.

   Ports are irrelevant to this. Each collaborator runs `rojo serve` on their
   own machine bound to `127.0.0.1`, so both can sit on 34872 and never
   collide. `--port` only matters for two servers on ONE machine. The lock is
   the constraint, not the port.

5. **Run world scripts once.** Non-idempotent Command Bar scripts have already
   left duplicate `Atmosphere`, `BloomEffect`, `SunRaysEffect` and `Sky` objects
   in `Lighting`. Two enabled blooms stack and two Atmospheres fight. Adopt an
   existing singleton with `FindFirstChildOfClass` rather than creating a second.
6. **Announce structural changes in a commit message.** Renaming a service or
   changing a remote's signature breaks the other instance's assumptions
   silently.
7. **Work in Workspace can vanish under you.** During the wall rebuild the
   `Towers` folder (1,100 parts) and `WallStairs` (483) were deleted between two
   of this session's own scripts — three separate times, along with the
   `_WallTowers` StringValue reverting to pre-fix values. Team Create allows
   simultaneous Workspace editing and there is no lock on it. So: **build and
   verify in as few scripts as possible**, re-read the stored StringValues
   rather than trusting an earlier write, and count parts before and after
   anything long-running.

### The Rojo hand-off, and why things "disappear"

**This has already confused a collaborator, so both instances must handle it
the same way.**

Connecting is not a merge. Rojo **replaces** the whole of `ReplicatedStorage`,
`ServerScriptService` and `StarterPlayerScripts` with the connecting person's
`src/`, and keeps them matching live. `rojo serve` is strictly one-way,
files → Studio.

So: A connects and the live tree becomes A's checkout. B then connects and it
becomes B's checkout. If B's tree is behind, everything A added rolls back out
of Studio. It looks like deletion. It is the projection being repainted from an
older set of files.

What that does and does not put at risk:

- **Committed work is safe.** `src/` on disk and on GitHub is the truth; the
  Studio script tree is a rendering of it.
- **`Workspace` is never touched by Rojo.** World geometry cannot be lost this
  way.
- **Scripts edited inside Studio are genuinely destroyed**, by either side's
  next sync, with no copy anywhere. Put Luau in `src/`.

The sequence that avoids it:

1. `git pull` **immediately before** pressing Connect — not earlier that day.
2. `git push` before disconnecting or handing the lock over.
3. Whoever connects next pulls again first.

If both trees match `origin/main`, the second Connect writes byte-identical
content and nothing changes. The disappearing only happens when the trees
differ. Also: only connect when you actually need to change scripts — world
geometry work needs no Rojo at all.

Do **not** reach for `rojo syncback` to fix this. It runs Studio → files and
would let a stale Studio tree overwrite source. Wrong direction.

**Tell your collaborator this, in their own session.** Both instances are
expected to raise it with their own user rather than assume the other already
has — the failure is silent, it looks like the other person deleted your work,
and only one of the two people involved can see it happening at a time. When
you take or release the lock, say so in chat and say whether you pulled and
pushed around it.
