package shooter

import "base:runtime"
import "core:c"
import "core:encoding/json"
import "core:math"
import "core:math/linalg"
import "core:os"
import rl "vendor:raylib"

Vec2 :: rl.Vector2
Vec2i :: [2]i32
Rect :: rl.Rectangle

PIXEL_WINDOW_HEIGHT :: 180
GAMEPLAY_ZOOM :: 1.2
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
	spawners:            [dynamic]Spawner,
	enemies:             [dynamic]Enemy `json:"-"`,
	bullets:             [dynamic]Bullet `json:"-"`,
	enemy_bullets:       [dynamic]Enemy_Bullet `json:"-"`,
	poison_clouds:       [dynamic]Poison_Cloud `json:"-"`,
	xp_orbs:             [dynamic]Xp_Orb `json:"-"`,
	pickups:             [dynamic]Pickup `json:"-"`,
	particles:           [dynamic]Particle `json:"-"`,
	screen_shake_trauma: f32 `json:"-"`,

	// true while the level-up modal is open; simulation is paused and only
	// draw_level_up_ui's buttons are live. never saved - a save taken
	// mid-modal simply reopens closed, which is fine since no run state is
	// lost (xp/level are already committed by collect_xp).
	leveling_up:   bool `json:"-"`,

	// true while the game-over modal is open; simulation is paused. never
	// saved, same rationale as leveling_up.
	game_over:     bool `json:"-"`,

	// F8-toggled dev view: gates enemy pathfinding-debug lines (previously
	// always drawn), and additionally shows actor colliders and the
	// currently-equipped weapon's hit area. Never saved, same rationale as
	// leveling_up/game_over.
	debug_overlay: bool `json:"-"`,
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

	game.player.weapon.variant = weapon_variant_from_save(game.player.weapon_variant_save)

	for &spawner in game.spawners {
		spawner.template = enemy_behaviour_from_save(spawner.template_save)
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
				weapon = weapon_create(.Sword),
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

	game.player.weapon_variant_save = weapon_variant_to_save(game.player.weapon.variant)

	for &spawner in game.spawners {
		spawner.template_save = enemy_behaviour_to_save(spawner.template)
	}

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
	reset_enemy_bullets()
	reset_poison_clouds()
	reset_xp_orbs()
	reset_pickups()
	reset_particles()
	reset_screen_shake()
	// runtime combat state, deliberately not persisted (see Player.health) -
	// reset here so both fresh games and loads start at full health
	game.player.health = PLAYER_MAX_HEALTH

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

	if is_key_pressed(.F8) {
		game.debug_overlay = !game.debug_overlay
	}

	switch game.program_mode {
	case .Playing:
		update_game_state()
	case .Editing:
		update_editor()
	}

	update_game_state :: proc() {
		if game.leveling_up || game.game_over {
			return
		}

		input: Vec2

		if is_key_down(.A) {
			input.x -= 1
		}
		if is_key_down(.D) {
			input.x += 1
		}
		if is_key_down(.W) {
			input.y -= 1
		}
		if is_key_down(.S) {
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

		// dev/debug weapon switching: left/right cycles within the current
		// Class, up/down cycles Class (see weapon.odin's cycle_weapon_kind/
		// cycle_class) - arrow keys are free for this since WASD alone
		// already covers movement
		if is_key_pressed(.LEFT) {
			game.player.weapon = weapon_create(cycle_weapon_kind(game.player.weapon.kind, -1))
		}
		if is_key_pressed(.RIGHT) {
			game.player.weapon = weapon_create(cycle_weapon_kind(game.player.weapon.kind, 1))
		}
		if is_key_pressed(.UP) {
			game.player.weapon = weapon_create(cycle_class(game.player.weapon.kind, 1))
		}
		if is_key_pressed(.DOWN) {
			game.player.weapon = weapon_create(cycle_class(game.player.weapon.kind, -1))
		}

		mouse_world := rl.GetScreenToWorld2D(game.mouse.position, game.camera)
		player_pos := Vec2{game.player.x, game.player.y}
		game.player.aim_dir = linalg.normalize0(mouse_world - player_pos)

		fire_pressed := game.player.weapon.fire_mode == .Automatic ? is_mouse_button_down(.LEFT) : is_mouse_button_pressed(.LEFT)

		if fire_pressed {
			try_use_weapon(&game.player.weapon, player_pos, game.player.aim_dir, mouse_world)
		}

		update_bullets(rl.GetFrameTime())
		update_enemy_bullets(rl.GetFrameTime())
		update_poison_clouds(rl.GetFrameTime())
		update_xp_orbs(rl.GetFrameTime())
		update_pickups(rl.GetFrameTime())
		update_particles(rl.GetFrameTime())

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
	// Weapon.variant is a union and is tagged json:"-" (see weapon.odin) -
	// this is the plain, persisted view of it, converted explicitly at the
	// save_game/load_game boundary so json.unmarshal's union-decode-order
	// guessing never runs on player-owned weapon state.
	weapon_variant_save: Weapon_Variant_Save,
	aim_dir:    Vec2, // world-space direction toward the mouse, updated every frame
	xp:         int, // progress toward next level; persisted run progression
	level:      int, // persisted run progression, starts at 1
	// runtime combat state, not persisted (see initialize_program) - a saved
	// game predating this field would otherwise unmarshal it as 0 and trigger
	// an instant game-over on load
	health:     f32 `json:"-"`,
}

PLAYER_MAX_HEALTH :: 100

// applies enemy damage to the player, opening the game-over modal at 0 hp
damage_player :: proc(amount: f32) {
	spawn_damage_burst(Vec2{game.player.x, game.player.y})
	trigger_screen_shake(amount / PLAYER_MAX_HEALTH)

	game.player.health -= amount
	if game.player.health <= 0 {
		game.player.health = 0
		game.game_over = true
	}
}

// restores player hp from a pickup, clamped so healing can't exceed max health
heal_player :: proc(amount: f32) {
	game.player.health = min(game.player.health + amount, PLAYER_MAX_HEALTH)
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
		game.camera.offset += update_screen_shake(rl.GetFrameTime())
	}

	begin_using_camera(game.camera)
	{
		draw_tilemap(&game.tilemap)
		for enemy in game.enemies {
			draw_actor(enemy.rect, enemy.animation, enemy.flip_x)
			if game.debug_overlay {
				draw_path(Vec2{enemy.x, enemy.y}, enemy.path)
			}
			draw_health_bar(enemy)
		}
		draw_actor(game.player.rect, game.player.animation, game.player.flip_x)
		draw_weapon(game.player)
		draw_flamethrower_cone(game.player)
		if game.debug_overlay {
			draw_debug_colliders()
			draw_debug_weapon_area(game.player)
			draw_debug_attack_ranges()
		}
		draw_spawners(game.spawners[:])
		draw_bullets(game.bullets[:])
		draw_enemy_bullets(game.enemy_bullets[:])
		draw_poison_clouds(game.poison_clouds[:])
		draw_xp_orbs(game.xp_orbs[:])
		draw_pickups(game.pickups[:])
		draw_particles(game.particles[:])

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
			draw_hud(game.player)
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

	if game.game_over {
		draw_game_over_ui()
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

	draw_path :: proc(from: Vec2, path: [dynamic]Vec2i) {
		point := from
		for cell in path {
			next := cell_center_to_world(cell)
			rl.DrawLineV(point, next, rl.YELLOW)
			point = next
		}
	}

	draw_spawners :: proc(spawners: []Spawner) {
		for spawner in spawners {
			rl.DrawCircleLinesV(spawner.position, 8, rl.RED)
			rl.DrawCircleV(spawner.position, 2, rl.RED)
		}
	}

	draw_bullets :: proc(bullets: []Bullet) {
		tex := atlas_textures[Texture_Name.Bullet]
		origin := Vec2{tex.rect.width / 2, tex.rect.height / 2}

		for bullet in bullets {
			// sprite's nose faces up (-y) by default, hence the +90 to align
			// it with the velocity direction (0 degrees = +x, clockwise)
			angle := math.to_degrees(math.atan2(bullet.velocity.y, bullet.velocity.x)) + 90
			dest := Rect{bullet.position.x, bullet.position.y, tex.rect.width, tex.rect.height}
			draw_atlas_tile(tex.rect, dest, origin, angle, rl.YELLOW)
		}
	}

	draw_enemy_bullets :: proc(bullets: []Enemy_Bullet) {
		tex := atlas_textures[Texture_Name.Bullet]
		origin := Vec2{tex.rect.width / 2, tex.rect.height / 2}

		for bullet in bullets {
			angle := math.to_degrees(math.atan2(bullet.velocity.y, bullet.velocity.x)) + 90
			dest := Rect{bullet.position.x, bullet.position.y, tex.rect.width, tex.rect.height}
			draw_atlas_tile(tex.rect, dest, origin, angle, rl.RED)
		}
	}

	draw_xp_orbs :: proc(orbs: []Xp_Orb) {
		for orb in orbs {
			rl.DrawCircleV(orb.position, XP_ORB_RADIUS, rl.SKYBLUE)
		}
	}

	// a short barrel pivoting at roughly chest height, rotated to face the
	// player's current aim direction - stands in for a weapon sprite until one exists
	draw_weapon :: proc(player: Player) {
		tex := atlas_textures[weapon_texture_names[player.weapon.kind]]

		doc := animation_atlas_texture(player.animation).document_size
		pivot := Vec2{player.x, player.y - doc.y / 2}
		angle := math.to_degrees(math.atan2(player.aim_dir.y, player.aim_dir.x))

		// melee swish (ticket 07): sweeps -arc_degrees/2 -> +arc_degrees/2
		// across swing_time, purely cosmetic - the hit already resolved
		// instantly in try_swing_melee before this ever plays
		switch v in player.weapon.variant {
		case Melee_Weapon:
			if v.swing_timer > 0 {
				progress := 1 - v.swing_timer / v.swing_time // 0 -> 1 across the swing
				angle += (progress - 0.5) * v.arc_degrees
			}
		case Gun, Magic:
		}

		// sprite's muzzle faces +x (right) by default; mirror vertically when
		// the drawn angle (post swing-offset, not the raw aim_dir) points
		// left, so the weapon stays right-side up instead of upside-down
		// mid-swing
		atlas_rect := tex.rect
		offset_top := tex.offset_top
		if math.cos(math.to_radians(angle)) < 0 {
			atlas_rect.height = -atlas_rect.height
			offset_top = tex.offset_bottom
		}

		// scale the weapon's full document (not just its trimmed rect) up to
		// match the player's size, preserving native aspect ratio - scaling
		// by the trimmed rect instead would size each weapon inconsistently
		// depending on how tightly the atlas happened to trim it
		scale := doc.y / tex.document_size.y
		width := tex.rect.width * scale
		height := tex.rect.height * scale

		dest := Rect{pivot.x, pivot.y, width, height}

		// origin (the grip, rotation pivot) sits at the document's left edge,
		// vertically centered - expressed relative to the trimmed rect's
		// top-left since the atlas is tightly trimmed and the grip may fall
		// in space that got cropped away (see draw_actor's similar use of
		// offset_left/top to correct for the same trimming)
		origin := Vec2{-tex.offset_left * scale, (tex.document_size.y / 2 - offset_top) * scale}

		draw_atlas_tile(atlas_rect, dest, origin, angle)
	}

	// translucent cone, cosmetic only, while the flamethrower is actively
	// channeling - the tick damage itself already resolved in
	// try_cast_magic (cast_flamethrower_tick); this just shows its reach
	draw_flamethrower_cone :: proc(player: Player) {
		magic, is_magic := player.weapon.variant.(Magic)
		if !is_magic || magic.spell_kind != .Flamethrower {
			return
		}
		if !is_mouse_button_down(.LEFT) {
			return
		}

		center := Vec2{player.x, player.y}
		angle := math.to_degrees(math.atan2(player.aim_dir.y, player.aim_dir.x))
		start := angle - magic.arc_degrees / 2
		end := angle + magic.arc_degrees / 2

		rl.DrawCircleSector(center, magic.range, start, end, 16, rl.Color{230, 100, 30, 90})
	}

	// F8 dev view: outlines the player's and every enemy's actual collision
	// rect (actor_collision_rect - the same box move_actor/melee/bullets hit
	// test against), not just their sprite bounds
	draw_debug_colliders :: proc() {
		rl.DrawRectangleLinesEx(actor_collision_rect(game.player.rect, game.player.animation), 1, rl.LIME)
		for enemy in game.enemies {
			rl.DrawRectangleLinesEx(actor_collision_rect(enemy.rect, enemy.animation), 1, rl.RED)
		}
	}

	// F8 dev view: each enemy's attack-trigger radius - a single circle at
	// attack_range for Melee (contact distance to land a hit), or two
	// circles (min_range/max_range) for Ranged marking the band it holds
	// inside to fire rather than chase or retreat. Inert enemies have no
	// attack, so nothing is drawn for them.
	draw_debug_attack_ranges :: proc() {
		for enemy in game.enemies {
			center := Vec2{enemy.x, enemy.y}
			switch b in enemy.behaviour {
			case Melee:
				rl.DrawCircleLinesV(center, b.attack_range, rl.ORANGE)
			case Ranged:
				rl.DrawCircleLinesV(center, b.min_range, rl.ORANGE)
				rl.DrawCircleLinesV(center, b.max_range, rl.ORANGE)
			case:
			}
		}
	}

	// F8 dev view: the equipped weapon's hit area, shown continuously
	// (unlike draw_flamethrower_cone's held-only fill) so range/arc tuning
	// doesn't require attacking to see it. Gun has no player-relative area to
	// show; fireball's AoE lands wherever it hits, not around the player, so
	// it's skipped too.
	draw_debug_weapon_area :: proc(player: Player) {
		center := Vec2{player.x, player.y}
		angle := math.to_degrees(math.atan2(player.aim_dir.y, player.aim_dir.x))

		draw_cone :: proc(center: Vec2, range, arc_degrees, angle: f32) {
			start := angle - arc_degrees / 2
			end := angle + arc_degrees / 2
			rl.DrawCircleSectorLines(center, range, start, end, 16, rl.SKYBLUE)
		}

		switch v in player.weapon.variant {
		case Melee_Weapon:
			draw_cone(center, v.range, v.arc_degrees, angle)
		case Magic:
			switch v.spell_kind {
			case .Flamethrower:
				draw_cone(center, v.range, v.arc_degrees, angle)
			case .Poison_Cloud:
				rl.DrawCircleLinesV(center, v.cast_range, rl.SKYBLUE)
			case .Fireball:
			}
		case Gun:
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
