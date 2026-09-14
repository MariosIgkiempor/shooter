Type: prototype
Status: resolved

## Question

What shape(s) represent the Player and Enemy (Floater, Swarmer) bodies once sprites are dropped, and what are the exact mechanics of the movement-conveying transform (tilt/squish) applied when an actor starts/stops moving?

This is the foundational ticket for the whole map: it sets the shape vocabulary (form, size relative to the collision box, fill vs stroke, color-by-entity-type) that every other in-scope entity (weapons, bullets, pickups, tilemap) will be judged against for consistency, and it's a "how should it look / how should it behave" question — raise the fidelity with a real prototype rather than deciding in the abstract.

Cover at minimum:

- Base shape per entity (e.g. a rounded rect for Player, distinct shapes or just color/size variation for Floater vs Swarmer) and how `flip_x` (today's only actor-body transform, main.odin:362) is preserved or reinterpreted.
- The transform trigger: does it fire once on movement-start (as the user's example describes — "tilt/squish the player rect when they start moving"), continuously while moving, or also on stop/direction-change? Player's `input: Vec2` (main.odin:344-366) and Enemy's per-frame `delta: Vec2` (enemy.odin:455-525) are the existing movement signals to key off.
- The transform's math and easing — squash/stretch scale, tilt angle, how it decays back to rest. `draw_weapon`'s pivot/angle/scale animation (main.odin:872-976, e.g. the sword's `ease_out_cubic` swing at lines 899-916) and `exp_approach` (editor.odin:147-149) are the existing precedent/tooling to build on or extend.
- Where this hooks into the render loop: `draw_actor` (main.odin:779-799) is the single shared call site for both Player and Enemy — confirm the transform lives there rather than being duplicated per entity type.

Unblocked from the start — nothing in this map depends on prior decisions here.

Prototype this directly (throwaway branch), per this map's Notes.

## Prototype

Captured on branch `prototype/actor-shape-transform` (commit `845e095`). Run it with `odin run . -out:build/shooter.bin` from `main` after checking out that branch, then in-game:

- **F9** cycles four states: Sprites (baseline, today's real art) → **A** continuous squash → **B** directional lean → **C** movement-start pulse. Current variant shown top-left.
- Applies to both Player and every enemy (Floater, Swarmer, Grounded) at once, so you can compare all three actor types per variant.
- Shape is chosen by entity type, held constant across variants A/B/C, so the comparison is about the *transform* only: Player/Grounded = rounded-ish rect (`draw_rectangle` with rotation/scale), Floater = circle, Swarmer = triangle (`rl.DrawPoly`).
- Known caveat surfaced while building this: Floater's circle can't visually show variant B's rotation at all (a circle is radially symmetric) - worth reacting to directly, since it may mean Floater needs a non-circular shape if B is the winner.

## Answer

**Variant A confirmed: continuous isotropic squash, no rotation/tilt.** Mechanics: while an actor is moving (`delta != {0,0}`), `scale_x` eases toward `1.15` and `scale_y` toward `0.85`; both ease back to `1.0` at rest. Eased via `exp_approach` at rate `12`/sec (`ART_PROTO_SQUASH_RATE`). `tilt_deg` stays `0` always — variant B's lean and variant C's edge-triggered pulse are both dropped, along with the `was_moving`/`pulse_timer` machinery C needed.

Base shapes, held constant across all three prototyped variants and implicitly validated alongside A: Player and Grounded enemies render as a rectangle (scaled per the above, anchored bottom-center at the actor's feet, same as the sprite it replaces); Floater renders as a circle (radius scaled by the average of `scale_x`/`scale_y`); Swarmer renders as a triangle (`rl.DrawPoly`, 3 sides, same radius rule). Since A never rotates, the caveat raised during prototyping — that a circle can't visually show rotation — turned out to be moot for the winning variant.

Colors used in the prototype (SKYBLUE player, RED grounded, VIOLET floater, ORANGE swarmer) were placeholder/first-pass only, not locked by this ticket — real palette is separate follow-on work, not raised as fog here since it's a content-authoring detail, not a structural decision.

This sets the shape vocabulary (rect/circle/triangle by entity type) and the transform mechanics (continuous squash, `exp_approach`-eased, no rotation) that [weapon shapes](02-weapon-shape-and-reconcile-weapon-action-feel.md), [bullets/pickups](03-bullets-and-pickups-shape-treatment.md), [tilemap](04-tilemap-shape-treatment.md), and the [shape-vocabulary consistency pass](05-shape-vocabulary-consistency-pass.md) all now build on.

## Comments

- Variant A's *continuous* squash was reversed to a one-shot pulse on rest↔moving transitions by [07](07-squash-pulse-on-movement-transitions.md): keyed off intent, "moving" was nearly always true for enemies, so every body sat permanently squished. Shape vocabulary and the `exp_approach`-eased, no-rotation mechanics stand.
