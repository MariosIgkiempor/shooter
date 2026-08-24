package shooter

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strings"
import rl "vendor:raylib"

import layout "vendor/ui"
import ui "vendor/ui/ui"

// The ui package handles the editor chrome: a window with tool buttons, the
// tile palette grid, and actions. It only emits rectangle/text render
// commands, so the atlas tiles inside the palette are overlaid afterwards
// using the rects the layout resolved this frame (layout.element_rects).

// what the editor is editing: tiles themselves, or their collision flags
EditorMode :: enum {
	Tiles,
	Collisions,
	Spawners,
}

EditorTool :: enum {
	Pencil,
	Rectangle,
	Erase,
}

TILESET_COLS :: len(tileset_normal)
TILESET_ROWS :: len(tileset_normal[0])
PALETTE_CELL_SIZE :: 20

Palette_Cell :: struct {
	node_id: u32,
	coords:  Vec2i,
}

editor: struct {
	mode:          EditorMode,
	tool:          EditorTool,
	selected_tile: Vec2i,
	// index into game.spawners; -1 = none selected
	selected_spawner: int,
	// whether the pointer was over an editor window last frame; world
	// painting is suppressed while true
	ui_hovered:    bool,
	// palette cell nodes declared this frame, so tiles can be drawn over
	// them after the ui render commands; allocated once, rebuilt each frame
	palette_cells: [dynamic]Palette_Cell,
	// rectangle tool drag, from mouse press to release
	dragging:      bool,
	drag_erasing:  bool,
	drag_start:    Vec2i,
	// the editor's remembered view; game.camera eases toward it while
	// editing, so switching back to the editor animates. zoom == 0 means
	// "not yet initialized, adopt the gameplay view on first entry"
	camera:        Camera,
}

initialize_editor :: proc() {
	// the layout engine assumes each wrapped line advances exactly font_size
	rl.SetTextLineSpacing(0)
	ui.set_measure_text_proc(editor_measure_text)

	// heap, not temp: the array outlives the per-frame free_all
	editor.palette_cells = make([dynamic]Palette_Cell, 0, TILESET_COLS * TILESET_ROWS)

	editor.selected_spawner = -1
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

	if editor.mode == .Spawners {
		update_spawners_mode(hovered_coord)
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
			tilemap_place_tile(&game.tilemap, hovered_coord, editor.selected_tile)
		case .Erase:
			tilemap_remove_tile(&game.tilemap, hovered_coord)
		case .Rectangle:
		// handled above
		}
	} else if is_mouse_button_down(.RIGHT) {
		tilemap_remove_tile(&game.tilemap, hovered_coord)
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

	for &tile in game.tilemap.tiles {
		if tile.world_coords == hovered_coord {
			tile.collides = collides
			return
		}
	}
}

// left-drag places a Melee spawner on each cell passed over, right-drag
// removes the spawner on the hovered cell. one spawner per cell, like tiles
update_spawners_mode :: proc(hovered_coord: Vec2i) {
	if editor.ui_hovered {
		return
	}

	if is_mouse_button_down(.LEFT) {
		spawner_place(hovered_coord)
	} else if is_mouse_button_down(.RIGHT) {
		spawner_remove(hovered_coord)
	}
}

spawner_place :: proc(cell: Vec2i) {
	for spawner, i in game.spawners {
		if world_to_cell_coord(spawner.position) == cell {
			editor.selected_spawner = i
			return
		}
	}

	append(
		&game.spawners,
		Spawner {
			position = cell_center_to_world(cell),
			interval = DEFAULT_SPAWNER_INTERVAL,
			animation = .Player_Walk,
			movement_template = Grounded{speed = 40},
			attack_template = Melee{attack_damage = 10, attack_range = 10, attack_cooldown = 1},
		},
	)

	editor.selected_spawner = len(game.spawners) - 1
}

spawner_remove :: proc(cell: Vec2i) {
	for spawner, i in game.spawners {
		if world_to_cell_coord(spawner.position) == cell {
			last := len(game.spawners) - 1
			unordered_remove(&game.spawners, i)

			if editor.selected_spawner == i {
				editor.selected_spawner = -1
			} else if editor.selected_spawner == last {
				editor.selected_spawner = i
			}
			return
		}
	}

	// right-click on empty space with nothing to remove: deselect
	editor.selected_spawner = -1
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
				tilemap_remove_tile(&game.tilemap, {x, y})
			} else {
				tilemap_place_tile(&game.tilemap, {x, y}, editor.selected_tile)
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

	cel := world_to_cell_coord(world)
	return {i32(cel.x), i32(cel.y)}
}

tilemap_place_tile :: proc(tilemap: ^Tilemap, world_coords, atlas_coords: Vec2i) {
	for &tile in tilemap.tiles {
		if tile.world_coords == world_coords {
			tile.atlas_coords = atlas_coords
			return
		}
	}

	append(&tilemap.tiles, Tile{atlas_coords = atlas_coords, world_coords = world_coords})
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

tile_world_rect :: proc(coords: Vec2i) -> Rect {
	tile_size := game.tilemap.tile_size

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
	tile_size := game.tilemap.tile_size

	// the player's collision box, so collider alignment can be eyeballed
	draw_rectangle_lines(actor_collision_rect(game.player.rect, game.player.animation), rl.SKYBLUE, 1)

	if editor.mode == .Collisions {
		for tile in game.tilemap.tiles {
			if tile.collides {
				draw_rectangle(tile_world_rect(tile.world_coords), COLLIDER_SHADE_COLOR)
			}
		}

		if !editor.ui_hovered {
			draw_rectangle_lines(tile_world_rect(hovered_tile_coords()), rl.ORANGE, 1)
		}

		return
	}

	if editor.mode == .Spawners {
		if !editor.ui_hovered {
			rl.DrawCircleLinesV(cell_center_to_world(hovered_tile_coords()), 8, rl.ORANGE)
		}

		if editor.selected_spawner >= 0 && editor.selected_spawner < len(game.spawners) {
			rl.DrawCircleLinesV(game.spawners[editor.selected_spawner].position, 10, rl.YELLOW)
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

	rect := tile_world_rect(hovered_tile_coords())
	draw_rectangle_lines(rect, editor.tool == .Erase ? rl.RED : rl.YELLOW, 1)
}

// -- editor windows ----------------------------------------------------------

draw_editor :: proc() {
	clear(&editor.palette_cells)
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

	// atlas tiles over the palette cells, plus the selection outline
	for cell in editor.palette_cells {
		rect, ok := layout.element_rects[cell.node_id]
		if !ok {
			continue
		}

		dest := Rect{rect.x, rect.y, rect.width, rect.height}
		draw_atlas_tile(tileset_normal[cell.coords.x][cell.coords.y], dest, 0)

		if cell.coords == editor.selected_tile {
			rl.DrawRectangleLinesEx(dest, 2, rl.YELLOW)
		}
	}
}

editor_window :: proc() {
	if ui.begin("Tilemap Editor") {
		record_ui_hover()

		if ui.row({gap = ui.theme.gap}) {
			mode_button("Tiles", .Tiles)
			mode_button("Collisions", .Collisions)
			mode_button("Spawners", .Spawners)
		}

		switch editor.mode {
		case .Tiles:
			tiles_mode_ui()
		case .Collisions:
			collisions_mode_ui()
		case .Spawners:
			spawners_mode_ui()
		}

		if ui.row({gap = ui.theme.gap}) {
			if ui.button("Save") {
				save_game()
			}

			if ui.button("Clear") {
				clear(&game.tilemap.tiles)
			}

			ui.spacer()
			ui.text("Tiles: {}", len(game.tilemap.tiles))
		}
	}
}

tiles_mode_ui :: proc() {
	if ui.row({gap = ui.theme.gap}) {
		tool_button("Pencil", .Pencil)
		tool_button("Rect", .Rectangle)
		tool_button("Erase", .Erase)
		ui.spacer()
		ui.text("Tile [{}, {}]", editor.selected_tile.x, editor.selected_tile.y)
	}

	if ui.column({gap = 1}) {
		for y in 0 ..< TILESET_ROWS {
			if ui.row({gap = 1}) {
				for x in 0 ..< TILESET_COLS {
					palette_cell(x, y)
				}
			}
		}
	}
}

collisions_mode_ui :: proc() {
	collider_count := 0
	for tile in game.tilemap.tiles {
		if tile.collides {
			collider_count += 1
		}
	}

	ui.text("Drag to mark colliders, right-drag to clear.")
	ui.text("Empty spots never collide.")
	ui.text("Colliders: {}", collider_count)
}

spawners_mode_ui :: proc() {
	ui.text("Click to place a spawner, right-click to remove.")
	ui.text("Spawners: {}", len(game.spawners))

	if editor.selected_spawner < 0 || editor.selected_spawner >= len(game.spawners) {
		return
	}

	spawner := &game.spawners[editor.selected_spawner]

	if ui.row({gap = ui.theme.gap}) {
		ui.text("Interval")
		ui.slider("interval", &spawner.interval, 0.1, 10)
		ui.text("{:.2f}", spawner.interval)
	}

	if ui.row({gap = ui.theme.gap}) {
		ui.text("Animation")
		animation_button("None", spawner, .None)
		animation_button("Walk", spawner, .Player_Walk)
		animation_button("Floater", spawner, .Enemy_Floater_Placeholder)
		animation_button("Swarmer", spawner, .Enemy_Swarmer_Placeholder)
	}

	if ui.row({gap = ui.theme.gap}) {
		ui.text("Movement")
		movement_template_none_button("None", spawner)
		movement_template_button("Grounded", spawner, Grounded{speed = 40})
		movement_template_button(
			"Floater",
			spawner,
			Floater{speed = 30, wobble_amplitude = 80, wobble_frequency = 3, pull_strength = 0.35},
		)
		movement_template_button("Swarmer", spawner, Swarmer{speed = 50})
	}

	switch &m in spawner.movement_template {
	case Grounded:
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Speed")
			ui.slider("grounded_speed", &m.speed, 0, 300)
			ui.text("{:.0f}", m.speed)
		}
	case Floater:
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Speed")
			ui.slider("floater_speed", &m.speed, 0, 300)
			ui.text("{:.0f}", m.speed)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Wobble Amplitude")
			ui.slider("floater_wobble_amplitude", &m.wobble_amplitude, 0, 80)
			ui.text("{:.0f}", m.wobble_amplitude)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Wobble Frequency")
			ui.slider("floater_wobble_frequency", &m.wobble_frequency, 0.1, 5)
			ui.text("{:.1f}", m.wobble_frequency)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Pull Toward Player")
			ui.slider("floater_pull_strength", &m.pull_strength, 0, 1)
			ui.text("{:.2f}", m.pull_strength)
		}
	case Swarmer:
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Speed")
			ui.slider("swarmer_speed", &m.speed, 0, 300)
			ui.text("{:.0f}", m.speed)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Surround Radius (from Attack Style)")
			ui.text("{:.0f}", swarmer_surround_radius(spawner.attack_template))
		}
	}

	if ui.row({gap = ui.theme.gap}) {
		ui.text("Attack")
		attack_template_none_button("None", spawner)
		attack_template_button(
			"Melee",
			spawner,
			Melee{attack_damage = 10, attack_range = 10, attack_cooldown = 1},
		)
		attack_template_button(
			"Ranged",
			spawner,
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

	switch &a in spawner.attack_template {
	case Melee:
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Attack Damage")
			ui.slider("melee_attack_damage", &a.attack_damage, 0, 100)
			ui.text("{:.0f}", a.attack_damage)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Attack Range")
			ui.slider("melee_attack_range", &a.attack_range, 0, 50)
			ui.text("{:.0f}", a.attack_range)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Attack Cooldown")
			ui.slider("melee_attack_cooldown", &a.attack_cooldown, 0.1, 5)
			ui.text("{:.2f}", a.attack_cooldown)
		}
	case Ranged:
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Min Range")
			ui.slider("ranged_min_range", &a.min_range, 0, 300)
			ui.text("{:.0f}", a.min_range)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Max Range")
			ui.slider("ranged_max_range", &a.max_range, 0, 300)
			ui.text("{:.0f}", a.max_range)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Attack Damage")
			ui.slider("ranged_attack_damage", &a.attack_damage, 0, 100)
			ui.text("{:.0f}", a.attack_damage)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Projectile Speed")
			ui.slider("ranged_projectile_speed", &a.projectile_speed, 0, 500)
			ui.text("{:.0f}", a.projectile_speed)
		}
		if ui.row({gap = ui.theme.gap}) {
			ui.text("Fire Rate")
			ui.slider("ranged_fire_rate", &a.fire_rate, 0.1, 10)
			ui.text("{:.1f}", a.fire_rate)
		}
	}
}

// like mode_button/tool_button, but bound to a spawner field rather than
// editor state
animation_button :: proc(label: string, spawner: ^Spawner, value: Animation_Name) {
	if selectable_button(label, spawner.animation == value) {
		spawner.animation = value
	}
}

movement_template_button :: proc(label: string, spawner: ^Spawner, value: $T) {
	_, is_active := spawner.movement_template.(T)
	if selectable_button(label, is_active) {
		spawner.movement_template = value
	}
}

movement_template_none_button :: proc(label: string, spawner: ^Spawner) {
	if selectable_button(label, spawner.movement_template == nil) {
		spawner.movement_template = nil
	}
}

attack_template_button :: proc(label: string, spawner: ^Spawner, value: $T) {
	_, is_active := spawner.attack_template.(T)
	if selectable_button(label, is_active) {
		spawner.attack_template = value
	}
}

attack_template_none_button :: proc(label: string, spawner: ^Spawner) {
	if selectable_button(label, spawner.attack_template == nil) {
		spawner.attack_template = nil
	}
}

// like ui.button, but stays highlighted while selected
selectable_button :: proc(label: string, selected: bool) -> (clicked: bool) {
	base := selected ? ui.theme.button_active : ui.theme.button

	if layout.node({key = label, padding = {6, 12, 6, 12}, background_color = base}) {
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
	if selectable_button(label, editor.mode == mode) {
		editor.mode = mode
	}
}

tool_button :: proc(label: string, tool: EditorTool) {
	if selectable_button(label, editor.tool == tool) {
		editor.tool = tool
	}
}

palette_cell :: proc(x, y: int) {
	key := fmt.tprintf("cell_{}_{}", x, y)

	if layout.node(
		{
			key = key,
			size_info = {layout.fixed(PALETTE_CELL_SIZE), layout.fixed(PALETTE_CELL_SIZE)},
			background_color = {0, 0, 0, 255},
		},
	) {
		_, _, clicked := layout.get_node_mouse_state()

		if clicked {
			editor.selected_tile = {i32(x), i32(y)}

			// picking a tile implies drawing, but keep pencil vs rectangle
			if editor.tool == .Erase {
				editor.tool = .Pencil
			}
		}

		append(
			&editor.palette_cells,
			Palette_Cell {
				node_id = layout.get_node(layout.current_open_node()).id,
				coords = {i32(x), i32(y)},
			},
		)
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
