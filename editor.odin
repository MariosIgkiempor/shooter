package shooter

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

import layout "vendor/ui"
import ui "vendor/ui/ui"

// The ui package handles the editor chrome: a window with tool buttons, the
// tile palette grid, and actions. It only emits rectangle/text render
// commands, so the atlas tiles inside the palette are overlaid afterwards
// using the rects the layout resolved this frame (layout.element_rects).

EditorTool :: enum {
	Paint,
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
	// them after the ui render commands; temp-allocated, rebuilt each frame
	palette_cells: [dynamic]Palette_Cell,
}

initialize_editor :: proc() {
	// the layout engine assumes each wrapped line advances exactly font_size
	rl.SetTextLineSpacing(0)
	ui.set_measure_text_proc(editor_measure_text)

	editor.palette_cells = make(
		[dynamic]Palette_Cell,
		0,
		TILESET_COLS * TILESET_ROWS,
		context.temp_allocator,
	)
}

editor_measure_text :: proc(text: string, font_size: i32) -> f32 {
	c := strings.clone_to_cstring(text, context.temp_allocator)
	return rl.MeasureTextEx(font, c, f32(font_size), 0).x
}

// -- world interaction -------------------------------------------------------

update_editor :: proc() {
	if editor.ui_hovered {
		return
	}

	hovered_coord := hovered_tile_coords()

	if rl.IsMouseButtonDown(.LEFT) {
		switch editor.tool {
		case .Paint:
			tilemap_place_tile(&game.tilemap, hovered_coord, editor.selected_tile)
		case .Erase:
			tilemap_remove_tile(&game.tilemap, hovered_coord)
		}
	} else if rl.IsMouseButtonDown(.RIGHT) {
		tilemap_remove_tile(&game.tilemap, hovered_coord)
	}
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

// outline of the tile under the cursor; call inside the world camera
draw_editor_world_overlay :: proc() {
	if editor.ui_hovered {
		return
	}

	coords := hovered_tile_coords()
	tile_size := game.tilemap.tile_size
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
			tool_button("Paint", .Paint)
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
			editor.tool = .Paint
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
