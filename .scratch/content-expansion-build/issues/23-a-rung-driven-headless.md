# 23: A rung driven headless

**What to build:** A whole Run can be played through in a test, so the failures
that only appear when the pieces are assembled — a body stranded where nothing
can reach it, a clear condition that never fires — are caught by the suite
rather than by playing.

**Blocked by:** 17, 11, 04

**Status:** resolved

- [x] A test builds an authored Map, ticks its timeline for the Map's full duration, and asserts the Map is cleared
- [x] The test asserts no enemy is ever stranded outside the reachable field
- [x] It runs without a window or any rendering

## Comments

`test_every_baked_map_is_cleared_by_a_headless_run_that_strands_no_enemy`
(`run_objective_test.odin`) plays every baked Map in rung order: the Map is
cloned, the player stood at `player_start`, and the frame loop's pieces are
ticked at 1/60 in the order `update_game_state` calls them — field, bullets,
pickups, Spawn Triggers, the Boss's field, enemies, the Run objectives — minus
input, the weapon and the player's move. All five Maps, not the one the ticket
asks for: the loop costs ~7 s and Pale Keep's Warden is where the wiring is
most likely to break. The Run must settle as Cleared before `time_limit`, must
record its rung, and on every frame every body of a terrain-colliding Movement
Style must stand where the flood from `player_start` can reach.

**The player's aim, stood in for.** The player cannot die (god mode — the Run
is the Map's, not the player's) and never moves; a body dies 15 s after it
spawned. A per-frame kill budget was tried first and rejected: the field is
empty most of the time, so the unspent budget wiped each batch on its own
spawn frame and nothing ever walked. 15 s is under Pale Keep's 30 s of slack
between the timeline's end and its `time_limit`, and long enough for a Grunt
to cross the Map from the widened ring. The Boss is spared until the timeline
is spent, so its stamp and its own field are live for the whole of Pale Keep.
Headless, `get_screen_width()` is 0 and the spawn ring collapses to 30 px
beside the player, so `OFFSCREEN_SPAWN_MARGIN` is widened for the test to the
shipped window's ring (`shipped_spawn_ring_radius`, shared with
`map_test.odin`'s sweep) and restored after.

**What "stranded" is measured against.** Probe fields flooded from
`player_start` per Map: one at the shipped radius for the roster, one at the
Boss's own radius for the Boss — what each steers by — rather than the live
fields, since the shared one is unfilled under the Warden's stamp ("no step
this frame", not "cannot get to the player"). The Warden is placed by the
shared-radius filter (ticket 21) and so lands outside its own radius-2
flood and walks in by the straight-line fallback, ~6 s on Pale Keep; it is
held to its own flood after a 15 s grace, so a Boss that never gets there is
caught (a 1 s grace fails as `Warden stands stranded at cell [48, 5] ... at
its radius 2`). Bodies are sampled at their collision box's centre, the
point `enemy_flow_obstacles` uses, not the feet anchor: `move_actor` parks a
body's feet exactly on a wall's top edge, which floors into the wall's own
row.

Since every body dies on its 15 s, the "pocket spawn holding Cleared open
forever" risk is carried by the stranded assertion, not the Cleared one:
Cleared here guards the timeline wiring (every trigger exhausts, `end_run`
fires and records the rung inside `time_limit`).

**What it caught.** Red on all five Maps the first time it ran: bodies
walking off the Map through its border, `Grunt stands stranded at cell
[-1, 28]`. Every one was embedded in a wall on its spawn frame. A spawn
candidate was tested as a point (`tile_blocks_point`), but what is stamped on
it is a 24 px body, and a point on the floor cell beside a wall puts the body's
box inside that wall — the state `move_actor` documents as never supported,
and resolves by pushing the box out the wall's far side. Through the border,
that is off the Map for good. Two fixes, each with its own test in
`enemy_spawn_test.odin` first:

- `tile_blocks_body` (`enemy.odin`) tests the candidate as the box `move_actor`
  collides, and `pick_offscreen_spawn_point` refuses a candidate by it before
  the candidate can be remembered as `first_reachable`.
- `flow_field_nearest_reachable` (the exhausted-retries fallback) now names
  the nearest filled cell *outside* the inflation envelope, falling back to
  the envelope only when the flood never left it. A player standing in the
  envelope floods the envelope too (`flow_can_enter`), and on Ember Ring —
  whose 489 px ring clamps almost every candidate into the border — the
  fallback named the corner floor cells and the whole first batch went off
  the Map.

Mutation-verified: `time_limit = 1` on every Map fails as `Timed_Out at 1.0
s, not Cleared` plus `should record its rung`; a Grunt appended at a wall
cell fails as `stranded at cell [0, -1]`; a 40 s kill span fails Pale Keep
as `Timed_Out at 210.0 s`; the spawn fix reverted to the point test fails the
new placement test 129 times in 200 picks.

**Peak bodies alive, the reading ticket 17 deferred here** (15 s lifetimes,
so a lower bound on what a slower player meets): Desert Dungeon 22 (Cleared
251.5 s of 330), Root Warren 24 (221.7 of 285), Cold Hall 33 (219.0 of 270),
Ember Ring **98** (213.9 of 245), Pale Keep 13 (190.0 of 210). Ember Ring is
under the catalog's 150–250 target at this kill rate; at a 40 s lifetime it
reads 254 (Cleared at 238.9 s, 6 s inside its limit).

351 tests pass under `odin test . -define:ODIN_TEST_THREADS=1`; the headless
Run is ~7 s of that.
