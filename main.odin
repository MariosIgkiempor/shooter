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
SAVE_GAME_PATH :: "data/game_save.json"

game: struct {
	window_width:  f32,
	window_height: f32,
	window_title:  cstring,
	camera:        Camera,
	ui_camera:     Camera,
	player:        Player,
	tilemap:       Tilemap,
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

	log_info("Loaded game from `{}`", SAVE_GAME_PATH)

	initialize_default_game_state :: proc() {
		game = {
			window_width = 1920 / 2,
			window_height = 1080 / 2,
			window_title = "Game",
			player = {rect = {1920 / 4 - 16, 1080 / 4 - 16, 32, 32}, animation = animation_create(.Player_Walk)},
			camera = Camera{target = Vec2{1920 / 4, 1080 / 4}, offset = Vec2{1920 / 4, 1080 / 4}, zoom = 1.0},
			tilemap = {
				tile_size = Vec2{16, 16},
			}
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
		game.window_width = f32(rl.GetScreenWidth())
		game.window_height = f32(rl.GetScreenHeight())
	}

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
	game.player.rect.x += input.x * rl.GetFrameTime() * 100
	game.player.rect.y += input.y * rl.GetFrameTime() * 100
}

Player :: struct {
	using rect: Rect,
	animation:  Animation,
	flip_x:     bool,
}

Tile :: struct {
	atlas_coords: Vec2i,
	world_coords: Vec2i,
}

Tilemap :: struct {
	tile_size: Vec2,
	tiles:     [dynamic]Tile,
}

draw_game :: proc() {
	begin_drawing()
	clear_background(rl.DARKGRAY)

	update_camera_center_smooth_follow(
		&game.camera,
		&game.player,
		rl.GetFrameTime(),
		int(game.window_width),
		int(game.window_height),
	)

	begin_using_camera(game.camera)
	{
		draw_tilemap(&game.tilemap)
		draw_player(&game.player)
	}
	end_using_camera()

	game.ui_camera = Camera {
		zoom = game.window_height / PIXEL_WINDOW_HEIGHT,
	}

	begin_using_camera(game.ui_camera)
	{
		draw_text("This would be the UI", {10, 10}, 10)
	}
	end_using_camera()

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
}
