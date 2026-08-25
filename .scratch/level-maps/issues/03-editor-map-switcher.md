Type: grilling
Status: resolved
Blocked by: 01

## Question

Specify how Editing mode gains and uses its own `game.editing_map: Map`, separate from `game.current_map`, including the in-editor UI for switching which map is being authored.

Needs to settle:

- **Default on entry.** Settled direction: entering Editing mode (`F1` from Playing) starts `game.editing_map` as a copy of `game.current_map`, so by default you're editing the map you're currently playing unless you explicitly switch. Per ticket 1's aliasing note, this must go through `clone_map`, not a plain value assignment — `game.current_map` is a live, actively-mutating value for the rest of the Playing session, so aliasing it here would let in-editor tile/spawner edits corrupt the running Playing state directly (worse than the baked-table aliasing risk ticket 4 flags, since this one's mid-session).
- **In-editor switch UI.** [Ticket 4](04-map-baking-tool.md) settled that Editing stays file-based (reads/writes live `data/maps/*.json` via `load_map`/`save_map`, never the baked table) — but the *list* of known maps can still reuse the same `Map_Name` enum the [selection screen](02-map-selection-screen.md) enumerates, mapping each case back to its source file path. So: does the in-editor switcher share the selection screen's list-and-pick UI component wholesale (same widget, different action on pick — `load_map(path)` here instead of a baked-table copy), or does it need its own? Reuse should be the default lean — call out anything that makes it impractical.
- **Save target.** "Save" in Editing mode writes `game.editing_map` to its own file via `save_map` (ticket 01) — confirm the save target is always whichever map is currently open in the editor, never `game.current_map`.
- **Isolation invariant.** Confirm and detail: nothing that happens in Editing mode (switching, editing, saving) ever mutates `game.current_map`. Leaving Editing (`F1`) always resumes Playing exactly where it left off, on whatever `game.current_map` already holds, regardless of `game.editing_map`'s state.
- **Call-site checklist.** Enumerate editor.odin's call sites that currently reference `game.tilemap`/`game.spawners` directly — `tilemap_place_tile`, `tilemap_remove_tile`, the `Spawner{...}` literal construction path (~editor.odin:239), and the editor's own draw calls — and confirm they all retarget to `game.editing_map` instead.

## Answer

**Path tracking.** `game` gains `editing_map_path: string`, set whenever `game.editing_map` is (re)loaded:
- Entering Editing from Playing (`F1`): `game.editing_map = clone_map(game.current_map)`, `game.editing_map_path = map_path_for_name(chosen_map_name)` (the same identity `game_save.json`'s active-map pointer already holds) — so by default the editor points at the exact file `game.current_map` was cloned from.
- Switching maps inside the editor: `game.editing_map, _ = load_map(new_path)`, `game.editing_map_path = new_path`.

`map_path_for_name :: proc(name: Map_Name) -> string` (deriving `data/maps/<slug>.json` from an enum case) belongs to the [map-baking tool](04-map-baking-tool.md), which already owns the filename↔enum-case naming convention — added as a note there.

**Switcher UI placement.** A new always-visible row near the top of `editor_window` (editor.odin:456-488), above the existing `Tiles`/`Collisions`/`Spawners` mode row — not a fourth `EditorMode`, since which map is open is orthogonal to which tool is active:

```odin
if ui.row({gap = ui.theme.gap}) {
	ui.text("Map: {}", game.editing_map.name)
	if ui.button("Switch") {
		// opens the shared list-and-pick component (see the map-selection
		// screen ticket) enumerating Map_Name; on pick, load_map(new_path)
		// into game.editing_map per "Path tracking" above
	}
}
```

**`Save` button rescoped.** editor.odin:476-478's `Save` button changes from calling `save_game()` to calling `save_map(game.editing_map_path, game.editing_map)` only. `game_save.json` continues to be written automatically on quit via `main()`'s existing post-loop `save_game()` call, unrelated to this button and unchanged by this effort — session-state persistence was never the level editor's concern, it just happened to ride along today because `save_game()` used to be the only save path that existed.

**Unsaved edits on leaving Editing.** Silently discarded. Pressing `F1` back to Playing does not prompt or auto-save; `game.editing_map` (and `game.editing_map_path`) are simply overwritten the next time Editing is entered (re-cloned from `game.current_map`, per "Path tracking" above). Consistent with the map's stance elsewhere of not building interactive safety nets beyond what was asked for.

**Isolation invariant.** Holds structurally by construction: `game.editing_map`/`game.editing_map_path` are never read by anything in the `.Playing` update/draw path, and nothing in Editing mode ever assigns to `game.current_map`. Leaving Editing always resumes Playing on whatever `game.current_map` already held, regardless of what was open, switched to, edited, or saved in `game.editing_map` during the detour — including the case where the same map was being edited (per ticket 1's aliasing note, `game.editing_map` is a `clone_map`, never an alias, so edits to it can't reach `game.current_map` even when they share a source file).

**Call-site checklist** (from the exhaustive grep in ticket 1's resolution — editor.odin entries only): `tilemap_place_tile`/`tilemap_remove_tile` (paint and erase), the tile-clear/tile-count/tile-draw loops, and the full Spawners-mode set (the `Spawner{...}` construction at ~line 238, select, remove, and draw-selected-highlight, plus the spawner count/list UI) — all retarget from `game.tilemap`/`game.spawners` to `game.editing_map.tilemap`/`game.editing_map.spawners`.
