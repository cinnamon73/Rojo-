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
| 2 | RNG — items, rarities, roll service, luck, pity, reveal, auto-roll | ✅ Done |
| 3 | Inventory — item instances, equip/unequip, sell, favourite, comparison | ✅ Done |
| 4 | Combat — weapons, attacks, damage, enemy AI, rewards | ✅ Done |
| 5 | World — village, castle, paths, lighting, dressing | ✅ Done |
| 5b | **Zone 1 rebuild — the hunting grounds** | ⬜ Next |
| 6 | **Boss — the Goblin King** | ⬜ Next |
| 7 | Progression — quests, dailies, boosts, zone gate enforcement | ⬜ |
| 8 | Polish — audio, VFX, notifications, settings UI | ⬜ |
| 9 | Monetization — gamepasses, products, VIP, cosmetics | ⬜ |
| 10 | Full test pass — rejoin, multiplayer, exploit attempts, mobile | ⬜ |

---

### Phase 5b — Zone 1 rebuild

`StarterZone` was built in an early pass and never got the treatment the
village did. It is now visibly the worst-looking part of the game, and it is
where players spend their combat time.

- Organic path network, built the same way as the village: one flat surface at
  a single height, no overlaps, colour and material variation only
- Lighting pass — the zone is unlit while the village is lit at dusk
- Terrain elevation and variation rather than a flat slab
- Dressing: proper copses, rocks, ruins, camp detail
- Rework the slime pit, goblin camps and boss arena as real places rather
  than markers with props around them
- The zone gate between village and zone needs to read as a real boundary

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
- **The guardhouse tower** outside the gate is the last un-rebuilt structure —
  a plain 52-stud shaft with a stepped-pyramid cap, standing at 75.5, taller
  than the castle keep. It needs redesigning or removing.
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
- **Save the place as `RNGArmory.rbxlx` after world changes** — see README
