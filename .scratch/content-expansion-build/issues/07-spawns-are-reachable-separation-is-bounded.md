# 07: Spawns are reachable and separation is bounded

**What to build:** An enemy never spawns somewhere it cannot walk out of, so a
Map cannot be left permanently uncleared by one body stranded in a sealed
pocket. Crowd separation costs the same per enemy whether ten or three hundred
are alive.

**Blocked by:** 04

**Status:** resolved

- [x] A candidate spawn position is rejected if the field never reached its cell
- [x] Separation samples a bounded number of neighbours rather than every other enemy
- [x] Crowding still pushes bodies apart at the densities the roster produces

## Comments

Implemented on `claude/spawns-reachability-separation-9fa362`.

### Reachability is not quite one lookup

`FLOW_UNREACHED`'s doc comment promised ticket 07 "one comparison", and the
first pass was one. It was wrong at the radius the game runs at. The flood only
ever *leaves* the inflation envelope, so at radius 1 a cell merely beside a wall
carries no distance — 741 of Desert Dungeon's 2239 standable cells, ticket 04's
own measurement — while sitting in open ground a body walks out of without
noticing. Reading "unfilled" as "unreachable" rejected a third of the map's
spawn candidates for `Grounded` and `Swarmer`, the very styles the test exists
for. Caught by the review: the first round of tests all flooded at radius 0,
where the filled set is just the walkable set and the question is trivial.

`flow_field_reaches` asks the question steering already asks instead: the cell
is filled, **or** it is walkable with a filled neighbour to step to — which is
exactly `flow_field_step_target`'s eight-neighbour fallback for a body
Separation has pushed into the envelope. A sealed pocket has neither, since its
neighbours are its own cells and the walls around them, so criterion 1 is
untouched. A wall's own cell is refused outright: with the player standing
against a wall the flood fills the envelope pocket around them, so that wall
*does* have filled neighbours, and "somewhere to step" alone would spawn a body
inside it.

It lives in flow_field.odin beside `flow_field_nearest_reachable`, not in
enemy.odin — it is a question about the field, and the two share
`flow_field_has_answers`. `pick_offscreen_spawn_point` takes the field as a
parameter rather than reading `game.flow_field`, so enemy_spawn_test.odin stays
on throwaway fixtures with no thread pinning — the same constraint
flow_field.odin puts on itself. Every field in those tests floods at
`FLOW_FIELD_INFLATION_RADIUS`, not 0.

**Only a body geometry stops is asked the question.** `fire_spawn_composition`
passes the field for a Movement Style in
`movement_style_collides_with_terrain` and `nil` for one that is not. This is
not in ADR-0025, and it matters: the flood's inflation envelope is unfilled, so
handing a `Floater` the field would reject every cell beside every wall — 741
of Desert Dungeon's 2239 standable cells at radius 1, per ticket 04 — to protect
a style that flies straight over them. `Inert` keeps the test even though it
never moves: a body that cannot walk out is exactly the one that holds
[ADR-0017](../../../docs/adr/0017-run-outcome-and-map-objective.md)'s Cleared
open.

**A field with no answers may not veto.** An unusable field, and a flood that
filled nothing because the player is standing inside a wall (the case ticket 04
left open), both answer "reachable" for everything. Reading them as "nowhere is
reachable" would reject every candidate on the map and leave placement worse
than it found it.

### Two divergences from the pre-settled design

The swarm-scale ticket said *"The spawn-anyway-on-exhaustion rule is untouched;
only what the retries test improves."* That holds for the rule — a trigger still
never silently under-spawns — but not for *where*:

- **Exhaustion prefers a reachable candidate, then asks the field.** The three
  tests are not equally serious. Appearing on-screen or inside a wall is
  cosmetic and self-correcting; landing in a sealed pocket is permanent and
  takes the Map's Cleared condition with it. So the loop remembers the first
  reachable candidate and returns that over the last one, and if no candidate
  was ever reachable — a player sealed into a room at one end of an open map,
  the whole ring clamping onto ground they cannot get to —
  `flow_field_nearest_reachable` names the filled cell nearest the last
  candidate. That is a scan of the field's cells, which is why it is on this
  path only, and it can only be reached with a field that *has* answers, so it
  never fails. The body may land nearer the player than the ring wanted, which
  is a worse spawn and a far better one than a body sealed in a pocket for the
  Run. Without it the ticket's opening sentence is simply false whenever six
  random candidates all miss.
- **The clamp lands inside the last authored cell.** `tilemap_world_bounds`'
  max is the far *edge* of the last tile, which is the near edge of the next
  cell along, so a candidate clamped straight onto it sat one cell outside the
  map — unfilled, and previously invisible. Found by the reachability test
  failing on `[0, 80]` in a five-row fixture. The clamp now insets by half a
  tile. Pinned with a nil field, since with one the reachability fallback hides
  it.

### What the bound actually counts

`SEPARATION_MAX_NEIGHBOURS` (8) caps the bodies one enemy *reads* — not the
bodies that turn out to matter. Distance is still checked after the budget is
spent, so a body in a ring cell 113px away, well past `Grounded`'s radius of 40,
costs a slot. That is deliberate and load-bearing: charging only for bodies that
turn out to be in range would make a cell full of out-of-range bodies unbounded
again, which is the thing being fixed. (An earlier draft of this write-up
claimed the bound was on "relevant neighbours"; the review was right that it is
not.) Three things keep it a useful bound rather than a nominal one:

- **The Movement Style is in the bucket key**, not a filter inside the scan.
  Separation only ever pushes against the same style, and filtering inside the
  scan would let a `Grounded` enemy spend its whole budget discarding
  `Floater`s in a mixed crowd and come away with no push at all — rung 4 fields
  both at once. This is the one filter the budget is *not* paid for.
- **The sweep visits the reader's own cell first.** With a budget rather than
  every neighbour to visit, the order stops being arbitrary: a plain `dx/dy`
  loop from -1 spends the whole budget on the cell up and to the left. Pinned
  by `test_separation_spends_its_budget_on_its_own_cell_first`.
- **Each reader starts at its own index in the bucket and wraps.** Otherwise
  every body in a cell is handed the same eight neighbours — one clique shoved
  against by the whole cell while the rest of the crowd is invisible to it. No
  random source and no frame counter, so the answer stays reproducible.

A stride through the bucket was tried instead of a contiguous run and measured
identical; it is not in the diff.

### What the bound costs, measured

300 disordered bodies, one second at 60fps, mean nearest-neighbour distance:

| sample | 90px blob | 180px blob | 300px blob |
|---|---|---|---|
| 4 neighbours | — | — | 9.3 → 11.6 |
| **8 (shipped)** | 2.8 → 3.9 | 5.6 → 8.1 | 9.3 → 14.9 |
| 16 | — | — | 9.3 → 18.2 |
| whole bucket | 2.8 → 9.4 | 5.6 → 14.6 | 9.3 → 20.0 |

So criterion 3 holds — a packed crowd still visibly spreads — at roughly 60% of
the unbounded rate. That is more than the swarm-scale ticket's *"the twentieth
neighbour changes the answer by nothing measurable"* implies, because a body
deep in a uniform crowd has a true push that is a small residual of many
near-cancelling terms, and a sample estimates a residual badly. It is still the
right trade at 250 bodies, and the ticket left the exact cap open as balance
work, so it is registered as a Tunable
(`enemy.separation.max_neighbours`, `.Enemy_Steering`) rather than frozen as a
constant.

**A measurement trap worth recording.** The first fixture packed the crowd on a
lattice, and the bounded sample appeared to make things *worse* — 3.5px going to
3.15px where the unbounded scan reached 7.3px. A grid is the spacing-maximising
arrangement for its density, so any movement at all lowers its mean
nearest-neighbour distance; the measurement was reading a crowd being
disordered as a crowd being crushed. The shipped fixture seeds deterministic
disorder instead.

### A shipped leak went with it

`build_separation_grid` read each bucket out of the map zero-valued and
`append`ed to it. A zero-valued `[dynamic]int` has no allocator of its own, so
it took `context.allocator` — one heap array per occupied cell per frame, never
freed, while the map itself sat on the temp allocator. The buckets are now made
on the temp allocator explicitly. Styles with no Separation radius are not
bucketed at all, since nothing ever looks them up.

### Tests

Six new tests in `enemy_spawn_test.odin`, seven in a new
`enemy_separation_test.odin` — both in the global-free, throwaway-fixture idiom,
neither needing `ODIN_TEST_THREADS=1` of itself. Full suite: **222 passing**
under `odin test . -define:ODIN_TEST_THREADS=1` — the flag is the suite's
standing requirement for the files that do touch `game`, not something this
diff introduced.

Every decision above was mutation-verified — the check was not that the tests
pass but that breaking each one fails exactly the test written for it:
reachability rejection, its envelope fallback, its wall guard, the clamp inset,
the nearest-reachable fallback, `flow_field_coord`'s index inverse, the
neighbour budget, the bucket rotation, the style in the key, the centre-first
order, and `flow_field_nearest_reachable` skipping unfilled cells.

Two escapes worth recording, both found by re-running the sweep after the review
fixes rather than by reading. The wall-cell assertion was passing for the wrong
reason — in the split-room fixture a wall's neighbours are *all* envelope, so
there was no filled neighbour to be tempted by and the guard was never
exercised; it needed the player standing against the wall. And the sealed-room
fixture was 3x3, which is symmetric under transpose, so a field index read back
with x and y swapped still named a cell inside it. The room is 3x1 now.

### Review

Both axes of `/code-review` ran against this diff. Acted on: the envelope
over-rejection and the radius-0 test fixtures (above, the one real defect);
`spawn_point_is_reachable` moved into flow_field.odin as `flow_field_reaches`,
with the guard it duplicated extracted as `flow_field_has_answers`;
`flow_field_coord` extracted as `flow_field_index`'s inverse; a dead `!ok ||`
in `flow_field_nearest_reachable` and a dead final `return point` in
`pick_offscreen_spawn_point`; the false "relevant neighbours" claim; a
speculative `SEPARATION_BUCKET_INITIAL_CAP`; a doc comment saying "best
candidate" where the code takes the first reachable one (the variable is
`first_reachable` now); a garbled sentence; and a test comment with wrong
cell-centre arithmetic.

Not acted on: `pick_offscreen_spawn_point` now takes five parameters and
`map_bounds` is derivable from the `tilemap` beside it, so a placement-context
type is arguably asking to be born — but `map_bounds` is hoisted out of the
per-enemy loop deliberately (its own comment says why, and ticket 06 is what
makes that scan cheap), and bundling it back in would undo that for a parameter
count.

### Not done here

`tile_blocks_point` still scans every tile per candidate — that is
[06](06-movement-reads-the-fields-solid-set.md)'s, and ADR-0025 names it there.
