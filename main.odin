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

// starting points only - tune visually against Shop/Run_End, same as
// weapon-action-feel's per-weapon timing constants were treated (see
// ADR-0015 and hud.odin's blurred_backdrop_strength)
BLUR_MAX_RADIUS_PX :: 6.0
BLUR_DIM_ALPHA_MAX :: 0.45

// how long Splash (ProgramMode.Splash) shows at minimum before a key/click
// can skip it - purely a branding beat, not tied to any real loading (see
// ProgramMode's doc comment)
SPLASH_MIN_SECONDS :: 1.5

// Splash is first (the zero value) so a fresh save, or one with no Run in
// progress, always starts there, regardless of what program_mode a stale
// save file might otherwise imply - see the json:"-" tag below, which
// already prevents that on its own. It's a cosmetic, button-less beat
// (draw_splash_ui) that update_game's .Splash case advances out of on a
// timer or the first key/click, landing unconditionally on Main_Menu -
// every launch shows it now, regardless of Player.run_started (ADR-0013).
// Main_Menu (draw_main_menu_ui, hud.odin) folds in the old
// Account_Progression content (ADR-0012) and offers "Continue" (only when
// run_started - straight to Selecting, matching today's map-choice-only
// resume) alongside an always-present "Start New Run" (through Run_Start,
// weapon-pick) - see CONTEXT.md's Run entry and ADR-0008.
ProgramMode :: enum {
	Splash,
	Main_Menu,
	Run_Start,
	Selecting,
	Playing,
	Editing,
}

game: struct {
	// never persisted: every launch starts at .Splash regardless of whatever
	// mode was active when the game was last saved - see load_game and
	// update_game's .Splash case for where it goes from there
	program_mode: ProgramMode `json:"-"`,
	// accumulated only while program_mode == .Splash (see update_game) -
	// never persisted, since Splash only ever runs once per process launch
	// and `game` starts zero-initialized either way
	splash_elapsed_seconds: f32 `json:"-"`,
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
	pickups:             [dynamic]Pickup `json:"-"`,
	particles:           [dynamic]Particle `json:"-"`,
	damage_numbers:      [dynamic]Damage_Number `json:"-"`,
	screen_shake_trauma: f32 `json:"-"`,

	// true while the Run End modal is open (death - see damage_player);
	// simulation is paused. Never saved - a save taken mid-modal simply
	// reopens closed, which is fine since no Run state is lost (the XP grant
	// is already committed by grant_account_xp at the moment of death).
	run_ended:     bool `json:"-"`,

	// the XP grant computed at the moment of death (compute_run_xp), kept
	// only for draw_run_end_ui to display - not itself a source of truth for
	// anything (game.player.xp/level/unspent_xp already reflect it via
	// grant_account_xp), so it's never saved.
	last_run_xp_earned: int `json:"-"`,

	// true while the Shop panel is open; simulation is paused the same way
	// run_ended already gates update_game_state (see CONTEXT.md's Shop
	// entry). Never saved - a save taken mid-Shop simply reopens closed,
	// same rationale as run_ended.
	shopping:      bool `json:"-"`,

	// true while the Main Menu's "Discard current Run?" panel is showing
	// (draw_main_menu_ui) - set when "Start New Run" is pressed with a Run
	// already in progress (ADR-0013), cleared by either Yes or Cancel. Never
	// saved, same rationale as run_ended/shopping: reopens closed on load,
	// no state is lost since nothing is actually discarded until a starter
	// weapon is picked on the Run_Start screen (start_new_run).
	confirming_new_run: bool `json:"-"`,

	// the shared Reveal/Dismiss transition record (ADR-0014, hud.odin) that
	// every Screen change goes through via request_screen_change - never
	// saved, same rationale as run_ended/shopping: a save taken mid-
	// transition simply reopens at rest (its zero value already matches a
	// fresh Splash launch, see Menu_Transition's doc comment).
	menu_transition: Menu_Transition `json:"-"`,

	// F8-toggled debug settings panel (debug.odin): each dev-view visualizer
	// (colliders, weapon area, attack ranges, movement styles, pathfinding)
	// toggles independently instead of the old single debug_overlay bool
	// that gated all of them together, plus a Gold grant and God Mode. Never
	// saved, same rationale as run_ended/shopping.
	debug: Debug_State `json:"-"`,
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

	// re-derive the loaded Weapon's stats, and move_speed/max_health, from
	// their preset/base-constant baselines plus the just-loaded
	// account_stat_stacks/upgrade_stacks (ADR-0007) - idempotent and a no-op
	// if the save already reflects them correctly, but keeps a hand-edited
	// save file self-healing instead of trusting its damage/action_rate/
	// move_speed/max_health fields to already be consistent with its stacks
	apply_upgrades(&game.player.weapon, game.player.upgrade_stacks, game.player.account_stat_stacks)
	recompute_player_stats()

	// never trust a stale persisted value even though program_mode's
	// json:"-" tag already prevents it from round-tripping. Always start at
	// Splash, which unconditionally advances to Main_Menu - that screen is
	// what branches on Player.run_started (draw_main_menu_ui, hud.odin),
	// showing "Continue" straight to Selecting on a save with a Run already
	// in progress rather than "Start New Run"'s Run_Start, since re-showing
	// weapon-pick would let a re-click in draw_run_start_ui blow away the
	// just-loaded (possibly Shop-upgraded) weapon/Gold/Upgrade-stacks above.
	game.program_mode = .Splash

	log_info("Loaded game from `{}`", SAVE_GAME_PATH)

	initialize_default_game_state :: proc() {
		game = {
			program_mode = .Splash,
			window_width = 1920 / 2,
			window_height = 1080 / 2,
			window_title = "Game",
			player = {
				rect = {1920 / 4 - 16, 1080 / 4 - 16, 32, 32},
				squash = {1, 1},
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
	reset_pickups()
	reset_particles()
	reset_damage_numbers()
	reset_screen_shake()
	// runtime combat state, deliberately not persisted (see Player.health) -
	// reset here so both fresh games and loads start at full health
	game.player.health = game.player.max_health
	// json:"-" (see Player.squash) - a fresh/loaded game would otherwise
	// start at the zero-value {0,0} and draw the player invisibly for one
	// frame until movement first eases it toward {1,1}
	game.player.squash = {1, 1}

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

	// once per frame, ahead of everything below that reads program_mode/
	// run_ended/shopping - so a Dismiss window that finishes this frame is
	// already reflected in every guard/switch further down (ADR-0014)
	update_menu_transition()

	if is_key_pressed(.F1) {
		switch game.program_mode {
		case .Splash:
		// no-op: F1 does nothing on the splash screen
		case .Main_Menu:
		// no-op: F1 does nothing on the Main Menu
		case .Run_Start:
		// no-op: F1 does nothing before a starter weapon has been chosen
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
			clear(&editor.expanded_spawn_triggers)
			game.program_mode = .Editing
		case .Editing:
			game.program_mode = .Playing
		}
	}

	// Only reachable from Playing, and mutually exclusive with Shop: both
	// panels drive the same vendor/ui library, which tracks click state in
	// package-level globals via a single ui.set_pointer_state call per frame
	// - draw_game would otherwise call it twice in one frame (once for each
	// open panel), and the second call always sees its own just-written
	// mouse-down state as "already down", so pointer_released (what a click
	// requires) can never fire for whichever panel draws second. Requiring
	// .Playing also keeps it from ever coexisting with the always-drawn
	// Editing-mode editor, which hits the same collision.
	if is_key_pressed(.F8) &&
	   game.program_mode == .Playing &&
	   !game.run_ended &&
	   !game.shopping {
		game.debug.panel_open = !game.debug.panel_open
	}

	// Shop open/close: a dedicated key (TAB - unused elsewhere), mirroring F1
	// for Editing (ticket 03). Only reachable from Playing, and not while the
	// Run End modal already has its own pause up - that can never become
	// true while shopping anyway, since game.shopping already pauses
	// update_game_state below, but this keeps the open trigger itself just
	// as guarded as F1 is against Run_Start/Selecting. Also mutually
	// exclusive with the debug panel - see its own guard above for why two
	// open panels in one frame is unsafe.
	if is_key_pressed(.TAB) &&
	   game.program_mode == .Playing &&
	   !game.run_ended &&
	   !game.debug.panel_open {
		// Shop<->Playing is a Screen change like any other (ADR-0014) - just
		// one whose "other side" isn't a Screen, hence request_screen_change
		// taking nil to mean "back to Playing" rather than a Screen_Kind
		if game.shopping {
			request_screen_change(nil)
		} else {
			request_screen_change(.Shop)
		}
	}

	switch game.program_mode {
	case .Splash:
		game.splash_elapsed_seconds += rl.GetFrameTime()
		if game.splash_elapsed_seconds >= SPLASH_MIN_SECONDS ||
		   is_mouse_button_pressed(.LEFT) ||
		   is_any_key_pressed() {
			request_screen_change(.Main_Menu)
		}
	case .Main_Menu:
	// no-op: draw_main_menu_ui's buttons handle their own clicks
	case .Run_Start:
	// no-op: draw_run_start_ui's buttons handle their own clicks
	case .Selecting:
	// no-op: draw_map_selection_ui's buttons handle their own clicks
	case .Playing:
		update_game_state()
	case .Editing:
		update_editor()
	}

	update_game_state :: proc() {
		if game.run_ended || game.shopping || game.debug.panel_open {
			return
		}

		game.player.survival_seconds += rl.GetFrameTime()

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

		update_actor_squash(&game.player.squash, input.x != 0 || input.y != 0, rl.GetFrameTime())

		input = linalg.normalize0(input)
		move_actor(&game.player.rect, &game.current_map.tilemap, input * rl.GetFrameTime() * game.player.move_speed)

		// blocked mid-Windup: a manually-triggered reload would otherwise
		// silently fail the pending Resolve (gun_can_fire would see
		// reload_timer > 0 once Windup completes), breaking the "a committed
		// Windup always resolves" invariant (story 17)
		if is_key_pressed(.R) && game.player.weapon.windup_timer <= 0 {
			start_reload(&game.player.weapon)
		}

		// dev/debug weapon switching: left/right cycles within the equipped
		// weapon's family (see weapon.odin's cycle_weapon_kind) - never
		// crosses into another family. Arrow keys are free for this since
		// WASD alone already covers movement.
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
		update_pickups(rl.GetFrameTime())
		update_particles(rl.GetFrameTime())
		update_damage_numbers(rl.GetFrameTime())
		update_player_resource_indicators(rl.GetFrameTime())

		update_spawn_triggers(rl.GetFrameTime())
		update_enemies(rl.GetFrameTime())
	}
}

// sprites are drawn with a bottom-center origin, so rect.x/y is the anchor at
// the actor's feet; the collision box is the drawn sprite's bounds around that
// anchor, not a top-left rect hanging below it
// fixed logical footprint for both Player and Enemy - matches the old sprite
// document_size (24x24) so hitboxes are unchanged from before the art revamp,
// now independent of the (removed) Animation/atlas system
ACTOR_SIZE :: Vec2{24, 24}

actor_collision_rect :: proc(rect: Rect) -> Rect {
	return {rect.x - ACTOR_SIZE.x / 2, rect.y - ACTOR_SIZE.y, ACTOR_SIZE.x, ACTOR_SIZE.y}
}

// moves an actor (player or enemy), resolving against colliding tiles one axis
// at a time so it slides along walls instead of stopping dead on diagonal input
move_actor :: proc(rect: ^Rect, tilemap: ^Tilemap, delta: Vec2) {
	box := actor_collision_rect(rect^)

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
	squash:     Vec2 `json:"-"`, // continuous isotropic squash while moving, eased back to {1,1} at rest (draw_actor)
	weapon:     Weapon,
	// Weapon.variant is a union and is tagged json:"-" (see weapon.odin) -
	// this is the plain, persisted view of it, converted explicitly at the
	// save_game/load_game boundary so json.unmarshal's union-decode-order
	// guessing never runs on player-owned weapon state.
	weapon_variant_save: Weapon_Variant_Save,
	aim_dir:    Vec2, // world-space direction toward the mouse, updated every frame

	// -- Account progression (survives Runs - see CONTEXT.md's Account
	// progression entry and ADR-0009). Only ever changed by grant_account_xp
	// (Run-end XP grant) and try_buy_account_stat (Account_Stat spend).
	xp:                  int, // progress toward next Account level; a milestone only, grants no purchasing power
	level:               int, // Account level, starts at 1
	unspent_xp:          int, // spendable balance for Account_Stat purchases; banks indefinitely, spending is optional
	account_stat_stacks: [Account_Stat]int, // how many times each Account_Stat has been bought, ever

	// true once a starter weapon has been picked for the Run currently in
	// progress (hud.odin's draw_run_start_ui) - load_game uses this to skip
	// straight past ProgramMode.Run_Start on a resumed save, unlike map
	// choice (ProgramMode.Selecting), which re-shows every launch
	// regardless. Cleared by the Run End screen's Continue after death, so
	// (unlike the retired class_chosen) it's re-earned every Run rather than
	// permanent.
	run_started: bool,
	// Run-scoped (ADR-0006): spent in the Shop, reset to 0 by start_new_run
	// but otherwise persisted through save/quit like xp/level already are.
	gold:       int,
	// Run-scoped: total Gold ever picked up this Run (never decreases when
	// spent in the Shop, unlike `gold` above) - one of compute_run_xp's
	// three inputs. Reset to 0 by start_new_run.
	gold_earned: int,
	// Run-scoped: kills this Run, tallied per Enemy_Kind - another of
	// compute_run_xp's inputs (see apply_hit_to_enemy). Reset to {} by
	// start_new_run.
	kills: [Enemy_Kind]int,
	// Run-scoped: seconds actually spent Playing this Run (see
	// update_game_state) - the third of compute_run_xp's inputs. Reset to 0
	// by start_new_run.
	survival_seconds: f32,
	// Run-scoped (ADR-0007): how many times each Upgrade_Kind has been
	// bought this Run - the sole source of truth an equipped Weapon's live
	// stats are recomputed from (see apply_upgrades), never mutated
	// in-place. Zeroed by start_new_run.
	upgrade_stacks: [Upgrade_Kind]int,
	// Run-scoped (ADR-0007), layered on top of any owned Account_Stat
	// Swiftness (see recompute_player_stats) - the live, Upgrade-scaled
	// value, reset by start_new_run.
	move_speed: f32,
	// Run-scoped (ADR-0007), layered on top of any owned Account_Stat Vigor
	// (see recompute_player_stats) - the live, Upgrade-scaled cap, reset by
	// start_new_run. A Max Health purchase (Upgrade or Vigor) heals current
	// health by the same amount it raises this.
	max_health: f32,
	// runtime combat state, not persisted (see initialize_program) - a saved
	// game predating this field would otherwise unmarshal it as 0 and trigger
	// an instant Run End on load
	health:     f32 `json:"-"`,
}

PLAYER_BASE_MOVE_SPEED :: 100
PLAYER_BASE_MAX_HEALTH :: 100

// derives move_speed/max_health fresh from PLAYER_BASE_MOVE_SPEED/
// PLAYER_BASE_MAX_HEALTH, layered through Account_Stat's Swiftness/Vigor
// (permanent) and then Run-scoped Move_Speed/Max_Health Upgrade stacks -
// mirrors apply_upgrades' weapon-side derivation (ADR-0007, CONTEXT.md's
// Account_Stat entry: "baseline weapon preset -> Account_Stat allocations ->
// Run-scoped Upgrade stacks"). Run every time a relevant Upgrade or
// Account_Stat is purchased, and at Run start / load, so both are always
// self-consistent with their sources of truth rather than accumulated in
// place.
recompute_player_stats :: proc() {
	swiftness := apply_account_stat_effect(PLAYER_BASE_MOVE_SPEED, .Swiftness, game.player.account_stat_stacks[.Swiftness])
	game.player.move_speed = apply_upgrade_effect(swiftness, .Move_Speed, game.player.upgrade_stacks[.Move_Speed])

	vigor := apply_account_stat_effect(PLAYER_BASE_MAX_HEALTH, .Vigor, game.player.account_stat_stacks[.Vigor])
	game.player.max_health = apply_upgrade_effect(vigor, .Max_Health, game.player.upgrade_stacks[.Max_Health])
}

// applies enemy damage to the player, granting this Run's XP and opening the
// Run End screen at 0 hp (ADR-0009, via request_screen_change - ADR-0014).
// God Mode (debug.odin) makes the player fully invulnerable - skipped before
// any damage-taken effects (burst/shake) fire, so a god-mode hit reads as a
// clean whiff rather than a damage flash with no health lost. Also bails
// once a Run_End Screen change is already pending - more than one attacking
// enemy/bullet can land a hit in the same frame (multiple update_enemies/
// update_enemy_bullets hits before the next frame's Playing guard kicks in),
// and without this guard each of those re-enters the health <= 0 branch
// below and double-grants this Run's XP. Checks screen_change_pending_to
// rather than game.run_ended itself, since run_ended no longer flips the
// instant death happens - it's deferred until Run_End's Dismiss window
// completes (see update_menu_transition), which would otherwise leave this
// guard open for the whole window instead of closing immediately.
damage_player :: proc(amount: f32) {
	if game.debug.god_mode || game.run_ended || screen_change_pending_to(.Run_End) {
		return
	}

	spawn_damage_burst(Vec2{game.player.x, game.player.y})
	spawn_damage_number(Vec2{game.player.x, game.player.y}, amount, rl.RED)
	trigger_screen_shake(amount / game.player.max_health)

	game.player.health -= amount
	if game.player.health <= 0 {
		game.player.health = 0
		game.last_run_xp_earned = compute_run_xp(game.player.kills, game.player.survival_seconds, game.player.gold_earned)
		grant_account_xp(game.last_run_xp_earned)
		request_screen_change(.Run_End)
	}
}

// restores player hp from a pickup, clamped so healing can't exceed max health
heal_player :: proc(amount: f32) {
	game.player.health = min(game.player.health + amount, game.player.max_health)
}

// resets Run-scoped state to a fresh Run's starting values and equips the
// freshly chosen starter weapon: Gold, gold_earned, kills, survival_seconds,
// upgrade_stacks, move_speed, max_health, and the equipped weapon all reset.
// Account progression (xp/level/unspent_xp/account_stat_stacks) stays
// untouched. Called from the Run_Start screen's weapon-pick button
// (hud.odin's draw_run_start_ui), both for the very first Run and every Run
// after a death.
start_new_run :: proc(starter_kind: Weapon_Kind) {
	clear(&game.enemies)
	clear(&game.bullets)
	clear(&game.enemy_bullets)
	clear(&game.pickups)
	clear(&game.particles)
	reset_screen_shake()

	game.player.gold = 0
	game.player.gold_earned = 0
	game.player.kills = {}
	game.player.survival_seconds = 0
	game.player.upgrade_stacks = {}
	recompute_player_stats()
	game.player.weapon = weapon_create(starter_kind)
	game.player.health = game.player.max_health
	game.player.run_started = true

	game.run_ended = false
}

XP_LEVEL_BASE :: 10 // xp required for level 1 -> 2
XP_LEVEL_GROWTH :: 1.25 // multiplicative growth per level

// xp required to advance from `level` to `level + 1`
xp_required_for_level :: proc(level: int) -> int {
	return int(f32(XP_LEVEL_BASE) * math.pow(f32(XP_LEVEL_GROWTH), f32(level - 1)))
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

// warm sand/stone palette (art-revamp ticket 04), distinct from the cool
// actor/weapon palette
TILEMAP_FLOOR_COLOR :: rl.Color{56, 48, 40, 255}
TILEMAP_WALL_COLOR :: rl.Color{124, 110, 90, 255}
TILEMAP_WALL_BEVEL_COLOR :: rl.Color{74, 64, 52, 255}

// Player renders as a rectangle (ACTOR_SIZE); every enemy renders as a
// square (see draw_enemy) - colors are a first-pass palette, not separately
// locked by any ticket.
ACTOR_PLAYER_COLOR :: rl.SKYBLUE
ENEMY_GROUNDED_COLOR :: rl.RED
ENEMY_FLOATER_COLOR :: rl.VIOLET
ENEMY_SWARMER_COLOR :: rl.ORANGE

// enemy square size grows with max_health, capped at ENEMY_SIZE_MAX so a
// high-health enemy never grows unreasonably huge. Tuned so today's uniform
// ENEMY_MAX_HEALTH (50) lands at the old fixed ACTOR_SIZE (24) - enemy
// variety with different max_health per kind will differentiate sizes once
// it exists.
ENEMY_SIZE_MIN :: 10.0
ENEMY_SIZE_MAX :: 48.0
ENEMY_SIZE_PER_MAX_HEALTH :: 0.28

enemy_body_size :: proc(max_health: f32) -> f32 {
	return clamp(ENEMY_SIZE_MIN + max_health * ENEMY_SIZE_PER_MAX_HEALTH, ENEMY_SIZE_MIN, ENEMY_SIZE_MAX)
}

// opacity fades toward ENEMY_MIN_OPACITY as health drops, so a badly-hurt
// enemy visibly reads as weakened at a glance, not just via a health bar
ENEMY_MIN_OPACITY :: 0.25

enemy_body_color :: proc(kind: Movement_Style_Kind, health_frac: f32) -> Color {
	base: Color
	switch kind {
	case .Grounded, .Inert:
		base = ENEMY_GROUNDED_COLOR
	case .Floater:
		base = ENEMY_FLOATER_COLOR
	case .Swarmer:
		base = ENEMY_SWARMER_COLOR
	}

	alpha := ENEMY_MIN_OPACITY + (1 - ENEMY_MIN_OPACITY) * clamp(health_frac, 0, 1)
	return rl.Fade(base, alpha)
}

ACTOR_SQUASH_RATE :: 12.0 // exp_approach rate, 1/s
ACTOR_MOVING_SCALE :: Vec2{1.15, 0.85} // scale_x/scale_y target while moving; eases back to {1,1} at rest

// continuous isotropic squash while moving (ticket 01's confirmed Variant A)
// - no rotation/tilt. Called once per frame per actor from the update phase
// (update_game_state for Player, update_enemies for Enemy); draw_actor only
// ever reads the already-eased result.
update_actor_squash :: proc(scale: ^Vec2, moving: bool, dt: f32) {
	target := moving ? ACTOR_MOVING_SCALE : Vec2{1, 1}
	scale.x = exp_approach(scale.x, target.x, ACTOR_SQUASH_RATE, dt)
	scale.y = exp_approach(scale.y, target.y, ACTOR_SQUASH_RATE, dt)
}

// t: 0 -> 1, decelerating toward 1 - the codebase's other general-purpose
// easing idiom alongside exp_approach (editor.odin), used by Sword's swing
// and (art-revamp ticket 02) particle fades
ease_out_cubic :: proc(t: f32) -> f32 {
	u := 1 - clamp(t, 0, 1)
	return 1 - u * u * u
}

draw_game :: proc() {
	begin_drawing()

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

	backdrop_strength := blurred_backdrop_strength()

	// a minimized/zero-sized window would divide-by-zero computing
	// draw_blurred_world's texel_size and hand LoadRenderTexture a 0x0 size -
	// falling back to the direct path here mirrors how
	// camera_visible_world_rect (renderer.odin) already falls back to
	// GAMEPLAY_ZOOM rather than dividing by a zero camera.zoom
	can_blur := backdrop_strength > 0 && game.window_width > 0 && game.window_height > 0

	if can_blur {
		draw_blurred_world(backdrop_strength)
	} else {
		clear_background(rl.DARKGRAY)
		begin_using_camera(game.camera)
		draw_world_contents()
		end_using_camera()
	}

	game.ui_camera = Camera {
		zoom = game.window_height / PIXEL_WINDOW_HEIGHT,
	}

	begin_using_camera(game.ui_camera)
	{
		switch game.program_mode {
		case .Splash:
		// no-op: draw_splash_ui (below, alongside the other modals) draws
		// its own full-screen content
		case .Main_Menu:
		// no-op: draw_main_menu_ui (below, alongside the other modals)
		// draws its own full-screen content
		case .Run_Start:
		// no-op: draw_run_start_ui (below, alongside the other modals)
		// draws its own full-screen content
		case .Selecting:
		// no-op: draw_map_selection_ui (below, alongside the other modals)
		// draws its own full-screen content
		case .Playing:
			// Run-scoped meta-stats (CONTEXT.md's Run entry), not an entity's
			// own Resource indicator (ADR-0011) - screen-space text is right
			// for this, unlike the world-space indicators drawn above. Reads
			// the same Player fields the Run End screen already shows
			// (hud.odin's draw_run_end_ui) and Spawn Trigger Kills_Reached
			// conditions check - no separate counter state.
			draw_hud_counters()
		case .Editing:
			draw_text("Editing", 10, 10, 0, rl.ORANGE)
		}
	}
	end_using_camera()

	if game.program_mode == .Editing {
		draw_editor()
	}

	if game.program_mode == .Splash {
		draw_splash_ui()
	}

	if game.program_mode == .Main_Menu {
		draw_main_menu_ui()
	}

	if game.program_mode == .Run_Start {
		draw_run_start_ui()
	}

	if game.program_mode == .Selecting {
		draw_map_selection_ui()
	}

	if game.run_ended {
		draw_run_end_ui()
	}

	if game.shopping {
		draw_shop_ui()
	}

	// re-checks .Playing (not just the panel_open flag the guard above
	// already restricts to Playing) since F1 can switch into Editing while
	// the panel is still open, and draw_editor also drives the same ui
	// library - see the F8 guard's comment on why two openers in one frame
	// is unsafe
	if game.debug.panel_open && game.program_mode == .Playing {
		draw_debug_panel_ui()
	}

	end_drawing()

	// the tilemap/enemies/player/weapon/debug-visualizer/bullet/particle/
	// damage-number/resource-indicator/editor-overlay draw calls that make up
	// "the game world" - factored out so draw_blurred_world can render the
	// identical content into an offscreen texture instead of straight to the
	// backbuffer, with zero duplication between the two paths.
	draw_world_contents :: proc() {
		draw_tilemap(&game.current_map.tilemap)
		for &enemy in game.enemies {
			draw_enemy(enemy)
			if game.debug.visualizers[.Pathfinding] {
				draw_path(Vec2{enemy.x, enemy.y}, enemy.path)
			}
		}
		draw_actor(game.player.rect, game.player.squash)
		draw_weapon(game.player)
		if game.debug.visualizers[.Colliders] {
			draw_debug_colliders()
		}
		if game.debug.visualizers[.Weapon_Area] {
			draw_debug_weapon_area(game.player)
		}
		if game.debug.visualizers[.Attack_Ranges] {
			draw_debug_attack_ranges()
		}
		if game.debug.visualizers[.Movement_Styles] {
			draw_debug_movement_styles()
		}
		draw_bullets(game.bullets[:])
		draw_enemy_bullets(game.enemy_bullets[:])
		draw_poison_clouds(game.poison_clouds[:])
		draw_pickups(game.pickups[:])
		draw_particles(game.particles[:])
		draw_damage_numbers(game.damage_numbers[:])
		if game.program_mode == .Playing {
			draw_player_resource_indicators(game.player)
		}

		if game.program_mode == .Editing {
			draw_editor_world_overlay()
		}
	}

	// renders draw_world_contents into an offscreen texture, blurs it through
	// a two-pass separable Gaussian shader, and composites the blurred result
	// plus a flat dim rect to the backbuffer instead of drawing straight to
	// it - both blur radius and dim alpha scale linearly with `strength`
	// (0..1) so this fades continuously through blurred_backdrop_strength's
	// own ramp rather than snapping on at a threshold. See hud.odin's
	// blurred_backdrop_strength and ADR-0015.
	draw_blurred_world :: proc(strength: f32) {
		ensure_blur_textures(int(game.window_width), int(game.window_height))

		full_rect := Rect{0, 0, game.window_width, game.window_height}
		texel_size := Vec2{1 / game.window_width, 1 / game.window_height}
		radius := BLUR_MAX_RADIUS_PX * strength

		begin_texture_mode(blur_scene_texture)
		clear_background(rl.DARKGRAY)
		begin_using_camera(game.camera)
		draw_world_contents()
		end_using_camera()
		end_texture_mode()

		begin_texture_mode(blur_pass_texture)
		// no clear needed here - the horizontal pass below is an opaque,
		// full-texture draw (the shader's Gaussian weights sum to 1.0 and
		// blur_scene_texture is itself fully opaque), so every pixel gets
		// overwritten regardless of what was here before
		begin_blur_shader_mode({radius, 0}, texel_size)
		draw_render_texture(blur_scene_texture, full_rect)
		end_shader_mode()
		end_texture_mode()

		begin_blur_shader_mode({0, radius}, texel_size)
		draw_render_texture(blur_pass_texture, full_rect)
		end_shader_mode()

		draw_rectangle(full_rect, rl.Fade(rl.BLACK, BLUR_DIM_ALPHA_MAX * strength))
	}

	// player body: a rectangle (ACTOR_SIZE), continuously squashed in place
	// by `scale` while moving - no rotation/tilt, see update_actor_squash
	// (art-revamp ticket 01). Enemies have their own draw_enemy below.
	draw_actor :: proc(rect: Rect, scale: Vec2) {
		dest := Rect{rect.x, rect.y, ACTOR_SIZE.x * scale.x, ACTOR_SIZE.y * scale.y}
		origin := Vec2{dest.width / 2, dest.height}
		draw_rectangle(dest, ACTOR_PLAYER_COLOR, origin, 0)
	}

	// every enemy is a square: sized by its max health (enemy_body_size),
	// continuously squashed in place while moving like the player, and faded
	// toward ENEMY_MIN_OPACITY as its remaining health drops - replaces the
	// old per-movement-style shape (rect/circle/triangle) and the separate
	// enemy Health bar, which the fade now stands in for
	draw_enemy :: proc(enemy: Enemy) {
		size := enemy_body_size(ENEMY_MAX_HEALTH)
		health_frac := clamp(enemy.health / ENEMY_MAX_HEALTH, 0, 1)
		color := enemy_body_color(movement_style_kind(enemy.movement), health_frac)

		dest := Rect{enemy.x, enemy.y, size * enemy.squash.x, size * enemy.squash.y}
		origin := Vec2{dest.width / 2, dest.height}
		draw_rectangle(dest, color, origin, 0)
	}

	// flat fill for both floor and wall, walls get a darker inset bevel
	// border for thickness (art-revamp ticket 04) - Tile.collides is the only
	// signal used, atlas_coords/Map/persistence are untouched
	draw_tilemap :: proc(tilemap: ^Tilemap) {
		for tile in tilemap.tiles {
			world_rect := Rect {
				f32(tile.world_coords.x) * tilemap.tile_size.x,
				f32(tile.world_coords.y) * tilemap.tile_size.y,
				tilemap.tile_size.x,
				tilemap.tile_size.y,
			}

			color := TILEMAP_WALL_COLOR if tile.collides else TILEMAP_FLOOR_COLOR
			draw_rectangle(world_rect, color)

			if tile.collides {
				bevel: f32 = 3
				inset := Rect {
					world_rect.x + bevel,
					world_rect.y + bevel,
					world_rect.width - bevel * 2,
					world_rect.height - bevel * 2,
				}
				draw_rectangle_lines(inset, TILEMAP_WALL_BEVEL_COLOR, 2)
			}
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

	// bullets reuse the streak shape (art-revamp ticket 03); tint unchanged
	// (player = gold/yellow, enemy = red)
	draw_bullets :: proc(bullets: []Bullet) {
		for bullet in bullets {
			if bullet.explosion_radius > 0 {
				draw_comet(bullet.position, bullet.velocity, BULLET_COMET_LENGTH, BULLET_COMET_WIDTH, rl.YELLOW)
			} else {
				draw_streak(bullet.position, bullet.velocity, BULLET_STREAK_LENGTH, BULLET_STREAK_WIDTH, rl.YELLOW)
			}
		}
	}

	draw_enemy_bullets :: proc(bullets: []Enemy_Bullet) {
		for bullet in bullets {
			draw_streak(bullet.position, bullet.velocity, BULLET_STREAK_LENGTH, BULLET_STREAK_WIDTH, rl.RED)
		}
	}

	WEAPON_WINDUP_PULLBACK :: 6.0 // px pulled back along -aim_dir while a Gun/Magic weapon winds up
	WEAPON_RECOIL_KICK :: 8.0 // px kicked back along -aim_dir during Gun's Automatic Follow-through (SMG)
	FLAME_STAFF_PULSE_SCALE :: 0.35 // extra scale at the start of a Follow-through pulse, decaying to 0
	SWORD_SWING_OUT_TIME :: 0.07 // seconds, ease-out draw-back angle -> follow-through extreme
	SWORD_SWING_RETURN_TIME :: 0.11 // seconds, ease-out extreme -> neutral
	SWORD_ECHO_COUNT :: 3 // motion-trail echoes sampled through the swing (ticket 02)
	SWORD_ECHO_STEP :: 0.025 // seconds between each sampled echo

	// angle offset (added to the pre-swing base angle) at `time_since_resolve`
	// seconds into Sword's Resolve swing-through - a two-phase eased curve (a
	// spring was prototyped and rejected as feeling wrong). Factored out so
	// both the live blade and its motion-trail echoes sample the same curve.
	sword_swing_offset :: proc(arc_degrees, time_since_resolve: f32) -> f32 {
		draw_back := -(arc_degrees / 2)
		extreme := arc_degrees / 2

		if time_since_resolve < SWORD_SWING_OUT_TIME {
			t := ease_out_cubic(time_since_resolve / SWORD_SWING_OUT_TIME)
			return draw_back + (extreme - draw_back) * t
		}

		t := ease_out_cubic((time_since_resolve - SWORD_SWING_OUT_TIME) / SWORD_SWING_RETURN_TIME)
		return extreme - extreme * t
	}

	// draws the player's weapon as a shape by family (art-revamp ticket 02):
	// Gun = rod, Melee = wedge, Magic = rod+orb; pivoting at roughly chest
	// height, rotated to face the player's current aim direction.
	// Windup/Follow-through motion below is transform-only animation on that
	// shape; the "punch" beyond transform comes from the enhanced particle
	// effects spawned during update (spawn_muzzle_flash/spawn_streak_burst,
	// weapon.odin) and Sword's motion-trail echoes drawn below, not from the
	// shape itself.
	draw_weapon :: proc(player: Player) {
		weapon := player.weapon

		pivot := Vec2{player.x, player.y - ACTOR_SIZE.y / 2}
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

		// Sword's Resolve swing-through, plus its motion-trail echoes
		// (ticket 02): several fading copies of the same wedge sampled at
		// slightly earlier points on the same swing curve, not a new
		// particle primitive - collected here, drawn after the main blade
		// below.
		echo_angles: [SWORD_ECHO_COUNT]f32
		echo_count := 0

		if v, is_melee := weapon.variant.(Melee_Weapon); is_melee && weapon.windup_fraction > 0 {
			windup_duration := weapon.windup_fraction / weapon.action_rate
			cycle := 1.0 / weapon.action_rate
			time_since_resolve := (cycle - windup_duration) - weapon.cooldown_timer
			swing_total := f32(SWORD_SWING_OUT_TIME + SWORD_SWING_RETURN_TIME)

			if time_since_resolve >= 0 && time_since_resolve < swing_total {
				base_angle := angle
				angle += sword_swing_offset(v.arc_degrees, time_since_resolve)

				if weapon.kind == .Sword {
					for i in 1 ..= SWORD_ECHO_COUNT {
						t := time_since_resolve - f32(i) * SWORD_ECHO_STEP
						if t < 0 || t >= swing_total {
							continue
						}
						echo_angles[echo_count] = base_angle + sword_swing_offset(v.arc_degrees, t)
						echo_count += 1
					}
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

		switch v in weapon.variant {
		case Gun:
			draw_rod(pivot, angle, WEAPON_GUN_ROD_LENGTH * pulse_scale, WEAPON_GUN_ROD_WIDTH * pulse_scale, WEAPON_GUN_COLOR)

		case Melee_Weapon:
			for i in 0 ..< echo_count {
				fade := 1 - f32(i + 1) / f32(SWORD_ECHO_COUNT + 1)
				draw_wedge(pivot, echo_angles[i], v.range * pulse_scale, WEAPON_MELEE_WEDGE_WIDTH * pulse_scale, rl.Fade(WEAPON_MELEE_COLOR, fade * 0.5))
			}
			draw_wedge(pivot, angle, v.range * pulse_scale, WEAPON_MELEE_WEDGE_WIDTH * pulse_scale, WEAPON_MELEE_COLOR)

		case Magic:
			length := WEAPON_MAGIC_ROD_LENGTH * pulse_scale
			draw_rod(pivot, angle, length, WEAPON_MAGIC_ROD_WIDTH * pulse_scale, WEAPON_MAGIC_ROD_COLOR)
			tip := rotate_point({length, 0}, pivot, angle)
			rl.DrawCircleV(tip, WEAPON_MAGIC_ORB_RADIUS * pulse_scale, WEAPON_MAGIC_ORB_COLOR)
		}
	}

	// F8 debug panel visualizer: outlines the player's and every enemy's actual collision
	// rect (actor_collision_rect - the same box move_actor/melee/bullets hit
	// test against), not just their sprite bounds
	draw_debug_colliders :: proc() {
		rl.DrawRectangleLinesEx(actor_collision_rect(game.player.rect), 1, rl.LIME)
		for enemy in game.enemies {
			rl.DrawRectangleLinesEx(actor_collision_rect(enemy.rect), 1, rl.RED)
		}
	}

	// F8 debug panel visualizer: each enemy's attack-trigger radius - a single circle at
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

	// F8 debug panel visualizer: each enemy's Separation neighbour radius (how close
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

	// F8 debug panel visualizer: the equipped weapon's hit area, shown continuously
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
