# 06: Actor movement reads the field's solid set

**What to build:** Moving an actor costs a handful of lookups instead of a scan
of every tile on the Map, twice per actor per frame. Wall resolution consults
the cell-indexed set of solid cells the field already maintains, checking only
the cells the actor's box overlaps. Behaviour is unchanged: the player and
enemies still slide along walls one axis at a time.

**Blocked by:** 04

**Status:** resolved

- [x] Actor movement resolves against the cells its box overlaps, not against every tile
- [x] The player uses the same path as enemies
- [x] Wall sliding, corner behaviour and collision results are unchanged

## Comments

Implemented on `claude/movement-reads-fields-solid-7d70bc`.

**The lookup.** `flow_field_is_solid(field, cell)` (flow_field.odin) is the
solid set read: an authored colliding tile's cell answers true; an untiled gap,
a cell off the extent (which holds every authored tile, so off it is untiled
ground) and an unusable field all answer false. `move_actor` now takes the
`^Flow_Field` instead of the `^Tilemap`, steps an axis, and asks only the cells
the box sweeps through on that step (`swept_box_cell_range`, the hull of the
box before and after) — 3×3 or so for a 24px body on 16px cells at any speed
the game moves at. The overlap test and the edge-snap are the ones it always
had, so the resolved position is bit-identical.

**Why the result is unchanged, and the one case it is not.** Resolution only
ever pushes the box back toward where it started, so every tile it can be
pushed against lies in the swept range, whatever the step. The first cut read
only the stepped box's own cells, which is the same thing for a step shorter
than a tile but not for a long one — the review caught that a dash frame at a
bad dt could land the box on the far side of a thick wall, where the old scan
chained ejections back out through tiles the stepped box never spanned. The
hull covers that. A body already embedded in a wall is the one divergence
left, and its old answer depended on the tiles' authoring order. Not a
supported state; noted on `move_actor`. Pinned by
`test_move_actor_matches_a_scan_of_every_tile`, which keeps the old resolver
verbatim as a file-private reference and sweeps ~20k moves — steps up to 50px,
into a three-deep wall — over a room with corners, a pillar, a one-cell gap
and an untiled doorway.

**Freshness is the frame loop's job, not the lookup's.** `flow_field_invalidate`
keeps the field's cells, so a lookup that answered "not solid" while unbuilt
would drop every wall for a frame, and one that answered from the cells would
give the previous Map's walls. Neither is fixable inside the lookup.
`update_game_state` now ensures the field *before* the player moves — the only
frame that does anything is the one after `apply_chosen_map` invalidates — and
keeps the existing post-move ensure that makes the flood's source exact. A
rebuild inside `apply_chosen_map` was the alternative; it makes freshness a
property every invalidation site has to remember, where the frame loop makes it
a property of the frame.

**`tile_blocks_point` took the same fix**, as ADR-0025 and ticket 07 said it
would: one cell lookup. It runs per spawn candidate rather than per frame, so
the saving is small; the point is that there is now one way to ask "is there a
wall here". `pick_offscreen_spawn_point`'s `field == nil` convention for
Floaters could not survive that — every style needs the field for its walls —
so the field is always passed and a `must_reach: bool` says whether the flood is
consulted. The `tilemap` parameter went with it.

**Not done here.** `bullet_hits_wall` (bullet.odin) still scans every tile per
bolt per step. Ticket 06 does not name it and ADR-0025 does not either; it is
the same shape and the same fix, and belongs to a ticket of its own.
