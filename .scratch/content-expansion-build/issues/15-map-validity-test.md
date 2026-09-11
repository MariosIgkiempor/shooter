# 15: Map validity test

**What to build:** A broken Map fails the build rather than the playtest. Every
authored Map is checked for the failures that make one unplayable or
unclearable.

**Blocked by:** 13, 04

**Status:** resolved

- [x] Every authored Map is asserted connected, with its start position on a floor tile and its spawn ring reachable
- [x] Extent is within bound, rung is unique, and rungs cover the full ladder
- [x] The time limit clears the Map's own timeline end, or the Map is untimed
- [x] Colours are authored rather than defaulted
- [x] The existing Map, which fails this today, is patched in the same change

## Comments

Implemented on `claude/map-validity-test-4a9ed4`. Seven tests in
map_test.odin, one per check, over the baked `maps` table; two more pin the
one new helper on stack literals. Desert Dungeon's 888 absent cells are filled
and `maps.odin` regenerated — 888 pure insertions, nothing else in the bake
moved.

### What "the full ladder" means here

Rungs are asserted to be exactly `1..len(Map_Name)` with no gaps and no
duplicates — not "1 through 5" as spec.md's sentence has it. Ticket 17, which
authors the four Maps that fill rungs 2–5, is blocked by this one, so a
hardcoded 5 would land red and stay red across two tickets; a test authored
red against the only content in the game is the thing issue 09 said to avoid.
`1..N` is issue 09's own wording, is the invariant ticket 16's gating needs
(clearing rung *n* opens exactly *n+1*), and reads "1 through 5" the moment
17's four Maps land. Green today at rungs 1 and 2.

### Where each Map stood before the patch, measured

| | Cold Hall | Desert Dungeon |
|---|---|---|
| extent | 54×48, 2592 tiles, 0 absent | 54×48, 1704 tiles, **888 absent** |
| `player_start` cell | (27,24), authored floor | (29,15), **no tile** |
| connected (radius-0 flood) | 2108 of 2108 | 2239 of 2239 |
| rung | 2 | 1 |
| colours | opaque, floor darker | opaque, floor darker |
| `time_limit` vs earliest end | 300 vs 270 | 330 vs 270 |

So exactly one check was red, and only on Desert Dungeon: the start on a floor
tile. Confirmed by running the finished sweep against the pre-patch bake
before patching — a check that was green all along would have proven nothing.

### The patch

Every absent cell inside the 54×48 box is now an authored tile: the 840
interior ones as floor, the 48 on the border as wall. Sealing the border was a
choice over filling all 888 as floor. The box had 48 walkable cells on its rim,
which is why ticket 04 had to grow the flow field's extent by the player's cell
— one step off the top edge put the source out of bounds. A Map with an edge
does not have that off switch, and ADR-0025's own model is that outside the
extent is solid. The walkable region shrinks from 2239 to 2191 cells and stays
one component from the start. The file is re-emitted in its existing
column-major order, so the JSON diff is the added tiles and nothing else.

This is a fill, not the redraw: Desert Dungeon is still rebuilt when 17
authors it as a rung, as issue 09 said.

### Connectivity floods at radius 0, and that is the design

The obvious sweep — flood at `FLOW_FIELD_INFLATION_RADIUS` and assert every
walkable cell is filled — fails on both Maps as they stand. At radius 1 the
flood never re-enters a wall's envelope, so 741 of Desert Dungeon's 2239
standable cells and 388 of Cold Hall's 2108 carry no distance. The softer
"every walkable cell passes `flow_field_reaches`" fails too: 47 and 16 cells
respectively are two-wide alcoves lying wholly inside the envelope, with no
filled neighbour to step to. Both Maps are connected; it is the radius that is
opinionated, and it is a property of the steering substrate rather than of the
layout. At radius 0 `inflated` is stamped only on the wall cells themselves,
so the filled set is exactly the source's walkable component and the assertion
has no slack. The spawn-ring check floods at the game's radius, because those
are the very points the live spawn filter asks about.

Both flood-backed tests first assert `field.filled_count > 0` and bail.
`flow_field_reaches` answers true for everything on a field with no answers
(ticket 07's "may not veto" rule), and a start inside a wall floods nothing —
without the guard the sweep passes silently on the worst Map there is.

### The spawn ring is sampled, not picked

`pick_offscreen_spawn_point` is the wrong proc to assert through, twice over:
it picks angles with `rand`, and on exhausted retries falls back to
`flow_field_nearest_reachable`, which always names a reachable cell. Asserting
through it is close to a tautology and would pass on a Map where one angle in
sixty-four works. The test walks 64 fixed angles on the ring the game uses —
half-diagonal of the shipped 960×540 window at `GAMEPLAY_ZOOM`, plus
`OFFSCREEN_SPAWN_MARGIN`, so 489px — with the same clamp and half-tile inset,
skips candidates under a wall (refused and retried in play, so ordinary), and
requires that none lands on walkable ground the player can never reach.
`camera_visible_world_rect` cannot supply the rect: with no window
`GetScreenWidth` is 0 and the ring collapses to the 30px margin.

Two things the sampling surfaced, neither one of the seven checks:

- **The ring is wider than the Maps.** 489px against a 432px half-width, so
  most angles clamp onto the border: 20 of Desert Dungeon's 64 land on floor
  after the patch, 8 of Cold Hall's. The rest hit border wall and are retried
  in play, which means a good share of spawn batches exhaust their six tries
  and take the fallback. A liveness floor was considered and dropped: the only
  number it could hold today is one measured off two Maps, and the
  threshold-free assertion is the check. Worth knowing when 17 draws its four.
- **Desert's old border was walkable.** Before the patch 30 angles landed on
  floor rather than 20 — the extra ten were absent rim cells reading as
  floor. Sealing the border is what moved it.

### What the time-limit check can and cannot say

`map_timeline_earliest_end` (map.odin) is a lower bound on the timeline, not
a prediction of it, and says so. A `Time_Elapsed` condition names its own
activation; a `Kills_Reached` one is play-dependent, so it is folded in at
zero. A `time_limit` that does not clear even the earliest possible finish is
broken for certain, which is a claim a validity test can make; the other
direction it cannot certify and does not pretend to. Separately, any
`Repeating` with `duration <= 0` makes the Map unclearable whatever its limit
(CONTEXT.md's Run outcome entry), and is its own assertion. A trigger's span is
`duration`, not `duration + interval`: `update_spawn_triggers` stops once
`elapsed` passes `duration`. `spawn_timeline_exhausted` is untouched — it
answers whether a Run's timeline is finished *now* off the runtime latches, a
different question with its own tests.

### The colour check asks two things

Issue 09 specified non-zero colours. `MAP_BEVEL_MIX`'s comment in map.odin
already promised this ticket would also ask that the floor is the darker of
the pair, since that is what keeps the derived bevel darker than the wall it
insets. The sweep asserts both, via a new `color_luma` beside `color_mix`.

### The extent bound is the shipped footprint

`MAP_MAX_CELL_EXTENT :: Vec2i{54, 48}`, per axis. Nothing encoded ~54×48
before; ADR-0021 holds footprint flat near it and both Maps measure exactly
it. Naming the shipped footprint is deliberate — a Map that wants more changes
the constant on purpose rather than drifting past it.

### Docs

ADR-0021's three-check sentence carries an amendment naming the seven and the
radius-0 decision; ADR-0022 and ADR-0024 already anticipated their own checks.
CONTEXT.md's Map entry lists the full set.

### Tests

Nine new tests in `map_test.odin`, all read-only against `maps` — a
`maps[name]` copy aliases the table's own arrays, so nothing appends to,
deletes or clones one — and each Flow_Field is built on the test's own stack,
so the file's no-thread-pinning discipline still holds. Full suite: **261
passing** under `odin test . -define:ODIN_TEST_THREADS=1`, up from 252.

Every check was mutation-verified: a start on an absent cell and a start in a
wall (check 1); a corner sealed by three walls (check 2); a ring cell sealed
into a pocket at (52,35) (check 3); a tile at x=60 (check 4); Cold Hall at rung
1 (check 5); a zeroed floor colour and the pair swapped (check 6); a limit of
200 against an end of 270, and a Repeating duration of 0 (check 7); and the
helper's kills-at-zero and unbounded branches. Each failed exactly the test
written for it, with the offending Map and cell named.

### Review

Both axes of `/code-review` ran against the diff. Neither reported a
violation or a spec gap. The one judgement call, not acted on: the spawn-ring
test reproduces `pick_offscreen_spawn_point`'s four-line half-tile clamp rather
than sharing a proc with it. The test's comment explains why it does not call
the proc itself; the clamp is small enough that extracting it would touch
enemy.odin for a test's benefit alone, and it is worth doing the next time that
clamp or its caller changes for its own reasons.
