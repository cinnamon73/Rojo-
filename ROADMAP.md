# RNG: ARMORY — roadmap

**Direction: medieval co-op wave survival / village defense.**

> ### These phases are provisional
>
> The direction changed once already — the project began as an RNG equipment
> RPG, and Phases 1–5b were built for that shape. What follows is the current
> best plan, not a commitment. Expect it to be reordered, cut and added to as
> the game is played and decided on.
>
> **Preserve what works.** New features adapt the existing game; they do not
> justify rebuilding it.

---

## Done

| Phase | Scope |
|---|---|
| 1 | Foundation — structure, config, remotes, data schema, saving, UI shell |
| 2 | ~~RNG~~ — **removed**, see below |
| 3 | ~~Inventory~~ — **removed**, see below |
| 4 | Combat — weapons, attacks, damage, enemy AI, rewards |
| 5 | World — village, castle, paths, lighting, dressing |
| 5b | **Zone 1 rebuild** — the wilds beyond the gate, on voxel terrain |

### Phases 2 and 3 were removed, not demoted

Both collaborators decided to strip rolling rather than keep it as a
between-wave reward. Deleted: `RNGService`, `MultiplierConfig`, `RarityConfig`,
`ItemConfig`, `ItemInstance`, `ModifierConfig`, `EquipmentService`, and the
roll, inventory and gear controllers. `profile.Inventory`, `profile.Equipment`,
`profile.Luck` and `profile.Pity` are gone from the schema.

**Classes replaced all of it.** `ClassConfig` plus `ClassService`: eight classes
across three tiers plus a paid one, each with fixed stats, a weapon and one
ability. See CLAUDE.md for the contract.

All three follow-ups are now built: `AbilityService` implements the eight
abilities, `ClassSelectController` is the join menu, and `MinionService` handles
the Necromancer and King squads.

### Phase 5b as built

Five review checkpoints, all complete.

| | Stage | Result |
|---|---|---|
| 1 | Perimeter and terrain | Cliffs, ravine, hollows, battlefield scarring, arena bowl. World sealed all round. |
| 2 | Route and combat spaces | Walkable spine plus four spurs, nothing over 26°. 14 spawn markers wired to the attribute contract. |
| 3 | Structures | Goblin camp and outpost, 3 watchtowers, trench works, ruins, siege engine, slime pond, arena, Zone 2 gate. |
| 4 | Vegetation | 234 trees by chapter, 452 bushes and tufts, 451 boulders, logs, stumps, dead trees on the battlefield. |
| 5 | Atmosphere | 21 torch posts, 4 junction cairns, glowing fungus. Wilds fog retuned against measured visibility. |

Final: **4,337 parts (72% of the 6,000 budget)**, zero holes over 5,625
samples, zero floating parts, every `EnemyId` resolving.

Also done outside the phase plan: the **village floor converted to voxel
terrain** with the roads painted into it and the `Paths` folder deleted, and the
**outer treeline** bridging the village wall to the Zone 1 hills.

---

## Next

### Phase 6 — the wave loop

The thing that makes it the game it now says it is. Nothing here exists yet.

- A `WaveService` that spawns from marker groups rather than statically
- Wave counter, escalating composition, a defined start and end per wave
- Recovery window between waves
- Where waves enter from, and whether the gate is the only approach
- What losing means — is there something in the village that can fall?

**`EnemyService` already discovers spawners by attribute**, so this is a change
to *when* it spawns, not *how*. Reuse it.

### Phase 7 — defenses and the village as a fort

- ~~Somewhere for players to actually hold.~~ **Done** — the fortifications
  were rebuilt for player use: 7 stair flights up from inside the village, a
  continuous runnable circuit round the whole 1,907-stud perimeter, and every
  drum tower open through at walk level. What is still missing is a *reason* to
  be up there — nothing about combat rewards holding the wall yet.
- Buildable or repairable defenses, if that fits
- Making the gate a real choke point rather than an open arch
- Enforcing `RequiresPower = 1200` on the gates, which currently nothing reads

### Phase 8 — the Goblin King

The arena is built and `BossSpawn` carries `BossId`; nothing spawns from it.

- Multiple attacks with **visible telegraphs**, so the fight is readable
- Phase transitions at health thresholds
- Large on-screen boss health bar
- Rare loot table, server-wide announcement on an exceptional drop
- How the boss relates to waves — a wave milestone, or a trip out?

### Phase 9 — rewards between waves

Wide open. Rolling is **gone and is not coming back** — anything here has to be
designed for waves from scratch. There is no levelling either; kills pay coins
and nothing spends them yet. Quests, dailies and zone travel may not survive.

### Phase 10 — polish

Audio throughout, VFX for rare reveals and boss phases, toast notifications,
settings panel, first-join tutorial.

### Phase 11 — monetization

Gamepasses, developer products, `ProcessReceipt` handled safely, cosmetics.

### Phase 12 — full test pass

Join, leave, rejoin, data integrity, multiple players, remote spam, invalid
payloads, shutdown mid-session, mobile layout and touch targets.

---

## Polish backlog

Everything here **works**. It is placeholder quality. None of it is blocking.

### The world

- **Building interiors** — every building is a shell with a door that does not
  open. The biggest remaining gap in the village.
- **NPCs** — no villagers, no shopkeepers. The market has stalls and wares but
  nobody tending them.
- Zone 2 exists only as a gate.

### Models

- **There is no armour any more** — a class carries its stats directly, and
  what you see is the class weapon and tint from `ClassConfig`.
- **Enemies and minions** are primitive rigs (`Blob`, `Biped`, `Quadruped`)
  assembled at spawn. They do not animate. A Goblin and a Goblin Warrior differ
  only in colour and scale.

### Animation

Only one animation exists: a single Motor6D swing arc per archetype. Needs idle
poses, combo chains, hit reactions, real projectiles for bows and staves, and
ability animations.

### GUI

Consistent spacing pass, class mannequins on the join menu at small viewports,
and panels for Quests, Shop and Settings which do not exist. Mobile designed
for but never tested on hardware.

---

## Known gaps

- **Waves do not exist.** Enemies spawn from static markers.
- **The boss does not spawn.**
- **Both zone gates are decorative** — the attribute exists, nothing reads it.
- **Nothing spends coins.** Kills pay them, there is no sink.
- **`Skeleton` is used as an id twice** — a hostile in `EnemyConfig` (the barrow
  camp) and the Necromancer's summon in `MinionConfig`. The registries are
  separate so nothing breaks, but players and logs see two different things
  called the same name. Rename one.
- **Mobile is untested on hardware**, and the world is now 14,341 parts with 227
  light sources.
- **No sound anywhere.**

---

## Manual steps (cannot be automated)

- Set `Lighting.Technology` to `Future` — scripts are not permitted to. All 227
  light sources currently glow without lighting anything.
- Enable Studio Access to API Services on any new place
- Create gamepasses and developer products, paste ids into `MonetizationConfig`
- Upload audio and icons, paste ids into `AssetConfig`
- Source or commission real meshes for enemies and minions
- **Refresh the place backup** at milestones and before anything destructive —
  File → Download a Copy, overwriting `RNGArmory.rbxl`. Not needed after every
  world change: the place is Team Create and Roblox holds the version history.
