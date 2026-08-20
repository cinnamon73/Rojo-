# Stances, carry and footwork — the brief

## The goal in one line

**You should be able to tell what someone is holding before they ever attack.**

Right now every class stands and walks identically — the stock R15 idle with a
weapon stapled to one hand. The weapon changes what a swing looks like and
nothing else. That is the gap: a greataxe weighs a hundred pounds and a pair of
daggers weigh nothing, and the body should say so at rest, while walking, and
while turning, not only during the 0.4 seconds of a swing.

## The principle

Weight is communicated by what the body does **between** actions.

- A heavy weapon is not held up. It is **rested, shouldered, planted or
  dragged**, because holding it out would be exhausting. Its owner leans to
  counterbalance it and moves slower and wider.
- A light weapon is held **ready**, close to the body, because it costs nothing
  to keep it there. Its owner is upright, compact, and quick.
- A ranged weapon is **carried**, not aimed, until it is needed.

Everything below is that one idea applied per class.

## Where this lives

Stance and locomotion belong to the **item**, exactly as movesets already do
(see `WeaponConfig`). Hand the Berserker a bow and he should stand like an
archer. The class contributes a body; the item contributes everything about how
that body carries itself.

So `WeaponConfig` gains, alongside `Combo`:

```
Stance      -- looping idle, played at Idle priority
Walk        -- looping locomotion, played at Movement priority
Run         -- optional; falls back to Walk
Carry       -- a tag describing the silhouette: "Drag", "Shoulder",
               "Ready", "Sling", "Rest"
```

Attacks already play at Action priority, so they override stance and walk with
no extra bookkeeping. Idle < Movement < Action is doing the work for us.

## Per class

**Berserker — greataxe, `Carry = "Drag"`.** The headline. The axe is too heavy
to carry, so he doesn't: it hangs from his right hand with the head **dragging
on the ground behind him**, and he leans forward against its weight to walk.
Standing still, the head is planted and he rests on the haft. Moving, the head
scrapes — which should throw dust and a scrape sound where it touches, because a
drag the player can see but not hear is half an effect. His turn should feel
like the axe has to be hauled around after him.

**Assassin — twin daggers, `Carry = "Ready"`.** He already spawns with a second
dagger, but it is welded flat to his forearm as decoration and never used. Both
daggers should be **held, one per hand**, in a low compact guard — right hand
forward, left hand reversed in an icepick grip near the hip. The combo should
genuinely alternate: right stab, left cross, then both. He is the one class
whose off-hand is a weapon rather than ballast, and that should be visible
standing still.

**Swordsman — arming sword, `Carry = "Ready"`.** Balanced middle guard, blade
angled up and across the body, free hand open and forward for balance. Upright
and neutral: he is the readable baseline the others are read against.

**Paladin — blade and shield, `Carry = "Rest"`.** Shield up and forward covering
the torso, blade held back and low behind it, weight on the back foot. He walks
**behind the shield** and should look like he could stop moving and hold ground
at any instant.

**King — royal blade, `Carry = "Shoulder"`.** Blade resting on the shoulder,
posture open and unhurried, free hand loose. Arrogance is the read: he is not
braced for anything.

**Archer — bow, `Carry = "Sling"`.** Bow carried in the left hand angled across
the body, string hand loose near the hip. Never drawn until firing.

**Musketeer — musket, `Carry = "Shoulder"`.** Musket shouldered across the back
diagonal or cradled in both arms, muzzle up and away.

**Necromancer — staff, `Carry = "Rest"`.** Staff planted like a walking stick,
taking weight on each step — the only class whose walk should look *aided*
rather than encumbered.

## Footwork

Feet must not slide. Whatever the stance, the walk cycle needs real weight
transfer: a contact, a passing pose and a push-off per stride, with the hips
rising and falling. Heavy carries take **fewer, longer, wider** steps; light
carries take more and shorter. The greataxe drag should visibly cost him
momentum when he changes direction.

## Constraints that already bit us, so do not relitigate them

- Author against a **default R15** (`tools/rig_standard_r15.json`). The
  authoring script refuses anything else. A player's own avatar can have
  shoulders at hip height and 0.996 studs of reach against a default's 1.729,
  and poses tuned to it look broken on everyone.
- Keep the wrist inside reach. The exporter range-checks every beat.
- Origin at the grip, weapon along +Z in Blender. Grip offsets and mesh
  `GripLift` already depend on it.
- Idle and walk **loop**, so the first and last pose must be identical or the
  cycle will pop once per revolution.

## Done means

Not "the animation uploaded". Done is: stand still as each class and the
silhouette tells you what they hold; walk and the feet do not slide; the
Berserker's axe head is on the ground behind him and throwing dust; the
Assassin has a dagger in each hand and uses both. Seen in a running session,
not inferred from a log line.
