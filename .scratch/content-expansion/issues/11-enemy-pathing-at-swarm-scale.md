# Enemy pathing at swarm scale

Type: grilling

Status: resolved

## Question

How do enemies move toward the player when there are hundreds of them rather than twenty?

Graduated from fog while resolving [Enemy catalog](04-enemy-catalog.md), which raised `MAX_ENEMIES` from 24 to 4096 and authored rung 4 at **150-250 concurrent bodies**. The cap was never the real ceiling; the movement code is. Rung 4 is unshippable until this is answered, so this ticket is the roster's precondition even though nothing formally blocks on it.

Four costs, all confirmed in code:

- **`find_path` runs per Grounded enemy per frame.** `chase_to` calls it unconditionally ([enemy.odin:826](../../../enemy.odin)). Each call heap-allocates a `map[Vec2i]Vec2i` and a queue, floods up to `MAX_SEARCH_NODES :: 1024` cells, then frees them; separately it `delete`s and reallocates that enemy's `Path` dynamic array. At 4096 that is roughly 4M node visits and 8192 alloc/free pairs per frame.
- **`assign_swarmer_slots` is O(n^2)** ([enemy.odin:474](../../../enemy.odin)): n Swarmers make n ring slots, and the greedy nearest-slot assignment scans every unclaimed slot for every Swarmer. ~20k distance checks at 200; 8.4M at 4096. It also allocates three temp collections per frame.
- **Separation degrades exactly when it matters.** `compute_separation_direction` is grid-bucketed, but a swarm converging on the player puts hundreds of bodies in one 3x3 neighbourhood, so it tends toward O(n^2) in precisely the case it exists for.
- **`MAX_SEARCH_NODES :: 1024` against 2592 cells is already broken** for any path spanning the map — this map's Notes have carried it as a standing hazard since [Map layout authoring model](02-map-layout-authoring-model.md). A path that fails returns not-ok, `enemy.path` empties, and the enemy straight-line chases into walls.

The obvious answer is a **shared flow field**: one flood fill from the player per frame (or every few frames) giving a direction and a distance per cell, which every enemy reads. O(map) once instead of O(enemies x map). It would close three other things at the same time — `MAX_SEARCH_NODES`'s truncation (a single fill covers the whole map), the Swarmer fix below, and Grounded/`Ranged`'s retreat and the Swarmer ring slot both being expressible off the distance channel without a second structure. That is a recommendation, not a decision; this ticket owns it.

To settle:

- **Is it a flow field, a staggered BFS budget, or something else?** A flow field has one goal, and today's goals are not uniform: `movement_goal_point` computes a retreat point for `Ranged` and Swarmers seek a rotating ring slot. Does a distance channel serve all three, or does something still need its own path?
- **What refresh rate?** A per-frame fill is cheaper than 4096 BFS but is not free; a stale field is a lagging chase. Where the line sits is the question.
- **What happens to `Enemy.path`?** It exists today for the debug draw as well as for movement. A flow field has no per-enemy path to draw.
- **The Swarmer fix, both halves**, scoped in [Enemy catalog](04-enemy-catalog.md) and handed here: a Swarmer must route to its slot rather than seek it in a straight line ([enemy.odin:740](../../../enemy.odin)), *and* a ring slot landing inside a wall must slide around the ring to the nearest open bearing, since `assign_swarmer_slots` places slots by pure trigonometry with no wall check. Fixing only the first leaves the same stuck enemy, now paying for a failed BFS.
- **Does Separation survive at 200+?** It is a steering force layered on movement, and a crowd is where it is most needed and most expensive.
- **`Charger`'s dash is a locked line, not a path.** [Enemy catalog](04-enemy-catalog.md) authored it as a committed dash along a bearing fixed at windup start. Confirm that whatever replaces per-enemy pathing leaves a Movement Style free to ignore it for a bounded window — and decide what a dash into a wall does.

This is a grilling ticket rather than a prototype one because the question is architectural rather than a look-at-it: the numbers above already say per-enemy BFS cannot survive, so what is open is which structure replaces it and what it costs the behaviours built on top.

## Answer

**One shared flow field, flooded from the player, and per-enemy pathfinding is deleted.** `find_path`, `Path`, `MAX_SEARCH_NODES` and `Enemy.path` all go; `assign_swarmer_slots` goes with them. The ticket's four named costs are answered by one structure, and three things it did not know about came out with them. [ADR-0025](../../../docs/adr/0025-enemies-steer-by-a-shared-flow-field.md).

### Settled

- **A flow field, not a staggered BFS budget.** One flood from the player's cell, 4-neighbour to match today's `get_neighbours`, storing a step direction and a path-distance per cell. At rung 4's 150-250 bodies, per-enemy BFS is up to **256,000 node visits** and ~1000 alloc/free pairs a frame (`find_path` heap-allocates a `map` and a queue per call; [enemy.odin:830](../../../enemy.odin) `delete`s and reallocates `enemy.path` per enemy per frame). One flood over the bounded extent is **~2600 visits**, once. The staggered budget was the smaller change and lost on two counts: it does not fix `MAX_SEARCH_NODES`, and it makes chase quality depend on crowd size — at 250 an enemy repaths every ~2 seconds and visibly lags a moving player. Hierarchical/portal paths are a lot of machinery for one hand-drawn 54x48 map.
- **Inverting the search is the point, not a side effect.** Flooding *from the player* means a cell unreachable from the player is simply never filled — a better answer than a failed path, and it deletes `MAX_SEARCH_NODES`'s truncation rather than raising it. That constant has been this map's standing hazard since [Map layout authoring model](02-map-layout-authoring-model.md); it is not tuned, it is removed.
- **Rebuilt when the player changes cell, not on a timer.** The field's goal is a cell, not a point, so a refresh interval buys staleness for nothing. At 100 move speed against 16px tiles the player crosses a boundary roughly every 10 frames, so this is ~1/10th of a per-frame rebuild with **structurally zero staleness** — the field is always exact for the cell the player is in. A frame-budget stagger stays available if profiling ever asks; it is not built now.
- **Keyed by inflation radius, built lazily for the radii in use.** [Boss model](05-boss-model.md) gave the boss its own collision map because a ~72px body handed paths through gaps it cannot enter jams against `move_actor` while the path insists. That split survives as a second field, and its accepted residual — a boss too wide for a corridor cannot enter it — is unchanged. What changes is the justification: two floods on a player-cell change is cheap enough that "there is exactly one boss" stops carrying the argument, so a future heavy could take its own radius without re-arguing cost.

### The map has holes, and they are the doorways

**Untiled means walkable, and that is load-bearing today.** `does_cell_collide` reads `collision_map[cell]`, `false` for an absent cell. The one authored map has **1704 tiles across a 54x48 box — 353 walls, 1351 floors, 888 cells with no tile at all**, and the player's own start cell `(29, 15)` is one of them. Rooms are authored; the corridors between them are *absence*:

```
11  #####    #####      ####
12       ....
15       ....            <- player_start, in the gap
18  #####    #####      ####
```

Untiled cells draw as the `0x181818` clear colour ([main.odin:916](../../../main.odin)), never `TILEMAP_FLOOR_COLOR`, so the walkable gaps render as background rather than as floor.

- **Nothing bounds the world either.** Flooding from `player_start` reaches 2887 cells, **648 of them outside the authored rectangle** — a search aimed at an unreachable goal walks off the edge of the map into open void. `MAX_SEARCH_NODES :: 1024` has been doing double duty as a search budget *and* as the only thing stopping that.
- **The field is bounded to the authored extent**; absent-inside stays walkable, outside is solid. Making absence solid everywhere is the cleaner model and the one [Per-map theming](07-per-map-theming-and-ambient-effects.md) assumes — a Map with an authored floor colour should not have holes that colour never reaches — but it is a content change that would put the player's start inside a wall until Desert Dungeon is redrawn.
- **The validity test already catches it.** [Map layout authoring model](02-map-layout-authoring-model.md) specified `player_start` on floor, one connected walkable region, a reachable spawn ring and a cell-extent bound as a test over the baked `maps` table. Desert Dungeon **fails the first of those today**. Nothing needs adding to that decision; the five new maps are drawn solid and the existing one is patched when it is redrawn as a rung.

### Goals, now that there is only one goal

- **A Ranged retreat is a step up the gradient.** `movement_goal_point` ([enemy.odin:797](../../../enemy.odin)) currently aims 100px directly behind the enemy with no wall check, so a cornered Spitter reverses into geometry. Retreat becomes the neighbouring cell with the greatest path-distance — every candidate walkable by construction. It keeps one failure: backing up a gradient walks into dead ends. Accepted, because a Spitter trapped at `min_range` in a corner is a kill the player set up, and the alternative is a second search per Ranged enemy.
- **Floaters never touch the field, retreat included.** `Floater` skips `move_actor` and flies through walls, so a path around geometry is what its identity denies; **Gazer** (Floater/Ranged, debuting rung 4) exists precisely to shoot from inside the geometry. The straight-line retreat that fails for a Spitter *succeeds* for a Gazer, because there is nothing to fail against. So `movement_goal_point` does not merge into the field — it splits on whether the Movement Style collides, the same seam `move_actor` already has.
- **The Swarmer's ring slots are deleted, not fixed.** The ticket handed over two halves — route to the slot rather than seek it in a straight line, and slide a slot that lands in a wall. Both dissolve: a Swarmer follows the field until its path-distance reaches its surround radius, then drifts along the contour. Routing *is* the field, and a slot cannot land in a wall when there are no slots. The ring is emergent — everyone at one distance, pushed apart by Separation — and it is a **better** ring, because path-distance wraps around walls where euclidean radius cut through them. `SWARMER_RING_ROTATION_SPEED`'s drift survives as a tangential term along the contour. This is the largest deletion here: `assign_swarmer_slots`'s O(n^2) (~20k distance checks at 200, three temp collections a frame) and `swarmer_surround_radius`'s first-Swarmer-radius approximation both go.
- **A cell with no value falls back to the best-valued of its eight neighbours, then to a straight line.** This is the hole the field opens and the one today's code quietly patches: `find_path` exempts the start and goal cells — "endpoints always allowed" ([enemy.odin:940](../../../enemy.odin)) — because radius-1 inflation marks every cell adjacent to a wall solid and Separation routinely pushes bodies into that envelope. The fallback reproduces the exemption without a special case: an enemy inside the envelope steps out of it and rejoins the field. The straight line is what the code already does on a failed path; the difference is it now fires only in a genuinely unreachable pocket, not every time a 1024-node budget ran out.
- **`Charger` opts out for its dash, and a wall ends it.** A field is a lookup, not a subscription, so ignoring it costs nothing. A dash into a wall **ends early into the recovery window** rather than burning out against the geometry — which makes walls a tool the player can bait a Lancer into, teaching the dodge from the map as well as from the timing.

### Two costs that outlived the pathfinder

- **`move_actor` scans every tile, twice, per actor, per frame** ([main.odin:503](../../../main.odin)) — one full `tilemap.tiles` loop per axis. At 250 enemies that is **852,000 `CheckCollisionRecs` calls a frame**, and a flow field does not touch it: after the field lands it is the largest per-enemy cost in the game. This ticket owns it, because resolving movement against the world is half of moving, and because it is nearly free once the field exists — the field already needs a cell-indexed solid set, so `move_actor` tests the ~9 cells its box overlaps instead of 1704 tiles (~4,500 checks a frame at 250). `tile_blocks_point` takes the same fix, and `build_inflated_collision_map` — 353x9 hash writes rebuilt every frame for a tilemap that cannot change during a Run ([enemy.odin:708](../../../enemy.odin)) — becomes a per-Run build. **The player gets the fix for nothing.**
- **Spawn candidates are rejected when the field has no value for their cell.** `pick_offscreen_spawn_point` retries against still-visible and wall-blocked candidates but has never checked *reachability*, so a candidate in a disconnected pocket spawns an enemy that can never arrive — and at rung 4 densities that is a permanent drip of enemies holding [ADR-0017](../../../docs/adr/0017-run-outcome-and-map-objective.md)'s Cleared open forever. The field's filled set **is** the reachable-from-player set, so this is one lookup. The spawn-anyway-on-exhaustion rule is untouched; only what the retries test improves.

### The crowd itself

- **No hard enemy-enemy collision.** Today `move_actor` resolves against the tilemap only and Separation is a soft force, so at 250 converging bodies interpenetrate freely. Hard collision is another n^2 at exactly the wrong scale, and it changes the threat model: a solid crowd is a wall the player cannot be reached through, turning rung 4's swarm into a shield for the shooters behind it. The pile-up stays a Separation problem.
- **Separation samples ~8 neighbours per enemy, not all of them.** `compute_separation_direction`'s 3x3 bucket neighbourhood is not a bound in the converging case — with no hard collision, nothing stops hundreds of bodies sharing one 120px square, so it degenerates toward O(n^2) exactly where it is needed. The result is a normalized direction, so a sample of the crowd points essentially where the full sum points; the 20th neighbour changes the answer by nothing measurable and costs the same as the first. O(n*8) unconditionally, no tuning-value change, no new structure.

### `Enemy.path` and the debug view

**Deleted**, along with [bullet.odin:177](../../../bullet.odin)'s free-on-death. `Debug_Visualizer.Pathfinding` already exists as a slot and keeps its name and toggle; it is repointed at a field overlay — arrows and distance across the map, one draw instead of 250 yellow polylines, which at rung 4 density is unreadable anyway. The debug view gets better as a side effect of deleting what it drew.

### Not decided here

- **Tuning constants** — the contour drift rate, the exact neighbour-sample cap, the Charger's wall-contact recovery duration. Balance work, matching every prior ticket on this map.

### Follow-on

- **[Content-scale integration sweep](09-content-scale-integration-sweep.md)** is unblocked from this side and takes six new seams (below).
- **Desert Dungeon fails `player_start`-on-floor** the moment [Map layout authoring model](02-map-layout-authoring-model.md)'s validity test is written. That is the test working, not a new decision.
