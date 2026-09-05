# Map layouts are hand-authored places, not generated parameters

Status: accepted

A Map's tile layout is drawn by a person in the level editor and baked into `maps.odin`, one file per Map. Generating layouts from parameters at Run start was considered for the content-expansion effort's difficulty ladder and rejected.

The case for generation was cost: a ladder needs several rungs, and drawing each one by hand looked like the constraint on how much content the effort could ever produce. That pricing was stale. The art revamp made `draw_tilemap` render flat fill keyed off `Tile.collides` alone, so nothing reads `Tile.atlas_coords` any more — the expensive part of drawing a map, choosing an atlas tile per cell and making wall joins read correctly, no longer exists. What is left is blocking out rectangles of wall, which the editor's rectangle tool already does.

Against that saving, a generator would have to re-earn by construction what hand-drawing gets by eye: one connected walkable region for BFS pathing, floor under the off-screen spawn ring, chokepoints and sightlines that make an arena worth fighting in. And it works directly against the point of the effort. The game is content-thin, and a ladder is supposed to be a sequence of *places* the player learns; generation is the answer to "I need a hundred arenas", not "I need six that feel different from each other".

Hybrid chunk assembly was rejected as the worst of both: it costs an assembler *and* the hand-drawn chunks, and still yields rungs that read as recombinations of the same parts.

So a Map is a fixed place. A Run on it is not fixed — spawn angles come from unseeded `rand` in `pick_offscreen_spawn_point`, so geometry is learnable while pressure is not. There is no Run seed and nothing asks for one; replays, daily runs and leaderboards are not features this game has.

## Consequences

**`Tile.atlas_coords` is deleted**, along with the editor's tileset palette (`TILESET_COLS`/`TILESET_ROWS`, `Palette_Cell`, `editor.selected_tile`), which becomes a wall/floor toggle. `Tile` is `{world_coords, collides}`. This destroys the authored tile-art choices held in `data/maps/*.json` and the baked literals — recoverable only by redrawing. `tileset_normal` stays in the generated `atlas.odin`, unreferenced: it regenerates every build at no cost and is the only surviving record of the tile art if a later effort wants texture back. The atlas itself remains essential for menu nine-slices, the splash background, and the font.

**Map footprint is held roughly flat across the ladder**, near the existing ~54×48. `MAX_SEARCH_NODES :: 1024` caps a BFS against a map of 2592 cells, so a path spanning the current map already fails and the enemy falls back to straight-line chase into walls. Bigger rungs would make that routine, and every fix — raising the cap, a per-frame flow field, cross-frame path caching — is real work against a per-enemy-per-frame budget. The ladder escalates by enemy mix, trigger density and `time_limit`, not by acreage.

**Map validity becomes machine-checked** rather than eyeballed: a test over the baked `maps` table asserts, for every `Map_Name`, one connected walkable region, `player_start` on floor, and a reachable off-screen spawn ring. Six hand-drawn rungs accumulated over time is where silent invalidity bites, and each failure mode is quiet rather than loud.

**The editor grows map-level authoring** — a "New map" button writing a stub file, plus fields for `name`, `player_start`, `time_limit` and `victory_multiplier` — because it is now the whole authoring surface and those are exactly the fields a ladder tunes per rung. Baking imposes one round-trip that is inherent, not a defect: a newly written file has no `Map_Name` case until the next build, so the author writes, rebuilds, then draws.

`Tilemap` keeps its sparse `[dynamic]Tile`. With floor tiles carrying no information, collapsing it to a set of solid cells is tempting and would make `build_inflated_collision_map` nearly free, but that container is load-bearing in `clone_map`'s aliasing guard, the JSON shape, the bake, and every scan site — and the per-frame cost is dominated by `find_path`, not by the tile scan.
