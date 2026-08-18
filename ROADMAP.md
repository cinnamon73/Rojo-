# RNG: ARMORY — roadmap

Two tracks run in parallel:

- **Phases** — systems that do not exist yet.
- **Polish** — systems that exist and work, but are placeholder quality.

Both matter. The game is currently a *functional* vertical slice and a *rough*
one; shipping needs both tracks closed.

---

## Build phases

Build in order. Test each phase before starting the next, and do not stack new
systems on top of broken ones.

| Phase | Scope | State |
|---|---|---|
| 1 | Foundation — structure, config, remotes, data schema, saving, UI shell | ✅ Done |
| 2 | RNG — items, rarities, roll service, luck, pity, reveal, auto-roll | ✅ Done |
| 3 | Inventory — item instances, equip/unequip, sell, favourite, comparison | ✅ Done |
| 4 | Combat — weapons, attacks, damage, enemy AI, rewards | ✅ Done |
| 5 | World — village hub, Verdant Fields, spawns, boss arena, zone gate | ✅ Done |
| 6 | **Boss — the Goblin King** | ⬜ Next |
| 7 | Progression — quests, dailies, boosts, zone gate enforcement | ⬜ |
| 8 | Polish — audio, VFX, notifications, settings UI | ⬜ |
| 9 | Monetization — gamepasses, products, VIP, cosmetics | ⬜ |
| 10 | Full test pass — rejoin, multiplayer, exploit attempts, mobile | ⬜ |

---

### Phase 6 — Goblin King

The arena and gate are already built and tagged; nothing spawns in them yet.

- Boss spawn from the `BossSpawn` marker (`BossId` attribute already set)
- Multiple attacks: sword swing, ground slam, charge, summon adds
- **Telegraphs** — a visible wind-up before each attack, so the fight is
  readable rather than reflex-based
- Phase transitions at health thresholds, changing attack mix and pace
- Large on-screen boss health bar, distinct from ordinary enemy bars
- Rare loot table with a genuinely better drop distribution
- Server-wide announcement on an exceptional drop
- Enforce the `RequiresPower = 1200` gate — currently the gate part exists and
  carries the attribute, but nothing reads it, so players can walk straight
  through

### Phase 7 — Progression

- Quest system, data-driven like items and enemies (kill counts, roll counts,
  boss kills, currency earned)
- Daily rewards on a 7-day escalating track, with **server time authoritative**
  so a client clock change cannot farm it
- Temporary boosts with durations, surfaced in the HUD
- Zone gate enforcement and travel, driven by the existing `ZoneTravelRequest`
  remote (declared and currently sealed as `NotImplemented`)
- Achievements and titles

### Phase 8 — Polish

- Audio throughout — UI, rolls, reveals by rarity tier, combat, boss
- VFX for rare reveals, level ups, boss phases
- Toast notifications and the global announcement banner (both remotes exist and
  currently only log to console)
- Settings panel wired to the settings already in the profile schema
- Tutorial prompts for the first-join flow

### Phase 9 — Monetization

- Gamepasses: VIP, Auto Roll, Fast Rolls, Extra Inventory, Extra Slot
- Developer products: luck boosts, coin packs, XP boosts
- `ProcessReceipt` handled safely — never grant twice; the profile already
  carries a capped `ProcessedReceipts` list for exactly this
- Cosmetics: trails, auras, weapon effects, titles

### Phase 10 — Full test pass

Join, leave, rejoin, data integrity, multiple players, remote spam, invalid
payloads, server shutdown mid-session, mobile layout and touch targets.

---

## Polish backlog

Everything here **works**. It is placeholder quality and needs a proper pass.
None of it is blocking, and none of it should be started before the phase work
it depends on.

### Models — armour and gear

Armour is coloured boxes welded at the right attach points. Weapons have real
shaped geometry, armour does not.

- Real meshes for helmet, chest, legs, boots, accessory, gear
- `ItemConfig.Appearance.MeshId` already exists as the hook — setting it is the
  only code change needed
- Attach offsets in `BodyConfig.AttachPoints` will need re-tuning per mesh
- Rarity should read on the model, not just the icon

### Models — enemies

Enemies are assembled from primitive rigs (`Blob`, `Biped`, `Quadruped`) at
spawn time. They animate not at all.

- Real models per enemy, hooked through `EnemyConfig.Appearance.ModelId`
- Walk, attack, hurt and death animations
- Distinct silhouettes — a Goblin and a Goblin Warrior currently differ only in
  colour and scale
- Death should do something better than fading out after two seconds

### Animations — weapons and characters

Only one animation exists: a single Motor6D swing arc per archetype.

- Idle pose per archetype so a held weapon does not sit rigid
- Multi-hit combo chains rather than one repeated swing
- Hit reactions on the player when damaged
- Ranged archetypes need actual projectiles — bows and staves currently hit
  instantly at up to 90 studs with no visible travel
- Ability animations (Whirlwind, Ground Slam, Dash Strike, Multi Shot, Arcane
  Blast) — the abilities are defined in config and granted on Rare+ weapons but
  are not implemented at all
- Footstep and landing effects

### Map and buildings

The world was fully rebuilt: a fortified walled village and an enclosed
overgrown hunting zone, ~7,200 parts, everything anchored and shadow-casting
with semantic names. What remains is depth rather than structure.

- Building interiors — every building is still a solid shell with a door that
  does not open. This is the biggest remaining gap in the village.
- NPCs — no villagers, no shopkeepers, nothing alive inside the walls
- Terrain variation — the ground is still a flat slab underneath the dressing.
  Real elevation, water and worn dirt would do more than additional props.
- Boss arena is a floor, pillars and braziers; it needs atmosphere befitting
  the fight it will host
- Skybox and a time-of-day pass — the lamp posts, forge and campfires all have
  working PointLights, but it never gets dark enough to show them off
- Interior light spill — windows read as glass but no light comes through them

### GUI cleanup

The HUD and panels are functional but visually unfinished.

- Consistent spacing and alignment pass across HUD, inventory and reveal
- Item icons — every card currently shows text only; `AssetConfig.Images` has
  the slots waiting
- Inventory grid needs better density and readability at small viewport sizes
- Reveal card is plain; rare drops should feel dramatically different
- Panels for Quests, Shop and Settings do not exist — those nav buttons fire a
  signal nothing listens to
- Mobile: verify touch targets and layout under the compact breakpoint; this has
  been designed for but never actually tested on a device
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
- **Mobile is untested on hardware.**
- **No sound anywhere.** Every asset id is `0`.

---

## Manual steps (cannot be automated)

- Enable Studio Access to API Services on any new place
- Create gamepasses and developer products, paste ids into `MonetizationConfig`
- Upload audio and icons, paste ids into `AssetConfig`
- Source or commission real meshes for armour and enemies
