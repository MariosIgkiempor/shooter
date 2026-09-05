Type: prototype
Status: resolved
Blocked by: 01

## Question

Prototype the Windup feel for Magic: Fire_Wand and Poison_Staff (both `Semi_Automatic`), plus a Follow-through pass for Flame_Staff (`Automatic`, currently zero animation). Magic has no real art yet at all — every kind reuses the Pistol icon placeholder (`weapon_texture_names`) — so this ticket is also the first real design pass on what Magic looks like in motion.

Build a cheap, concrete artifact the user can react to: a Fire_Wand Windup (a charge-up/glow-build before the fireball launches), a Poison_Staff Windup (note it's ground-targeted at the live mouse position per `cast_range`/`clamp_point_to_range`, not `aim_dir` like the others — confirm the live-tracking-aim decision extends naturally to a tracked cursor-position target), and a Flame_Staff Follow-through (a flicker/pulse sustained across its ~100ms tick rate while channeling). Flag concretely what new art/particles each needs, since Magic has none to build on today.

Call the Skill tool with "prototype" to run this.

## Answer

Built an interactive HTML/canvas prototype (Fire_Wand, Poison_Staff, Flame_Staff lanes) and reviewed it live with the user, including one correction round.

**Fire_Wand's Windup**: `windup_fraction = 0.21` (~175ms out of an 833ms cycle) confirmed as a good starting point — charge-up glow reads as gathering energy before the bolt launches.

**Poison_Staff — this ticket's real finding**: `windup_fraction = 0.18` confirmed for timing, but the first pass's targeting was wrong. It was built live-tracking the mouse throughout Windup (matching this map's locked "aim tracks live" rule) — **rejected live**: "poison staff shouldn't follow mouse after click - place it where the mouse was clicked + let it wind up there." Ground-targeted casts are a discrete pick, not a continuous aim, so unlike `aim_dir`-based weapons the target now **locks at Trigger**, not tracked through Windup. This is a genuine, confirmed exception to the map's locked aim-tracking rule, scoped specifically to ground-targeted casts (Poison_Cloud today) — written up as [ADR-0005](../../../docs/adr/0005-ground-targeted-casts-lock-at-trigger.md), with a pointer added to [Trigger/Windup/Resolve state machine](01-trigger-windup-resolve-state-machine.md) since it requires a small addition to that ticket's Trigger-time path. Vocabulary/locked-decisions updated in CONTEXT.md and this map's Notes. The prototype was corrected to match and republished.

**Flame_Staff's Follow-through**: `follow_through_time = 80ms`, and **discrete per-tick pulse confirmed over continuous stream** — at a 100ms tick rate, the pulse read as channeling better than a blended stream did.

**Art call: all three need real new art**, same as every other weapon-kind across this map — consistent with Ranged and Melee's findings, and expected here even more given Magic currently has zero art of its own (every kind reuses the Pistol icon placeholder).

**Prototype captured as a primary source**: committed to the throwaway branch `prototype/magic-windup` (commit `b258db7`), out of main.

**Amendment (Art revamp map)**: the "all three need real new art" call above is superseded — see [Weapon shape and reconcile weapon-action-feel](../../art-revamp/issues/02-weapon-shape-and-reconcile-weapon-action-feel.md). Fire_Wand's shape+enhanced-particle-effects treatment (converging charge streaks, an impact flash/ring, non-linear fades) was confirmed sufficient, live-tested; expected to generalize to Poison_Staff/Flame_Staff.
