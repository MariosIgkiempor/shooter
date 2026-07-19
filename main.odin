package shooter

import "core:c"
import "core:math/linalg"
import rl "vendor:raylib"

Vec2 :: rl.Vector2
Rect :: rl.Rectangle

PIXEL_WINDOW_HEIGHT :: 180

game: struct {
	window_width:  f32,
	window_height: f32,
	window_title:  cstring,
	player:        Player,
} = {
	window_width = 1920 / 2,
	window_height = 1080 / 2,
	window_title = "Game",
	player = {rect = {1920 / 4 - 16, 1080 / 4 - 16, 32, 32}},
}

main :: proc() {
	init_program()

	for !program_should_exit() {
		update_game()
		draw_game()
		free_all(context.temp_allocator)
	}

	deinit_program()
}

init_program :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(c.int(game.window_width), c.int(game.window_height), game.window_title)

	init_renderer()

	game.player.animation = animation_create(.Player_Walk)
}

deinit_program :: proc() {
	deinit_renderer()
	rl.CloseWindow()
}

update_game :: proc() {
	{
		// update platform state
		game.window_width = f32(rl.GetScreenWidth())
		game.window_height = f32(rl.GetScreenHeight())
	}

	input: Vec2

	if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) {
		input.x -= 1
	}
	if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) {
		input.x += 1
	}

	if input.x != 0 {
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

draw_game :: proc() {
	begin_drawing()
	clear_background(rl.DARKGRAY)

	game_camera := Camera {
		zoom   = game.window_height / PIXEL_WINDOW_HEIGHT,
		target = {game.player.rect.x, game.player.rect.y},
		offset = {game.window_width / 2, game.window_height / 2},
	}

	begin_using_camera(game_camera)
	{
		draw_player(&game.player)
	}
	end_using_camera()

	ui_camera := Camera {
		zoom = game.window_height / PIXEL_WINDOW_HEIGHT,
	}

	begin_using_camera(ui_camera)
	{
		draw_text("This would be the UI", {10, 10}, 10)
	}
	end_using_camera()

	end_drawing()
}

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

program_should_exit :: proc() -> bool {
	return rl.WindowShouldClose()
}
