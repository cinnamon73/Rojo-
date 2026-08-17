# RNG: ARMORY

A Roblox RPG built around an RNG equipment system.

> Roll for equipment → Equip better gear → Fight enemies → Earn currency →
> Upgrade → Unlock new zones → Better loot → Repeat

**Status: playable vertical slice.** The full loop runs end to end — roll,
reveal, equip, walk out of the village, fight, earn XP and coins, level up, roll
better. It is not polished and it is not finished. [ROADMAP.md](ROADMAP.md) has
what is left to build and what needs a second pass.

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
| World | Village safe hub, Verdant Fields, boss arena (built but empty) |
| Characters | Standard R15 body for everyone; head, face, hair and accessories preserved |
| Anti-exploit | Server decides every outcome; token-bucket limits on all remotes |

**Not built yet:** the boss, quests, daily rewards, shop, monetization, audio.

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
tools/        → not synced             one-off scripts, e.g. the world builder
```

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

In Studio: **Toolbox → Creator Store → Plugins → search "Rojo" → Install**
(publisher `rojo-rbx`).

Do **not** use `rojo plugin install`. It looks up a
`HKCU\Software\Roblox\RobloxStudio\ContentFolder` registry value that current
Studio builds no longer write, and fails with a misleading "Roblox might not be
installed".

### 4. Enable Studio as an MCP server

In Studio: **Assistant → … → Manage MCP Servers → Enable Studio as MCP server**.

`.mcp.json` in this repo already points Claude Code at the launcher via
`%LOCALAPPDATA%\Roblox\mcp.bat`, so Windows machines need no further config —
just restart Claude Code so it picks the server up. On macOS the path is
`/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP` and `.mcp.json` needs
editing to match.

### 5. Build the world

**The map is not in the repo as geometry — it is generated.** Workspace is not
Rojo-managed and `.rbxlx` is gitignored, so the world lives here as a builder
script instead. Cloning gets you the code but an empty place.

Open the place in Studio, then paste the entire contents of
[`tools/BuildWorld.luau`](tools/BuildWorld.luau) into the **Command Bar**
(View → Command Bar) in **Edit mode** and press Enter. It is idempotent —
running it twice produces one world, not two.

### 6. Sync and play

```bash
rojo serve
```

Click **Connect** in the Rojo panel, then press Play. You should spawn in the
village plaza with a HUD, a working ROLL button, and enemies out past the gate.

---

## Daily workflow

```bash
git pull
rojo serve
```

…work…

```bash
git add -A && git commit -m "what changed" && git push
```

**Pull before you start and push when you finish.** Two people work on this repo
and neither Rojo nor Studio will merge anything for you. If you both run
`rojo serve` against the same Team Create place, last write wins.

---

## Manual steps still outstanding

These cannot be done from code. Nothing breaks without them — the affected
features stay inert rather than erroring — but they are required before launch.

- [ ] **Enable Studio Access to API Services** — Game Settings → Security.
      Without it every DataStore call fails. Already enabled on the current
      place; needed again on any new one.
- [ ] **Create gamepasses and developer products** on the Creator Dashboard and
      paste their ids into `src/shared/Config/MonetizationConfig.luau`. Every id
      is `0` today, which reads as inactive — nothing is granted, nothing errors.
- [ ] **Upload audio and icons**, then fill in
      `src/shared/Config/AssetConfig.luau`. Ids of `0` make the helpers return
      `nil` and callers no-op, so the game is silent rather than broken.

---

## Troubleshooting

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

**Village geometry looks wrong.** Re-run `tools/BuildWorld.luau`. The
pitched-roof maths is documented at the top of that file — it is easy to get
wrong and only shows up at ground level.

**Play-testing a change did nothing.** Rojo syncs to the Edit datamodel. A play
session started before the sync landed is running the old code — stop, confirm
the change is in Edit, and start again.
