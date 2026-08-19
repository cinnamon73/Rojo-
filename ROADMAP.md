# RNG: ARMORY — roadmap

Two tracks run in parallel:

- **Phases** — systems that do not exist yet.
- **Polish** — systems that exist and work, but are placeholder quality.

The world is now finished to a good standard. The *systems* are the rough half.

---

## Build phases

Build in order. Test each phase before starting the next, and do not stack new
systems on top of broken ones.

| Phase | Scope | State |
|---|---|---|
| 1 | Foundation — structure, config, remotes, data schema, saving, UI shell | ✅ Done |
| 2 | RNG — items, rarities, roll service, luck, pity, reveal, auto-roll | ✅ Done — **reworked**, see below |
| 3 | Inventory — item instances, equip/unequip, sell, favourite, comparison | ✅ Done — **reworked**, see below |
| 4 | Combat — weapons, attacks, damage, enemy AI, rewards | ✅ Done |
| 5 | World — village, castle, paths, lighting, dressing | ✅ Done |
| 5b | **Zone 1 rebuild — the hunting grounds** | ⬜ Next |
| 6 | **Boss — the Goblin King** | ⬜ Next |
| 7 | Progression — quests, dailies, boosts, zone gate enforcement | ⬜ |
| 8 | Polish — audio, VFX, notifications, settings UI | ⬜ |
| 9 | Monetization — gamepasses, products, VIP, cosmetics | ⬜ |
| 10 | Full test pass — rejoin, multiplayer, exploit attempts, mobile | ⬜ |

---

### Reworked since Phases 2 and 3 were first marked done

Both still read "Done" because their scope is delivered, but the systems
underneath are not what the original entries describe. `CLAUDE.md` carries the
full contracts — this is the short version of what changed and why.

**Rolling is a chain, not a single draw.** A multiplier card sits in the pool;
landing on it starts another roll with the next rung swapped in. From 4x up each
rung guarantees a rarity floor (4x Rare, 8x Epic, 16x Legendary, 32x Mythic).
Before the floors, a 32x's single likeliest outcome was a Rare, which read as
the multiplier doing nothing.

**Luck now scales harder at higher ranks** (`LuckRankScaling`). Flat luck left
the ratios inside the boosted block untouched, so luck only moved you out of
Common — never up the ladder. Base rates are provably unchanged: at luck 1 the
exponent is inert.

**Inventory is unlimited and duplicates stack.** Stacks key on template +
modifier and keep the best-rolled copy. This is not cosmetic — without stacking,
an uncapped inventory would grow the DataStore payload without bound.

**Equipping lost its level gate**, and rolling auto-equips anything that beats
the slot on Power.

**The UI moved with it**: a painted gear tab (`GearController`), an always-on
gear strip cut from the same uploaded asset as a sprite sheet
(`GearHudController`), vertical case-opening reels that open side by side per
chain step, and script-driven fog (`AtmosphereController`).

Still untested in anger: none of this has been through a rejoin or a
multiplayer session. Phase 10 has more to cover than it did.

### Phase 5b — Zone 1 rebuild

`StarterZone` was built in an early pass and never got the treatment the
village did. It is now visibly the worst-looking part of the game, and it is
where players spend their combat time. It is being **rebuilt from scratch**,
not patched.

**The village is not Zone 1 and is not part of this work.** Zone 1 begins
beyond the village gate. The entire village — walls, gate, buildings, roads,
lighting, props — is read-only for the duration of this phase. Proximity does
not mean ownership: if something sits near the zone boundary but belongs to the
village, it stays.

#### Decisions taken

| | Decision |
|---|---|
| Landforms | **Roblox voxel Terrain**, the first use of it in this project |
| Structures, props, vegetation | Parts, as everywhere else |
| Atmosphere | A small client script blending fog/ambient by player position |
| Part budget | ~6,000, taking the place to roughly 15,000 total |
| Review | Five checkpoints, screenshots at each before continuing |

Everything except the terrain itself still obeys the house rule: every
generated `Part` / `WedgePart` / `MeshPart` is `Anchored = true` and
`CastShadow = true`. Voxel Terrain has neither property, which is the one
deliberate exception.

#### Layout

The gate faces south at `z = 66`, road running out to `z ≈ 24`, so the zone is
a lobe extending into negative Z — roughly **520 × 460 studs** against the
village's ~560 span. Comparable, slightly smaller: the brief is density over
size.

| Chapter | Roughly |
|---|---|
| Gate apron, outskirts | z 24 → −40 |
| Outer forest | −40 → −140 |
| Goblin territory (west lobe) | −140 → −250 |
| Abandoned battlefield (centre/east) | −160 → −280 |
| Slime hollow (east, low ground) | −220 → −300 |
| Deep forest | −280 → −370 |
| Goblin King domain and arena | −370 → −450 |
| Zone 2 gate | far south, ~−470 |

Perimeter is a ridge-and-cliff arc west, a ravine on the east flank, and dense
timber closing the south. Never a straight run and never a visible wall of
world edge.

#### Checkpoints

| | Stage | Delivered |
|---|---|---|
| 1 | Perimeter and terrain sculpt | Bare landforms — ridge, ravine, hollows, battlefield scarring, arena bowl. No props. Mistakes are cheapest to fix here. |
| 2 | Main route and combat spaces | Road from the gate, forks, clearings, camp footprints, arena floor, spawn markers wired up |
| 3 | Structures | Camps, watchtowers, ruins, trench works, Zone 2 gate, arena build |
| 4 | Vegetation and dressing | Forest, undergrowth, rocks, debris, slime pools |
| 5 | Atmosphere | Lighting, the fog-blend script, final sweep |

#### Risks identified before starting

- **The village/zone ground seam.** `Ground_Pasture` is a Part cylinder, radius
  411 centred at `(0, 380)`, so it ends at about `z = −31` — barely past the
  gate. Voxel Terrain meeting a flat Part slab at that line will show a seam
  unless the terrain edge is tucked under the slab and the join hidden in the
  gate approach. Solve it at checkpoint 1, not checkpoint 5.
- **Slime pools must be Parts, not Terrain water.** `Terrain.WaterColor` is a
  single global property; making it slime-green would turn every body of water
  in the place green. Parts also give proper glow and translucency.
- **Vegetation is where the budget lives or dies.** A naive tree is 8–15 parts;
  400 of them would eat 5,000 on their own. Build a small set of tree
  archetypes and clone them — which also keeps the forest readable rather than
  noisy.
- **The arena is ~450 studs from spawn**, with no shortcut back. Worth deciding
  whether the Zone 2 gate area doubles as a return point.

#### Enemy placement

All six defined enemies get a home in the layout: `Slime`, `Goblin`, `Wolf`,
`GoblinWarrior`, `EliteGoblin`, `GoblinKing`. New spawn markers must carry the
attribute contract `EnemyService` reads — see CLAUDE.md, "The enemy spawn
contract".

---

### Phase 6 — Goblin King

The arena and gate are built and tagged; nothing spawns in them yet.

- Boss spawn from the `BossSpawn` marker (`BossId` attribute already set)
- Multiple attacks: sword swing, ground slam, charge, summon adds
- **Telegraphs** — a visible wind-up before each attack, so the fight is
  readable rather than reflex-based
- Phase transitions at health thresholds, changing attack mix and pace
- Large on-screen boss health bar, distinct from ordinary enemy bars
- Rare loot table with a genuinely better drop distribution
- Server-wide announcement on an exceptional drop
- Enforce the `RequiresPower = 1200` gate — the gate part exists and carries
  the attribute, but nothing reads it, so players walk straight through

### Phase 7 — Progression

- Quest system, data-driven like items and enemies
- Daily rewards on a 7-day escalating track, with **server time authoritative**
- Temporary boosts with durations, surfaced in the HUD
- Zone gate enforcement and travel via the existing `ZoneTravelRequest` remote
- Achievements and titles

### Phase 8 — Polish

- Audio throughout — UI, rolls, reveals by rarity tier, combat, boss
- VFX for rare reveals, level ups, boss phases
- Toast notifications and the global announcement banner
- Settings panel wired to the settings already in the profile schema
- Tutorial prompts for the first-join flow

### Phase 9 — Monetization

- Gamepasses: VIP, Auto Roll, Fast Rolls, Extra Inventory, Extra Slot
- Developer products: luck boosts, coin packs, XP boosts
- `ProcessReceipt` handled safely — never grant twice
- Cosmetics: trails, auras, weapon effects, titles

### Phase 10 — Full test pass

Join, leave, rejoin, data integrity, multiple players, remote spam, invalid
payloads, server shutdown mid-session, mobile layout and touch targets.

---

## Polish backlog

Everything here **works**. It is placeholder quality and needs a proper pass.
None of it is blocking.

### The world — largely done

The village was rebuilt end to end and is no longer a weak point. What remains:

- **Building interiors** — every building is still a shell with a door that
  does not open. This is the biggest remaining gap in the village.
- **NPCs** — no villagers, no shopkeepers. The market has stalls and wares but
  nobody tending them, which is now the most conspicuous absence.
- **A hidden spawn exists now** (`VillageSpawn`, behind the well). Before this
  the place had no SpawnLocation at all — worth knowing if spawn behaviour
  ever looks odd.
- **Terrain elevation** — the ground is still a flat slab under the dressing.
- **Zone 1 (`StarterZone`) needs remaking** — see Phase 5b. It has not had the
  village treatment and is visibly the roughest part of the game.
- Boss arena is a floor, pillars and braziers; it needs atmosphere.

### Models — armour and gear

Armour is coloured boxes welded at the right attach points. Weapons have real
shaped geometry, armour does not.

- Real meshes for helmet, chest, legs, boots, accessory, gear
- `ItemConfig.Appearance.MeshId` already exists as the hook
- Attach offsets in `BodyConfig.AttachPoints` will need re-tuning per mesh
- Rarity should read on the model, not just the icon

### Models — enemies

Enemies are assembled from primitive rigs (`Blob`, `Biped`, `Quadruped`) at
spawn time. They animate not at all.

- Real models per enemy, hooked through `EnemyConfig.Appearance.ModelId`
- Walk, attack, hurt and death animations
- Distinct silhouettes — a Goblin and a Goblin Warrior currently differ only in
  colour and scale

### Animations — weapons and characters

Only one animation exists: a single Motor6D swing arc per archetype.

- Idle pose per archetype
- Multi-hit combo chains rather than one repeated swing
- Hit reactions on the player when damaged
- Ranged archetypes need actual projectiles — bows and staves currently hit
  instantly at up to 90 studs with no visible travel
- Ability animations — the abilities are defined in config and granted on
  Rare+ weapons but are not implemented at all
- Footstep and landing effects

### GUI cleanup

The HUD and panels are functional but visually unfinished.

- Consistent spacing and alignment pass across HUD, inventory and reveal
- Item icons — every card currently shows text only
- Inventory grid needs better density at small viewport sizes
- Reveal card is plain; rare drops should feel dramatically different
- Panels for Quests, Shop and Settings do not exist
- Mobile: designed for but never tested on a device
- Button, hover and disabled states are inconsistent between panels

---

## Known gaps and caveats

- **Abilities are config-only.** Defined in `ItemConfig`, granted on Rare+
  weapons, never implemented.
- **The zone gate is decorative.** The part and attribute exist; nothing reads
  them.
- **Four remotes are declared but sealed** — `DailyClaimRequest`,
  `QuestRequest`, `ShopRequest`, `ZoneTravelRequest`. They return
  `NotImplemented` rather than hanging, which is intended until their phases land.
- **Gear stat aggregation is only partly proven.** Baselines verified; adding
  Health and MoveSpeed from equipped armour has not been explicitly tested.
- **Mobile is untested on hardware**, and the world is now ~14,000 parts with
  ~190 light sources, so a mobile performance check matters more than it did.
- **No sound anywhere.** Every asset id is `0`.

---

## Manual steps (cannot be automated)

- Set `Lighting.Technology` to `Future` — scripts are not permitted to
- Enable Studio Access to API Services on any new place
- Create gamepasses and developer products, paste ids into `MonetizationConfig`
- Upload audio and icons, paste ids into `AssetConfig`
- Source or commission real meshes for armour and enemies
- **Save the place after world changes** — File → Download a Copy, overwriting
  `RNGArmory.rbxl`. See README, "Saving the world".
