package shooter

import "core:fmt"
import "core:math"
import "core:math/linalg"
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
}

EditorTool :: enum {
	Pencil,
	Rectangle,
	Erase,
}

editor: struct {
	mode:          EditorMode,
	tool:          EditorTool,
	// whether the pointer was over an editor window last frame; world
	// painting is suppressed while true
	ui_hovered:    bool,
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
	// which rows of the always-visible Spawn Trigger list (editor_window)
	// are expanded, keyed by index into game.editing_map.spawn_triggers -
	// purely a UI toggle, unrelated to the persisted Spawn_Trigger itself,
	// same rationale as picking_map above. Multiple rows may be expanded at
	// once (ticket 04's prototype used a Set, not a single accordion slot).
	// Grown/shrunk in lockstep with spawn_triggers by spawn_trigger_row_add/
	// spawn_trigger_row_remove so indices always line up.
	expanded_spawn_triggers: [dynamic]bool,
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

	hovered_coord := hovered_tile_coords()

	if editor.mode == .Collisions {
		update_collisions_mode(hovered_coord)
		return
	}

	if editor.tool == .Rectangle {
		update_rectangle_tool(hovered_coord)
		return
	}

	if editor.ui_hovered {
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
	if editor.ui_hovered {
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
		if editor.ui_hovered {
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

	if editor.mode == .Collisions {
		for tile in game.editing_map.tilemap.tiles {
			if tile.collides {
				draw_rectangle(tile_world_rect(tile.world_coords, tile_size), COLLIDER_SHADE_COLOR)
			}
		}

		if !editor.ui_hovered {
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

	if editor.ui_hovered {
		return
	}

	rect := tile_world_rect(hovered_tile_coords(), tile_size)
	draw_rectangle_lines(rect, editor.tool == .Erase ? rl.RED : rl.YELLOW, 1)
}

// -- editor windows ----------------------------------------------------------

draw_editor :: proc() {
	editor.ui_hovered = false

	ui.set_pointer_state(game.mouse, is_mouse_button_down(.LEFT))
	ui.begin_frame(game.window_width, game.window_height)

	if ui.row({size = {layout.grow(0, 0), layout.grow(0, 0)}, padding = 12}) {
		editor_window()
	}

	render_commands := ui.end_frame()

	for cmd in render_commands {
		switch cmd.kind {
		case .Rectangle:
			rl.DrawRectangleV(rl.Vector2(cmd.pos), rl.Vector2(cmd.size), rl.Color(cmd.color))
		case .Text:
			rl.DrawTextEx(
				font,
				strings.clone_to_cstring(cmd.text, context.temp_allocator),
				rl.Vector2(cmd.pos),
				f32(cmd.font_size),
				0,
				rl.Color(cmd.color),
			)
		}
	}
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
		}

		if editor.picking_map {
			if ui.row({gap = ui.theme.gap}) {
				for name in Map_Name {
					if ui.button(maps[name].name) {
						switch_editing_map(name)
						editor.picking_map = false
					}
				}
			}
		}

		if ui.row({gap = ui.theme.gap}) {
			mode_button("Tiles", .Tiles)
			mode_button("Collisions", .Collisions)
		}

		switch editor.mode {
		case .Tiles:
			tiles_mode_ui()
		case .Collisions:
			collisions_mode_ui()
		}

		// always-visible, like the Map row above - there's no map position to
		// click-place a Spawn Trigger at anymore, so authoring lives in its
		// own panel rather than a dedicated Editor_Mode (ticket 04)
		spawn_triggers_ui()

		if ui.row({gap = ui.theme.gap}) {
			if ui.button("Save") {
				save_map(game.editing_map_path, game.editing_map)
			}

			if ui.button("Clear") {
				clear(&game.editing_map.tilemap.tiles)
			}

			ui.spacer()
			ui.text("Tiles: {}", len(game.editing_map.tilemap.tiles))
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

	// free the map being switched away from, or repeated Switch clicks leak
	// one copy of each previously-open map
	delete_map(game.editing_map)
	game.editing_map = loaded
	game.editing_map_path = path
	// row-expand state is keyed by index into the *previous* map's
	// spawn_triggers - stale once the map underneath it changes
	clear(&editor.expanded_spawn_triggers)
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

// -- Spawn Trigger authoring (enemy-spawn-revamp map, ticket 04) -----------
//
// Always-visible list, one row per Spawn Trigger, mirroring the Map row's
// own always-visible placement above - there's no map position to
// click-place a trigger at anymore, so this isn't a dedicated EditorMode.
// Clicking a row's summary toggles an inline detail panel beneath it
// (multiple rows may be expanded at once, per the winning prototype).

DEFAULT_SPAWN_TRIGGER_INTERVAL :: 3
DEFAULT_SPAWN_CONDITION_KILLS :: 10

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
		fmt.sbprintf(
			&sb,
			"{}x {}+{}",
			entry.count,
			movement_style_label(entry.movement_template),
			attack_style_label(entry.attack_template),
		)
	}
	return strings.to_string(sb)
}

movement_style_label :: proc(movement: Movement_Style) -> string {
	switch _ in movement {
	case Grounded:
		return "Grounded"
	case Floater:
		return "Floater"
	case Swarmer:
		return "Swarmer"
	}
	return "None"
}

attack_style_label :: proc(attack: Attack_Style) -> string {
	switch _ in attack {
	case Melee:
		return "Melee"
	case Ranged:
		return "Ranged"
	}
	return "None"
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
		spawn_composition_entry_add(
			trigger,
			Spawn_Composition_Entry {
				movement_template = Grounded{speed = 40},
				attack_template = Melee{attack_damage = 10, attack_range = 10, attack_cooldown = 1},
				count = 1,
			},
		)
	}
}

draw_spawn_composition_entry_ui :: proc(entry: ^Spawn_Composition_Entry, key: string) {
	if ui.row({gap = ui.theme.gap}) {
		ui.text("Movement")
		movement_template_none_button(key, "None", entry)
		movement_template_button(key, "Grounded", entry, Grounded{speed = 40})
		movement_template_button(
			key,
			"Floater",
			entry,
			Floater{speed = 30, wobble_amplitude = 80, wobble_frequency = 3, pull_strength = 0.35},
		)
		movement_template_button(key, "Swarmer", entry, Swarmer{speed = 50})
	}

	switch &m in entry.movement_template {
	case Grounded:
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Speed")
			ui.slider(fmt.tprintf("{}_grounded_speed", key), &m.speed, 0, 300)
			ui.text("{:.0f}", m.speed)
		}
	case Floater:
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Speed")
			ui.slider(fmt.tprintf("{}_floater_speed", key), &m.speed, 0, 300)
			ui.text("{:.0f}", m.speed)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Wobble Amplitude")
			ui.slider(fmt.tprintf("{}_floater_wobble_amplitude", key), &m.wobble_amplitude, 0, 80)
			ui.text("{:.0f}", m.wobble_amplitude)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Wobble Frequency")
			ui.slider(fmt.tprintf("{}_floater_wobble_frequency", key), &m.wobble_frequency, 0.1, 5)
			ui.text("{:.1f}", m.wobble_frequency)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Pull Toward Player")
			ui.slider(fmt.tprintf("{}_floater_pull_strength", key), &m.pull_strength, 0, 1)
			ui.text("{:.2f}", m.pull_strength)
		}
	case Swarmer:
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Speed")
			ui.slider(fmt.tprintf("{}_swarmer_speed", key), &m.speed, 0, 300)
			ui.text("{:.0f}", m.speed)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Surround Radius (from Attack Style)")
			ui.text("{:.0f}", swarmer_surround_radius(entry.attack_template))
		}
	}

	if ui.row({gap = ui.theme.gap}) {
		ui.text("Attack")
		attack_template_none_button(key, "None", entry)
		attack_template_button(
			key,
			"Melee",
			entry,
			Melee{attack_damage = 10, attack_range = 10, attack_cooldown = 1},
		)
		attack_template_button(
			key,
			"Ranged",
			entry,
			Ranged {
				min_range = 60,
				max_range = 120,
				attack_damage = 8,
				projectile_speed = 200,
				fire_rate = 1,
				bullet_lifetime = 2,
			},
		)
	}

	switch &a in entry.attack_template {
	case Melee:
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Attack Damage")
			ui.slider(fmt.tprintf("{}_melee_attack_damage", key), &a.attack_damage, 0, 100)
			ui.text("{:.0f}", a.attack_damage)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Attack Range")
			ui.slider(fmt.tprintf("{}_melee_attack_range", key), &a.attack_range, 0, 50)
			ui.text("{:.0f}", a.attack_range)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Attack Cooldown")
			ui.slider(fmt.tprintf("{}_melee_attack_cooldown", key), &a.attack_cooldown, 0.1, 5)
			ui.text("{:.2f}", a.attack_cooldown)
		}
	case Ranged:
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Min Range")
			ui.slider(fmt.tprintf("{}_ranged_min_range", key), &a.min_range, 0, 300)
			ui.text("{:.0f}", a.min_range)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Max Range")
			ui.slider(fmt.tprintf("{}_ranged_max_range", key), &a.max_range, 0, 300)
			ui.text("{:.0f}", a.max_range)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Attack Damage")
			ui.slider(fmt.tprintf("{}_ranged_attack_damage", key), &a.attack_damage, 0, 100)
			ui.text("{:.0f}", a.attack_damage)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Projectile Speed")
			ui.slider(fmt.tprintf("{}_ranged_projectile_speed", key), &a.projectile_speed, 0, 500)
			ui.text("{:.0f}", a.projectile_speed)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Fire Rate")
			ui.slider(fmt.tprintf("{}_ranged_fire_rate", key), &a.fire_rate, 0.1, 10)
			ui.text("{:.1f}", a.fire_rate)
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

movement_template_button :: proc(key_prefix: string, label: string, entry: ^Spawn_Composition_Entry, value: $T) {
	_, is_active := entry.movement_template.(T)
	if selectable_button(fmt.tprintf("{}_movement_{}", key_prefix, label), label, is_active) {
		entry.movement_template = value
	}
}

movement_template_none_button :: proc(key_prefix: string, label: string, entry: ^Spawn_Composition_Entry) {
	if selectable_button(fmt.tprintf("{}_movement_{}", key_prefix, label), label, entry.movement_template == nil) {
		entry.movement_template = nil
	}
}

attack_template_button :: proc(key_prefix: string, label: string, entry: ^Spawn_Composition_Entry, value: $T) {
	_, is_active := entry.attack_template.(T)
	if selectable_button(fmt.tprintf("{}_attack_{}", key_prefix, label), label, is_active) {
		entry.attack_template = value
	}
}

attack_template_none_button :: proc(key_prefix: string, label: string, entry: ^Spawn_Composition_Entry) {
	if selectable_button(fmt.tprintf("{}_attack_{}", key_prefix, label), label, entry.attack_template == nil) {
		entry.attack_template = nil
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
				[]Spawn_Composition_Entry {
					{
						movement_template = Grounded{speed = 40},
						attack_template = Melee{attack_damage = 10, attack_range = 10, attack_cooldown = 1},
						count = 1,
					},
				},
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
// Trigger panel can show the same variant label (e.g. "Grounded") more than
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
	}
}

tool_button :: proc(label: string, tool: EditorTool) {
	if selectable_button(label, label, editor.tool == tool) {
		editor.tool = tool
	}
}

// called just inside ui.begin: the current open node is the window content,
// whose parent is the window itself (title bar included)
record_ui_hover :: proc() {
	content := layout.get_node(layout.current_open_node())
	window := layout.get_node(content.parent)

	if layout.is_node_with_id_hovered(window.id) {
		editor.ui_hovered = true
	}
}
