Type: grilling
Status: resolved

## Question

Ticket [01](01-actor-shape-and-movement-transform.md) confirmed Variant A: a *continuous* squash — `scale` eases toward `{1.15, 0.85}` for as long as an actor is moving, back to `{1,1}` at rest. In play, every player and enemy body looked permanently squished. Why, and what replaces it? The report also asked whether the collision rect should squash along with the body.

## Answer

**Why it stuck:** "moving" was keyed off *intent*, not displacement. The player fed raw WASD, so holding into a wall kept the squash even though `move_actor` resolved the step to zero. Enemies fed their steering `delta`, which is nearly never exactly `{0,0}` for a live body — Floater's sinusoidal wobble, Swarmer's orbit, separation pushing any body near another of its kind, a flow-field direction into a wall it can't pass. So the decay path existed but the "at rest" state was almost never reached.

**Variant A reversed: the squash is now a one-shot pulse on the rest→moving *and* moving→rest transitions** (`update_actor_squash`, main.odin). Both edges snap `scale` straight to the peak `ACTOR_PULSE_SCALE` (`{1.15, 0.85}`, same for start and stop — a stop reads as a plant, an inverse tall stretch reads as a jump), then `exp_approach` eases it back to `{1,1}` at `ACTOR_SQUASH_RATE` (12/s). No timer and no debounce: a retrigger just resets the peak, so back-to-back edges are self-limiting. This is *not* a return to 01's prototyped Variant C — that carried `pulse_timer` machinery and an explicit curve; this is one `was_moving` bool per actor and the easing already in place.

**"Moving" is actual displacement this frame**, uniform for every actor: `actor_moved(before, after)` compares the position before and after the movement step against `ACTOR_MOVE_EPSILON` (0.01px). Player and terrain-colliding enemies read across `move_actor`; Floater/Swarmer, which bypass `move_actor`, read across their direct position add. A player pushing into a wall is at rest; a melee enemy toggling `delta = {}` at reach boundary no longer flickers.

**The shop and run-ended screens no longer freeze a pulse mid-squash**: `update_game_state` returned before the squash update, so a body caught mid-ease stayed there for the whole shop. `decay_actor_squashes` now runs in that early-return branch with `moving = false` (nothing moves there, so the flag is exact).

**Collider: deliberately untouched.** The request's second half — squash the collision rect with the body — was dropped during grilling. `actor_collision_rect` stays the fixed 24×24 AABB for every consumer (terrain, bullets, melee, hitscan, relics, poison, Tell areas); a fluctuating collider against terrain is a tunnelling/stuck-in-wall source and the player would not perceive it. The pre-existing enemy draw-size/collider-size mismatch (tuning.odin, `ACTOR_SIZE` comment) is likewise unchanged and remains its own question.

**Tunables** keep their F8 exposure: `player.squash_rate`, and `player.moving_scale_x/y` renamed to `player.pulse_scale_x/y` (ids are not persisted anywhere). **Tests**: `actor_squash_test.odin` pins both edges, the no-re-peak decay in either steady state, an undisturbed resting body, and the epsilon.

## Comments

- Amended by [08](08-squash-pulse-follows-the-movement-axis.md): the peak is no longer a fixed `{1.15, 0.85}` in x/y. Starting stretches the body *along* its movement axis and stopping squashes it along that axis (the swap), drawn as a rotation-free axis scale about the body centre; the rate dropped from 12/s to 6/s. The edge rule, the displacement-not-intent rule, the shop decay and the untouched collider all stand.
