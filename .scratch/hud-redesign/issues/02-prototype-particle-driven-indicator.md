Type: prototype
Status: resolved
Blocked by: 01

## Question

Build a rough, concrete, reactable prototype of the particle-driven resource indicator(s) decided in [Decide the shape and content of the above-player indicators](01-above-player-indicator-shape-and-content.md), playing live above the player in-game.

Cover:
- The actual particle mapping: how density, color, spawn rate, and/or motion communicate resource level (e.g. health draining from 100%→10% should read as visibly different at a glance, not just "fewer particles eventually").
- How the effect stays *constantly playing* using the existing primitives in [particle.odin](../../../particle.odin) (`spawn_particle_burst`, `spawn_particle_sprite`) — every current effect in that file is spawned imperatively (once, or per-frame-polled from game logic); decide whether a lightweight continuous-emitter concept is worth adding, or whether calling a spawn function every frame from `update`/`draw` is enough.
- Legibility during actual gameplay (movement, combat, enemies on screen) — not just a static screenshot.

Reuses the world-space anchor formula already established in the map's Notes (`entity.y - document_size.y - gap`, matching `draw_health_bar`'s existing pattern) — no new positioning system to invent.

This raises the fidelity of discussion for [Decide the fate of enemy health bars](03-enemy-health-bar-unification.md), which decides how much of this design carries over to enemies.

## Answer

Primary source: `prototype/hud-resource-indicator-bars` branch, commit `bd6b359`.

**Refines ticket 01's shape** (not a reversal): the first pass built exactly what ticket 01 described — icon with particles floating/orbiting/pulsing freely around it — and it was rejected live: "I want a rectangular health bar with particles inside the filled-in area." Icon + particles, no nine-slice, and no numeric readout all still hold; only the particle *arrangement* changed, from free-floating to contained-in-a-bar.

**Validated design**: icon beside a flat rect bar (no nine-slice — a plain background rect + a translucent fill rect sized to the resource fraction, so the level stays legible even where particles are sparse), with particles bouncing inside that filled region. Two motion variants were built and compared live:

- **Simmer** (random-direction jitter, bouncing off the fill bounds) — **won**.
- **Current** (rightward flowing drift) — rejected.

Particle *count*, not spawn rate, tracks the resource fraction directly (a near-empty bar sustains one or two particles, a full bar sustains many), so the fill width and the particle count always agree rather than sending two competing signals. Reload (Gun) gets its own distinct treatment regardless of variant: faster, fully chaotic motion in the reload color, so it reads apart from "just low."

Iterated to: bars sized 30×6 (up from an initial 18×3 — "bars should be bigger"), the two rows (Health, Ammo) stacked close together (row spacing reduced to 1), and particles drawn translucent (55% max alpha) fading via the same `lifetime / max_lifetime` convention `particle.odin`'s own `draw_particles` uses, rather than solid dots.

**Answers the ticket's open questions directly**:
- Per-frame imperative spawning (no new continuous-emitter type) reads fine as "constantly playing" once particle *count* is tied to fraction rather than raw spawn rate — no need for the lightweight continuous-emitter concept the ticket raised as an option.
- **New technical finding**: communicating level via particles *contained* inside a shrinking rect needs bounded/bouncing motion, which the shared drag-based primitives in `particle.odin` (`spawn_particle_burst`, `spawn_particle_sprite`) don't support — they're built to fly outward and fade, not to be clamped inside bounds. The real implementation will need its own small per-bar particle set (position/velocity/lifetime), not `game.particles`.
- **Bug found and fixed during iteration, worth carrying into the real implementation**: storing particle positions in world-space coordinates made them visibly react to player velocity — the bar itself is recomputed fresh from the player's position every frame, so on player movement the bar's bounds shifted out from under the particles' static absolute positions and the boundary-clamping code yanked them back, reading as if particles were being dragged by player motion. Fixed by storing each particle's position as a local offset relative to the bar's corner, converting to world-space only at draw time — this decouples particle motion from player motion entirely and should be the pattern the real implementation uses.
