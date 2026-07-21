package shooter

import "base:runtime"
import "core:c"
import "core:encoding/json"
import "core:math/linalg"
import "core:os"
import rl "vendor:raylib"

Vec2 :: rl.Vector2
Vec2i :: [2]i32
Rect :: rl.Rectangle

PIXEL_WINDOW_HEIGHT :: 180
GAMEPLAY_ZOOM :: 1.0
SAVE_GAME_PATH :: "data/game_save.json"

ProgramMode :: enum {
	Playing,
	Editing,
}

game: struct {
	program_mode:  ProgramMode,
	mouse:         MouseState,
	window_width:  f32,
	window_height: f32,
	window_title:  cstring,
	camera:        Camera,
	ui_camera:     Camera,
	player:        Player,
	tilemap:       Tilemap,
}

MouseState :: struct {
	using position: Vec2,
}

main :: proc() {
	context = initialize_program()

	for !program_should_exit() {
		update_game()
		draw_game()
		free_all(context.temp_allocator)
	}

	deinitialize_program()

	save_game()
}

load_game :: proc() {
	log_info("Loading game from save file `{}`", SAVE_GAME_PATH)

	file_contents, file_error := os.read_entire_file(SAVE_GAME_PATH, context.temp_allocator)
	if file_error != nil {
		log_warning("Couldn't read save file at `{}`: {}", SAVE_GAME_PATH, file_error)
		log_info("Initialising new game state instead.")
		initialize_default_game_state()
		return
	}

	json_error := json.unmarshal(file_contents, &game, allocator = context.temp_allocator)
	if json_error != nil {
		log_error("Couldn't unmarshal save file at `{}`: {}", SAVE_GAME_PATH, json_error)
		log_info("Initialising new game state instead.")
		initialize_default_game_state()
		return
	}

	// the unmarshal above allocates into the temp allocator, which is freed
	// every frame — re-home the tiles array so the editor can mutate it
	tiles := make([dynamic]Tile, len(game.tilemap.tiles))
	copy(tiles[:], game.tilemap.tiles[:])
	game.tilemap.tiles = tiles

	log_info("Loaded game from `{}`", SAVE_GAME_PATH)

	initialize_default_game_state :: proc() {
		game = {
			program_mode = .Playing,
			window_width = 1920 / 2,
			window_height = 1080 / 2,
			window_title = "Game",
			player = {
				rect = {1920 / 4 - 16, 1080 / 4 - 16, 32, 32},
				animation = animation_create(.Player_Walk),
			},
			camera = Camera {
				target = Vec2{1920 / 4, 1080 / 4},
				offset = Vec2{1920 / 4, 1080 / 4},
				zoom = 1.0,
			},
			tilemap = {tile_size = Vec2{16, 16}},
		}
	}
}

save_game :: proc() {
	log_info("Saving game to save file `{}`", SAVE_GAME_PATH)

	json_data, json_error := json.marshal(game, allocator = context.temp_allocator)
	if json_error != nil {
		log_error("Couldn't marshal struct!")
		return
	}

	file_error := os.write_entire_file(SAVE_GAME_PATH, json_data)
	if file_error != nil {
		log_error("Couldn't write save file at `{}`", SAVE_GAME_PATH)
		return
	}

	log_info("Saved game to `{}`", SAVE_GAME_PATH)
}

initialize_program :: proc() -> runtime.Context {
	ctx := context
	initialize_logger(&ctx)
	context = ctx // so the rest of initialize_program can log too

	load_game()

	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(c.int(game.window_width), c.int(game.window_height), game.window_title)

	initialize_renderer()
	initialize_editor()

	return ctx
}

deinitialize_program :: proc() {
	deinitialize_renderer()
	deinitialize_logger()
	rl.CloseWindow()
}

update_game :: proc() {
	{
		// update platform state
		game.window_width = get_screen_width()
		game.window_height = get_screen_height()
		game.mouse.position = get_mouse_position()
	}

	// mode toggle lives outside the mode switch so it works in both modes
	if is_key_pressed(.F1) {
		if game.program_mode == .Playing {
			game.program_mode = .Editing
		} else {
			game.program_mode = .Playing
		}
	}

	switch game.program_mode {
	case .Playing:
		update_game_state()
	case .Editing:
		update_editor()
	}

	update_game_state :: proc() {
		input: Vec2

		if is_key_down(.LEFT) || is_key_down(.A) {
			input.x -= 1
		}
		if is_key_down(.RIGHT) || is_key_down(.D) {
			input.x += 1
		}
		if is_key_down(.UP) || is_key_down(.W) {
			input.y -= 1
		}
		if is_key_down(.DOWN) || is_key_down(.S) {
			input.y += 1
		}

		if input.x != 0 || input.y != 0 {
			// Only update animation if there is input.
			animation_update(&game.player.animation, rl.GetFrameTime())
			game.player.flip_x = input.x < 0
		}

		input = linalg.normalize0(input)
		move_player(&game.player, &game.tilemap, input * rl.GetFrameTime() * 100)
	}
}

// the sprite is drawn with a bottom-center origin, so player.rect.x/y is the
// anchor at the sprite's feet; the collision box is the drawn sprite's bounds
// around that anchor, not a top-left rect hanging below it
player_collision_rect :: proc(player: ^Player) -> Rect {
	doc := animation_atlas_texture(player.animation).document_size

	return {player.rect.x - doc.x / 2, player.rect.y - doc.y, doc.x, doc.y}
}

// moves the player, resolving against colliding tiles one axis at a time so
// the player slides along walls instead of stopping dead on diagonal input
move_player :: proc(player: ^Player, tilemap: ^Tilemap, delta: Vec2) {
	box := player_collision_rect(player)

	box.x += delta.x

	for tile in tilemap.tiles {
		if !tile.collides {
			continue
		}

		tile_rect := tile_world_rect(tile.world_coords)
		if !rl.CheckCollisionRecs(box, tile_rect) {
			continue
		}

		if delta.x > 0 {
			box.x = tile_rect.x - box.width
		} else if delta.x < 0 {
			box.x = tile_rect.x + tile_rect.width
		}
	}

	box.y += delta.y

	for tile in tilemap.tiles {
		if !tile.collides {
			continue
		}

		tile_rect := tile_world_rect(tile.world_coords)
		if !rl.CheckCollisionRecs(box, tile_rect) {
			continue
		}

		if delta.y > 0 {
			box.y = tile_rect.y - box.height
		} else if delta.y < 0 {
			box.y = tile_rect.y + tile_rect.height
		}
	}

	// resolved box back to the bottom-center anchor
	player.rect.x = box.x + box.width / 2
	player.rect.y = box.y + box.height
}

Player :: struct {
	using rect: Rect,
	animation:  Animation,
	flip_x:     bool,
}

Tile :: struct {
	atlas_coords: Vec2i,
	world_coords: Vec2i,
	collides:     bool,
}

Tilemap :: struct {
	tile_size: Vec2,
	tiles:     [dynamic]Tile,
}

draw_game :: proc() {
	begin_drawing()
	clear_background(rl.DARKGRAY)

	// in editor mode the camera is driven by update_editor_camera instead
	if game.program_mode == .Playing {
		update_camera_center_smooth_follow(
			&game.camera,
			&game.player,
			rl.GetFrameTime(),
			int(game.window_width),
			int(game.window_height),
		)
	}

	begin_using_camera(game.camera)
	{
		draw_tilemap(&game.tilemap)
		draw_player(&game.player)

		if game.program_mode == .Editing {
			draw_editor_world_overlay()
		}
	}
	end_using_camera()

	game.ui_camera = Camera {
		zoom = game.window_height / PIXEL_WINDOW_HEIGHT,
	}

	begin_using_camera(game.ui_camera)
	{
		switch game.program_mode {
		case .Playing:
			draw_text("Playing", 10, 10, 0, rl.GREEN)
		case .Editing:
			draw_text("Editing", 10, 10, 0, rl.ORANGE)
		}
	}
	end_using_camera()

	if game.program_mode == .Editing {
		draw_editor()
	}

	end_drawing()

	draw_player :: proc(player: ^Player) {
		anim_texture := animation_atlas_texture(player.animation)
		atlas_rect := anim_texture.rect
		offset := Vec2{anim_texture.offset_left, anim_texture.offset_top}

		if player.flip_x {
			atlas_rect.width = -atlas_rect.width
			offset.x = anim_texture.offset_right
		}

		dest := Rect {
			player.rect.x + offset.x,
			player.rect.y + offset.y,
			anim_texture.rect.width,
			anim_texture.rect.height,
		}

		origin := Vec2{anim_texture.document_size.x / 2, anim_texture.document_size.y}

		draw_atlas_tile(atlas_rect, dest, origin)
	}

	draw_tilemap :: proc(tilemap: ^Tilemap) {
		for tile in tilemap.tiles {
			atlas_rect := tileset_ping[tile.atlas_coords.x][tile.atlas_coords.y]
			world_rect := Rect {
				f32(tile.world_coords.x) * tilemap.tile_size.x,
				f32(tile.world_coords.y) * tilemap.tile_size.y,
				tilemap.tile_size.x,
				tilemap.tile_size.y,
			}
			draw_atlas_tile(atlas_rect, world_rect, 0)
		}
	}
}

program_should_exit :: proc() -> bool {
	return rl.WindowShouldClose()
}

update_camera_center_smooth_follow :: proc(
	camera: ^Camera,
	player: ^Player,
	delta: f32,
	width: int,
	height: int,
) {
	minSpeed: f32 = 30.0
	minEffectLength: f32 = 10.0
	fractionSpeed: f32 = 0.8

	camera.offset = Vec2{f32(width) / 2.0, f32(height) / 2.0}
	diff := Vec2{player.rect.x, player.rect.y} - camera.target
	length := rl.Vector2Length(diff)

	if (length > minEffectLength) {
		speed := max(fractionSpeed * length * (0.1 * length), minSpeed)
		camera.target = camera.target + diff * (speed * delta / length)
	}

	// gameplay zoom is independent of the editor's: ease back to it, so
	// leaving the editor animates the zoom as well as the position
	camera.zoom = exp_approach(camera.zoom, GAMEPLAY_ZOOM, 8, delta)
}
