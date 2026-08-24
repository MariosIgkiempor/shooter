Type: prototype
Status: resolved

## Question

What does "ghostly" Floater movement concretely look like, mechanically?

Settled so far: no tilemap collision (ignores the BFS collision map that grounded enemies route around) and erratic drift (not a direct beeline to the player). Still open: what "no collision" means specifically near the player and other solids (can it overlap the player's hitbox, does it still respect arena bounds, does it collide with other enemies), and what the erratic-drift feel actually is (noise function, wobble amplitude/frequency, how strongly it's still pulled toward the player despite the wobble).

Build a cheap, rough prototype to react to — per the wayfinder skill's Ticket Types section, call the Skill tool with "prototype".

## Answer

Prototype: an interactive canvas simulation with a draggable player and a draggable wall, a Floater dot (wobbly, phases through the wall) alongside a simplified direct-line "Grounded" contrast dot blocked by the wall, sliders for wobble amplitude/frequency/pull-toward-player, and toggles for arena-bounds respect and Floater-Floater separation. Prototype preserved on the throwaway branch `prototype/floater-movement` (commit cf9bd0d) — see `.scratch/enemy-behaviours/prototypes/floater-movement.html` on that branch for the primary source; the file also sits untracked in the working tree on `main` for convenience.

**Validated after live tuning:**
- **Overlaps the player**: yes — Floater is not blocked by or repelled from the player's own hitbox
- **Arena bounds**: not respected — Floater can drift past the canvas/arena edges rather than being clamped
- **Separation from other Floaters**: still applies (confirming ticket 02's "grouped by Movement Style" design holds), but much lower than Grounded's resolved radius 40px/strength 3.0 — Floater uses **radius ~15px, strength ~0.5**
- **Wobble amplitude**: 80px — confirmed as the real ceiling, not just "whatever the slider allowed"
- **Wobble frequency**: 3Hz
- **Pull toward player**: 0.35 (lower than the prototype's 0.55 default — noticeably wanders more than it homes, while still net-drifting toward the player over time)

The wobble/blend shape validated in the prototype: a homing direction toward the player is blended with a perpendicular wobble signal (layered sine, not true noise) whose contribution shrinks as pull strength rises — `Steering.floaterDirection` in the prototype file is the reference implementation for the exact formula.

Note for whoever implements this: "doesn't respect arena bounds" and "no tilemap collision" both mean Floater skips the checks `move_actor`/the collision map currently apply to every other enemy (enemy.odin's `move_actor` call in `update_enemies`) — Floater likely needs its own movement-application path rather than going through the same collision-clamped `move_actor` the other Movement Styles use.
