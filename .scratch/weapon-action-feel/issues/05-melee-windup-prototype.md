Type: prototype
Status: resolved
Blocked by: 01

## Question

Prototype the Windup feel for Melee: Sword (`Semi_Automatic`, currently has no real Windup — its existing `swing_time`/`swing_timer` sweep is a post-hit flourish being retired per ADR-0003), plus restyling Dagger's existing post-hit sweep as the new Follow-through (`Automatic`, this one already has an animation — the question is whether it stays as-is or gets adjusted to sit consistently alongside the new system).

Build a cheap, concrete artifact the user can react to: a Sword Windup (a visible draw-back/telegraph before the swing lands, distinct from today's instant-hit-then-sweep), and a Dagger Follow-through pass (confirm today's sweep still reads well under the new model, or adjust it). Use ticket 01's settled Trigger/Windup/Resolve control flow as the concrete mechanics to animate against. Flag whether Sword's Windup needs new art or can work as transform-only animation on the existing sprite.

Call the Skill tool with "prototype" to run this.

## Answer

Built an interactive HTML/canvas prototype (Sword and Dagger lanes, running the real resolved timing model from tickets 01-03) and reviewed it live with the user, including an A/B round after the first pass.

**Sword's Windup**: `windup_fraction = 0.37` (~206ms out of a 556ms cycle) confirmed as a good starting point.

**Sword's Resolve motion — this ticket's real open question**: the architecture locks "Windup-gated weapons go straight from Resolve to Ready, no separate flourish timer" (ticket 01), so whatever visual plays at Resolve has to be derived from existing state (time-since-resolve, recoverable from `cooldown_timer`), not a new persisted field. First candidate — a spring reacting to the Resolve moment, the same idiom validated for gun recoil in the Ranged prototype — **was rejected live: "feels wrong."** Two alternatives were built for direct A/B comparison, both still derived (no new field), differing only in motion curve:
- Hard snap + quick linear return (no ease, no bounce)
- **Eased sweep-through, no bounce** (ease-out from the windup's draw-back angle through to the follow-through extreme over ~70ms, then ease-out back to neutral over ~110ms) — **confirmed as the one that works.**

Takeaway for whoever implements this: `draw_weapon()`'s Sword rendering needs a small deterministic (non-physics) two-phase ease curve keyed off time-since-resolve, not a spring-decay. The spring approach validated for Gun recoil does *not* generalize to Sword — different weapon, different motion language.

**Dagger's Follow-through**: `follow_through_time = 150ms` (carried straight over from its current `swing_time`, unchanged) — **confirmed fine as-is**, no adjustment needed from today's already-shipped feel.

**Art call: both need real new art**, same as every Ranged weapon in the prior ticket — transform-only motion sells the mechanic, not the punch.

**Prototype captured as a primary source**: committed to the throwaway branch `prototype/melee-windup` (commit `1731104`), out of main.
