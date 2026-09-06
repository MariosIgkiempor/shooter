# Enemy pathing at swarm scale

Type: grilling

Status: open

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
