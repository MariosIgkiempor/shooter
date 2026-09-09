# 05: Swarmers surround by contour

**What to build:** A swarming pack forms a ring around the player that wraps
walls instead of cutting through them. A Swarmer follows the shared field
inward until it reaches its surround distance, then drifts along the contour at
that distance rather than pressing further in.

**Blocked by:** 04

**Status:** resolved

- [x] Pre-assigned surround slots are deleted
- [x] A Swarmer approaches by the field and, at surround distance, drifts along the contour
- [x] A Swarmer separated from the player by a wall moves around it rather than into it

## Comments

Implemented on `claude/swarmers-surround-contour-f78900`.

### What replaced the slots

`assign_swarmer_slots` and `SWARMER_RING_ROTATION_SPEED` are gone. In their
place a Swarmer reads the shared field and falls into one of three regimes,
expressed with the `Movement_Intent` enum ticket 04 already introduced:

- **Approach** - path distance more than a band outside the surround distance.
  Straight to `field_chase_direction`, the same steering `Grounded` uses.
- **Withdraw** - more than a band inside it. `flow_field_retreat_target`, again
  shared with `Grounded`.
- **Hold** - on the contour. The only new steering: `flow_field_contour_target`
  picks the neighbouring cell that is both on the contour and furthest around it
  in the direction this Swarmer turns.

So the ticket's three criteria are one mechanism rather than three: the ring is
the set of cells at one *path* distance, which wraps geometry because the flood
does, and a Swarmer behind a wall is simply Approaching along a route that goes
round it.

### The contour step

The tangent is the cell's own inward gradient (`FLOW_STEP_OFFSET[cell.step]`)
turned ninety degrees. Candidates are the eight neighbours, filtered to those
that are **filled** and within `FLOW_CONTOUR_BAND` (one diagonal step, 14) of the
target cost; among those, the one nearest the contour wins, and alignment only
breaks a tie.

That ordering is the fix for the one real defect the review found. Ranking by
alignment first let a perfectly tangential neighbour a whole diagonal *inside*
the contour beat a slightly angled one sitting on it - and near geometry that
walks a Swarmer inward a step at a time until it stands a full band closer than
it was asked to. The band bounds the drift; the ordering keeps it on the ring.

Three properties, each verified by mutation - the check was not that the tests
pass but that breaking the code fails exactly one of them:

- A colliding cell is never filled, so a wall across the contour is not a
  candidate (`test_a_swarmer_never_drifts_into_a_wall`), while a wall the drift
  merely runs beside does not stop it
  (`test_a_drift_slides_along_a_wall_it_runs_beside`).
- The drift applies the flood's **own** diagonal corner rule: a diagonal whose
  two flanking cells are not both enterable is refused. Without it the drift
  squeezes past a corner the field itself routed around - which is criterion 3
  failing at the level of a single step, and the second defect the review found.
- The band is a filter, not a tie-break: where no neighbour is on the ring the
  drift declines rather than taking the best-aligned cell going
  (`test_a_drift_step_never_leaves_the_contours_band`).

A step must be *strictly* forward around the contour (`align > 0`). A backward
one would reverse the drift every frame a Swarmer spent against a wall. Where
the arc dead-ends into geometry there is no forward candidate, and
`swarmer_direction` steers nowhere while still reporting `drifting` - pressing
inward there is exactly the converge-on-one-point this Movement Style exists to
avoid, and Separation still spreads the pack along the arc.

### Divergences from the plan

- **`drift_sign` is per-spawn, not per-frame.** Which way a Swarmer turns is a
  new `f32` on the `Swarmer` struct, chosen in `spawn_enemy_at` beside Floater's
  `wobble_phase` randomization, so half a pack goes each way and a ring closes
  from both sides. Deriving it from a heading each frame would need a stored
  velocity the Enemy does not have, and at the moment of arrival the heading is
  radial - perpendicular to both tangents - so the sign would be noise. `0`
  reads as `+1`: not a save-compat path (`spawn_enemy_at` always writes the
  sign), but the defined answer for a `Swarmer` value built anywhere else, so
  the seam has no undefined input.

### Behaviour to watch

- **The inflation envelope swallows the contour near walls.** The shipped field
  inflates walls by one cell and the flood only ever *leaves* that envelope, so
  a Swarmer standing beside a wall has no path distance of its own and cannot
  read a contour off one. It takes the fallback every other field consumer takes
  - close on the player - so it does not hold the ring while wall-hugging; it
  steps out, picks the contour back up, and criterion 3 still holds because the
  approach is field-steered. Ticket 04 measured the envelope at 741 of Desert
  Dungeon's 2239 standable cells, so this is not a corner case. Pinned
  deliberately by `test_a_swarmer_inside_the_inflation_envelope_closes_on_the_player`
  so the fallback is a decision rather than an accident. Narrowing it belongs
  with whatever revisits the envelope, not here.
- **Withdraw is not new behaviour.** The review read it as scope creep against
  "follows the field inward... then drifts". The retired ring placed slots on
  every side of the player, so a Swarmer inside the ring already moved outward
  to reach one; without a Withdraw the surround radius would only be a floor and
  a Swarmer the player walked into would press to contact. The reasoning is in
  `swarmer_intent`'s doc comment.

### Tuning

`SWARMER_RING_ROTATION_SPEED` (0.3 rad/s) becomes `SWARMER_DRIFT_SPEED_SCALE`
(0.35), the fraction of `speed` used while drifting. A Swarmer rushes in at full
speed and settles into a slow orbit. Registered as
`enemy.swarmer.drift_speed_scale` under `.Enemy_AI`.

`swarmer_surround_radius` is unchanged - the distance still comes from the
Swarmer's own Attack Style. The deleted proc's "first Swarmer's radius for the
whole ring" approximation dies with it: each Swarmer now holds its own contour,
so mixed Attack Styles in one pack give concentric rings rather than one
averaged one.

### Debug overlay

`draw_debug_movement_styles` still draws a euclidean circle at the surround
radius. It is now the *nominal* distance only; the contour actually drifted
along is a path distance, visible in the `.Flow_Field` overlay. The comment says
so.

### Tests

Ten new tests in `flow_field_test.odin`, in the file's existing idiom - throwaway
ASCII fixtures, no `game`, no thread pinning. Full suite: 189 passing.

### Review

Both axes of `/code-review` ran against this diff. Acted on: the contour
ordering and the missing corner rule (above); an unused `player_pos` parameter on
`swarmer_intent`; `test_a_swarmer_inside_its_surround_distance_backs_out`
asserting a scan-order tie-break rather than "away"; a band test that no longer
discriminated once the ordering changed; "surround distance" drifting from
CONTEXT.md's *surround radius*; and a dropped forward pointer to Charger as
ADR-0025's third field reader.

Not acted on: the neighbour scan in `flow_field_contour_target` does duplicate
`flow_field_extreme_neighbour`'s loop shape, but unifying them behind a scoring
proc buys one caller an indirect call per neighbour in the file that chose Dial's
buckets over a heap precisely to avoid those.
