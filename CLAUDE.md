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

**Workspace is NOT managed by Rojo.** Zone geometry, spawns, and the boss arena
are built through `execute_luau` via MCP. They live in the place file, not git.

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

Build in order; test each before starting the next. Do not stack systems on top
of broken ones.

1. **Foundation** — structure, config, remotes, data schema, saving, UI shell
2. **RNG** — items, rarities, roll service, luck, pity, reveal
3. **Inventory** — item instances, equip/unequip, sell, favorite, compare
4. **Combat** — weapons, attacks, damage, enemy AI, rewards
5. **World** — Verdant Fields, spawns, boss arena, zone gate
6. **Boss** — Goblin King, phases, telegraphs, rare drops
7. **Progression** — XP, levels, power, quests, dailies
8. **Polish** — sound, VFX, UI animation, announcements, settings
9. **Monetization** — gamepasses, products, VIP, boosts
10. **Testing** — full pass including rejoin, multiplayer, and exploit attempts

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
