package shooter

import "base:runtime"
import "core:c"
import "core:encoding/json"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:reflect"
import rl "vendor:raylib"

Vec2 :: rl.Vector2
Vec2i :: [2]i32
Rect :: rl.Rectangle

PIXEL_WINDOW_HEIGHT :: 180
GAMEPLAY_ZOOM :: 1.2
SAVE_GAME_PATH :: "data/game_save.json"

// Choosing_Class is first (the zero value) so a save with no Class chosen
// yet always starts there, regardless of what program_mode a stale save
// file might otherwise imply - see the json:"-" tag below, which already
// prevents that on its own. Unlike Selecting (map choice, which re-runs
// every launch), load_game skips straight past Choosing_Class once
// Player.class_chosen is true, since Class must stay locked in for the
// whole game rather than be re-pickable launch to launch.
ProgramMode :: enum {
	Choosing_Class,
	Selecting,
	Playing,
	Editing,
}

game: struct {
	// never persisted: every launch starts at .Choosing_Class (or .Selecting,
	// once player.class_chosen - see load_game) regardless of whatever mode
	// was active when the game was last saved
	program_mode: ProgramMode `json:"-"`,
	mouse:         MouseState,
	window_width:  f32,
	window_height: f32,
	window_title:  cstring,
	camera:        Camera,
	ui_camera:     Camera,
	player:        Player,

	// Playing mode's live map state, instantiated (via clone_map) from the
	// baked `maps` table once a map is chosen on the Selecting screen. Never
	// persisted: game_save.json stores only active_map_pointer below, and
	// every launch re-derives current_map fresh from the baked table -
	// writing the full tilemap/spawners out here would just bloat the save
	// file with data that's never read back on load.
	current_map:        Map `json:"-"`,
	// game_save.json's pointer to the active map's identity (a Map_Name's
	// enum-case name - see map_identity_string), read by apply_chosen_map to
	// decide resume-vs-reset player positioning on the next map choice
	active_map_pointer: string,

	// Editing mode's own map, isolated from current_map - see editor.odin's
	// map switcher. Never persisted: edits are silently discarded on
	// leaving Editing, so there's nothing worth saving between sessions.
	editing_map:      Map `json:"-"`,
	editing_map_path: string `json:"-"`,

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

	// true while the Shop panel is open; simulation is paused the same way
	// leveling_up/game_over already gate update_game_state (see CONTEXT.md's
	// Shop entry). Never saved - a save taken mid-Shop simply reopens closed,
	// same rationale as leveling_up.
	shopping:      bool `json:"-"`,

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

	// a save file predating move_speed/max_health (this feature's addition)
	// unmarshals them as Odin's zero value, not their real defaults - left
	// unguarded, a 0 max_health freezes movement (move_actor scales by
	// move_speed) and divides-by-zero in damage_player/the HUD health bar.
	// Neither field can legitimately be <= 0 in a valid Run (Upgrades only
	// ever raise them above their base constants), so this is a safe
	// missing-field signal, not a false positive on real data.
	if game.player.move_speed <= 0 {
		game.player.move_speed = PLAYER_BASE_MOVE_SPEED
	}
	if game.player.max_health <= 0 {
		game.player.max_health = PLAYER_BASE_MAX_HEALTH
	}

	game.player.weapon.variant = weapon_variant_from_save(game.player.weapon_variant_save)

	// re-derive the loaded Weapon's stats from its preset baseline plus the
	// just-loaded upgrade_stacks (ADR-0007) - idempotent and a no-op if the
	// save already reflects them correctly, but keeps a hand-edited or
	// future-migrated save file self-healing instead of trusting its
	// damage/action_rate/etc fields to already be consistent with its stacks
	apply_upgrades(&game.player.weapon, game.player.upgrade_stacks)

	// never trust a stale persisted value even though program_mode's
	// json:"-" tag already prevents it from round-tripping. Skip straight
	// past Choosing_Class on a save that already locked one in - showing it
	// again would let a same-class re-click in draw_class_selection_ui blow
	// away the just-loaded (possibly Shop/level-up upgraded) weapon above,
	// and Class is meant to be permanent for the whole game, not just
	// one-shot-per-launch the way map choice is.
	game.program_mode = game.player.class_chosen ? .Selecting : .Choosing_Class

	log_info("Loaded game from `{}`", SAVE_GAME_PATH)

	initialize_default_game_state :: proc() {
		// zeroed explicitly, ahead of the literal below: weapon_create(.Sword)
		// in that literal reads the global game.player.upgrade_stacks before
		// the `game = {...}` assignment takes effect, so a prior (possibly
		// partially-unmarshaled, then discarded) game.player.upgrade_stacks
		// would otherwise leak into this supposedly-fresh starting weapon
		game.player.upgrade_stacks = {}

		game = {
			program_mode = .Choosing_Class,
			window_width = 1920 / 2,
			window_height = 1080 / 2,
			window_title = "Game",
			player = {
				rect = {1920 / 4 - 16, 1080 / 4 - 16, 32, 32},
				animation = animation_create(.Player_Walk),
				class = .Melee,
				weapon = weapon_create(.Sword),
				level = 1,
				move_speed = PLAYER_BASE_MOVE_SPEED,
				max_health = PLAYER_BASE_MAX_HEALTH,
			},
			camera = Camera {
				target = Vec2{1920 / 4, 1080 / 4},
				offset = Vec2{1920 / 4, 1080 / 4},
				zoom = 1.0,
			},
		}
	}
}

save_game :: proc() {
	log_info("Saving game to save file `{}`", SAVE_GAME_PATH)

	game.player.weapon_variant_save = weapon_variant_to_save(game.player.weapon.variant)

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
	game.player.health = game.player.max_health

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
		switch game.program_mode {
		case .Choosing_Class:
		// no-op: F1 does nothing before a Class has been chosen
		case .Selecting:
		// no-op: F1 does nothing before a map has been chosen
		case .Playing:
			// entering Editing always starts from a clone of the map
			// currently being played (never a plain value copy - see
			// clone_map's aliasing note), so by default you're editing the
			// map you're currently playing unless you explicitly switch.
			// free the previous editing_map's backing arrays first, or
			// repeated F1 toggles leak one copy of the old map each time.
			delete_map(game.editing_map)
			game.editing_map = clone_map(game.current_map)
			if name, ok := reflect.enum_from_name(Map_Name, game.active_map_pointer); ok {
				game.editing_map_path = map_path_for_name(name)
			}
			game.program_mode = .Editing
		case .Editing:
			game.program_mode = .Playing
		}
	}

	if is_key_pressed(.F8) {
		game.debug_overlay = !game.debug_overlay
	}

	// Shop open/close: a dedicated key (TAB - unused elsewhere), mirroring F1
	// for Editing (ticket 03). Only reachable from Playing, and not while the
	// level-up/game-over modals already have their own pause up - those can
	// never become true while shopping anyway, since game.shopping already
	// pauses update_game_state below, but this keeps the open trigger itself
	// just as guarded as F1 is against Choosing_Class/Selecting.
	if is_key_pressed(.TAB) && game.program_mode == .Playing && !game.leveling_up && !game.game_over {
		game.shopping = !game.shopping
	}

	switch game.program_mode {
	case .Choosing_Class:
	// no-op: draw_class_selection_ui's buttons handle their own clicks
	case .Selecting:
	// no-op: draw_map_selection_ui's buttons handle their own clicks
	case .Playing:
		update_game_state()
	case .Editing:
		update_editor()
	}

	update_game_state :: proc() {
		if game.leveling_up || game.game_over || game.shopping {
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
		move_actor(&game.player.rect, game.player.animation, &game.current_map.tilemap, input * rl.GetFrameTime() * game.player.move_speed)

		// blocked mid-Windup: a manually-triggered reload would otherwise
		// silently fail the pending Resolve (gun_can_fire would see
		// reload_timer > 0 once Windup completes), breaking the "a committed
		// Windup always resolves" invariant (story 17)
		if is_key_pressed(.R) && game.player.weapon.windup_timer <= 0 {
			start_reload(&game.player.weapon)
		}

		// dev/debug weapon switching: left/right cycles within the player's
		// locked-in Class (see weapon.odin's cycle_weapon_kind) - never
		// crosses into another Class, since Class is chosen once on the
		// Choosing_Class screen and locked in for the whole game. Arrow keys
		// are free for this since WASD alone already covers movement.
		if is_key_pressed(.LEFT) {
			game.player.weapon = weapon_create(cycle_weapon_kind(game.player.weapon.kind, -1))
		}
		if is_key_pressed(.RIGHT) {
			game.player.weapon = weapon_create(cycle_weapon_kind(game.player.weapon.kind, 1))
		}

		mouse_world := rl.GetScreenToWorld2D(game.mouse.position, game.camera)
		player_pos := Vec2{game.player.x, game.player.y}
		game.player.aim_dir = linalg.normalize0(mouse_world - player_pos)

		// moved to after aim_dir/mouse_world/player_pos are freshly computed
		// this frame (not before, as before Windup existed), so a Resolve on
		// Windup completion always fires against current-frame aim state
		update_weapon(
			&game.player.weapon,
			rl.GetFrameTime(),
			player_pos,
			game.player.aim_dir,
			mouse_world,
			game.enemies[:],
		)

		fire_pressed := game.player.weapon.fire_mode == .Automatic ? is_mouse_button_down(.LEFT) : is_mouse_button_pressed(.LEFT)

		if fire_pressed {
			try_use_weapon(&game.player.weapon, player_pos, game.player.aim_dir, mouse_world, game.enemies[:])
		}

		update_magic_cast_particles(game.player.weapon, player_pos, game.player.aim_dir, is_mouse_button_down(.LEFT))

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

		tile_rect := tile_world_rect(tile.world_coords, tilemap.tile_size)
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

		tile_rect := tile_world_rect(tile.world_coords, tilemap.tile_size)
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
	// chosen once on the Choosing_Class screen (hud.odin's
	// draw_class_selection_ui) and locked in for the whole game from then on
	// - see CONTEXT.md's Class entry and ADR-0002. Persisted so the choice
	// survives relaunches; class_chosen (below) is what actually gates
	// whether Choosing_Class shows again, since Class's own zero value
	// (.Ranged) is indistinguishable from a real choice of Ranged.
	class:      Class,
	// true once `class` has been set via draw_class_selection_ui - load_game
	// uses this to skip straight past Choosing_Class on a resumed save,
	// unlike map choice (ProgramMode.Selecting), which re-shows every
	// launch. Without this gate, re-showing the picker would let a
	// same-class re-click wipe out an already-loaded, possibly upgraded
	// weapon (draw_class_selection_ui always equips the class's base tier).
	class_chosen: bool,
	weapon:     Weapon,
	// Weapon.variant is a union and is tagged json:"-" (see weapon.odin) -
	// this is the plain, persisted view of it, converted explicitly at the
	// save_game/load_game boundary so json.unmarshal's union-decode-order
	// guessing never runs on player-owned weapon state.
	weapon_variant_save: Weapon_Variant_Save,
	aim_dir:    Vec2, // world-space direction toward the mouse, updated every frame
	xp:         int, // progress toward next level; persisted run progression
	level:      int, // persisted run progression, starts at 1
	// Run-scoped (ADR-0006): spent in the Shop, reset to 0 on Restart but
	// otherwise persisted through save/quit like xp/level already are.
	gold:       int,
	// Run-scoped (ADR-0007): how many times each Upgrade_Kind has been
	// bought this Run - the sole source of truth an equipped Weapon's live
	// stats are recomputed from (see apply_upgrades), never mutated
	// in-place. Zeroed on Restart.
	upgrade_stacks: [Upgrade_Kind]int,
	// Run-scoped (ADR-0007): replaces the old hardcoded `100` movement
	// literal - the live, Move Speed-Upgrade-scaled value, reset to
	// PLAYER_BASE_MOVE_SPEED on Restart.
	move_speed: f32,
	// Run-scoped (ADR-0007): replaces the old PLAYER_MAX_HEALTH constant -
	// the live, Max Health-Upgrade-scaled cap, reset to
	// PLAYER_BASE_MAX_HEALTH on Restart. A Max Health purchase heals current
	// health by the same amount it raises this (see try_buy_upgrade).
	max_health: f32,
	// runtime combat state, not persisted (see initialize_program) - a saved
	// game predating this field would otherwise unmarshal it as 0 and trigger
	// an instant game-over on load
	health:     f32 `json:"-"`,
}

PLAYER_BASE_MOVE_SPEED :: 100
PLAYER_BASE_MAX_HEALTH :: 100

// applies enemy damage to the player, opening the game-over modal at 0 hp
damage_player :: proc(amount: f32) {
	spawn_damage_burst(Vec2{game.player.x, game.player.y})
	trigger_screen_shake(amount / game.player.max_health)

	game.player.health -= amount
	if game.player.health <= 0 {
		game.player.health = 0
		game.game_over = true
	}
}

// restores player hp from a pickup, clamped so healing can't exceed max health
heal_player :: proc(amount: f32) {
	game.player.health = min(game.player.health + amount, game.player.max_health)
}

// resets Run-scoped state to a fresh Run's starting values (ADR-0006): Gold,
// upgrade_stacks, move_speed, max_health, and the equipped weapon (back to
// the Class's tier-1, with zeroed stacks reapplying as a no-op) all reset.
// Class/class_chosen/xp/level are Account progression and stay untouched.
// Extracted from draw_game_over_ui's Restart button, which is still its only
// caller.
restart_game :: proc() {
	clear(&game.enemies)
	clear(&game.bullets)
	clear(&game.enemy_bullets)
	clear(&game.xp_orbs)
	clear(&game.pickups)
	clear(&game.particles)
	reset_screen_shake()

	game.player.gold = 0
	game.player.upgrade_stacks = {}
	game.player.move_speed = PLAYER_BASE_MOVE_SPEED
	game.player.max_health = PLAYER_BASE_MAX_HEALTH
	game.player.weapon = weapon_create(class_weapon_kinds[game.player.class][0])
	game.player.health = game.player.max_health

	game.game_over = false
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
		draw_tilemap(&game.current_map.tilemap)
		for enemy in game.enemies {
			draw_actor(enemy.rect, enemy.animation, enemy.flip_x)
			if game.debug_overlay {
				draw_path(Vec2{enemy.x, enemy.y}, enemy.path)
			}
			draw_health_bar(enemy)
		}
		draw_actor(game.player.rect, game.player.animation, game.player.flip_x)
		draw_weapon(game.player)
		if game.debug_overlay {
			draw_debug_colliders()
			draw_debug_weapon_area(game.player)
			draw_debug_attack_ranges()
			draw_debug_movement_styles()
		}
		draw_spawners(game.current_map.spawners[:])
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
		case .Choosing_Class:
		// no-op: draw_class_selection_ui (below, alongside the other modals)
		// draws its own full-screen content
		case .Selecting:
		// no-op: draw_map_selection_ui (below, alongside the other modals)
		// draws its own full-screen content
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

	if game.program_mode == .Choosing_Class {
		draw_class_selection_ui()
	}

	if game.program_mode == .Selecting {
		draw_map_selection_ui()
	}

	if game.leveling_up {
		draw_level_up_ui()
	}

	if game.game_over {
		draw_game_over_ui()
	}

	if game.shopping {
		draw_shop_ui()
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
			atlas_rect := tileset_normal[tile.atlas_coords.x][tile.atlas_coords.y]
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
			next := cell_center_to_world(cell, game.current_map.tilemap.tile_size)
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

	WEAPON_WINDUP_PULLBACK :: 6.0 // px pulled back along -aim_dir while a Gun/Magic weapon winds up
	WEAPON_RECOIL_KICK :: 8.0 // px kicked back along -aim_dir during Gun's Automatic Follow-through (SMG)
	FLAME_STAFF_PULSE_SCALE :: 0.35 // extra sprite scale at the start of a Follow-through pulse, decaying to 0
	SWORD_SWING_OUT_TIME :: 0.07 // seconds, ease-out draw-back angle -> follow-through extreme
	SWORD_SWING_RETURN_TIME :: 0.11 // seconds, ease-out extreme -> neutral

	ease_out_cubic :: proc(t: f32) -> f32 {
		u := 1 - clamp(t, 0, 1)
		return 1 - u * u * u
	}

	// draws weapon_texture_names[player.weapon.kind]'s icon pivoting at
	// roughly chest height, rotated to face the player's current aim
	// direction. Windup/Follow-through motion below is transform-only
	// animation on that per-kind sprite (validated for timing by ticket
	// 04/05/06's prototypes); the "punch" beyond transform comes from Magic's
	// windup/cast particles (update_magic_cast_particles, weapon.odin), spawned
	// during update rather than drawn here.
	draw_weapon :: proc(player: Player) {
		tex := atlas_textures[weapon_texture_names[player.weapon.kind]]
		weapon := player.weapon

		doc := animation_atlas_texture(player.animation).document_size
		pivot := Vec2{player.x, player.y - doc.y / 2}
		angle := math.to_degrees(math.atan2(player.aim_dir.y, player.aim_dir.x))
		pulse_scale: f32 = 1

		// Windup (Semi_Automatic): draw the telegraph ahead of Resolve - melee
		// sweeps its arc backward, everything else pulls back along -aim_dir
		if weapon.windup_timer > 0 {
			progress := weapon_windup_progress(weapon)

			switch v in weapon.variant {
			case Melee_Weapon:
				angle -= (v.arc_degrees / 2) * progress
			case Gun, Magic:
				pivot -= player.aim_dir * WEAPON_WINDUP_PULLBACK * progress
			}
		}

		// Sword's Resolve swing-through (ticket 05): a two-phase eased curve
		// (a spring was prototyped and rejected as feeling wrong), derived
		// purely from time-since-Resolve rather than a new persisted timer -
		// recovered from cooldown_timer, since Windup-gated weapons otherwise
		// go straight from Resolve to Ready with no separate Follow-through
		if v, is_melee := weapon.variant.(Melee_Weapon); is_melee && weapon.windup_fraction > 0 {
			windup_duration := weapon.windup_fraction / weapon.action_rate
			cycle := 1.0 / weapon.action_rate
			time_since_resolve := (cycle - windup_duration) - weapon.cooldown_timer
			swing_total := f32(SWORD_SWING_OUT_TIME + SWORD_SWING_RETURN_TIME)

			if time_since_resolve >= 0 && time_since_resolve < swing_total {
				draw_back := -(v.arc_degrees / 2)
				extreme := v.arc_degrees / 2

				if time_since_resolve < SWORD_SWING_OUT_TIME {
					t := ease_out_cubic(time_since_resolve / SWORD_SWING_OUT_TIME)
					angle += draw_back + (extreme - draw_back) * t
				} else {
					t := ease_out_cubic((time_since_resolve - SWORD_SWING_OUT_TIME) / SWORD_SWING_RETURN_TIME)
					angle += extreme - extreme * t
				}
			}
		}

		// Follow-through (Automatic): Dagger's post-hit sweep (unchanged from
		// the old swing_time/swing_timer, now the Weapon-level generalized
		// fields - ticket 01), SMG's recoil-kick, Flame_Staff's per-tick pulse
		if weapon.follow_through_timer > 0 && weapon.follow_through_time > 0 {
			progress := 1 - weapon.follow_through_timer / weapon.follow_through_time // 0 -> 1

			switch v in weapon.variant {
			case Melee_Weapon:
				angle += (progress - 0.5) * v.arc_degrees
			case Gun:
				pivot -= player.aim_dir * WEAPON_RECOIL_KICK * (1 - progress)
			case Magic:
				pulse_scale += FLAME_STAFF_PULSE_SCALE * (1 - progress)
			}
		}

		// sprite's muzzle faces +x (right) by default; mirror vertically when
		// the drawn angle (post windup/swing offset, not the raw aim_dir)
		// points left, so the weapon stays right-side up instead of
		// upside-down mid-swing
		atlas_rect := tex.rect
		offset_top := tex.offset_top
		if math.cos(math.to_radians(angle)) < 0 {
			atlas_rect.height = -atlas_rect.height
			offset_top = tex.offset_bottom
		}

		// scale so the grip-to-tip reach matches the player's size (Gun/Magic),
		// or matches Melee_Weapon's own range (Sword/Dagger) so the blade's
		// drawn tip lands exactly where its hit-arc actually reaches, instead
		// of an icon-sized blade implying a shorter reach than it has. Reach
		// at scale=1 is rect.width + offset_left (grip-to-visible-tip in the
		// same dest-local coords `origin` below is expressed in, assuming the
		// blade tip is the atlas's last opaque pixel with ~0 offset_right).
		scale: f32
		switch v in weapon.variant {
		case Melee_Weapon:
			reach := tex.rect.width + tex.offset_left
			scale = reach > 0 ? v.range / reach : doc.y / tex.document_size.y
		case Gun, Magic:
			scale = doc.y / tex.document_size.y
		}
		scale *= pulse_scale

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
	// inside to fire rather than chase or retreat. Enemies with no Attack
	// Style have no attack, so nothing is drawn for them.
	draw_debug_attack_ranges :: proc() {
		for enemy in game.enemies {
			center := Vec2{enemy.x, enemy.y}
			switch a in enemy.attack {
			case Melee:
				rl.DrawCircleLinesV(center, a.attack_range, rl.ORANGE)
			case Ranged:
				rl.DrawCircleLinesV(center, a.min_range, rl.ORANGE)
				rl.DrawCircleLinesV(center, a.max_range, rl.ORANGE)
			case:
			}
		}
	}

	// F8 dev view: each enemy's Separation neighbour radius (how close
	// same-Movement-Style enemies must be before they push apart), plus a
	// dedicated ring for Swarmer's surround distance - the band around the
	// player it seeks to orbit, read from its own Attack Style's engagement
	// range (see swarmer_surround_radius).
	draw_debug_movement_styles :: proc() {
		player_pos := Vec2{game.player.x, game.player.y}

		for enemy in game.enemies {
			center := Vec2{enemy.x, enemy.y}
			kind := movement_style_kind(enemy.movement)
			if kind == .Inert {
				continue
			}

			rl.DrawCircleLinesV(center, SEPARATION_RADIUS[kind], rl.PURPLE)

			if kind == .Swarmer {
				rl.DrawCircleLinesV(player_pos, swarmer_surround_radius(enemy.attack), rl.PURPLE)
			}
		}
	}

	// F8 dev view: the equipped weapon's hit area, shown continuously
	// (unlike Flamethrower's held-only cone particles) so range/arc tuning
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
