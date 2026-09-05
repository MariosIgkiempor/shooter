# Map layout authoring model

Type: grilling
Status: resolved

## Question

Where do new map layouts come from — a human drawing tiles in the editor, a generator, or a hybrid that assembles hand-made chunks?

Today there is exactly one Map, hand-drawn tile by tile in the level editor and baked into `maps.odin` by `vendor/map-builder`. That pipeline works, but it makes every new rung of a difficulty ladder a slow manual act, which is the real constraint on how much content this effort can ever produce.

The branches:

- **Hand-authored** — keep the editor as the only source. Each new Map is a `task` ticket handing over a precise brief (size, chokepoints, sightlines, spawn timeline) for someone to draw.
- **Generated** — Maps carry generator parameters rather than a baked `Tilemap`, produced at Run start. Radically cheaper per map, and it makes a ladder's escalation a matter of tuning numbers.
- **Hybrid** — hand-made chunks or rooms, assembled procedurally into a layout.

What the answer has to settle:

- **Map's core invariant.** [Maps](../../level-maps/map.md) established that one struct shape serves both the on-disk file and the live runtime copy, with `clone_map` guarding the slice-header aliasing hazard. A generator either fills that same struct at load time (invariant intact) or displaces it (invariant redrawn).
- **The level editor's role.** If layouts are generated, is the editor retired, kept for spawn-timeline authoring only, or kept whole for hand-made chunks? Note the editor already handles Spawn Triggers as a non-`EditorMode` panel rather than click-placed markers.
- **`vendor/map-builder` and `data/maps/*.json`.** Generation may make the bake step meaningless, or may bake parameter sets instead of tiles.
- **Determinism.** Does a Map play the same twice? A seeded, reproducible layout is a very different content object from a fresh one every Run, and it changes what "clearing a Map" means to a player.
- **Pathfinding and spawn placement.** `pick_offscreen_spawn_point` retries against solid tiles and clamps to `tilemap_world_bounds`; BFS pathing assumes a connected walkable region. A generator must guarantee what hand-drawing guaranteed by eye.

This ticket blocks both the ladder's shape and per-map theming, because what a "rung" is made of depends on it.

## Answer

**Hand-authored.** Each rung of the ladder is a layout drawn in the level editor and baked into `maps.odin`, one file per Map. Generation and hybrid chunk assembly were both rejected. [ADR-0021](../../../docs/adr/0021-map-layouts-are-hand-authored-places.md).

### The cost premise this ticket was built on was stale

The ticket priced hand-authoring as "a slow manual act". It no longer is. `draw_tilemap` ([main.odin:1107](../../../main.odin)) renders flat fill keyed off `tile.collides` alone since the art revamp, and **nothing anywhere reads `Tile.atlas_coords`** — only the struct definition and the editor palette that writes it. The expensive part of drawing a map (an atlas choice per cell, wall joins reading correctly) is already gone; what remains is blocking out rectangles of wall, which the rectangle tool does.

Against a saving that small, a generator would have to re-earn by construction what hand-drawing gets by eye — one connected walkable region for BFS, floor under the spawn ring, chokepoints worth fighting in — and it works against the effort's purpose. A ladder is a sequence of *places*; generation answers "I need a hundred arenas", not "I need six that feel different". Hybrid costs the assembler *and* the chunks and still yields recombinations.

### Settled

- **`Map`'s core invariant is untouched.** One struct shape for file and runtime, `clone_map` still guarding the slice-header aliasing. `Map_Name` stays a compile-time enum baked from `data/maps/*.json`; `game.active_map_pointer` keeps persisting a case name into the save.
- **`Tile.atlas_coords` is deleted**, with the editor's tileset palette (`TILESET_COLS`/`TILESET_ROWS`, `Palette_Cell`, `selected_tile`) collapsing to a wall/floor toggle. `Tile` becomes `{world_coords, collides}`. This destroys the authored tile art in the JSON and the baked literals; recoverable only by redrawing. `tileset_normal` stays generated-but-unreferenced in `atlas.odin` — free to regenerate, and the only surviving record of the art. The atlas stays essential for menu nine-slices, the splash background and the font.
- **Footprint is held flat across the ladder**, near today's ~54×48. `MAX_SEARCH_NODES :: 1024` ([enemy.odin](../../../enemy.odin)) against 2592 cells means a path spanning the current map *already* fails — `find_path` returns `ok = false`, `enemy.path = {}`, and the enemy straight-line chases into walls. Bigger rungs make that routine. The ladder escalates by enemy mix, trigger density and `time_limit`, not by acreage.
- **Map validity becomes a test over the baked `maps` table** — per `Map_Name`: one connected walkable region, `player_start` on floor, a reachable spawn ring, and a cell-extent bound. Matches the repo's `*_test.odin` idiom, needs no editor UI, and catches every rung at once. Stated on the **Map** glossary entry as a property of the concept.
- **Footprint stays conventional, not data.** No width/height on `Tilemap` — the sparse-scan model is documented as deliberate and several systems lean on it. The test enforces the bound instead.
- **The editor grows map-level authoring**: "New map" (writes a stub file), plus `name`, click-to-place `player_start`, and `time_limit` / `victory_multiplier` fields. Today it has *none* of these — the Save button writes tiles and triggers only ([editor.odin:439](../../../editor.odin)), so metadata is hand-edited JSON, which is exactly how rungs drift. Baking imposes one inherent round-trip: a new file has no `Map_Name` case until the next build, so the author writes, rebuilds, then draws.
- **`Tilemap` keeps `[dynamic]Tile`.** With floor tiles now carrying no information, collapsing to a set of solid cells would make `build_inflated_collision_map` nearly free, but that container is load-bearing in `clone_map`, the JSON shape, the bake, and every scan site — and per-frame cost is dominated by `find_path`, not the tile scan. Dropping one field is surgery the migration absorbs; reshaping the container is a separate change.
- **Fixed place, variable encounter.** No Run seed. Recorded as decided-against, not fog, so it isn't reopened by accident.
- **`vendor/map-builder` and `data/maps/*.json` survive**, minus `atlas_coords` in the builder's mirror `Tile`. The bake step keeps its meaning: layouts are still tiles, not parameters.

### Follow-on

- The `MAX_SEARCH_NODES` shortfall is a live bug today, independent of this decision → [Content-scale integration sweep](09-content-scale-integration-sweep.md).
- Per-rung layout briefs are outputs of [Map ladder shape](03-map-ladder-shape.md), not task tickets here — drawing a map is authoring, which the Destination puts in the implementation follow-on.
- [Per-map theming and ambient effects](07-per-map-theming-and-ambient-effects.md) is unblocked with its generator caveat void: a Map owns its own theming as authored data, since nothing generates it.
