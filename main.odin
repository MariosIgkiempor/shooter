package shooter

import "base:runtime"
import "core:c"
import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

import layout "vendor/ui"
import ui "vendor/ui/ui"

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

	// spawners are level data and persist; enemies/bullets/xp_orbs are
	// transient runtime state spawned/created during play, so they're
	// never saved
	spawners:      [dynamic]Spawner,
	enemies:       [dynamic]Enemy `json:"-"`,
	bullets:       [dynamic]Bullet `json:"-"`,
	xp_orbs:       [dynamic]Xp_Orb `json:"-"`,

	// true while the level-up modal is open; simulation is paused and only
	// draw_level_up_ui's buttons are live. never saved - a save taken
	// mid-modal simply reopens closed, which is fine since no run state is
	// lost (xp/level are already committed by collect_xp).
	leveling_up:   bool `json:"-"`,
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

	json_error := json.unmarshal(file_contents, &game)
	if json_error != nil {
		log_error("Couldn't unmarshal save file at `{}`: {}", SAVE_GAME_PATH, json_error)
		log_info("Initialising new game state instead.")
		initialize_default_game_state()
		return
	}

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
				weapon = weapon_create(.SMG),
				level = 1,
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
	reset_enemies()
	reset_bullets()
	reset_xp_orbs()

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
		if game.leveling_up {
			return
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
		move_actor(&game.player.rect, game.player.animation, &game.tilemap, input * rl.GetFrameTime() * 100)

		update_weapon(&game.player.weapon, rl.GetFrameTime())

		if is_key_pressed(.R) {
			start_reload(&game.player.weapon)
		}

		mouse_world := rl.GetScreenToWorld2D(game.mouse.position, game.camera)
		player_pos := Vec2{game.player.x, game.player.y}
		game.player.aim_dir = linalg.normalize0(mouse_world - player_pos)

		fire_pressed := game.player.weapon.fire_mode == .Automatic ? is_mouse_button_down(.LEFT) : is_mouse_button_pressed(.LEFT)

		if fire_pressed {
			try_fire_weapon(&game.player.weapon, player_pos, game.player.aim_dir)
		}

		update_bullets(rl.GetFrameTime())
		update_xp_orbs(rl.GetFrameTime())

		update_spawners(rl.GetFrameTime())
		update_enemies(rl.GetFrameTime())
	}
}

// sprites are drawn with a bottom-center origin, so rect.x/y is the anchor at
// the actor's feet; the collision box is the drawn sprite's bounds around that
// anchor, not a top-left rect hanging below it
actor_collision_rect :: proc(rect: Rect, animation: Animation) -> Rect {
	doc := animation_atlas_texture(animation).document_size

	return {rect.x - doc.x / 2, rect.y - doc.y, doc.x, doc.y}
}

// moves an actor (player or enemy), resolving against colliding tiles one axis
// at a time so it slides along walls instead of stopping dead on diagonal input
move_actor :: proc(rect: ^Rect, animation: Animation, tilemap: ^Tilemap, delta: Vec2) {
	box := actor_collision_rect(rect^, animation)

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
	rect.x = box.x + box.width / 2
	rect.y = box.y + box.height
}

Player :: struct {
	using rect: Rect,
	animation:  Animation,
	flip_x:     bool,
	weapon:     Weapon,
	aim_dir:    Vec2, // world-space direction toward the mouse, updated every frame
	xp:         int, // progress toward next level; persisted run progression
	level:      int, // persisted run progression, starts at 1
}

XP_LEVEL_BASE :: 10 // xp required for level 1 -> 2
XP_LEVEL_GROWTH :: 1.25 // multiplicative growth per level

// xp required to advance from `level` to `level + 1`
xp_required_for_level :: proc(level: int) -> int {
	return int(f32(XP_LEVEL_BASE) * math.pow(f32(XP_LEVEL_GROWTH), f32(level - 1)))
}

// adds xp and, if it crosses the current threshold, levels up and opens the
// choice modal. XP_ORB_VALUE is always well under XP_LEVEL_BASE, the curve's
// smallest threshold, so at most one level lands per call - if that
// invariant ever changes (e.g. a bigger orb value), turn the `if` below into
// a `for` loop to handle multiple crossings.
collect_xp :: proc(amount: int) {
	game.player.xp += amount

	required := xp_required_for_level(game.player.level)
	if game.player.xp >= required {
		game.player.xp -= required
		game.player.level += 1
		game.leveling_up = true
	}
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
		for enemy in game.enemies {
			draw_actor(enemy.rect, enemy.animation, enemy.flip_x)
			draw_path(enemy.path)
			draw_health_bar(enemy)
		}
		draw_actor(game.player.rect, game.player.animation, game.player.flip_x)
		draw_weapon(game.player)
		draw_spawners(game.spawners[:])
		draw_bullets(game.bullets[:])
		draw_xp_orbs(game.xp_orbs[:])

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
			draw_weapon_hud(game.player.weapon)
			draw_text(
				fmt.tprintf(
					"Lv {}  XP {}/{}",
					game.player.level,
					game.player.xp,
					xp_required_for_level(game.player.level),
				),
				{10, 55},
				10,
				0,
				rl.WHITE,
			)
		case .Editing:
			draw_text("Editing", 10, 10, 0, rl.ORANGE)
		}
	}
	end_using_camera()

	if game.program_mode == .Editing {
		draw_editor()
	}

	if game.leveling_up {
		draw_level_up_ui()
	}

	end_drawing()

	draw_actor :: proc(rect: Rect, animation: Animation, flip_x: bool) {
		anim_texture := animation_atlas_texture(animation)
		atlas_rect := anim_texture.rect
		offset := Vec2{anim_texture.offset_left, anim_texture.offset_top}

		if flip_x {
			atlas_rect.width = -atlas_rect.width
			offset.x = anim_texture.offset_right
		}

		dest := Rect {
			rect.x + offset.x,
			rect.y + offset.y,
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

	draw_path :: proc(path: [dynamic]Vec2i) {
		for cell in path {
			world := cell_center_to_world(cell)
			rl.DrawCircleV(world, 4, rl.YELLOW)
		}
	}

	draw_spawners :: proc(spawners: []Spawner) {
		for spawner in spawners {
			rl.DrawCircleLinesV(spawner.position, 8, rl.RED)
			rl.DrawCircleV(spawner.position, 2, rl.RED)
		}
	}

	draw_bullets :: proc(bullets: []Bullet) {
		for bullet in bullets {
			rl.DrawCircleV(bullet.position, BULLET_RADIUS, rl.YELLOW)
		}
	}

	draw_xp_orbs :: proc(orbs: []Xp_Orb) {
		for orb in orbs {
			rl.DrawCircleV(orb.position, XP_ORB_RADIUS, rl.SKYBLUE)
		}
	}

	draw_level_up_ui :: proc() {
		ui.set_pointer_state(game.mouse, is_mouse_button_down(.LEFT))
		ui.begin_frame(game.window_width, game.window_height)

		if ui.row({size = {layout.grow(0, 0), layout.grow(0, 0)}, align = {.Center, .Center}}) {
			if ui.begin("Level Up!") {
				ui.text("Level {} - choose an upgrade", game.player.level)

				if ui.button("Upgrade Weapon") {
					upgrade_weapon(&game.player.weapon)
					game.leveling_up = false
				}
				if ui.button("Refill Ammo") {
					refill_weapon_reserve(&game.player.weapon)
					game.leveling_up = false
				}
				if ui.button("Skip") {
					game.leveling_up = false
				}
			}
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

	// a short barrel pivoting at roughly chest height, rotated to face the
	// player's current aim direction - stands in for a weapon sprite until one exists
	draw_weapon :: proc(player: Player) {
		WEAPON_LENGTH: f32 = 10
		WEAPON_THICKNESS: f32 = 3

		doc := animation_atlas_texture(player.animation).document_size
		pivot := Vec2{player.x, player.y - doc.y / 2}
		angle := math.to_degrees(math.atan2(player.aim_dir.y, player.aim_dir.x))

		draw_rectangle(
			{pivot.x, pivot.y, WEAPON_LENGTH, WEAPON_THICKNESS},
			rl.DARKGRAY,
			{0, WEAPON_THICKNESS / 2},
			angle,
		)
	}

	draw_health_bar :: proc(enemy: Enemy) {
		WIDTH: f32 = 16
		HEIGHT: f32 = 2
		GAP_ABOVE_SPRITE: f32 = 5

		doc := animation_atlas_texture(enemy.animation).document_size
		pos := Vec2{enemy.x - WIDTH / 2, enemy.y - doc.y - GAP_ABOVE_SPRITE}
		fill := WIDTH * clamp(enemy.health / ENEMY_MAX_HEALTH, 0, 1)

		draw_rectangle({pos.x, pos.y, WIDTH, HEIGHT}, rl.BLACK)
		draw_rectangle({pos.x, pos.y, fill, HEIGHT}, rl.RED)
	}

	draw_weapon_hud :: proc(weapon: Weapon) {
		ammo_text := fmt.tprintf(
			"Ammo: {}/{}  Reserve: {}",
			weapon.ammo_in_clip,
			weapon.clip_size,
			weapon.reserve_ammo,
		)
		draw_text(ammo_text, {10, 25}, 10, 0, rl.WHITE)

		if weapon.reload_timer > 0 {
			draw_text("Reloading...", {10, 40}, 10, 0, rl.ORANGE)
		} else if weapon.ammo_in_clip <= 0 && weapon.reserve_ammo <= 0 {
			draw_text("Out of ammo!", {10, 40}, 10, 0, rl.RED)
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
