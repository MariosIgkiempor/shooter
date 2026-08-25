Type: grilling
Status: resolved

## Question

Specify the exact `Map` struct shape and the `load_map`/`save_map` procs that replace today's inline tilemap/spawner handling in `save_game`/`load_game` (main.odin).

This ticket blocks the [map-selection screen](02-map-selection-screen.md) and [editor map switcher](03-editor-map-switcher.md) tickets — both need `Map`, `load_map`, and `save_map` to exist concretely before their UI flows can be pinned down.

Needs to settle:

- **Field list.** At minimum `player_start: Vec2`, `tilemap: Tilemap`, `spawners: [dynamic]Spawner`. Does `Map` also carry its own `name`/id field, or is the filename (`data/maps/<slug>.json`) the map's only identity, with no in-struct name field?
- **The relocated union-conversion shim.** Today's per-spawner `movement_template_save`/`attack_template_save` conversion loop runs inline in `main.odin`'s `save_game`/`load_game` (main.odin:104-106, 138-140), following the `Movement_Style_Save`/`Attack_Style_Save` pattern in enemy.odin:118-154. Relocate this into `load_map`/`save_map` exactly as-is, just running over `map.spawners` instead of `game.spawners` inline in the old procs — don't invent a new persistence idiom for this move.
- **`game_save.json`'s active-map pointer.** What does this field look like (store the map's filename/slug? a full path?), and confirm `load_game`/`save_game` read/write only this pointer plus player/camera/mouse now — never touching tilemap or spawner data.
- **Player-start vs. resume-position algorithm.** Already settled: resume the player's position from `game_save.json` when the newly chosen map matches the previously-active pointer; reset to the map's `player_start` only on an actual switch, or on first-ever launch. Pin down exactly where this comparison runs and what "matches" means precisely (compare by filename/slug against the pointer above).
- **Call-site checklist.** Confirm `game.tilemap`/`game.spawners` are fully replaced by `game.current_map: Map`, and enumerate the existing call sites that'll need retargeting so the implementation follow-on has a concrete list rather than having to rediscover them: `draw_tilemap`, `draw_spawners`, `move_actor`'s collision loop over `tilemap.tiles`, `build_inflated_collision_map`, `update_spawners`, plus editor.odin's `tilemap_place_tile`/`tilemap_remove_tile` and the `Spawner{...}` construction path (~editor.odin:239).

## Answer

**1. Field list.** `Map` gets its own display `name: string`, separate from the on-disk filename/slug (the two are allowed to diverge — e.g. filename `desert_dungeon.json`, name `"Desert Dungeon"`):

```odin
Map :: struct {
	name:         string,
	player_start: Vec2,
	tilemap:      Tilemap,
	spawners:     [dynamic]Spawner,
}
```

**2. `load_map`/`save_map` shape.**

```odin
load_map :: proc(path: string) -> (map_data: Map, ok: bool)
save_map :: proc(path: string, map_data: Map) -> bool
```

Pure value-in/value-out — logging happens inside (`log_error`/`log_warning`, matching `load_game`/`save_game`'s existing style), the bool is just for the caller to branch on (e.g. the selection screen refusing to transition to `.Playing` on a failed load). The relocated shim (today's `movement_template_save`/`attack_template_save` conversion loop, main.odin:104-106/138-140, following the `Movement_Style_Save`/`Attack_Style_Save` pattern at enemy.odin:118-194) moves into these two procs unchanged, run over `map_data.spawners` instead of `game.spawners`. `save_game`/`load_game` no longer touch spawners, tilemap, or the shim at all — only player/camera/mouse/active-map-pointer.

A `Map` value itself is small regardless of how many tiles/spawners it holds — `name` and `player_start` are a string header and a `Vec2`, and `tilemap.tiles`/`spawners` are `[dynamic]T` slice headers (pointer+len+cap), not inline arrays. No "huge struct on the stack" risk from returning `Map` by value.

**Correctness note carried forward to every consumer of `Map` (including the map-baking ticket below):** assigning a `Map` value (`a := b`) copies those slice headers only, aliasing the same backing memory — it does **not** deep-copy tile/spawner contents. `load_map` is safe as written because `json.unmarshal` allocates fresh backing arrays on every call, so no two `load_map` results ever alias. Any future path that instantiates a runtime `Map` from an *existing, reused* `Map` value (the baked template table, for instance) must go through an explicit deep-copy proc — a naive value copy would let in-run tile/spawner mutation corrupt the shared template, defeating the entire point of copy-on-load. Add:

```odin
clone_map :: proc(template: Map) -> Map {
	result := template
	result.tilemap.tiles = slice.clone_to_dynamic(template.tilemap.tiles[:])
	result.spawners = slice.clone_to_dynamic(template.spawners[:])
	return result
}
```

`load_map` itself doesn't need to call this (already fresh per-call), but anything copying out of a long-lived shared `Map` value does.

**3. Active-map pointer.** `game_save.json` stores the map's canonical identity as a string — once the [map-baking ticket](04-map-baking-tool.md) settles the `Map_Name` enum, this field stores that enum value's name (Odin's `encoding/json` serializes enums as their string name by default), not a raw file path. `load_game`/`save_game` read/write only this pointer plus player/camera/mouse.

**4. Resume-vs-reset.** Lives here, next to the pointer field and `Map.player_start` it reads:

```odin
// called once, at the point the player's map choice is finalized (Selecting -> Playing)
apply_chosen_map :: proc(map_data: Map, chosen_identity: string) {
	if chosen_identity != game.active_map_pointer {
		game.player.rect.x = map_data.player_start.x
		game.player.rect.y = map_data.player_start.y
	}
	game.active_map_pointer = chosen_identity
}
```

First-ever launch falls out naturally: `game.active_map_pointer` starts as the zero value (empty string), which never matches any real identity, so the reset branch always fires.

**5. Call-site checklist** (confirmed via `grep -rn "game\.tilemap\|game\.spawners" --include="*.odin" .` this session — this list is exhaustive, not illustrative):

- `main.odin`: `move_actor` call (tilemap collision), `draw_tilemap` call, `draw_spawners` call, plus the two spawner shim loops in `save_game`/`load_game` (moving out entirely, see above).
- `bullet.odin:76`: wall-collision loop over `game.tilemap.tiles` — not previously listed in this ticket's Question, caught by the grep.
- `enemy.odin`: the spawner-update loop, `build_inflated_collision_map`, `move_actor` call, and the world-to-tile-cell math (four lines using `game.tilemap.tile_size`).
- `editor.odin`: `tilemap_place_tile`/`tilemap_remove_tile` (both call sites, paint and erase), the tile-clear/tile-count/tile-draw loops, and the full Spawners-mode set — add (`Spawner{...}` construction ~line 238), select, remove, and draw-selected-highlight, plus the spawner count/list UI.

All of the above retarget from `game.tilemap`/`game.spawners` to `game.current_map.tilemap`/`game.current_map.spawners`.
