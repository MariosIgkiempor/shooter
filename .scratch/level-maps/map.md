# Maps

Label: wayfinder:map

## Destination

A spec for introducing `Map` as a first-class concept: a named, reusable level definition (tile layout, spawner definitions, player start position) stored as its own file under `data/maps/`, with the same struct shape serving both the on-disk file and the live runtime copy a session plays on. Reaching the end of this map means the `Map` type's exact shape, its persistence procs, and both UI flows (startup selection, in-editor map switching) are fully specified — implementation itself is a separate follow-on.

**Status: all tickets resolved.** Every decision needed to build this is closed — the `Map` type and its `load_map`/`save_map`/`clone_map` procs, the build-time baking tool that mirrors `vendor/atlas-builder`, the editor's isolated `game.editing_map` switcher, and the startup selection screen. Nothing left to decide before the implementation follow-on starts.

## Notes

- Domain: see `CONTEXT.md`'s `## Language` section for **Map** (already written during this map's charting). No separate Level/Blueprint/Spawn_Point split — one struct serves both the blueprint and runtime roles, matching how `Spawner` already mixes blueprint fields with a runtime `timer` on one struct today.
- `game.tilemap`/`game.spawners` are replaced by a single `game.current_map: Map` field (Playing mode's live state).
- Editing mode gets its own separate `game.editing_map: Map`, independent from `game.current_map`. Switching maps inside Editing never touches the Playing map; leaving Editing (`F1`) always resumes Playing on `game.current_map` untouched, even if a different (or the same) map was edited and saved during the detour — no mid-session re-sync, Playing stays on its already-loaded copy until the next relaunch.
- A new `ProgramMode.Selecting` is shown at every launch before Playing/Editing become reachable. Map choice is one-shot per launch — no in-game return to the selector. `F1` continues to toggle Playing ↔ Editing unchanged once a map is active.
- `data/game_save.json` shrinks to pure session state: player (position/xp/level/weapon), camera, mouse, and a pointer to the active map. It no longer contains tilemap/spawner data.
- Player progression (xp/level/weapon) stays global regardless of map choice.
- Player position resumes from `game_save.json` when the newly chosen map matches the previously-active one; it resets to the map's `player_start` only on an actual map switch, or on first-ever launch.
- The existing union-conversion shim (`Movement_Style`/`Attack_Style` ↔ plain-struct, for `Spawner`) moves fully into new `load_map`/`save_map` procs; `save_game`/`load_game` no longer reference spawners at all.
- Migrating the existing desert dungeon into `data/maps/desert_dungeon.json` is a one-off manual extraction, not a reusable code path — specifying it is in scope for this map, executing it is not (see Out of scope).
- Playing mode consumes maps baked into the executable at build time (mirroring `vendor/atlas-builder` → `atlas.odin`), not runtime file I/O — see [Map type and persistence](issues/01-map-type-and-persistence.md) and [Map baking tool](issues/04-map-baking-tool.md). Editing mode is the exception: it always reads/writes the live `data/maps/*.json` files directly, never the baked table, so edits need a generator re-run plus a rebuild before Playing reflects them.
- Grilling tickets in this map should call the Skill tool per wayfinder's Ticket Types section ("grilling" + "domain-modeling").

## Decisions so far

- [Map type and persistence](issues/01-map-type-and-persistence.md): `Map` struct (`name`, `player_start`, `tilemap`, `spawners`) with value-in/value-out `load_map`/`save_map` procs; the union-conversion shim moves into them wholesale. `game_save.json`'s active-map pointer stores the map's identity as a string. Resume-vs-reset player positioning is a standalone `apply_chosen_map` proc. Flags a real aliasing hazard: copying a `Map` value only copies its dynamic-array slice headers, not contents — anything instantiating a runtime `Map` from a reused source value must go through a new `clone_map` deep-copy proc.
- [Editor map switcher](issues/03-editor-map-switcher.md): `game.editing_map`/`game.editing_map_path` pair, cloned from `game.current_map` on entering Editing; an always-visible "Map: <name> [Switch]" row in `editor_window`, not a fourth `EditorMode`; `Save` now calls `save_map` only, decoupled from `save_game()`; unsaved edits are silently discarded on leaving Editing.
- [Map baking tool](issues/04-map-baking-tool.md): new `vendor/map-builder/` (mirroring `vendor/atlas-builder` exactly, including its `strings.to_ada_case` naming convention), wired into `build.sh`, generating `maps.odin` — a `Map_Name` enum plus a runtime-initialized `maps: [Map_Name]Map` table and a `map_path_for_name` proc. Only the selection screen ever reads `maps`, always through `clone_map`. Editing stays fully file-based; changes are stale until the generator re-runs and the executable rebuilds, matching the existing texture workflow, no dev-mode fallback.
- [Map-selection screen](issues/02-map-selection-screen.md): `draw_map_selection_ui`, mirroring the existing Level-Up/Game-Over full-screen modal pattern, one button per `Map_Name`. `ProgramMode` gains `Selecting` as its first (zero-value) case and is tagged `json:"-"` so every launch starts there regardless of what was last saved.

## Not yet specified

## Out of scope

- Creating a brand-new blank map from scratch in-game (no "New Map" UI) — both the startup selector and the in-editor switcher only ever work with existing files under `data/maps/`.
- An in-game "reset level to blueprint" action/button — the data model supports it structurally (reload = re-copy from file), but no trigger ships as part of this effort.
- Mid-session return to the map-selection screen without restarting the game — map choice is one-shot per launch.
- Re-syncing `game.current_map` from a file saved during an Editing detour — Playing always stays on its already-loaded copy until the next relaunch, even if the active map's file changes underneath it.
