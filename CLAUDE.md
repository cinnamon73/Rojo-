# RNG: ARMORY — project context

Read this before making changes. It is written for Claude Code instances working
on this repo, and there are **two of us** — one per collaborator. Coordination
rules are at the bottom and they matter more than anything else here.

## What this is

A Roblox RPG built around an RNG equipment system. Core loop:

> Roll for equipment → Equip better gear → Fight enemies → Earn currency →
> Upgrade → Unlock new zones → Better loot → Repeat

Working title **RNG: ARMORY**. Target is a polished, publishable experience, not
a prototype.

## How code reaches the game

Two independent channels. Know which one you are using.

| Channel | Covers | How |
|---|---|---|
| **Rojo** | `ReplicatedStorage`, `ServerScriptService`, `StarterPlayerScripts` | Edit files in `src/`. `rojo serve` pushes to Studio. |
| **Studio MCP** | Everything else — `Workspace` geometry, live inspection, running Luau | `mcp__Roblox_Studio__*` tools against the live session |

**Rojo is authoritative for `src/`.** Anything you write into those three
services *inside Studio* gets overwritten on the next sync. Put Luau in `src/`.

**Workspace is NOT managed by Rojo, and it is NOT delivered by the repo either.**
This is a **Team Create cloud place**. Both collaborators edit the same live
`Workspace` and see each other's changes immediately. Roblox holds the version
history — the place is past version 125 and every earlier one is recoverable
from the Creator Dashboard or File → Open from Roblox. **That is the first
resort if the world gets destroyed.**

`RNGArmory.rbxl` in this repo is a **backup snapshot**, not the source of truth
and not a sync mechanism. Refresh it before anything destructive, around large
structural jobs like the Phase 5b Zone 1 rebuild, and at milestones worth
returning to — **not after every world change**. Earlier revisions of this file
claimed geometry you do not save "exists on your machine only"; that was wrong,
and it was written before anyone checked that the place was Team Create.

To refresh it: File → **Download a Copy** (a cloud-opened place has no "Save to
File As"), overwrite `RNGArmory.rbxl`, commit. Binary — restores perfectly,
does not diff, cannot be merged. Fine for a backup, useless for collaboration,
which is exactly why collaboration does not use it.

[`tools/BuildWorld.luau`](tools/BuildWorld.luau) once regenerated the world, but
at ~14,000 parts that is no longer practical. It is legacy, carries a warning
banner, and running it would destroy the current world.

[`tools/RestoreGround.luau`](tools/RestoreGround.luau) is the other world tool:
same channel (paste into the Command Bar in Edit mode), but it only ADDS floors
that are missing and never wipes. It exists because the ground went missing once
and rebuilding it by hand from the documented dimensions was slower than writing
it down. Its Zone 1 slab is an explicitly named `_TEMP` placeholder — Phase 5b
replaces that with voxel Terrain, and it is in its own folder so it deletes in
one click.

**The ground is voxel Terrain everywhere — village and Zone 1 both.** The old
`Ground_Pasture` Part disc is gone, and so is the `Paths` folder: roads are now
painted into the terrain as `Cobblestone`, tracks as `Sandstone`/`Ground`. Four
things follow that will bite you if you do not know them.

- **Terrain is not a `Part`.** It cannot be `Anchored` or `CastShadow` — the
  sole exception to that rule. `Terrain.WaterColor` is **global**, so Terrain
  water cannot be slime-green in one place and blue in another.
- **Only `Grass` and `LeafyGrass` grow blades.** Painting either under paving or
  against a wall pushes grass through it. Anywhere people walk is `Ground`,
  `Mud`, `Cobblestone` or `Sandstone`, chosen from a per-cell footprint map.
- **The village floor is pinned at `y = 0.10`** under every one of the ~3,500
  parts that meet the ground, held flat by a mask built from their real
  footprints, with hills only in the open ring at r 213–411. **Rebuild that mask
  from live geometry before re-sculpting** or the buildings will end up on
  hillsides.
- **`_PathRoutes` and `_PathMask` on the Village folder are now the only record
  of the road network.** The tiles they generated have been deleted. Do not
  remove those StringValues. `_PathRoutes` is `kind|width|name|x,z;x,z;...`
  where kind `C` is a cobbled way and `D` a dirt lane — and note the `Market`
  entry is stored with **width 0**, which silently paints nothing unless you
  substitute a real width.

### Geometry lessons, each of which cost real bugs

- **Pitched roofs.** A slab at `z = s * run/2` takes rotation `s * pitch`, not
  `-s * pitch`. `CFrame.Angles(φ,0,0)` maps local Z to `(0, -sin φ, cos φ)`.
  Getting this backwards builds a valley instead of a ridge, and it is only
  obvious from ground level.
- **Cylinders lie along local X.** A `Cylinder` part needs a 90° roll about Z
  to stand upright. Twenty-eight brazier bowls were built as barrels on their
  side before this was spotted.
- **Rotated parts need local-frame tests.** A world-axis-aligned box around a
  rotated object over-covers badly and will swallow things you are looking for.
- **Roof extents are not wall extents.** Roofs overhang walls by 8–13 studs
  here. Carving ground using a building's full extent deletes the paving its
  own door opens onto. Use the plinth.
- **Props positioned relative to a plinth top will float** if they stand off
  the plinth. This has now been fixed three separate times.
- **Terrain occupancy is measured from the voxel CENTRE, not its bottom.**
  `occ = (h - voxelCentreY) / 4` puts the surface at `h`. The intuitive
  `(h - voxelBottom) / 4` puts it **exactly 2 studs too high**, everywhere, and
  because the error is uniform the terrain still looks plausible — it was only
  caught when village parts pinned at `y = 0.10` came out floating. Calibrate
  against a test strip rather than reasoning about it; the correct form lands
  within 0.003 studs.
- **Raycasts do not see voxels written earlier in the same script.** Verify
  terrain in a separate call or every probe reports the state before the write.
  This has produced two phantom bug reports — 41 imaginary holes and a whole
  calibration strip that read as empty.
- **Axis-aligned footprints over-cover rotated parts badly.** Stamping village
  buildings by AABB inflated every rotated one into a bare rectangle and
  dissolved the dirt lanes into a patchwork. Test the cell centre against the
  part's oriented rect in its own local frame instead.
- **Build assemblies as chains, not from a common origin.** Place each piece
  from the endpoint of the one it attaches to: a bar of length `L` pointing
  along `d` with its base at `B` has centre `B + d*(L/2)` and ends at
  `B + d*L`. Every fixture built by eye-tuned offsets — 68 torches, 6 market
  stalls, 2 lean-tos — came out with floating pieces. Rotating a part moves
  its ends, so offsets guessed before the rotation never meet after it.
- **Rings of blocks on an arc need a depth stagger.** Voussoirs rotated about
  Z keep their faces parallel, so every block in the ring sits on one plane
  and they z-fight however narrow you make them. Size them from measured
  neighbour spacing AND offset alternate blocks along their own normal.
- **Recovering a yaw from a LookVector is `atan2(-L.X, -L.Z)`**, not
  `atan2(L.X, L.Z)` — the latter is θ+π and silently flips the building. This
  has now spun a building backwards twice.
- **The curtain wall is a curve, not a rectangle.** Anything joining it must
  read the bay's actual bearing. Axis-aligned gate wings left a 12-stud gap.
- **A "floating parts" test must accept ground support**, or every prop
  standing on the paving reads as broken. Raycast down before flagging.
- **Coplanar-overlap tests over-report.** They count masses that meet flush
  inside a wall, and they treat a rolled cylinder as a box. Only pairs with
  *both* faces exposed on a shared plane actually flicker. Check a screenshot
  before acting on a large count.

**Screenshot at player eye height before trusting any geometry change.** A
top-down view has hidden every one of the bugs above.

## Layout

```
src/
├── shared/          → ReplicatedStorage
│   ├── Config/      Designer-tunable values. No magic numbers in services.
│   └── Modules/     Shared utilities, types, the remote manifest
├── server/          → ServerScriptService
│   └── Services/    Server systems (DataService, RNGService, ...)
└── client/          → StarterPlayer.StarterPlayerScripts
    └── Controllers/ Client systems (UIController, RollController, ...)
```

Rojo suffix conventions: `.server.luau` → `Script`, `.client.luau` →
`LocalScript`, bare `.luau` → `ModuleScript`.

## Conventions

- **The server decides everything that matters.** RNG, currency, inventory,
  damage, rewards, quest completion, purchases. The client may *request*; it
  never *determines*. Treat every remote argument as hostile input.
- **Config over code.** Drop rates, stats, prices, enemy health, zone gates, and
  luck/pity values live in `src/shared/Config/`. If a designer would plausibly
  want to change it, it does not belong in a service.
- **Remotes are declared in one place**: `src/shared/Modules/Remotes.luau`. Add
  an entry there; the server builds instances from the manifest at runtime.
  Never create a remote instance ad hoc.
- **Never overwrite good data with empty data.** A failed profile load kicks the
  player rather than handing them a blank profile that would save over the real
  one. See `DataService`.
- Type annotations where they help. `--!strict` on modules that tolerate it.
- Small modules, clear names, comments only where the logic is genuinely
  non-obvious.

## The enemy spawn contract

This matters more than it looks, because it is the only link between the world
geometry and the combat system, and it is entirely attribute-driven.

`EnemyService.populate()` walks **every descendant of `Workspace.World`** and
picks up any `BasePart` carrying an `EnemyId` string attribute. Nothing is
matched by name, and no folder path is hardcoded.

| Attribute | Meaning |
|---|---|
| `EnemyId` | Required, string. Must match an id in `EnemyConfig`. |
| `MaxAlive` | How many live at this marker at once. Defaults to `2`. |
| `Radius` | Scatter radius around the marker. |

Two consequences:

- **Deleting and rebuilding a zone breaks nothing**, provided the new markers
  carry the same attributes. You are free to restructure folders.
- **A marker with a typo'd `EnemyId` fails silently.** `EnemyConfig.Get`
  returns nil and the marker is skipped with no warning.

Defined ids: `Slime`, `Goblin`, `Wolf`, `GoblinWarrior`, `EliteGoblin`,
`GoblinKing`. The boss marker is `BossSpawn` and carries `BossId`.

## The roll pipeline

This changed substantially and is now the core of the game's feel. Read it
before touching `RNGService`, `MultiplierConfig` or `RollController`.

**One RollRequest can be several rolls.** The pool contains a **multiplier
card** alongside the items. Landing on it awards nothing — it consumes that roll
and immediately starts another, with the next rung swapped into the pool in its
place (2x → 4x → 8x → 16x → 32x). The chain ends the first time you land on a
real item. All of it resolves in one server pass, so a chain cannot be used to
dodge the roll cooldown.

`MultiplierConfig.RollChain` returns the final value, the final rung, and the
**ordered list of rungs landed on**. The client replays that list as one spin
each. Do not reconstruct the chain client-side — what it draws must be what
actually happened.

**From 4x up, every rung sets a rarity floor** (`MinRarity` on the ladder):
4x → Rare, 8x → Epic, 16x → Legendary, 32x → Mythic. Everything below the floor
gets weight **zero**, not "very small" — the guarantee is the point. Two things
exist solely to keep it honest, and breaking either reintroduces Commons into a
floored roll:

- `PickRarity`'s fallback returns the highest tier that still had weight, never
  a hardcoded `"Common"`.
- `MinCommonWeightRatio` (which floors Common's share at 4%) is **skipped**
  whenever a floor is active.

**Luck scales harder at higher ranks.** `LuckRankScaling` raises each tier above
`LuckMinRank` to a slightly higher power of luck. Without it, luck multiplied
every boosted tier equally, the ratios inside the boosted block never moved, and
a 32x's most likely outcome was a *Rare* — the lowest boosted tier. At luck 1
the exponent is inert (`1^x == 1`), so **base drop rates are unchanged**.

**The multiplier applies on top of the `MaxLuck` clamp**, not before it.
`MaxLuck` caps stacked boosts; a roll multiplier is a separate deliberate spike.
Folding it in first makes 8x and 16x identical for anyone near the ceiling.

## Inventory: unlimited, and it stacks

There is **no capacity**. `InventoryFull` no longer exists anywhere.

Duplicates stack instead of taking slots, keyed on **template + modifier**
(`ItemInstance.StackKey`), so a Vampiric Iron Sword never merges with a plain
one. `Inventory.Items` is now a map of **stacks**, not of individual items.

Two consequences that will bite if missed:

- **`Count` is optional.** Profiles written before stacking have no such field.
  Every read goes through `ItemInstance.GetCount()`, which treats nil as 1. Do
  not make it required without a migration.
- **A stack keeps the best-rolled copy.** `Variance` is a continuous roll, so
  duplicates are never identical and something must be discarded. The weaker
  roll is dropped and the stack keeps its original `Id` — so equipment
  references stay valid, and a stack you are *wearing* silently improves when a
  better copy lands.

That bound is also what makes an unlimited inventory safe: the profile grows by
distinct item-and-modifier combinations, not by rolls, so a long auto-roll run
cannot grow the DataStore payload without limit.

**Equipping has no level requirement.** `ItemConfig.LevelRequirement` still
exists as a tier hint for sorting and balance work, but **nothing enforces it**
and the client no longer renders a "requires level" line. Anything that drops
can be worn immediately.

**Rolling auto-equips upgrades.** `EquipmentService` subscribes to
`RNGService.ItemRolled` and equips the new item if it beats the slot on Power —
strictly greater, so sidegrades do not churn character visuals. Subscribed from
EquipmentService rather than called from RNGService, so the roll path stays
unaware of equipment.

## Client UI conventions

- **Labels left, equipment right.** Every numeric readout (coins, level, power,
  luck) lives in UIController's single left-hand column; the gear strip owns the
  top-right corner. Do not split numbers across both sides.
- **`GearController` is laid out on artwork, not on layouts.** The gear tab is
  one painted image with invisible hitboxes on top. Every rect is a **fraction
  of the 1596x924 template**, measured from the image by edge detection rather
  than estimated. Re-cut the artwork and every number is wrong — re-run the
  measurement rather than nudging them by hand.
- **`GearHudController` cuts its icons out of that same uploaded asset** at
  runtime via `ImageRectOffset`/`ImageRectSize`, sprite-sheet style, so the HUD
  needs no art of its own. Its rects are in the pixel space of the **uploaded
  1024x593** image (the template scaled by 1024/1596); re-upload at a different
  size and they must be rescaled. Icons are sized to equal **area**, not to a
  bounding box, or square frames (belt, rings) read half again bigger than tall
  ones (sword, chest).
- **Auto-roll paces itself** on `AutoRollIntervalSeconds`, plus
  `AutoRollChainPauseSeconds` per rung landed — not on the shared roll cooldown.
  Manual rolls are unaffected. The old behaviour rolled faster than the reveal
  could play, so spins were cut off mid-flight.

## Lighting is owned by a script

`AtmosphereController` drives fog, atmosphere and outdoor ambient from the
player's Z position, blending a clear village profile into a heavy wilds one
across the gate.

Lighting is **not** in the Rojo tree (`default.project.json` claims only
ReplicatedStorage, ServerScriptService and StarterPlayerScripts), so a
hand-tuned Atmosphere in the place file would sit outside version control and be
overwritten at runtime anyway. Tune `AtmosphereConfig`, not Lighting.

Two traps. An **`Atmosphere` object overrides legacy fog entirely** — while one
exists `FogStart`/`FogEnd`/`FogColor` do nothing, and all visible thickness
comes from `Density`/`Offset`/`Haze`. And the controller **adopts** any existing
Atmosphere rather than adding a second, because two of them fight and flicker.

## Build phases

**[ROADMAP.md](ROADMAP.md) is the authoritative plan.** Read it before starting
work — it carries the detailed scope for each remaining phase plus a polish
backlog for systems that already work but are placeholder quality.

Build in order; test each before starting the next. Do not stack systems on top
of broken ones.

| Phase | Scope | State |
|---|---|---|
| 1 | Foundation — structure, config, remotes, data schema, saving, UI shell | Done |
| 2 | RNG — items, rarities, roll service, luck, pity, reveal, auto-roll | Done |
| 3 | Inventory — item instances, equip/unequip, sell, favourite, compare | Done |
| 4 | Combat — weapons, attacks, damage, enemy AI, rewards | Done |
| 5 | World — village, castle, paths, lighting, dressing | Done |
| 5b | Zone 1 rebuild — hunting grounds on voxel Terrain | **Next** |
| 6 | Boss — Goblin King, phases, telegraphs, rare drops | |
| 7 | Progression — quests, dailies, boosts, zone gates | |
| 8 | Polish — sound, VFX, UI animation, announcements, settings | |
| 9 | Monetization — gamepasses, products, VIP, cosmetics | |
| 10 | Testing — rejoin, multiplayer, exploit attempts, mobile | |

### Things that look done but are not

Worth knowing before you assume a system is finished:

- **Abilities are config-only.** Defined in `ItemConfig` and granted on Rare+
  weapons; never implemented.
- **The zone gate is decorative.** The part carries `RequiresPower = 1200`;
  nothing reads it, so players walk straight through.
- **Four remotes are declared but sealed** — `DailyClaimRequest`,
  `QuestRequest`, `ShopRequest`, `ZoneTravelRequest`. They answer
  `NotImplemented` rather than hanging. That is intended until their phase lands.
- **Armour and enemies are primitive rigs.** Weapons have real shaped geometry;
  armour is coloured boxes and enemies are assembled from blocks.
- **No audio anywhere.** Every sound id in `AssetConfig` is `0`. Images are no
  longer all zero — `Images.GearPanel` is a real uploaded asset, owned by the
  **CGS Student Development group**, and both gear UIs depend on it.
- **The gear panel artwork paints 14 slot frames; the game has 7.** The unused
  seven get an explicit locked treatment in `GearController`. They are not
  broken slots — delete an entry from `LOCKED_RECTS` the day a real slot claims
  one.
- **The gear tab's "Drop" button sells.** The artwork says Drop, but there is no
  world-drop system; it is wired to `SellRequest` and labelled accordingly.
- **`Inventory.BaseCapacity` is vestigial.** Still in the schema and still
  replicated, but nothing enforces it now that duplicates stack.
- **Buildings are shells.** No interiors; doors do not open. And the village has
  no NPCs — the market has stalls and wares but nobody tending them.
- **A hidden `VillageSpawn` sits behind the well.** Before it was added the
  place had no SpawnLocation at all.
- **Zone 1 (`StarterZone`) is being rebuilt from scratch.** The hunting grounds
  were built in an early pass and never had any of the village treatment — no
  organic paths, no lighting, no dressing. It is visibly rougher than
  everything inside the walls, and it is where players actually spend their
  combat time. **ROADMAP Phase 5b carries the full spec**: voxel Terrain for
  landforms, Parts for everything else, a ~6,000 part budget, and five review
  checkpoints. While that work is live, **the village is read-only** — it is
  not Zone 1, and proximity to the boundary does not make something part of it.

## Outstanding manual steps

These cannot be done from code. Ask the user; do not work around them.

- [ ] **Set `Lighting.Technology` to `Future`** in Properties. Scripts are not
      permitted to set it, and cannot even read it. Until then the ~190 light
      sources glow but do not light the surfaces around them.
- [ ] **Enable Studio Access to API Services** — File → Game Settings →
      Security. Until this is on, every DataStore call fails and data saving
      cannot be tested.
- [ ] **Create gamepasses and developer products** on the Creator Dashboard,
      then paste their ids into `src/shared/Config/MonetizationConfig.luau`.
      Every id is currently `0`, which means "inactive" — nothing is granted.
- [ ] **Upload audio and icons**, then fill in
      `src/shared/Config/AssetConfig.luau`. Ids are `0` = not configured; the
      helpers return `nil` and callers no-op rather than erroring.

## Coordination between the two Claudes

The collaborators decided **both Claudes work on everything**. That makes
collisions likely, so:

1. **Pull before you start, push when you finish.** `git pull` then `git push`.
   Do not work for an hour on stale files.
2. **Check the live DataModel before assuming.** The other instance may have
   already built what you are about to build. Use `search_game_tree` and read
   `src/` before writing new systems.
3. **Write idempotent bootstrap code.** Services should be safe to start twice
   and safe to run against a partially-built tree. Assume nothing about what
   already exists.
4. **Only one person can Rojo-sync at a time.** The Rojo plugin claims a lock —
   an `ObjectValue` at `ServerStorage.__Rojo_SessionLock` whose `Value` is the
   holder's `Player`. If it is held, the other side gets *"Could not sync
   because user 'X' is already syncing"*. To take it over, delete that
   ObjectValue and press Connect; the plugin claims a fresh one. This does not
   remove anyone from Team Create and is not the same thing as evicting a
   collaborator.
5. **Run world scripts once.** Non-idempotent Command Bar scripts have already
   left duplicate `Atmosphere`, `BloomEffect`, `SunRaysEffect` and `Sky`
   objects in `Lighting`. Two enabled Bloom effects stack, and two Atmospheres
   fight; the scene silently looked wrong for a while. Before adding a
   singleton, adopt the existing one — `FindFirstChildOfClass` — rather than
   creating a second.
6. **Announce structural changes in a commit message.** Renaming a service or
   changing a remote's signature breaks the other instance's assumptions
   silently.
