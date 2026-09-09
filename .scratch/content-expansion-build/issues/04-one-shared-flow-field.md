# 04: One shared flow field replaces per-enemy pathfinding

**What to build:** Enemies chase the player correctly with hundreds of bodies on
screen. Instead of every enemy running its own search, the Map holds a single
field flooded outward from the player's cell, rebuilt only when the player
crosses into a new cell; an enemy reads the direction stored in its own cell.
Styles that do not collide with walls ignore the field entirely and steer
straight at the player as they always did.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] A field covering the Map's cells is built by flooding from the player's cell and rebuilt when that cell changes
- [x] Colliding movement styles steer by the field; non-colliding styles steer directly and are unaffected
- [x] Per-enemy path storage, the path search, and its node budget are deleted
- [x] The debug visualiser shows the field rather than per-enemy paths, and is renamed to match
- [x] A flood descends toward the player, and an enclosed pocket is never filled

## Comments

**Scope of criterion 2.** `Grounded` steers by the field here. `Swarmer` is left
exactly as it was — pre-assigned ring slots, straight-line seek — because
[05](05-swarmers-surround-by-contour.md) deletes `assign_swarmer_slots` wholesale
and replaces it with contour drift; converting it here would be work 05 tears up.
The steering/collision split is now named once, as
`movement_style_collides_with_terrain` (enemy.odin), so 05 changes a call site
rather than a concept.

**Supersedes one sentence of [ADR-0025](../../../docs/adr/0025-enemies-steer-by-a-shared-flow-field.md).**
The ADR said `Debug_Visualizer.Pathfinding` keeps its name; this ticket's fourth
criterion says renamed, and CONTEXT.md's Flow field entry lists *pathfinding*
under `_Avoid_`. The member is now `.Flow_Field` and the ADR sentence is amended
to match.

**The inflation envelope is the common case, not an edge case.** Measured on
Desert Dungeon at radius 1: 741 of its 2239 standable cells lie inside some
wall's envelope, and 101 have no free orthogonal neighbour at all. A flood that
only exempted its own source cell would therefore collapse to a single cell
whenever the player stood on one of those 101, stranding every enemy on the map.
The build's traversal rule — an envelope cell is enterable only *from* an
envelope cell, and only the source is ever seeded inside one — lets the flood
walk out of whatever pocket the player is standing in without ever re-entering
the envelope from open ground. It generalises the deleted `find_path`'s
"endpoints always allowed" exemption. With it, all 2239 possible sources flood;
`player_start`'s reaches 1498 cells at a maximum path distance of 56, comfortably
past the 1024-node cap the old search silently truncated at. Both halves of the
rule are pinned by tests (`..._floods_out_of_a_fully_inflated_corridor` and
`..._does_not_re_enter_the_envelope_from_open_ground`), verified by mutation.

**Two places this diverges from [ADR-0025](../../../docs/adr/0025-enemies-steer-by-a-shared-flow-field.md), beyond the amended sentence.**
The ADR says the field is "keyed by inflation radius, built lazily for the radii
in use: radius 1 for the roster, and the boss's size-derived radius while a boss
is alive". There is one field here, holding one radius, and a differing radius is
a *rebuild trigger* rather than a second field — correct while only the roster
exists, and wrong the moment two radii are ensured in the same frame, which would
re-flood the whole map on every call. [21](21-the-warden.md) is where a Boss and
its own radius arrive, and where the keying belongs. The ADR also calls the
eight-neighbour fallback a reproduction of the old "endpoints always allowed"
exemption "without a special case"; that is true of the fallback itself, but the
build needed the traversal rule below on top of it, which the ADR did not
anticipate.

**Two shipped leaks went with the deletion.**
`build_inflated_collision_map` allocated a heap `map` every frame and never freed
it, and `reset_enemies` only `clear`s `game.enemies`, so every live enemy's
`Path` leaked on reset.

**Behaviour change to watch in play.** A `Ranged` enemy's retreat was a BFS
toward a point 100px behind itself, which usually degenerated to a straight line;
it is now a single step to the highest path-distance neighbour, so it rounds
corners but has only one cell of lookahead and can still reverse into a dead end
(accepted by the ADR). The step is required to strictly *increase* the distance
to the player: at a local maximum of the field — a dead end's back, roughly 3% of
the cells a flood from `player_start` fills — every neighbour is closer, and
taking the least-close one would oscillate the enemy on the spot. There it falls
back to the euclidean back-away, which at least holds a stable direction.
`ARRIVE_RADIUS` is deleted rather than ported: the cell transition is the arrival
test now.

Also worth knowing at the table: because the flood may traverse the inflation
envelope connected to the player's own cell, the filled set changes as the player
crosses that boundary — by up to 84 cells on Desert Dungeon — so a few routes
visibly flip while the player walks along a wall.
