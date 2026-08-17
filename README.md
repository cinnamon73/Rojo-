# RNG: ARMORY

A Roblox RPG built around an RNG equipment system.

> Roll for equipment → Equip better gear → Fight enemies → Earn currency →
> Upgrade → Unlock new zones → Better loot → Repeat

Luau source lives in `src/` and syncs into Roblox Studio through
[Rojo](https://rojo.space). See [CLAUDE.md](CLAUDE.md) for architecture,
conventions, and the build plan.

## Setting up a second machine

Everything below is one-time. Windows instructions; macOS differs where noted.

### 1. Clone

```bash
git clone <repo-url>
cd "roblox studio"
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

Do not bother with `rojo plugin install` — it depends on a
`HKCU\Software\Roblox\RobloxStudio\ContentFolder` registry value that current
Studio builds do not write, and it fails with a misleading "Roblox might not be
installed".

### 4. Enable Studio as an MCP server

In Studio: **Assistant → … → Manage MCP Servers → Enable Studio as MCP server**.

`.mcp.json` in this repo already points Claude Code at the launcher via
`%LOCALAPPDATA%\Roblox\mcp.bat`, so Windows machines need no further config —
just restart Claude Code so it picks up the server. On macOS the path is
`/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP` and `.mcp.json` needs
editing to match.

### 5. Open the place and sync

Open the Team Create place in Studio, then from the project folder:

```bash
rojo serve
```

Click **Connect** in the Rojo panel. You should see `Config` appear in
`ReplicatedStorage` and `Main` in both `ServerScriptService` and
`StarterPlayerScripts`.

## Daily workflow

```bash
git pull
rojo serve
```

...work...

```bash
git add -A && git commit -m "what changed" && git push
```

**Pull before you start and push when you finish.** Two people work on this repo
and neither Rojo nor Studio will merge anything for you.

## Layout

```
src/shared/   → ReplicatedStorage      (config, shared modules, remote manifest)
src/server/   → ServerScriptService    (authoritative game systems)
src/client/   → StarterPlayerScripts   (UI and input)
```

`Workspace` geometry is **not** in this repo — it lives in the place file and is
edited in Studio directly.

## Manual setup still outstanding

- Enable **Studio Access to API Services** (Game Settings → Security) or all
  DataStore calls fail
- Create gamepasses/products and fill in `src/shared/Config/MonetizationConfig.luau`
- Upload audio/icons and fill in `src/shared/Config/AssetConfig.luau`
