Type: prototype
Status: resolved
Blocked by: 01, 02

## Question

Prototype the Windup feel for Ranged: Pistol and Shotgun (both `Semi_Automatic`), plus a refined Follow-through pass for SMG (`Automatic`, currently zero animation).

Build a cheap, concrete artifact the user can react to — motion/timing sketches and rough visual treatment for: a Pistol Windup (quick, snappy), a Shotgun Windup (should read heavier/more deliberate than Pistol given its role), and an SMG Follow-through (a per-shot recoil-kick, sustained across rapid re-triggers without feeling janky at ~83ms between shots). Use ticket 01's settled Trigger/Windup/Resolve control flow and ticket 02's settled empty-clip behavior as the concrete mechanics to animate against. Flag whether each needs new art (sprite frames/particles) or can land as transform-only (rotation/offset/scale, like melee's existing sweep) despite this map's default assumption that new art is needed — a prototype is exactly where that assumption gets tested.

Call the Skill tool with "prototype" to run this.

## Answer

Built an interactive HTML/canvas prototype (three "lanes" — Pistol, Shotgun, SMG — each running the real resolved timing model from tickets 01-03: cycle = `1/action_rate`, Windup as a `windup_fraction` proportion per ADR-0004) and reviewed it live with the user.

**Feel confirmed for all three**, at these starting values (still content-authoring's to finalize, not locked numbers, but validated as a good starting point):
- Pistol: `windup_fraction = 0.24` (~80ms out of a 333ms cycle) — reads quick/snappy.
- Shotgun: `windup_fraction = 0.26` (~236ms out of a 909ms cycle) — reads clearly heavier than Pistol despite a similar fraction, because the cycle itself is ~2.7x longer.
- SMG: `follow_through_time = 45ms` (within an 83ms cycle) — recoil-kick keeps up under sustained hold-to-fire without looking cut off or janky.

**Art call: all three need real new art** (sprite frames and/or particles — e.g. a muzzle flash, recoil frames), confirming this map's default assumption rather than overturning it. Plain rotation/offset transform animation on the existing placeholder sold the *mechanic* (the timing and weight read correctly) but not the *punch* — none of the three were judged convincing enough to ship as transform-only.

**Prototype captured as a primary source**: committed to the throwaway branch `prototype/ranged-windup` (commit `a60f97a`), out of main — not merged, main never carries the throwaway code. Also published live as an Artifact for the review itself: https://claude.ai/code/artifact/38115330-078d-481d-aea3-2f7aed6c02fa (may not remain live/updated indefinitely; the branch is the durable record).
