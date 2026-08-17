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

**Workspace is NOT managed by Rojo**, and `.rbxlx` is gitignored — so the world
would otherwise exist only inside one person's place file. It lives in the repo
as a builder instead: [`tools/BuildWorld.luau`](tools/BuildWorld.luau), pasted
into the Studio Command Bar in Edit mode. It is idempotent.

**Edit the builder, not the place.** Sculpting geometry by hand in Studio makes
the world unreproducible and invisible to the other collaborator. If you change
the map through MCP while iterating, fold the change back into the builder
before you finish.

A geometry warning, because it cost three bugs: pitched roofs are easy to get
wrong and only look wrong from ground level. The correct maths is documented at
the top of the builder. **Screenshot at player eye height before trusting any
geometry change** — a top-down view hid all three.

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
| 5 | World — village hub, Verdant Fields, spawns, arena, gate | Done |
| 6 | Boss — Goblin King, phases, telegraphs, rare drops | **Next** |
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
- **No audio anywhere.** Every id in `AssetConfig` is `0`.

## Outstanding manual steps

These cannot be done from code. Ask the user; do not work around them.

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
4. **Two `rojo serve` instances race.** If you both sync to the same Team Create
   place, last write wins. Check the DataModel before pushing, not after.
5. **Announce structural changes in a commit message.** Renaming a service or
   changing a remote's signature breaks the other instance's assumptions
   silently.
