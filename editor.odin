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

EditorTool :: enum {
	Pencil,
	Rectangle,
	Erase,
}

TILESET_COLS :: len(tileset_ping)
TILESET_ROWS :: len(tileset_ping[0])
PALETTE_CELL_SIZE :: 20

Palette_Cell :: struct {
	node_id: u32,
	coords:  Vec2i,
}

editor: struct {
	tool:          EditorTool,
	selected_tile: Vec2i,
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

	return {
		i32(math.floor(world.x / game.tilemap.tile_size.x)),
		i32(math.floor(world.y / game.tilemap.tile_size.y)),
	}
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

// outline of the tile under the cursor, or of the in-flight rectangle drag;
// call inside the world camera
draw_editor_world_overlay :: proc() {
	tile_size := game.tilemap.tile_size

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

	coords := hovered_tile_coords()
	rect := Rect {
		f32(coords.x) * tile_size.x,
		f32(coords.y) * tile_size.y,
		tile_size.x,
		tile_size.y,
	}

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
		draw_atlas_tile(tileset_ping[cell.coords.x][cell.coords.y], dest, 0)

		if cell.coords == editor.selected_tile {
			rl.DrawRectangleLinesEx(dest, 2, rl.YELLOW)
		}
	}
}

editor_window :: proc() {
	if ui.begin("Tilemap Editor") {
		record_ui_hover()

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

// like ui.button, but stays highlighted while its tool is selected
tool_button :: proc(label: string, tool: EditorTool) {
	selected := editor.tool == tool
	base := selected ? ui.theme.button_active : ui.theme.button

	if layout.node({key = label, padding = {6, 12, 6, 12}, background_color = base}) {
		hot, active, clicked := layout.get_node_mouse_state()

		if clicked {
			editor.tool = tool
		}

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
