# Map layout authoring model

Type: grilling
Status: open

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
