package shooter

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:slice"
import "core:strings"
import rl "vendor:raylib"

import layout "vendor/ui"
import ui "vendor/ui/ui"

// The ui package handles the editor chrome: a window with tool buttons, the
// Spawn Trigger list, and actions. It only emits rectangle/text render
// commands, which is all the editor needs now that tiles are authored by
// blocking out rectangles rather than picked from a tileset palette.

// what the editor is editing: tiles themselves, or their collision flags.
// Spawn Trigger authoring has no dedicated mode - there's no map position to
// click-place anymore, so its panel is always-visible instead (see
// editor_window's Spawn Triggers section) - the enemy-spawn-revamp map's
// ticket 04.
EditorMode :: enum {
	Tiles,
	Collisions,
	// the Map's own properties rather than its tiles: name, player start,
	// time limit, payout multiplier, rung and the two authored colours
	// (ADR-0021 put the first four here, ADR-0024 the colours). Its own mode
	// for the same reason Tuning has one - it is mutually exclusive with the
	// work Tiles/Collisions do, and the pointer means something different in
	// it while a player start is armed for placing.
	Map,
	// balance/feel numbers rather than map content (tuning.odin). A fourth mode
	// rather than an always-visible section because it's mutually exclusive
	// with the work Tiles/Collisions do.
	Tuning,
}

EditorTool :: enum {
	Pencil,
	Rectangle,
	Erase,
}

editor: struct {
	mode:          EditorMode,
	tool:          EditorTool,
	// rectangle tool drag, from mouse press to release
	dragging:      bool,
	drag_erasing:  bool,
	drag_start:    Vec2i,
	// the editor's remembered view; game.camera eases toward it while
	// editing, so switching back to the editor animates. zoom == 0 means
	// "not yet initialized, adopt the gameplay view on first entry"
	camera:        Camera,
	// whether the map-switcher's list-and-pick panel is open; purely a UI
	// toggle, unrelated to game.editing_map itself
	picking_map:   bool,
	// which Tuning Group is expanded in Tuning mode, at most one at a time -
	// the same one-open-at-a-time shape as expanded_spawn_triggers below, but a
	// single value since a Tuning Group list is a menu rather than a set of
	// independently-inspectable rows
	expanded_tuning_group: Maybe(Tuning_Group),
	// which rows of the always-visible Spawn Trigger list (editor_window)
	// are expanded, keyed by index into game.editing_map.spawn_triggers -
	// purely a UI toggle, unrelated to the persisted Spawn_Trigger itself,
	// same rationale as picking_map above. Multiple rows may be expanded at
	// once (ticket 04's prototype used a Set, not a single accordion slot).
	// Grown/shrunk in lockstep with spawn_triggers by spawn_trigger_row_add/
	// spawn_trigger_row_remove so indices always line up.
	expanded_spawn_triggers: [dynamic]bool,
	// Map mode's "Place Start" button, armed by a click on it and disarmed by
	// the world click that places (update_map_mode). One-shot rather than a
	// sticky tool: a stray click in the world should not silently move where
	// every Run on this Map begins.
	placing_player_start:  bool,
	// the Map's name as it is being typed. game.editing_map.name is a view
	// into this buffer for as long as a Map is open in the editor (see
	// adopt_editing_map_name), which is what lets a name be edited at all
	// without an allocation to own - vendor/ui has no text widget, so the
	// field is editor.odin's own (see text_field).
	name_buffer:           Text_Buffer,
	name_field_focused:    bool,
	// game.editing_map_path for a Map the editor itself created: derived from
	// the name on the first Save (see editor_save_editing_map). A buffer
	// rather than an allocation because the field it feeds otherwise only
	// ever holds map_path_for_name's static literals, which nothing frees.
	path_buffer:           Text_Buffer,
	// whether the last Save was refused because a file already lives where
	// this Map's name sends it. The log is not the editor's user interface -
	// a Save button that does nothing and says nothing is a Save button an
	// author believes. Cleared by anything that could change the answer.
	save_refused:          bool,
}

initialize_editor :: proc() {
	// the layout engine assumes each wrapped line advances exactly font_size
	rl.SetTextLineSpacing(0)
	ui.set_measure_text_proc(editor_measure_text)

}

editor_measure_text :: proc(text: string, font_size: i32) -> f32 {
	c := strings.clone_to_cstring(text, context.temp_allocator)
	return rl.MeasureTextEx(font, c, f32(font_size), 0).x
}

// -- world interaction -------------------------------------------------------

// per world unit of scroll input; negate to invert swipe direction
EDITOR_PAN_SPEED :: 12.0
EDITOR_KEY_PAN_SPEED :: 300.0 // world units per second
EDITOR_ZOOM_STEP :: 0.08 // zoom factor per scroll unit
EDITOR_ZOOM_MIN :: 0.25
EDITOR_ZOOM_MAX :: 10.0

EDITOR_CAMERA_EASE_RATE :: 12.0

// input edits editor.camera directly; the rendered game.camera eases toward
// it each frame, which also animates the switch back from gameplay
update_editor_camera :: proc() {
	// first entry: adopt the gameplay view
	if editor.camera.zoom == 0 {
		editor.camera = game.camera
	}

	screen_center := Vec2{game.window_width / 2, game.window_height / 2}
	editor.camera.offset = screen_center

	camera := &editor.camera
	wheel := get_mouse_wheel_move()

	// a gesture the editor's ui owns must not also pan or zoom the world. One
	// frame stale, like the shared ui_hovered it sits beside (hud.odin): the
	// ui is declared during the draw phase, so the newest answer available
	// here is the one last frame's layout produced - and it's about where the
	// pointer is, not about a delta having arrived, so it holds steady across
	// a trackpad gesture's gaps rather than letting the camera drift between
	// them
	if layout.scroll_captured() {
		wheel = {}
	}

	if is_key_down(.LEFT_SUPER) || is_key_down(.RIGHT_SUPER) {
		if wheel.y != 0 {
			mouse_world := rl.GetScreenToWorld2D(game.mouse, camera^)
			new_zoom := clamp(
				camera.zoom * (1 + wheel.y * EDITOR_ZOOM_STEP),
				EDITOR_ZOOM_MIN,
				EDITOR_ZOOM_MAX,
			)

			// keep the world point under the cursor fixed while zooming,
			// with the offset pinned to the screen center so the editor and
			// gameplay views stay directly comparable for easing
			camera.target = mouse_world - (game.mouse.position - screen_center) / new_zoom
			camera.zoom = new_zoom
		}
	} else {
		// swipe drags the world along with the fingers; divide by zoom so
		// panning covers the same screen distance at any zoom level
		camera.target -= wheel * EDITOR_PAN_SPEED / camera.zoom
	}

	// a name being typed owns the keyboard: WASD belongs to the field, not to
	// the view behind it, and the arrow keys go with them rather than staying
	// live - so a typo is fixed by looking at the field instead of wondering
	// why the map drifted. The wheel above is deliberately still live: it is
	// the pointer's, and the pointer is not what is typing.
	if editor.name_field_focused {
		ease_camera_towards(&game.camera, editor.camera, rl.GetFrameTime())
		return
	}

	key_pan: Vec2
	if is_key_down(.LEFT) || is_key_down(.A) {
		key_pan.x -= 1
	}
	if is_key_down(.RIGHT) || is_key_down(.D) {
		key_pan.x += 1
	}
	if is_key_down(.UP) || is_key_down(.W) {
		key_pan.y -= 1
	}
	if is_key_down(.DOWN) || is_key_down(.S) {
		key_pan.y += 1
	}

	camera.target +=
		linalg.normalize0(key_pan) * EDITOR_KEY_PAN_SPEED * rl.GetFrameTime() / camera.zoom

	ease_camera_towards(&game.camera, editor.camera, rl.GetFrameTime())
}

// frame-rate independent exponential approach
exp_approach :: proc(current, target, rate, dt: f32) -> f32 {
	return current + (target - current) * (1 - math.exp(-rate * dt))
}

ease_camera_towards :: proc(camera: ^Camera, to: Camera, dt: f32) {
	camera.target.x = exp_approach(camera.target.x, to.target.x, EDITOR_CAMERA_EASE_RATE, dt)
	camera.target.y = exp_approach(camera.target.y, to.target.y, EDITOR_CAMERA_EASE_RATE, dt)
	camera.zoom = exp_approach(camera.zoom, to.zoom, EDITOR_CAMERA_EASE_RATE, dt)
	camera.offset = to.offset
}

update_editor :: proc() {
	update_editor_camera()

	// raylib queues typed characters whether or not anything is listening.
	// Drained in every frame the name field isn't reading them (text_field
	// does that itself, from the draw phase), so focusing the field never
	// delivers a burst of whatever was typed while it was closed.
	if !editor.name_field_focused {
		for get_char_pressed() != 0 {}
	}

	hovered_coord := hovered_tile_coords()

	if editor.mode == .Map {
		update_map_mode(hovered_coord)
		return
	}

	if editor.mode == .Collisions {
		update_collisions_mode(hovered_coord)
		return
	}

	if editor.tool == .Rectangle {
		update_rectangle_tool(hovered_coord)
		return
	}

	if ui_hovered {
		return
	}

	if is_mouse_button_down(.LEFT) {
		switch editor.tool {
		case .Pencil:
			tilemap_place_tile(&game.editing_map.tilemap, hovered_coord)
		case .Erase:
			tilemap_remove_tile(&game.editing_map.tilemap, hovered_coord)
		case .Rectangle:
		// handled above
		}
	} else if is_mouse_button_down(.RIGHT) {
		tilemap_remove_tile(&game.editing_map.tilemap, hovered_coord)
	}
}

// left-drag marks tiles as colliding, right-drag clears them. only existing
// tiles can collide: painting over an empty spot does nothing
update_collisions_mode :: proc(hovered_coord: Vec2i) {
	if ui_hovered {
		return
	}

	collides: bool
	if is_mouse_button_down(.LEFT) {
		collides = true
	} else if !is_mouse_button_down(.RIGHT) {
		return
	}

	for &tile in game.editing_map.tilemap.tiles {
		if tile.world_coords == hovered_coord {
			tile.collides = collides
			return
		}
	}
}

// left-drag fills a rectangle with the selected tile, right-drag erases one.
// a drag that started in the world keeps going over ui windows; only starting
// one there is blocked
update_rectangle_tool :: proc(hovered_coord: Vec2i) {
	if !editor.dragging {
		if ui_hovered {
			return
		}

		if is_mouse_button_pressed(.LEFT) || is_mouse_button_pressed(.RIGHT) {
			editor.dragging = true
			editor.drag_erasing = is_mouse_button_pressed(.RIGHT)
			editor.drag_start = hovered_coord
		}

		return
	}

	if is_mouse_button_down(editor.drag_erasing ? .RIGHT : .LEFT) {
		return
	}

	// released: apply the rectangle
	min_coord, max_coord := coord_rect(editor.drag_start, hovered_coord)

	for y in min_coord.y ..= max_coord.y {
		for x in min_coord.x ..= max_coord.x {
			if editor.drag_erasing {
				tilemap_remove_tile(&game.editing_map.tilemap, {x, y})
			} else {
				tilemap_place_tile(&game.editing_map.tilemap, {x, y})
			}
		}
	}

	editor.dragging = false
}

coord_rect :: proc(a, b: Vec2i) -> (min_coord, max_coord: Vec2i) {
	min_coord = {min(a.x, b.x), min(a.y, b.y)}
	max_coord = {max(a.x, b.x), max(a.y, b.y)}
	return
}

hovered_tile_coords :: proc() -> Vec2i {
	world := rl.GetScreenToWorld2D(game.mouse, game.camera)

	cel := world_to_cell_coord(world, game.editing_map.tilemap.tile_size)
	return {i32(cel.x), i32(cel.y)}
}

// a tile is either there or it isn't - with no art identity left to repaint,
// placing over an occupied cell is a no-op rather than an overwrite, so
// dragging the pencil back over ground already covered changes nothing.
// Collides is deliberately preserved: it's authored in Collisions mode, and
// re-drawing a floor tile shouldn't silently clear a wall.
tilemap_place_tile :: proc(tilemap: ^Tilemap, world_coords: Vec2i) {
	for tile in tilemap.tiles {
		if tile.world_coords == world_coords {
			return
		}
	}

	append(&tilemap.tiles, Tile{world_coords = world_coords})
}

tilemap_remove_tile :: proc(tilemap: ^Tilemap, world_coords: Vec2i) {
	for tile, i in tilemap.tiles {
		if tile.world_coords == world_coords {
			unordered_remove(&tilemap.tiles, i)
			return
		}
	}
}

COLLIDER_SHADE_COLOR :: Color{230, 41, 55, 110}

// tile_size is passed explicitly (rather than always reading a global)
// since callers span both Playing (game.current_map) and Editing
// (game.editing_map), which can be different maps once the map switcher is
// in play - see world_to_cell_coord/cell_center_to_world's doc comment
tile_world_rect :: proc(coords: Vec2i, tile_size: Vec2) -> Rect {
	return {
		f32(coords.x) * tile_size.x,
		f32(coords.y) * tile_size.y,
		tile_size.x,
		tile_size.y,
	}
}

// collider shading, plus the outline of the tile under the cursor or of the
// in-flight rectangle drag; call inside the world camera
draw_editor_world_overlay :: proc() {
	tile_size := game.editing_map.tilemap.tile_size

	// the player's collision box, so collider alignment can be eyeballed
	draw_rectangle_lines(actor_collision_rect(game.player.rect), rl.SKYBLUE, 1)

	// where every Run on this Map begins, drawn in every mode rather than
	// only in Map mode: it is map content like a collider is, and blocking
	// out walls around a start you cannot see is how a start ends up inside
	// one
	draw_player_start_marker(tile_size)

	if editor.mode == .Map {
		if editor.placing_player_start && !ui_hovered {
			draw_rectangle_lines(tile_world_rect(hovered_tile_coords(), tile_size), rl.GREEN, 1)
		}
		return
	}

	if editor.mode == .Collisions {
		for tile in game.editing_map.tilemap.tiles {
			if tile.collides {
				draw_rectangle(tile_world_rect(tile.world_coords, tile_size), COLLIDER_SHADE_COLOR)
			}
		}

		if !ui_hovered {
			draw_rectangle_lines(tile_world_rect(hovered_tile_coords(), tile_size), rl.ORANGE, 1)
		}

		return
	}

	if editor.tool == .Rectangle && editor.dragging {
		min_coord, max_coord := coord_rect(editor.drag_start, hovered_tile_coords())
		rect := Rect {
			f32(min_coord.x) * tile_size.x,
			f32(min_coord.y) * tile_size.y,
			f32(max_coord.x - min_coord.x + 1) * tile_size.x,
			f32(max_coord.y - min_coord.y + 1) * tile_size.y,
		}

		draw_rectangle_lines(rect, editor.drag_erasing ? rl.RED : rl.YELLOW, 1)
		return
	}

	if ui_hovered {
		return
	}

	rect := tile_world_rect(hovered_tile_coords(), tile_size)
	draw_rectangle_lines(rect, editor.tool == .Erase ? rl.RED : rl.YELLOW, 1)
}

// -- editor windows ----------------------------------------------------------

draw_editor :: proc() {
	ui.set_pointer_state(game.mouse, is_mouse_button_down(.LEFT), get_mouse_wheel_move())
	ui.begin_frame(game.window_width, game.window_height)

	if ui.row({size = {layout.grow(0, 0), layout.grow(0, 0)}, padding = 12}) {
		editor_window()
	}

	draw_ui_render_commands(ui.end_frame())
}

editor_window :: proc() {
	if ui.begin("Tilemap Editor") {
		record_ui_hover()

		// always-visible, independent of which tool mode is active - which
		// map is open in the editor is orthogonal to which tool edits it
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Map: {}", game.editing_map.name)
			if ui.button("Switch") {
				editor.picking_map = !editor.picking_map
			}
			ui.spacer()
			ui.text("{}", editing_map_file_summary())
		}

		if editor.picking_map {
			if ui.row({gap = ui.theme.gap}) {
				for name in Map_Name {
					if ui.button(maps[name].name) {
						switch_editing_map(name)
						editor.picking_map = false
					}
				}
				// the switcher lists what the bake knows about, so a Map that
				// does not exist yet belongs at the end of that list rather
				// than on a row of its own
				if ui.button("+ New Map") {
					editor_new_map()
					editor.picking_map = false
				}
			}
		}

		if ui.row({gap = ui.theme.gap}) {
			mode_button("Tiles", .Tiles)
			mode_button("Collisions", .Collisions)
			mode_button("Map", .Map)
			mode_button("Tuning", .Tuning)
		}

		switch editor.mode {
		case .Tiles:
			tiles_mode_ui()
		case .Collisions:
			collisions_mode_ui()
		case .Map:
			map_mode_ui()
		case .Tuning:
			tuning_mode_ui()
		}

		// Tuning edits globals, not the open Map - the Spawn Trigger panel and
		// the map Save/Clear footer below would both be misleading next to it,
		// so Tuning mode ends here with its own footer (see tuning_mode_ui)
		if editor.mode == .Tuning {
			return
		}

		// always-visible, like the Map row above - there's no map position to
		// click-place a Spawn Trigger at anymore, so authoring lives in its
		// own panel rather than a dedicated Editor_Mode (ticket 04)
		spawn_triggers_ui()

		if ui.row({gap = ui.theme.gap}) {
			if ui.button(game.editing_map_path == "" ? "Save New Map" : "Save") {
				editor_save_editing_map()
			}

			if ui.button("Clear") {
				clear(&game.editing_map.tilemap.tiles)
			}

			ui.spacer()
			ui.text("Tiles: {}", len(game.editing_map.tilemap.tiles))
		}

		if editor.save_refused {
			ui.text(
				"Not saved: {} already exists. Rename this Map in Map mode.",
				map_file_path_for_slug(map_file_slug(game.editing_map.name)),
			)
		}
	}
}

// loads a different map into the editor from its live file - never touches
// the baked `maps` table (Editing stays file-based, see the map-baking
// ticket), so this always reflects whatever was last saved to disk, not
// necessarily what Playing currently has compiled in
switch_editing_map :: proc(name: Map_Name) {
	path := map_path_for_name(name)

	loaded, ok := load_map(path)
	if !ok {
		return
	}

	// json.unmarshal allocated this name out of the file, and the adopt inside
	// open_editing_map replaces the only pointer to it with a view into the
	// editor's own buffer. Freeing it is the same discipline load_map already
	// applies to the identity strings it resolves (ADR-0028) - otherwise a
	// switch leaks one name per switch.
	loaded_name := loaded.name

	open_editing_map(loaded, path)

	if len(loaded_name) > 0 {
		delete(loaded_name)
	}
}

// blocking out a map is placing and erasing rectangles - there's nothing to
// pick, so the mode is its three tools and nothing else.
tiles_mode_ui :: proc() {
	if ui.row({gap = ui.theme.gap}) {
		tool_button("Pencil", .Pencil)
		tool_button("Rect", .Rectangle)
		tool_button("Erase", .Erase)
	}
}

collisions_mode_ui :: proc() {
	collider_count := 0
	for tile in game.editing_map.tilemap.tiles {
		if tile.collides {
			collider_count += 1
		}
	}

	ui.text("Drag to mark colliders, right-drag to clear.")
	ui.text("Empty spots never collide.")
	ui.text("Colliders: {}", collider_count)
}

// -- Map mode (content-expansion-build ticket 14) --------------------------
//
// Everything about the open Map that isn't a tile: its name, where the player
// starts, the objective numbers a ladder rung tunes (ADR-0017/ADR-0022) and
// the two colours the place is made of (ADR-0024). Together with the New Map
// button in the switcher above, this is the whole of authoring a Map without
// leaving the editor.
//
// The colours preview live because Editing draws game.editing_map's tilemap
// rather than game.current_map's (draw_world_contents) - there is no separate
// preview path, the world behind the panel simply is the Map being edited.

MAPS_DIR :: "data/maps"

// what a Map with no usable name slugs to: map_builder turns a filename into
// a Map_Name case, so an empty one would bake as an empty case name
UNTITLED_MAP_SLUG :: "untitled"

DEFAULT_NEW_MAP_NAME :: "New Map"
DEFAULT_TILE_SIZE :: Vec2{16, 16}

// a new Map's starting objective and palette. Deliberately not a copy of the
// open Map's: a stub that looks like the place you were just in is a stub you
// forget to theme.
NEW_MAP_TIME_LIMIT :: 300
NEW_MAP_VICTORY_MULTIPLIER :: 1.5
NEW_MAP_FLOOR_COLOR :: Color{44, 46, 52, 255}
NEW_MAP_WALL_COLOR :: Color{96, 102, 116, 255}

// slider ranges. Rung runs past the Maps that exist so a rung can be authored
// before the rungs below it are; the payout range covers ADR-0022's planned
// 1.5..2.5 ladder with room either side.
EDITOR_RUNG_MAX :: 10
EDITOR_TIME_LIMIT_MAX :: 900
EDITOR_VICTORY_MULTIPLIER_MAX :: 3

// a Map name is bounded well inside Text_Buffer's capacity, which also has to
// hold the "data/maps/<slug>.json" the name derives
MAP_NAME_MAX_LENGTH :: 64

PLAYER_START_MARKER_COLOR :: Color{120, 255, 140, 230}
PLAYER_START_ANCHOR_COLOR :: Color{120, 255, 140, 140}

// -- a typed-into buffer -----------------------------------------------------
//
// vendor/ui has no text widget and no keyboard capture at all, so a Map's name
// is typed into one of these and the widget that draws it (text_field) is the
// editor's own. Fixed capacity rather than a [dynamic]u8 because
// game.editing_map.name is a *view* into the buffer for as long as a Map is
// open (adopt_editing_map_name): a growing buffer would move out from under
// it, and a name that owned an allocation would need freeing at every point a
// Map is replaced - of which there are four, one of them raylib's F1 handler.
TEXT_BUFFER_CAPACITY :: 96

Text_Buffer :: struct {
	data:  [TEXT_BUFFER_CAPACITY]u8,
	count: int,
}

text_buffer_string :: proc(buf: ^Text_Buffer) -> string {
	return string(buf.data[:buf.count])
}

// truncates rather than failing: the callers that type into a buffer are
// bounded already (a name at MAP_NAME_MAX_LENGTH, and the path derived from
// one inside the same capacity). The one caller that isn't is
// adopt_editing_map_name, which takes whatever name a map file carries - so a
// truncation says so rather than silently shortening a name the next Save
// would then write back.
text_buffer_set :: proc(buf: ^Text_Buffer, text: string) {
	if len(text) > TEXT_BUFFER_CAPACITY {
		log_error(
			"`{}` is longer than the {} bytes a text field holds, and is kept truncated",
			text,
			TEXT_BUFFER_CAPACITY,
		)
	}

	buf.count = min(len(text), TEXT_BUFFER_CAPACITY)
	copy(buf.data[:buf.count], text[:buf.count])
}

// printable ASCII only. The name becomes a filename by way of map_file_slug,
// and a rune that has no byte in a filename would either be dropped there
// (silently changing the name) or land in a file nobody can name back.
text_buffer_insert :: proc(buf: ^Text_Buffer, r: rune) -> bool {
	if buf.count >= TEXT_BUFFER_CAPACITY {
		return false
	}
	if r < ' ' || r > '~' {
		return false
	}

	buf.data[buf.count] = u8(r)
	buf.count += 1
	return true
}

text_buffer_backspace :: proc(buf: ^Text_Buffer) -> bool {
	if buf.count == 0 {
		return false
	}
	buf.count -= 1
	return true
}

// -- name, slug and path -----------------------------------------------------

// the filename a Map's name earns: lowercase, one underscore per run of
// anything that isn't a letter or a digit, and nothing hanging off either
// end. map_builder runs strings.to_ada_case over exactly this to get the
// Map_Name case, so "Cold Hall" -> cold_hall.json -> .Cold_Hall round-trips.
map_file_slug :: proc(name: string, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make(allocator)

	pending_separator := false
	for r in name {
		is_word := (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9')
		if !is_word {
			// held rather than written, so a trailing run leaves nothing behind
			pending_separator = strings.builder_len(sb) > 0
			continue
		}

		if pending_separator {
			strings.write_rune(&sb, '_')
			pending_separator = false
		}

		lowered := r
		if r >= 'A' && r <= 'Z' {
			lowered = r + ('a' - 'A')
		}
		strings.write_rune(&sb, lowered)
	}

	if strings.builder_len(sb) == 0 {
		return UNTITLED_MAP_SLUG
	}
	return strings.to_string(sb)
}

map_file_path_for_slug :: proc(slug: string, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("{}/{}.json", MAPS_DIR, slug, allocator = allocator)
}

// what the Map row says about where a Save lands. A Map the editor created
// has no path until its first Save, so it advertises the one it would take -
// and says out loud that the bake, not the Save, is what puts it in the
// switcher (ADR-0021's inherent round trip).
editing_map_file_summary :: proc() -> string {
	if game.editing_map_path != "" {
		return fmt.tprintf("File: {}", game.editing_map_path)
	}
	return fmt.tprintf(
		"New: {} - rebuild to play it",
		map_file_path_for_slug(map_file_slug(game.editing_map.name)),
	)
}

// re-points game.editing_map.name at the editor's own buffer, so the name can
// be typed into. Only called by open_editing_map, which is every point a Map
// arrives in the editor.
adopt_editing_map_name :: proc() {
	text_buffer_set(&editor.name_buffer, game.editing_map.name)
	game.editing_map.name = text_buffer_string(&editor.name_buffer)
}

// puts a Map in front of the editor, from wherever it came: the F1 clone of
// the Map being played (main.odin), the switcher's load from disk, or New
// Map's stub. One proc rather than the same six lines at each of the three,
// because every one of them is a way to get the ritual half-right - the free
// before the replace (or the previous Map's tiles leak), the name adopted into
// the editor's buffer (or Map mode's field edits a string it doesn't own), and
// the per-Map ui state dropped (or a row-expand index, an armed Place Start or
// a refused Save outlives the Map it described).
//
// `path` empty means the Map has no file yet, and the first Save derives one
// from its name (editor_save_editing_map).
open_editing_map :: proc(map_data: Map, path: string) {
	delete_map(game.editing_map)
	game.editing_map = map_data
	game.editing_map_path = path
	adopt_editing_map_name()

	clear(&editor.expanded_spawn_triggers)
	editor.placing_player_start = false
	editor.name_field_focused = false
	editor.save_refused = false
}

// -- creating and saving -----------------------------------------------------

// a blank Map carrying everything an author would otherwise have to think of
// before drawing anything: opaque colours a floor-darker-than-wall apart
// (ADR-0024 calls a zero-valued colour invalid, and MAP_BEVEL_MIX reads wrong
// if the floor is the lighter of the two), rung 1, and an objective a Run can
// actually be timed out against.
//
// It is deliberately *not* a valid Map yet, in CONTEXT.md's sense: it has no
// tiles, so it has no connected walkable region and its player start is not on
// floor. Blocking those out is what the author does next, and ticket 15's
// sweep over the baked table is what catches one that never was.
new_map_stub :: proc(name: string, tile_size: Vec2) -> Map {
	return Map {
		name = name,
		player_start = editor_start_position_for_cell({0, 0}, tile_size),
		tilemap = Tilemap{tile_size = tile_size},
		time_limit = NEW_MAP_TIME_LIMIT,
		victory_multiplier = NEW_MAP_VICTORY_MULTIPLIER,
		rung = 1,
		floor_color = NEW_MAP_FLOOR_COLOR,
		wall_color = NEW_MAP_WALL_COLOR,
	}
}

// player_start is the player rect's feet anchor in world units and a click
// lands anywhere inside a cell, so it snaps to that cell's centre rather than
// to wherever in the cell the pointer happened to be - which is also what
// keeps a start authored against the grid the walls are authored against.
editor_start_position_for_cell :: proc(cell: Vec2i, tile_size: Vec2) -> Vec2 {
	return cell_center_to_world(cell, tile_size)
}

// opens a brand-new Map in the editor, unsaved. Inherits only the open Map's
// tile size, which is a property of the grid rather than of the place.
editor_new_map :: proc() {
	tile_size := game.editing_map.tilemap.tile_size
	if tile_size.x <= 0 || tile_size.y <= 0 {
		tile_size = DEFAULT_TILE_SIZE
	}

	// no file yet: the first Save derives one from the name
	open_editing_map(new_map_stub(DEFAULT_NEW_MAP_NAME, tile_size), "")

	// straight into the panel that names it, with the field already live -
	// the name is the one field a new Map cannot be left alone with
	editor.mode = .Map
	editor.name_field_focused = true
}

// Save for a Map that already has a file is exactly save_map. For one the
// editor created it is a save-as: the path comes from the name, and lands only
// where nothing already lives.
editor_save_editing_map :: proc() -> bool {
	if game.editing_map_path != "" {
		return save_map(game.editing_map_path, game.editing_map)
	}

	path := map_file_path_for_slug(map_file_slug(game.editing_map.name))

	// an existing file at this path is an authored place, and a blank stub
	// written over it is only recoverable by redrawing it (ADR-0021). Renaming
	// is the fix, and it is one field away - which the panel says, because a
	// refusal only the log knows about is a Save button that lies.
	if os.exists(path) {
		log_error("A map already lives at `{}` - rename this Map before saving it", path)
		editor.save_refused = true
		return false
	}

	if !save_map(path, game.editing_map) {
		return false
	}

	text_buffer_set(&editor.path_buffer, path)
	game.editing_map_path = text_buffer_string(&editor.path_buffer)
	editor.save_refused = false
	return true
}

// -- placing the player start ------------------------------------------------

// Map mode's whole world interaction: no tile is placed or erased in it, so a
// click that isn't placing a start does nothing at all
update_map_mode :: proc(hovered_coord: Vec2i) {
	if !editor.placing_player_start || ui_hovered {
		return
	}

	if is_mouse_button_pressed(.LEFT) {
		game.editing_map.player_start = editor_start_position_for_cell(
			hovered_coord,
			game.editing_map.tilemap.tile_size,
		)
		editor.placing_player_start = false
	}
}

// the player's body at the authored start, drawn where the player would stand
// rather than as a dot at the anchor - a start is only correct if the body it
// puts there clears the walls around it
draw_player_start_marker :: proc(tile_size: Vec2) {
	start := game.editing_map.player_start

	draw_rectangle_lines(actor_collision_rect({start.x, start.y, 0, 0}), PLAYER_START_MARKER_COLOR, 1)
	draw_rectangle(tile_world_rect(world_to_cell_coord(start, tile_size), tile_size), PLAYER_START_ANCHOR_COLOR)
}

// -- the panel ---------------------------------------------------------------

map_mode_ui :: proc() {
	if ui.row({gap = ui.theme.gap}) {
		ui.text("Name")
		if text_field("map_name", &editor.name_buffer, MAP_NAME_MAX_LENGTH, &editor.name_field_focused) {
			// the name is a view into the buffer that just changed length,
			// so it has to be re-taken rather than left pointing at the old
			// one
			game.editing_map.name = text_buffer_string(&editor.name_buffer)
			// renaming is the fix a refused Save asks for, so the complaint
			// goes away the moment it is being acted on
			editor.save_refused = false
		}
	}

	if ui.row({gap = ui.theme.gap}) {
		if selectable_button("map_place_start", "Place Start", editor.placing_player_start) {
			editor.placing_player_start = !editor.placing_player_start
		}
		ui.text(
			"Start: {:.0f}, {:.0f}",
			game.editing_map.player_start.x,
			game.editing_map.player_start.y,
		)
	}

	if editor.placing_player_start {
		ui.text("Click a cell to start every Run on this Map in it.")
	}

	map_int_row("map_rung", "Rung", &game.editing_map.rung, 1, EDITOR_RUNG_MAX)

	if ui.row({gap = ui.theme.gap}) {
		ui.text("Time Limit")
		ui.slider("map_time_limit", &game.editing_map.time_limit, 0, EDITOR_TIME_LIMIT_MAX)
		ui.text("{:.0f}s", game.editing_map.time_limit)
	}

	if game.editing_map.time_limit <= 0 {
		ui.text("Untimed - only clearable if the trigger timeline ends.")
	}

	if ui.row({gap = ui.theme.gap}) {
		ui.text("Victory Multiplier")
		ui.slider(
			"map_victory_multiplier",
			&game.editing_map.victory_multiplier,
			1,
			EDITOR_VICTORY_MULTIPLIER_MAX,
		)
		ui.text("{:.2f}x", game.editing_map.victory_multiplier)
	}

	authored_color_rows("map_floor", "Floor", &game.editing_map.floor_color)
	authored_color_rows("map_wall", "Wall", &game.editing_map.wall_color)

	// derived, never authored (ADR-0024) - shown so the pair can be judged by
	// the inset they produce rather than by the two swatches alone
	if ui.row({gap = ui.theme.gap}) {
		ui.text("Bevel (derived)")
		color_swatch("map_bevel_swatch", map_bevel_color(game.editing_map))
	}

	// the ambient set, one toggle per effect. Previews live like the colours
	// do: update_ambience and draw_world_contents read the editing Map
	if ui.row({gap = ui.theme.gap}) {
		ui.text("Ambient")
		ambient_effect_toggle("map_ambient_motes", "Motes", .Motes)
		ambient_effect_toggle("map_ambient_patches", "Floor Patches", .Floor_Patches)
		ambient_effect_toggle("map_ambient_wash", "Light Wash", .Light_Wash)
	}
}

ambient_effect_toggle :: proc(key: string, label: string, effect: Ambient_Effect) {
	if selectable_button(key, label, effect in game.editing_map.ambient) {
		game.editing_map.ambient ~= {effect}
	}
}

// ui.slider is f32-only, so an int rides an f32 proxy - the same idiom
// tuning_row and the Kills_Reached count already use
map_int_row :: proc(key: string, label: string, value: ^int, min_value, max_value: f32) {
	proxy := f32(value^)
	if ui.row({gap = ui.theme.gap}) {
		ui.text("{}", label)
		if ui.slider(key, &proxy, min_value, max_value) {
			value^ = int(proxy)
		}
		ui.text("{}", value^)
	}
}

// one of a Map's two authored colours: a swatch, a readout and a slider per
// channel. Alpha is held opaque rather than exposed - both are world colours,
// and a Map that could be saved half-transparent is exactly the invalidity
// ADR-0024 names. Indexed rather than named (Color is a distinct [4]u8, so a
// channel's address is an element's) with the names in the labels.
authored_color_rows :: proc(key_prefix: string, label: string, color: ^Color) {
	if ui.row({gap = ui.theme.gap}) {
		ui.text("{}", label)
		color_swatch(fmt.tprintf("{}_swatch", key_prefix), color^)
		ui.text("{} {} {}", color[0], color[1], color[2])
	}

	color_channel_slider(fmt.tprintf("{}_r", key_prefix), "R", &color[0])
	color_channel_slider(fmt.tprintf("{}_g", key_prefix), "G", &color[1])
	color_channel_slider(fmt.tprintf("{}_b", key_prefix), "B", &color[2])
	color[3] = 255
}

color_channel_slider :: proc(key: string, label: string, channel: ^u8) {
	proxy := f32(channel^)
	if ui.row({gap = ui.theme.gap}) {
		ui.text("{}", label)
		if ui.slider(key, &proxy, 0, 255) {
			channel^ = u8(clamp(proxy, 0, 255))
		}
		ui.text("{}", channel^)
	}
}

COLOR_SWATCH_SIZE :: Vec2{34, 20}

color_swatch :: proc(key: string, color: Color) {
	if layout.node(
		{
			key = key,
			size_info = {
				layout.fixed(COLOR_SWATCH_SIZE.x),
				layout.fixed(COLOR_SWATCH_SIZE.y),
			},
			background_color = layout.Color(color),
		},
	) {}
}

// a floor rather than a width: the box grows with the name so a long one is
// never clipped by its own field, and an empty one is still wide enough to
// aim at
TEXT_FIELD_MIN_WIDTH :: 200

// the editor's own text widget, on the same layout.node escape hatch
// selectable_button uses. Focus is a bool the caller owns rather than a
// focused-key registry because the name is the only field in the editor that
// is typed into; a second one is the moment that stops being true.
//
// max_length is a separate bound rather than the buffer's own capacity because
// what a name is typed into is not the only thing it has to fit: the
// "data/maps/<slug>.json" it derives goes into a buffer of the same capacity
// (editor_save_editing_map), and needs the room the difference leaves.
//
// Typed characters are read here, in the draw phase, which is where the field
// knows whether it has focus. update_editor drains raylib's character queue in
// every frame this doesn't, so focusing the field never delivers a burst of
// whatever was typed while it was closed.
text_field :: proc(
	key: string,
	buf: ^Text_Buffer,
	max_length: int,
	focused: ^bool,
) -> (
	changed: bool,
) {
	// input is read before the box is declared, so a character typed this
	// frame is in the box this frame rather than a frame behind the caret.
	// The focus it reads is last frame's, which is the same one-frame-old
	// answer ui_hovered gives every other pointer decision in the editor.
	if focused^ {
		for r := get_char_pressed(); r != 0; r = get_char_pressed() {
			if buf.count >= max_length {
				continue
			}
			if text_buffer_insert(buf, r) {
				changed = true
			}
		}

		if is_key_pressed(.BACKSPACE) && text_buffer_backspace(buf) {
			changed = true
		}

		// Enter, or a press anywhere else (below). Deliberately not Escape:
		// nothing calls rl.SetExitKey, so Escape is still raylib's default
		// exit key and would close the window rather than the field.
		if is_key_pressed(.ENTER) || is_key_pressed(.KP_ENTER) {
			focused^ = false
		}
	}

	label := text_buffer_string(buf)
	// a caret while focused, and a space when empty so the box doesn't
	// collapse to its padding and become hard to aim at
	shown := label
	if focused^ {
		shown = fmt.tprintf("{}|", label)
	} else if label == "" {
		shown = " "
	}

	if layout.node(
		{
			key = key,
			padding = {6, 12, 6, 12},
			size_info = {layout.fit(TEXT_FIELD_MIN_WIDTH, 0), layout.fit(0, 0)},
			background_color = focused^ ? ui.theme.button_active : ui.theme.button,
		},
	) {
		hot, _, clicked := layout.get_node_mouse_state()

		if clicked {
			focused^ = true
		} else if is_mouse_button_pressed(.LEFT) && !hot {
			// checked on press rather than on release, so the release that
			// ends a slider drag elsewhere doesn't have to travel back here
			focused^ = false
		}

		layout.text(
			{
				kind = .Text,
				text = shown,
				font_size = ui.theme.font_size,
				background_color = ui.theme.button_text,
			},
		)
	}

	return
}


// -- Spawn Trigger authoring (enemy-spawn-revamp map, ticket 04) -----------
//
// Always-visible list, one row per Spawn Trigger, mirroring the Map row's
// own always-visible placement above - there's no map position to
// click-place a trigger at anymore, so this isn't a dedicated EditorMode.
// Clicking a row's summary toggles an inline detail panel beneath it
// (multiple rows may be expanded at once, per the winning prototype).

// -- Tuning mode -------------------------------------------------------------
// Every Tuning Group as a collapsible row, at most one expanded (see
// editor.expanded_tuning_group). Only the expanded group emits Tunable rows,
// which is what keeps a frame's node count small - the ~275 Tunables all at
// once would be about 1700 nodes against layout's cap of 1024 - and what makes
// the group list itself the navigation.
//
// The list scrolls (vendor/ui gained scroll containers for this); the Save/
// Reset footer above it deliberately doesn't, so the two buttons stay put
// wherever you are in the list. The scroll box takes a share of the window
// height rather than growing into the editor window's slack, which keeps
// Tiles and Collisions mode laying out exactly as they did.
TUNING_LIST_HEIGHT_FRACTION :: 0.6

tuning_mode_ui :: proc() {
	overridden := 0
	for t in tunables {
		if tunable_overridden(t) {
			overridden += 1
		}
	}

	if ui.row({gap = ui.theme.gap}) {
		// edits are already live in memory (see tuning_row); Save only writes
		// them to disk, exactly like the map editor's own Save button below.
		// Deliberately not autosaved on drag: that would thrash the file mid-
		// drag and turn every experiment into a git diff.
		if ui.button("Save Tuning") {
			save_tuning()
		}
		if ui.button("Reset All") {
			for t in tunables {
				tunable_reset(t)
			}
			apply_tuning_change()
		}
		ui.spacer()
		ui.text("{} of {} overridden", overridden, len(tunables))
	}

	// explicitly keyed, as ui.scroll_area requires: the offset is retained
	// across frames by node id, and this container's siblings come and go as
	// groups expand
	if ui.scroll_area(
		"tuning_groups",
		{
			size = {y = layout.fixed(game.window_height * TUNING_LIST_HEIGHT_FRACTION)},
			gap = ui.theme.gap,
		},
	) {
		tuning_group_list()
	}
}

tuning_group_list :: proc() {
	for group in Tuning_Group {
		expanded := false
		if current, ok := editor.expanded_tuning_group.?; ok {
			expanded = current == group
		}

		// the override count rides on the group's own label so a collapsed
		// group still says whether anything inside it has been moved
		group_overrides := tuning_group_override_count(group)
		label := tuning_group_display_name[group]
		if group_overrides > 0 {
			label = fmt.tprintf("{} [{}]", label, group_overrides)
		}

		if selectable_button(fmt.tprintf("tuning_group_{}", group), label, expanded) {
			editor.expanded_tuning_group = expanded ? nil : group
		}

		if !expanded {
			continue
		}

		for tunable in tunables_in_group(group) {
			tuning_row(tunable)
		}

		if group_overrides > 0 {
			if ui.row({gap = ui.theme.gap}) {
				ui.spacer()
				if selectable_button(fmt.tprintf("tuning_reset_group_{}", group), "Reset Group", false) {
					tuning_reset_group(group)
					apply_tuning_change()
				}
			}
		}
	}
}

// one Tunable: a label+value line (with Reset when Overridden), then the
// control. ui.slider is f32-only, so int rides on an f32 proxy - the same
// idiom draw_spawn_trigger_detail already uses for Kills_Reached.count - and
// bool gets an ON/OFF button instead, matching debug.odin's toggles.
tuning_row :: proc(tunable: ^Tunable) {
	if ui.row({gap = ui.theme.gap}) {
		ui.text("{}: {}", tunable.label, tunable_value_text(tunable^))
		ui.spacer()
		if tunable_overridden(tunable^) {
			if selectable_button(fmt.tprintf("{}_reset", tunable.slug), "Reset", false) {
				tunable_reset(tunable^)
				apply_tuning_change()
			}
		}
	}

	switch value in tunable.value {
	case ^bool:
		if selectable_button(tunable.slug, value^ ? "ON" : "OFF", value^) {
			value^ = !value^
			apply_tuning_change()
		}
	case ^int:
		proxy := f32(value^)
		if ui.slider(tunable.slug, &proxy, tunable.min, tunable.max) {
			tunable_set(tunable^, proxy)
			apply_tuning_change()
		}
	case ^f32:
		// ui.slider uses its label as the node key, and a slug is already
		// unique across the whole registry - so it doubles as the key here
		if ui.slider(tunable.slug, value, tunable.min, tunable.max) {
			apply_tuning_change()
		}
	}
}

tunable_value_text :: proc(tunable: Tunable) -> string {
	switch value in tunable.value {
	case ^bool:
		return value^ ? "ON" : "OFF"
	case ^int:
		return fmt.tprintf("{}", value^)
	case ^f32:
		// two literal format strings rather than one with a runtime precision:
		// Odin's fmt has no `{:.*f}`, and writing it emits its own error text
		// into the label. A 0..1 ratio needs more digits to read as changing at
		// all than a 0..800 speed does.
		if tunable.max <= 2 {
			return fmt.tprintf("{:.3f}", value^)
		}
		return fmt.tprintf("{:.1f}", value^)
	}
	return ""
}

DEFAULT_SPAWN_TRIGGER_INTERVAL :: 3
DEFAULT_SPAWN_CONDITION_KILLS :: 10
DEFAULT_SPAWN_COMPOSITION_KIND :: Enemy_Kind.Grunt // the roster's baseline, so a fresh entry spawns something ordinary

spawn_triggers_ui :: proc() {
	ui.text("Spawn Triggers: {}", len(game.editing_map.spawn_triggers))

	remove_index := -1
	for &trigger, i in game.editing_map.spawn_triggers {
		row_key := fmt.tprintf("trigger{}", i)

		summary := fmt.tprintf(
			"{}. {}   {}   {}",
			i + 1,
			spawn_condition_summary(trigger.condition),
			spawn_mode_summary(trigger.mode),
			spawn_composition_summary(trigger.composition),
		)

		if ui.row({gap = ui.theme.gap}) {
			if ui.button(summary) {
				toggle_spawn_trigger_row_expanded(i)
			}
			ui.spacer()
			if ui.button(fmt.tprintf("Remove {}", i + 1)) {
				remove_index = i
			}
		}

		if spawn_trigger_row_expanded(i) {
			draw_spawn_trigger_detail(&trigger, row_key, i + 1)
		}
	}

	if remove_index >= 0 {
		spawn_trigger_row_remove(remove_index)
	}

	if ui.button("+ Add Spawn Trigger") {
		spawn_trigger_row_add()
	}
}

spawn_condition_summary :: proc(condition: Spawn_Condition) -> string {
	switch c in condition {
	case Time_Elapsed:
		return fmt.tprintf("Time {:.0f}s", c.seconds)
	case Kills_Reached:
		return fmt.tprintf("Kills {}", c.count)
	}
	return "?"
}

spawn_mode_summary :: proc(mode: Spawn_Mode) -> string {
	switch m in mode {
	case One_Shot:
		return "One-Shot"
	case Repeating:
		if m.duration > 0 {
			return fmt.tprintf("Repeating {:.1f}s for {:.0f}s", m.interval, m.duration)
		}
		return fmt.tprintf("Repeating {:.1f}s", m.interval)
	}
	return "?"
}

spawn_composition_summary :: proc(composition: []Spawn_Composition_Entry) -> string {
	if len(composition) == 0 {
		return "empty"
	}

	sb := strings.builder_make(context.temp_allocator)
	for entry, i in composition {
		if i > 0 {
			strings.write_string(&sb, ", ")
		}
		fmt.sbprintf(&sb, "{}x {}", entry.count, entry.kind)
	}
	return strings.to_string(sb)
}

draw_spawn_trigger_detail :: proc(trigger: ^Spawn_Trigger, key: string, trigger_number: int) {
	if ui.row({gap = ui.theme.gap}) {
		ui.text("Condition")
		spawn_condition_type_button(key, "Time Elapsed", trigger, Time_Elapsed{seconds = 0})
		spawn_condition_type_button(key, "Kills Reached", trigger, Kills_Reached{count = DEFAULT_SPAWN_CONDITION_KILLS})
	}

	switch &c in trigger.condition {
	case Time_Elapsed:
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Seconds")
			ui.slider(fmt.tprintf("{}_condition_seconds", key), &c.seconds, 0, 300)
			ui.text("{:.0f}", c.seconds)
		}
	case Kills_Reached:
		count_f := f32(c.count)
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Count")
			if ui.slider(fmt.tprintf("{}_condition_count", key), &count_f, 0, 100) {
				c.count = int(count_f)
			}
			ui.text("{}", c.count)
		}
	}

	if ui.row({gap = ui.theme.gap}) {
		ui.text("Mode")
		spawn_mode_type_button(key, "One-Shot", trigger, One_Shot{})
		spawn_mode_type_button(key, "Repeating", trigger, Repeating{interval = DEFAULT_SPAWN_TRIGGER_INTERVAL, duration = 0})
	}

	switch &m in trigger.mode {
	case One_Shot:
	case Repeating:
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Interval")
			ui.slider(fmt.tprintf("{}_mode_interval", key), &m.interval, 0.1, 10)
			ui.text("{:.2f}", m.interval)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Duration (0 = forever)")
			ui.slider(fmt.tprintf("{}_mode_duration", key), &m.duration, 0, 300)
			ui.text("{:.0f}", m.duration)
		}
	}

	ui.text("Composition")
	remove_entry_index := -1
	for &entry, i in trigger.composition {
		draw_spawn_composition_entry_ui(&entry, fmt.tprintf("{}_entry{}", key, i))
		if ui.button(fmt.tprintf("Remove Entry {} (Trigger {})", i + 1, trigger_number)) {
			remove_entry_index = i
		}
	}
	if remove_entry_index >= 0 {
		spawn_composition_entry_remove(trigger, remove_entry_index) // no-op below one entry
	}

	if ui.button(fmt.tprintf("+ Add Entry (Trigger {})", trigger_number)) {
		spawn_composition_entry_add(trigger, Spawn_Composition_Entry{kind = DEFAULT_SPAWN_COMPOSITION_KIND, count = 1})
	}
}

// An entry is a Kind and a count, so this is a Kind picker and a count
// slider - the ~130 lines of movement/attack sliders it replaces are gone
// with the templates they edited. What a Grunt *is* is authored in
// enemy_presets (enemy.odin) and tuned by editing that table, not per Map
// (ADR-0020); a Map picks from the roster and says how many.
draw_spawn_composition_entry_ui :: proc(entry: ^Spawn_Composition_Entry, key: string) {
	if ui.row({gap = ui.theme.gap}) {
		ui.text("Kind")
		for kind in Enemy_Kind {
			enemy_kind_button(key, kind, entry)
		}
	}

	if ui.row({gap = ui.theme.gap}) {
		ui.text("Count")
		count_f := f32(entry.count)
		if ui.slider(fmt.tprintf("{}_count", key), &count_f, 1, 20) {
			entry.count = int(count_f)
		}
		ui.text("{}", entry.count)
	}
}

spawn_condition_type_button :: proc(key_prefix: string, label: string, trigger: ^Spawn_Trigger, value: $T) {
	_, is_active := trigger.condition.(T)
	if selectable_button(fmt.tprintf("{}_condition_{}", key_prefix, label), label, is_active) {
		trigger.condition = value
	}
}

spawn_mode_type_button :: proc(key_prefix: string, label: string, trigger: ^Spawn_Trigger, value: $T) {
	_, is_active := trigger.mode.(T)
	if selectable_button(fmt.tprintf("{}_mode_{}", key_prefix, label), label, is_active) {
		trigger.mode = value
	}
}

enemy_kind_button :: proc(key_prefix: string, kind: Enemy_Kind, entry: ^Spawn_Composition_Entry) {
	label := fmt.tprintf("{}", kind)
	if selectable_button(fmt.tprintf("{}_kind_{}", key_prefix, label), label, entry.kind == kind) {
		entry.kind = kind
	}
}

// game.editing_map.spawn_triggers is [dynamic], so add/remove use
// append/ordered_remove directly - ordered (not unordered) so the visible
// list doesn't reshuffle out of authored order on a mid-list removal.
// expanded_spawn_triggers is kept in lockstep so row-expand state doesn't
// drift onto the wrong trigger after a removal.
spawn_trigger_row_add :: proc() {
	append(
		&game.editing_map.spawn_triggers,
		Spawn_Trigger {
			condition = Time_Elapsed{seconds = 0},
			mode = One_Shot{},
			// seeded with one real (heap-allocated, not a bare literal -
			// see spawn_composition_entry_add's own doc comment) entry
			// rather than left empty: an author who adds a trigger and
			// forgets to also add a composition entry would otherwise
			// save a trigger that silently spawns nothing, forever
			composition = slice.clone(
				[]Spawn_Composition_Entry{{kind = DEFAULT_SPAWN_COMPOSITION_KIND, count = 1}},
			),
		},
	)
	append(&editor.expanded_spawn_triggers, true)
}

spawn_trigger_row_remove :: proc(index: int) {
	delete(game.editing_map.spawn_triggers[index].composition)
	ordered_remove(&game.editing_map.spawn_triggers, index)
	if index < len(editor.expanded_spawn_triggers) {
		ordered_remove(&editor.expanded_spawn_triggers, index)
	}
}

spawn_trigger_row_expanded :: proc(index: int) -> bool {
	if index >= len(editor.expanded_spawn_triggers) {
		return false
	}
	return editor.expanded_spawn_triggers[index]
}

toggle_spawn_trigger_row_expanded :: proc(index: int) {
	for len(editor.expanded_spawn_triggers) <= index {
		append(&editor.expanded_spawn_triggers, false)
	}
	editor.expanded_spawn_triggers[index] = !editor.expanded_spawn_triggers[index]
}

// Spawn_Trigger.composition is a plain slice (its own persisted shape,
// ticket 03) rather than [dynamic], since it never grows at gameplay time -
// only here, during editing, where a manual make+copy+delete reallocation is
// an acceptable trade for keeping the persisted type a plain slice. Every
// composition this editor ever assigns must be a genuine heap allocation
// (make, or slice.clone of a literal) rather than a bare `{...}` slice
// literal directly - a literal used as a struct-field value isn't a
// context.allocator allocation (confirmed directly: deleting one trips the
// tracking allocator's bad-free check), so it can never be delete()'d later
// the way spawn_trigger_row_remove/this proc's own delete() calls do.
spawn_composition_entry_add :: proc(trigger: ^Spawn_Trigger, entry: Spawn_Composition_Entry) {
	new_composition := make([]Spawn_Composition_Entry, len(trigger.composition) + 1)
	copy(new_composition, trigger.composition)
	new_composition[len(trigger.composition)] = entry
	delete(trigger.composition)
	trigger.composition = new_composition
}

// a no-op below one entry: a Spawn Trigger with zero composition entries
// would silently spawn nothing forever (see spawn_trigger_row_add), so
// "keep at least one" is enforced here rather than left to the caller -
// draw_spawn_trigger_detail also disables the remove button at that point,
// but a future second caller (e.g. a keyboard shortcut) shouldn't need to
// remember the same rule independently.
spawn_composition_entry_remove :: proc(trigger: ^Spawn_Trigger, index: int) {
	if len(trigger.composition) <= 1 {
		return
	}

	new_composition := make([]Spawn_Composition_Entry, len(trigger.composition) - 1)
	copy(new_composition[:index], trigger.composition[:index])
	copy(new_composition[index:], trigger.composition[index + 1:])
	delete(trigger.composition)
	trigger.composition = new_composition
}

// like ui.button, but stays highlighted while selected. key/label are split
// (unlike ui.button, where the label doubles as the key) because the Spawn
// Trigger panel can show the same label (e.g. "Grunt") more than
// once in a single frame - one per composition entry, across however many
// trigger rows are expanded at once (ticket 04's multi-expand) - and
// ui.slider/ui.button's own doc comments warn that a duplicate key
// misattributes interaction state, so every call site here builds a key
// that also folds in which trigger/entry it belongs to.
selectable_button :: proc(key: string, label: string, selected: bool) -> (clicked: bool) {
	base := selected ? ui.theme.button_active : ui.theme.button

	if layout.node({key = key, padding = {6, 12, 6, 12}, background_color = base}) {
		hot, active: bool
		hot, active, clicked = layout.get_node_mouse_state()

		if active {
			layout.get_node(layout.current_open_node()).background_color = ui.theme.button_active
		} else if hot && !selected {
			layout.get_node(layout.current_open_node()).background_color = ui.theme.button_hot
		}

		layout.text(
			{
				kind = .Text,
				text = label,
				font_size = ui.theme.font_size,
				background_color = ui.theme.button_text,
			},
		)
	}

	return
}

mode_button :: proc(label: string, mode: EditorMode) {
	if selectable_button(label, label, editor.mode == mode) {
		editor.mode = mode
		// the name field only exists in Map mode, and the mode buttons sit
		// above the switch that draws it - so leaving this way never reaches
		// text_field's own blur path. Without this the keyboard stays captured
		// and update_editor_camera keeps refusing to pan.
		editor.name_field_focused = false
	}
}

tool_button :: proc(label: string, tool: EditorTool) {
	if selectable_button(label, label, editor.tool == tool) {
		editor.tool = tool
	}
}
