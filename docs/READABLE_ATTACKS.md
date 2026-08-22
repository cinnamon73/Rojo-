# Readable attacks — the brief

## The requirement, in one line

**A player must be able to tell what an attack is while it is happening.**

Not "is it smooth", not "does it clip" — those are the absence of faults, and
an animation can pass all of them and still be unreadable mush. The test is
whether someone watching, once, at normal speed, can say what just happened:
*he cut down-left*, *he stabbed*, *he brought it over the top*.

Right now they cannot, and that is the only thing that matters.

## Why the current ones fail

**They rewind.** Each swing rotates the blade out to full sweep and then
rotates it straight back along the same path to return to the guard pose. Out
and back through the same arc is not a strike — it is a wave. The eye sees the
blade go left, then go right, and reads no intent in either.

That is a structural mistake, not a tuning one. It came from wanting every
clip to start and end on the guard so transitions never snap. The goal was
right; the method was wrong.

**Everything is the same size.** Nine of eleven melee clips sweep 95–130° at
roughly the same speed over roughly the same duration. A thrust should not
look like a cleave. If the silhouettes are interchangeable, the moveset reads
as one move played repeatedly.

**No moment of impact.** The blade travels at a fairly even rate throughout.
Nothing says *here — this is the hit*. Readability comes from contrast: a slow
load, a strike too fast to track, and a held moment after it.

## The rules

1. **One idea per attack.** A hit is a single sentence: *diagonal cut from
   high-right to low-left*. If it cannot be said in one clause, it is two
   attacks or it is noise.

2. **One direction of travel.** The blade goes one way through the strike and
   does not come back the way it came. Reversal is what makes motion illegible.

3. **The combo is a chain, not three separate clips.** Hit 1 ends in its
   follow-through; hit 2 *starts* from that follow-through and carries on.
   That is how a real combo flows, and it removes the need for any clip to
   rewind — the return to guard happens once, at the end of the chain, or as a
   crossfade when the player stops attacking.

4. **Recovery is not the strike backwards.** After the follow-through the
   weapon is brought back by a different, smaller, quicker path — dropped and
   pulled in, not re-swept. It should be visibly a recovery, never a second
   swing.

5. **Contrast the timing.** Roughly: 35% load, 15% strike, 50% recovery. The
   strike should feel almost instant against the parts either side of it. Even
   pacing is what makes a swing read as a wave.

6. **Make the silhouettes different.** A thrust travels along the body's
   forward axis and barely rotates. A cleave sweeps horizontally. An overhead
   comes down the vertical plane. Three attacks should be distinguishable as
   three shapes even in freeze-frame.

## How this gets checked

The existing measurements stay — clearance, elbow snap, tip evenness — because
regressions there are real. But they are necessary, not sufficient, so add:

- **REVERSALS** — how many times the blade's direction of travel flips during
  the strike phase. A readable attack has **zero**. This is the measurement
  that would have caught the rewind, and its absence is why the rewind
  survived several passes of "improvement".
- **STRIKE RATIO** — peak tip speed over mean tip speed. Even pacing scores
  near 1 and reads as a wave; a real strike should be well above it.

## Done means

Freeze any frame of the strike and the attack is identifiable. Watch the three
sword hits and they are three different moves that flow into one another, not
one move played three times. Seen at normal speed, in the game, not inferred
from a metric.
