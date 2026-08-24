Type: prototype
Status: resolved

## Question

What are the concrete mechanics of the Separation steering force — the anti-clump behaviour that keeps same-Movement-Style enemies apart?

Needs a decided radius (how close is "too near"), strength (how hard it pushes apart relative to the chase-toward-player force), and the blend formula with the existing BFS-chase direction from `chase_to` (enemy.odin). Also confirm brute-force pairwise neighbour checks are fine at `MAX_ENEMIES :: 24` (enemy.odin:9), or whether a spatial-partition optimization is actually warranted.

Build a cheap, rough prototype to react to — per the wayfinder skill's Ticket Types section, call the Skill tool with "prototype".

## Answer

Prototype: an interactive canvas simulation with sliders for radius/strength, three colour-coded groups (Grounded/Melee, Grounded/Ranged, Floater-placeholder), guided scenarios (single pack, stress test at the real `MAX_ENEMIES :: 24`, past-the-cap, mixed movement styles), and a live per-frame neighbour-check timer to compare brute-force vs. a spatial grid. Prototype preserved on the throwaway branch `prototype/separation-force` (commit 1273201) — see `.scratch/enemy-behaviours/prototypes/separation-force.html` on that branch for the primary source; the file also sits untracked in the working tree on `main` for convenience.

**Validated after live tuning:**
- **Radius**: 40px (prototype canvas units)
- **Strength**: 3.0 (separation dominates the chase-toward-player pull 3:1) — confirmed as the real ceiling, not just "whatever the slider allowed"
- **Blend formula**: `normalize(chase_dir + separation_dir * strength) * speed * dt` — i.e. separation is summed into the chase direction before normalizing and scaling by speed, mirroring `chase_to`'s existing `normalize0(dir) * speed * dt` shape so it drops in as a direct addition to `update_enemies`'s per-enemy delta computation
- **Grouping confirmed**: separation applies within the same Movement Style only — the "Mixed movement styles" scenario showed Floater-placeholder dots passing through the Grounded cluster unaffected, while Grounded/Melee and Grounded/Ranged (different Attack Style, same Movement Style) separated from each other, confirming grouping keys off Movement Style alone
- **Neighbour lookup**: build the spatial grid (not brute-force), even though `MAX_ENEMIES :: 24` alone wouldn't force it — chosen for headroom in case the cap ever grows, after the prototype's "push past the cap" scenario made the cost difference visible

Note: `enemy_cell`/`world_to_cell_coord` (enemy.odin:221-226) already bucket positions into tile-sized cells for the BFS collision map — the spatial grid's cell bucketing can likely reuse or mirror that existing coordinate-to-cell conversion rather than inventing a second one, though the exact cell size for separation lookups (probably the separation radius itself, not the tile size) is an implementation detail for whoever builds this off this ticket.
