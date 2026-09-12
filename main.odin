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

// the inset bevel drawn inside a colliding tile, so walls read as solid
// blocks rather than flat fills
TILEMAP_WALL_BEVEL_INSET: f32 = 3
TILEMAP_WALL_BEVEL_THICKNESS: f32 = 2
GAMEPLAY_ZOOM: f32 = 1.2
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
	program_mode:           ProgramMode `json:"-"`,
	// accumulated only while program_mode == .Splash (see update_game) -
	// never persisted, since Splash only ever runs once per process launch
	// and `game` starts zero-initialized either way
	splash_elapsed_seconds: f32 `json:"-"`,
	mouse:                  MouseState,
	window_width:           f32,
	window_height:          f32,
	window_title:           cstring,
	camera:                 Camera,
	ui_camera:              Camera,
	player:                 Player,

	// Playing mode's live map state, instantiated (via clone_map) from the
	// baked `maps` table once a map is chosen on the Selecting screen. Never
	// persisted: game_save.json stores only active_map_pointer below, and
	// every launch re-derives current_map fresh from the baked table -
	// writing the full tilemap/spawners out here would just bloat the save
	// file with data that's never read back on load.
	current_map:            Map `json:"-"`,
	// game_save.json's pointer to the active map's identity (a Map_Name's
	// enum-case name - see persistence.odin), read by apply_chosen_map to
	// decide resume-vs-reset player positioning on the next map choice
	active_map_pointer:     string,

	// Editing mode's own map, isolated from current_map - see editor.odin's
	// map switcher. Never persisted: edits are silently discarded on
	// leaving Editing, so there's nothing worth saving between sessions.
	editing_map:            Map `json:"-"`,
	editing_map_path:       string `json:"-"`,
	enemies:                [dynamic]Enemy `json:"-"`,
	bullets:                [dynamic]Bullet `json:"-"`,
	enemy_bullets:          [dynamic]Enemy_Bullet `json:"-"`,
	poison_clouds:          [dynamic]Poison_Cloud `json:"-"`,
	pickups:                [dynamic]Pickup `json:"-"`,
	particles:              [dynamic]Particle `json:"-"`,
	damage_numbers:         [dynamic]Damage_Number `json:"-"`,
	screen_shake_trauma:    f32 `json:"-"`,

	// every Relic's transient runtime (relic.odin) - the orbit phase and
	// tick timer the Orbiting Orb rotates on. Never persisted: the purchased
	// stack counts live on Player (relic_stacks) and the ring is derived
	// from them every frame, so a saved phase would only restore the orbs to
	// a stale angle for one frame on load.
	relic_state:            Relic_State `json:"-"`,

	// the one flow field every terrain-colliding enemy steers by, flooded
	// from the player's cell (flow_field.odin, ADR-0025). Lives here rather
	// than on Map because a Map is serialised to data/maps/*.json and
	// deep-cloned; this is derived runtime state with no business in a level
	// definition. Never persisted - it is re-flooded from current_map on the
	// first frame after any load anyway.
	flow_field:             Flow_Field `json:"-"`,

	// the live Map theme's ambient effects - the mote field and the floor
	// patches (ambience.odin, ADR-0024). Here and not on Map for the flow
	// field's reason: derived runtime state, re-placed from the live Map on
	// the first frame it is seen. Never persisted.
	ambience:               Ambience `json:"-"`,

	// true while the Run End modal is open (see end_run); simulation is
	// paused. Never saved - a save taken mid-modal simply reopens closed,
	// which is fine since no Run state is lost (the Gold settle is already
	// committed by bank_run_gold at the moment the Run ended).
	run_ended:              bool `json:"-"`,

	// how the last Run finished, and what it settled into the wallet
	// (bank_run_gold) - kept only for draw_run_end_ui to display. Neither is
	// a source of truth: game.player.gold/banked_progress/level already
	// reflect the settle, so neither is saved.
	last_run_outcome:       Run_Outcome `json:"-"`,
	last_run_receipt:       Run_Receipt `json:"-"`,

	// true while the Shop panel is open; simulation is paused the same way
	// run_ended already gates update_game_state (see CONTEXT.md's Shop
	// entry). Never saved - a save taken mid-Shop simply reopens closed,
	// same rationale as run_ended.
	shopping:               bool `json:"-"`,

	// true while the Main Menu's "Discard current Run?" panel is showing
	// (draw_main_menu_ui) - set when "Start New Run" is pressed with a Run
	// already in progress (ADR-0013), cleared by either Yes or Cancel. Never
	// saved, same rationale as run_ended/shopping: reopens closed on load,
	// no state is lost since nothing is actually discarded until a starter
	// weapon is picked on the Run_Start screen (start_new_run).
	confirming_new_run:     bool `json:"-"`,

	// the shared Reveal/Dismiss transition record (ADR-0014, hud.odin) that
	// every Screen change goes through via request_screen_change - never
	// saved, same rationale as run_ended/shopping: a save taken mid-
	// transition simply reopens at rest (its zero value already matches a
	// fresh Splash launch, see Menu_Transition's doc comment).
	menu_transition:        Menu_Transition `json:"-"`,

	// F8-toggled debug settings panel (debug.odin): each dev-view visualizer
	// (colliders, weapon area, attack ranges, movement styles, flow field)
	// toggles independently instead of the old single debug_overlay bool
	// that gated all of them together, plus a Gold grant and God Mode. Never
	// saved, same rationale as run_ended/shopping.
	debug:                  Debug_State `json:"-"`,
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

	// resolved before apply_upgrades below, which indexes weapon_presets by
	// weapon.kind and reads magic.spell_kind - a stale value here would be
	// baked into the re-derived stats. A name this build doesn't have is a
	// load failure, not a value to guess at (ADR-0028), and lands on the
	// same default-state fallback the unmarshal error above does.
	variant, variant_ok := weapon_variant_from_save(game.player.weapon_variant_save)
	kind, kind_ok := enum_from_identity_string(Weapon_Kind, game.player.weapon.kind_save)
	fire_mode, fire_mode_ok := enum_from_identity_string(Fire_Mode, game.player.weapon.fire_mode_save)
	if !variant_ok || !kind_ok || !fire_mode_ok {
		log_error(
			"Save file at `{}` names a weapon this build doesn't have (kind `{}`, fire mode `{}`)",
			SAVE_GAME_PATH,
			game.player.weapon.kind_save,
			game.player.weapon.fire_mode_save,
		)
		log_info("Initialising new game state instead.")
		initialize_default_game_state()
		return
	}
	game.player.weapon.variant = variant
	game.player.weapon.kind = kind
	game.player.weapon.fire_mode = fire_mode

	// the file is the authority on what has been Cleared: json.unmarshal
	// leaves a key absent from the file untouched in the long-lived `game`,
	// so the live set is blanked first rather than merged into - a save
	// written before this field existed loads as no clears, which is what
	// it means. A name this build doesn't have is the same load failure as
	// an unknown weapon above (ADR-0028). The loaded identity strings are
	// heap and deliberately not freed - the posture delete_identity_string's
	// doc comment states for load_game, and deviating for one field
	// re-opens exactly the double-free class that helper exists to close.
	game.player.maps_cleared = {}
	for identity, cleared_index in game.player.maps_cleared_save {
		name, name_ok := enum_from_identity_string(Map_Name, identity)
		if !name_ok {
			log_error(
				"Cleared Map {} in `{}` names a Map this build doesn't have",
				cleared_index,
				SAVE_GAME_PATH,
			)
			log_info("Initialising new game state instead.")
			initialize_default_game_state()
			return
		}
		game.player.maps_cleared[name] = true
	}

	// re-derive the loaded Weapon's stats, and move_speed/max_health, from
	// their preset/base-constant baselines plus the just-loaded
	// account_stat_stacks/upgrade_stacks (ADR-0007) - idempotent and a no-op
	// if the save already reflects them correctly, but keeps a hand-edited
	// save file self-healing instead of trusting its damage/action_rate/
	// move_speed/max_health fields to already be consistent with its stacks
	apply_upgrades(
		&game.player.weapon,
		game.player.upgrade_stacks,
		game.player.account_stat_stacks,
	)
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

	game.player.weapon.kind_save = enum_identity_string(game.player.weapon.kind)
	game.player.weapon.fire_mode_save = enum_identity_string(game.player.weapon.fire_mode)
	game.player.weapon_variant_save = weapon_variant_to_save(game.player.weapon.variant)

	// one identity string per Cleared Map, rebuilt from the live set the way
	// save_map rebuilds ambient_save from the live bit_set (ADR-0022,
	// ADR-0028). The strings point into static type info; the temp slice
	// holding them is all there is, and it must not outlive this proc -
	// `game` is long-lived and the temp arena is freed every frame - hence
	// the blank on every way out.
	cleared_save := make([dynamic]string, 0, len(Map_Name), context.temp_allocator)
	for name in Map_Name {
		if game.player.maps_cleared[name] {
			append(&cleared_save, enum_identity_string(name))
		}
	}
	game.player.maps_cleared_save = cleared_save[:]
	defer game.player.maps_cleared_save = nil

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

	// Tunables first: registration captures every Default from the code, then
	// load_tuning applies any Override on top - and load_game re-derives the
	// player's weapon from weapon_presets and their stats from
	// PLAYER_BASE_MOVE_SPEED/PLAYER_BASE_MAX_HEALTH, so it has to see the
	// post-Override values. See tuning.odin.
	register_tunables()
	load_tuning()

	load_game()
	reset_enemies()
	reset_bullets()
	reset_enemy_bullets()
	reset_poison_clouds()
	reset_pickups()
	reset_particles()
	reset_damage_numbers()
	reset_screen_shake()
	reset_relics()
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
	flow_field_destroy(&game.flow_field)
	deinit_tunables()
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

	// every mode, outside update_game_state's pause, on purpose: the world is
	// drawn behind every Screen and the Shop and Run End blur, and ambience
	// is steady-state (CONTEXT.md's Ambient effect entry) - it keeps
	// drifting wherever the world is visible. In Editing it reads the Map
	// being edited, so the Ambient toggles preview live like the colour
	// sliders do.
	update_ambience(rl.GetFrameTime())

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
			// open_editing_map does the rest of the ritual - the free of the
			// previous editing_map, the name adopted into the editor's own
			// buffer so Map mode can type into it, and the per-Map ui state.
			editing_path: string
			if name, ok := enum_from_identity_string(Map_Name, game.active_map_pointer); ok {
				editing_path = map_path_for_name(name)
			}
			open_editing_map(clone_map(game.current_map), editing_path)
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
	if is_key_pressed(.F8) && game.program_mode == .Playing && !game.run_ended && !game.shopping {
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
		// the debug panel is deliberately absent here: it's a non-modal
		// overlay and the simulation keeps running underneath it (ADR-0021),
		// which is the whole point of it - toggling a visualizer has to act on
		// a live scene to be worth anything. Nothing compensates for the extra
		// danger that brings; God Mode already sits on that very panel.
		if game.run_ended || game.shopping {
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
		move_actor(
			&game.player.rect,
			&game.current_map.tilemap,
			input * rl.GetFrameTime() * game.player.move_speed,
		)

		// re-floods only when the player has crossed into a new cell, so the
		// goal is a cell rather than a point and the field is exact rather
		// than merely fresh. Placed here, right after the player moves and
		// before update_spawn_triggers, so every later system this frame -
		// spawn placement included - reads one field describing where the
		// player actually is.
		flow_field_ensure(
			&game.flow_field,
			&game.current_map.tilemap,
			Vec2{game.player.x, game.player.y},
			i32(FLOW_FIELD_INFLATION_RADIUS),
		)

		// blocked mid-Windup: a manually-triggered reload would otherwise
		// silently fail the pending Resolve (gun_can_fire would see
		// reload_timer > 0 once Windup completes), breaking the "a committed
		// Windup always resolves" invariant (story 17)
		if is_key_pressed(.R) && game.player.weapon.windup_timer <= 0 {
			start_reload(&game.player.weapon)
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

		// a click the debug panel owns must not also fire the weapon, now that
		// the panel leaves the game running (ADR-0021): without this an
		// Automatic weapon sprays for as long as the pointer rests on the
		// panel, and a Semi_Automatic one burns a Windup per toggle. Gating
		// the held input rather than just the press covers both, and the same
		// flag also holds the cast particles back so the telegraph doesn't
		// play for an action that never happens. The cost is that the panel's
		// own corner is a dead zone for shooting while it's open - accepted,
		// since it's a dev surface opened deliberately, in the emptiest corner
		// of the screen.
		fire_input :=
			game.player.weapon.fire_mode == .Automatic ? is_mouse_button_down(.LEFT) : is_mouse_button_pressed(.LEFT)
		fire_pressed := fire_input && !ui_hovered

		if fire_pressed {
			try_use_weapon(
				&game.player.weapon,
				player_pos,
				game.player.aim_dir,
				mouse_world,
				game.enemies[:],
			)
		}

		update_magic_cast_particles(
			game.player.weapon,
			player_pos,
			game.player.aim_dir,
			is_mouse_button_down(.LEFT) && !ui_hovered,
		)

		update_bullets(rl.GetFrameTime())
		update_enemy_bullets(rl.GetFrameTime())
		update_poison_clouds(rl.GetFrameTime())
		update_relics(rl.GetFrameTime())
		update_pickups(rl.GetFrameTime())
		update_particles(rl.GetFrameTime())
		update_damage_numbers(rl.GetFrameTime())
		update_player_resource_indicators(rl.GetFrameTime())

		update_spawn_triggers(rl.GetFrameTime())
		update_enemies(rl.GetFrameTime())

		// last, so a kill landing this frame is already reflected in
		// game.enemies when the clear check reads it
		check_run_objectives()
	}
}

// sprites are drawn with a bottom-center origin, so rect.x/y is the anchor at
// the actor's feet; the collision box is the drawn sprite's bounds around that
// anchor, not a top-left rect hanging below it
// fixed logical footprint for both Player and Enemy - matches the old sprite
// document_size (24x24) so hitboxes are unchanged from before the art revamp,
// now independent of the (removed) Animation/atlas system
ACTOR_SIZE := Vec2{24, 24}

actor_collision_rect :: proc(rect: Rect) -> Rect {
	return {rect.x - ACTOR_SIZE.x / 2, rect.y - ACTOR_SIZE.y, ACTOR_SIZE.x, ACTOR_SIZE.y}
}

// moves an actor (player or enemy), resolving against colliding tiles one axis
// at a time so it slides along walls instead of stopping dead on diagonal input.
// Reports whether any tile resolved the move - a slide along a wall counts,
// since one axis was stopped - which is the signal a Charger's dash ends on;
// every other caller discards it.
move_actor :: proc(rect: ^Rect, tilemap: ^Tilemap, delta: Vec2) -> (blocked: bool) {
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
			blocked = true
		} else if delta.x < 0 {
			box.x = tile_rect.x + tile_rect.width
			blocked = true
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
			blocked = true
		} else if delta.y < 0 {
			box.y = tile_rect.y + tile_rect.height
			blocked = true
		}
	}

	// resolved box back to the bottom-center anchor
	rect.x = box.x + box.width / 2
	rect.y = box.y + box.height
	return
}

Player :: struct {
	using rect:          Rect,
	squash:              Vec2 `json:"-"`, // continuous isotropic squash while moving, eased back to {1,1} at rest (draw_actor)
	weapon:              Weapon,
	// Weapon.variant is a union and is tagged json:"-" (see weapon.odin) -
	// this is the plain, persisted view of it, converted explicitly at the
	// save_game/load_game boundary so json.unmarshal's union-decode-order
	// guessing never runs on player-owned weapon state.
	weapon_variant_save: Weapon_Variant_Save,
	aim_dir:             Vec2, // world-space direction toward the mouse, updated every frame

	// -- Account progression (survives Runs - see CONTEXT.md's Account
	// progression entry and ADR-0016). Only ever changed by bank_run_gold
	// (Run-end settle) and try_buy_account_stat (Account_Stat spend).
	banked_progress:     int, // banked Gold counted toward the next Account level, net of the remainder each level-up consumes
	level:               int, // Account level, starts at 1 - gates Account_Stat unlock_level
	account_stat_stacks: [Account_Stat]int, // how many times each Account_Stat has been bought, ever
	// how many times each Relic has been bought, ever - Account progression's
	// behavioural axis alongside account_stat_stacks' numeric one (ADR-0019).
	// The sole source of truth every Relic's live effect is derived from
	// (relic.odin's relic_orb_count), never applied onto anything that could
	// then drift out of sync with it.
	relic_stacks:        [Relic_Kind]int,
	// which Maps have been Cleared at least once - the gate on the Map
	// ladder (ADR-0022): rung 1 is always open, and every rung above it
	// opens on a clear of the rung directly below (map_rung_open). One bool
	// per Map and nothing richer - no clear counts, no best times.
	// Account-scoped, so start_new_run leaves it alone alongside
	// gold/level/account_stat_stacks/relic_stacks.
	//
	// json:"-" is load-bearing. Marshalled as an enum-keyed array this would
	// go out as a positional list of bools, and Map_Name is generated by
	// map_builder from a filename-sorted directory listing - adding
	// boss_keep.json would renumber every case after it and silently credit
	// clears never earned. maps_cleared_save is the persisted form.
	maps_cleared:        [Map_Name]bool `json:"-"`,
	// the on-disk form of maps_cleared: one Map_Name identity string per
	// Cleared Map (ADR-0028), rebuilt by save_game and resolved by load_game
	// - the same shape as Map.ambient/Map.ambient_save. Nil at runtime.
	maps_cleared_save:   []string,

	// true once a starter weapon has been picked for the Run currently in
	// progress (hud.odin's draw_run_start_ui) - load_game uses this to skip
	// straight past ProgramMode.Run_Start on a resumed save, unlike map
	// choice (ProgramMode.Selecting), which re-shows every launch
	// regardless. Cleared by the Run End screen's Continue after death, so
	// (unlike the retired class_chosen) it's re-earned every Run rather than
	// permanent.
	run_started:         bool,
	// The single currency (ADR-0016), spent both in the Shop (weapon tiers
	// and Upgrade stacks) and on the Main Menu (Account_Stat). Account-scoped:
	// unlike every other field in the Run-scoped block below, start_new_run
	// deliberately does *not* reset it - carrying Gold between Runs is what
	// makes a Shop purchase cost Account progression.
	gold:                int,
	// The wallet's balance at the moment this Run started, so bank_run_gold
	// can tell this Run's net take (picked up minus spent) from savings
	// carried in. Set by start_new_run.
	run_start_gold:      int,
	// Run-scoped: gross Gold picked up this Run - never decreases when Gold
	// is spent, unlike the `gold` wallet above. Its only consumer is the Run
	// End receipt (hud.odin's draw_run_end_ui), which needs earned and spent
	// as separate lines to make a Run's spending visible after the fact.
	// Reset to 0 by start_new_run.
	gold_earned:         int,
	// Run-scoped: kills this Run, tallied per Enemy_Kind (see
	// apply_hit_to_enemy). Reset to {} by start_new_run.
	kills:               [Enemy_Kind]int,
	// Run-scoped: seconds actually spent Playing this Run (see
	// update_game_state), checked against the Map's time_limit (ADR-0017).
	// Reset to 0 by start_new_run.
	survival_seconds:    f32,
	// Run-scoped (ADR-0007): how many times each Upgrade_Kind has been
	// bought this Run - the sole source of truth an equipped Weapon's live
	// stats are recomputed from (see apply_upgrades), never mutated
	// in-place. Zeroed by start_new_run.
	upgrade_stacks:      [Upgrade_Kind]int,
	// Run-scoped (ADR-0007), layered on top of any owned Account_Stat
	// Swiftness (see recompute_player_stats) - the live, Upgrade-scaled
	// value, reset by start_new_run.
	move_speed:          f32,
	// Run-scoped (ADR-0007), layered on top of any owned Account_Stat Vigor
	// (see recompute_player_stats) - the live, Upgrade-scaled cap, reset by
	// start_new_run. A Max Health purchase (Upgrade or Vigor) heals current
	// health by the same amount it raises this.
	max_health:          f32,
	// runtime combat state, not persisted (see initialize_program) - a saved
	// game predating this field would otherwise unmarshal it as 0 and trigger
	// an instant Run End on load
	health:              f32 `json:"-"`,
}

PLAYER_BASE_MOVE_SPEED: f32 = 100
PLAYER_BASE_MAX_HEALTH: f32 = 100

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
	swiftness := apply_account_stat_effect(
		PLAYER_BASE_MOVE_SPEED,
		.Swiftness,
		game.player.account_stat_stacks[.Swiftness],
	)
	game.player.move_speed = apply_upgrade_effect(
		swiftness,
		.Move_Speed,
		game.player.upgrade_stacks[.Move_Speed],
	)

	vigor := apply_account_stat_effect(
		PLAYER_BASE_MAX_HEALTH,
		.Vigor,
		game.player.account_stat_stacks[.Vigor],
	)
	game.player.max_health = apply_upgrade_effect(
		vigor,
		.Max_Health,
		game.player.upgrade_stacks[.Max_Health],
	)
}

// how a Run finished (ADR-0017). Cleared is the only outcome that pays a
// victory multiplier; the other two bank at face value.
Run_Outcome :: enum {
	Killed,
	Timed_Out,
	Cleared,
}

// settles the Run and opens the Run End screen (via request_screen_change -
// ADR-0014). The single exit from Playing, shared by all three outcomes, so
// the Gold settle happens in exactly one place no matter how a Run finished.
// Bails once a Run_End Screen change is already pending - more than one
// enemy/bullet can land a killing hit in the same frame (multiple
// update_enemies/update_enemy_bullets hits before the next frame's Playing
// guard kicks in), and without this guard each of those re-enters the
// health <= 0 branch below and double-banks this Run. Checks
// screen_change_pending_to rather than game.run_ended itself, since
// run_ended no longer flips the instant the Run ends - it's deferred until
// Run_End's Dismiss window completes (see update_menu_transition), which
// would otherwise leave this guard open for the whole window instead of
// closing immediately.
end_run :: proc(outcome: Run_Outcome) {
	if game.run_ended || screen_change_pending_to(.Run_End) {
		return
	}

	game.last_run_outcome = outcome
	game.last_run_receipt = bank_run_gold(outcome == .Cleared, game.current_map.victory_multiplier)

	// a clear is the only outcome that leaves a permanent mark on the
	// Account: it opens the rung above (ADR-0022). Recorded here, inside the
	// guard above, so the rung that opens is the rung that was played,
	// exactly once. Named by identity rather than by current_map, which is a
	// clone with no Map_Name on it. A warning rather than an error on a
	// pointer that names nothing: the Run has already banked, and this is
	// not a load failure.
	if outcome == .Cleared {
		if name, name_ok := enum_from_identity_string(Map_Name, game.active_map_pointer); name_ok {
			record_map_cleared(name)
		} else {
			log_warning(
				"Cleared a Run whose active map pointer `{}` names no Map - no rung recorded",
				game.active_map_pointer,
			)
		}
	}

	request_screen_change(.Run_End)
}

// whether every Spawn Trigger on the current Map has fired and finished, so
// no further enemies can arrive (ADR-0017). A One_Shot trigger is done the
// moment it fires; a Repeating one is done once its elapsed clock passes its
// duration - and a Repeating trigger with duration <= 0 means indefinite, so
// a Map containing one can never satisfy this and is by construction
// unclearable. Deriving the win from the timeline this way rather than from
// an authored kill quota is deliberate: fire_spawn_composition silently
// skips spawns once MAX_ENEMIES is reached, so a quota can exceed what the
// Map is ever able to put on the field.
spawn_timeline_exhausted :: proc() -> bool {
	for trigger in game.current_map.spawn_triggers {
		if !trigger.fired {
			return false
		}

		repeating, is_repeating := trigger.mode.(Repeating)
		if !is_repeating {
			continue
		}

		if repeating.duration <= 0 || trigger.elapsed <= repeating.duration {
			return false
		}
	}
	return true
}

// the Run's two non-death endings, checked once per simulated frame (see
// update_game_state). Clearing is checked before the clock so a final kill
// landing on the same frame the limit expires reads as the win it was.
check_run_objectives :: proc() {
	if spawn_timeline_exhausted() && len(game.enemies) == 0 {
		end_run(.Cleared)
		return
	}

	if game.current_map.time_limit > 0 && game.player.survival_seconds >= game.current_map.time_limit {
		end_run(.Timed_Out)
	}
}

// applies enemy damage to the player, ending the Run at 0 hp (ADR-0017, via
// end_run). God Mode (debug.odin) makes the player fully invulnerable -
// skipped before any damage-taken effects (burst/shake) fire, so a god-mode
// hit reads as a clean whiff rather than a damage flash with no health lost.
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
		end_run(.Killed)
	}
}

// restores player hp from a pickup, clamped so healing can't exceed max health
heal_player :: proc(amount: f32) {
	game.player.health = min(game.player.health + amount, game.player.max_health)
}

// resets Run-scoped state to a fresh Run's starting values and equips the
// freshly chosen starter weapon: gold_earned, kills, survival_seconds,
// upgrade_stacks, move_speed, max_health, and the equipped weapon all reset.
// Account progression (gold/banked_progress/level/account_stat_stacks/
// relic_stacks/maps_cleared) stays untouched - Gold included, since ADR-0016
// made it the Account-scoped currency both the Shop and Account_Stat spend
// from, and the cleared set included, since a clear opens a rung for good
// (ADR-0022). Called from the Run_Start screen's weapon-pick button
// (hud.odin's draw_run_start_ui), both for the very first Run and every Run
// after a death.
start_new_run :: proc(starter_kind: Weapon_Kind) {
	clear(&game.enemies)
	clear(&game.bullets)
	clear(&game.enemy_bullets)
	clear(&game.pickups)
	clear(&game.particles)
	reset_screen_shake()
	// the ring itself is Account-scoped and survives (relic_stacks is not
	// reset here, deliberately, same as gold/level/account_stat_stacks) -
	// only its transient phase/tick timer restart with the Run
	reset_relics()

	// deliberately NOT reset: `gold` is the single, Account-scoped currency
	// (ADR-0016). Only the balance this Run starts from is recorded, so
	// bank_run_gold can settle this Run's net take without re-banking
	// savings carried in.
	game.player.run_start_gold = game.player.gold
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

// banked Gold required for level 1 -> 2. Scaled up from the retired
// XP curve's base of 10 by roughly the income ratio between the two
// currencies: XP was minted tens-per-Run by a formula, whereas Gold is
// picked up hundreds-per-Run, so the old base would have unlocked every
// Account_Stat within a single session and left the gates never biting.
LEVEL_BASE: int = 500
LEVEL_GROWTH: f32 = 1.25 // multiplicative growth per level

// banked Gold required to advance from `level` to `level + 1`
gold_required_for_level :: proc(level: int) -> int {
	return int(f32(LEVEL_BASE) * math.pow(f32(LEVEL_GROWTH), f32(level - 1)))
}

// A tile carries no art identity: the tilemap draws as flat fill, so where the
// cell sits and whether it blocks movement is the whole of it. The atlas
// coordinate that used to ride along here went unread by every draw path after
// the art revamp, and kept the editor tied to a tileset palette it no longer
// needed.
Tile :: struct {
	world_coords: Vec2i,
	collides:     bool,
}

Tilemap :: struct {
	tile_size: Vec2,
	tiles:     [dynamic]Tile,
}

// Player renders as a rectangle (ACTOR_SIZE); every enemy renders as a
// square (see draw_enemy), in its own Kind's authored colour - see the
// movement-family palette in enemy.odin.
ACTOR_PLAYER_COLOR :: rl.SKYBLUE

// enemy square size grows with the Kind's own max_health, capped at
// ENEMY_SIZE_MAX so a high-health enemy never grows unreasonably huge.
// Tuned so a 50-health body (the Grunt, the roster's baseline) lands at the
// old fixed ACTOR_SIZE of 24, which is what makes size read as toughness:
// it is derived from health rather than authored, so nothing can be drawn
// heavier than it actually is.
ENEMY_SIZE_MIN: f32 = 10.0
ENEMY_SIZE_MAX: f32 = 48.0
ENEMY_SIZE_PER_MAX_HEALTH: f32 = 0.28

enemy_body_size :: proc(max_health: f32) -> f32 {
	return clamp(
		ENEMY_SIZE_MIN + max_health * ENEMY_SIZE_PER_MAX_HEALTH,
		ENEMY_SIZE_MIN,
		ENEMY_SIZE_MAX,
	)
}

// opacity fades toward ENEMY_MIN_OPACITY as health drops, so a badly-hurt
// enemy visibly reads as weakened at a glance, not just via a health bar
ENEMY_MIN_OPACITY: f32 = 0.25

// `base` is the Kind's own authored colour (Enemy_Preset.color), which the
// preset table takes from the movement-family palette - so the hue says
// which family the body belongs to and the fade says how hurt it is,
// without either channel having to carry the other's meaning.
enemy_body_color :: proc(base: Color, health_frac: f32) -> Color {
	alpha := ENEMY_MIN_OPACITY + (1 - ENEMY_MIN_OPACITY) * clamp(health_frac, 0, 1)
	return rl.Fade(base, alpha)
}

// the body half of a Tell: a pulse that quickens as the Tell runs. The
// prototype's numbers (prototype/boss-tell, Form E).
TELL_FLASH_BASE_MIX: f32 = 0.35 // how far toward white the body sits for the whole Tell
TELL_FLASH_PULSE_MIX: f32 = 0.65 // how much further the pulse pushes it at full progress
TELL_FLASH_PULSE_HZ: f32 = 3 // pulses per Tell at its start...
TELL_FLASH_PULSE_HZ_GAIN: f32 = 6 // ...and how many more it gains by the end

// a quickening pulse toward white while a Tell runs. It moves *value* only:
// hue still means Movement Style family and alpha still means remaining
// health (enemy_body_color), so the target keeps the base's own alpha and
// the blend never touches it. White rather than the zone's amber on purpose
// - green pulsed most of the way toward amber lands on Swarmer yellow, so a
// telling Breaker would read as a Mite at the peak of every pulse.
tell_flash_color :: proc(base: Color, progress: f32) -> Color {
	pulse := 0.5 + 0.5 * math.sin(progress * math.TAU * (TELL_FLASH_PULSE_HZ + progress * TELL_FLASH_PULSE_HZ_GAIN))
	mix := TELL_FLASH_BASE_MIX + TELL_FLASH_PULSE_MIX * pulse * progress
	return color_lerp(base, Color{255, 255, 255, base.a}, mix)
}

// weapon-animation feel. Hoisted out of draw_game so Tunables can hold their
// addresses; the values are unchanged.
WEAPON_WINDUP_PULLBACK: f32 = 6.0 // px pulled back along -aim_dir while a Gun/Magic weapon winds up
WEAPON_RECOIL_KICK: f32 = 8.0 // px kicked back along -aim_dir during Gun's Automatic Follow-through (SMG)
FLAME_STAFF_PULSE_SCALE: f32 = 0.35 // extra scale at the start of a Follow-through pulse, decaying to 0
// how far back along the swing curve each motion-trail echo is sampled, as a
// fraction of the Follow-through window. A fraction rather than the 0.025s it
// used to be, for the same reason SWING_OUT_FRACTION is one: the swing's shape
// is now expressed relative to its own window, so a kind with a different
// follow_through_time trails its echoes over the same portion of its swing
// instead of a fixed slice of somebody else's.
SWORD_ECHO_STEP: f32 = 0.14
SWORD_ECHO_FADE: f32 = 0.5 // alpha multiplier on an echo's already-faded color

ACTOR_SQUASH_RATE: f32 = 12.0 // exp_approach rate, 1/s
ACTOR_MOVING_SCALE := Vec2{1.15, 0.85} // scale_x/scale_y target while moving; eases back to {1,1} at rest

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
		clear_background(rl.GetColor(0x181818))
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

	// cleared here rather than inside each surface's own draw: a surface that
	// isn't drawn this frame can't clear anything, so a panel closed (or an
	// editor left) while the pointer sat over it would otherwise leave the
	// flag stuck true and suppress firing forever. It has to sit *after*
	// draw_world_contents above, since draw_editor_world_overlay reads the
	// flag to hide the hovered-tile outline under an editor window - and
	// *before* the two surfaces below, which re-record into it. Everything
	// reading it outside this window (update_game_state, update_editor) sees
	// last frame's answer, which is the one-frame staleness it's documented
	// for (hud.odin).
	ui_hovered = false

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
		// Editing draws the Map it is editing, not the one Playing left
		// behind: a tile blocked out, a collider marked or a colour moved is
		// visible in the world the moment it changes, which is what makes
		// the editor's colour sliders a preview rather than a guess
		// (content-expansion-build ticket 14). The two are the same place by
		// default - F1 enters on a clone of current_map - so this only
		// diverges once an edit or a map switch makes it diverge.
		map_data := game.program_mode == .Editing ? &game.editing_map : &game.current_map
		draw_tilemap(map_data)
		// the Map theme's light, before anything the world or the player
		// puts on the floor, so it tints the place and never the information
		// on it (ambience.odin)
		draw_ambient_light_wash(map_data, game.camera)
		draw_ground_layer(map_data, game.ambience.patches[:game.ambience.patch_count], game.enemies[:])
		// under the bodies rather than over them: the field is terrain
		// furniture, and it is one drawing for the whole map rather than one
		// per enemy - there are no per-enemy routes to draw any more
		if game.debug.visualizers[.Flow_Field] {
			draw_debug_flow_field()
		}
		for &enemy in game.enemies {
			draw_enemy(enemy)
		}
		draw_actor(game.player.rect, game.player.squash)
		draw_weapon(game.player)
		// gated the same way draw_player_resource_indicators is below: the
		// ring is Playing-only combat furniture, not something the editor's
		// or a menu Screen's view of the world should show
		if game.program_mode == .Playing {
			draw_relics()
		}
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
		// dust in the air above the bodies, under everything that carries
		// information (ambience.odin)
		draw_ambient_motes(map_data, game.ambience.motes[:], game.ambience.time)
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
		clear_background(rl.GetColor(0x181818))
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

	// every enemy is a square: sized by its Kind's max health
	// (enemy_body_size), coloured by its Kind's own hue, continuously
	// squashed in place while moving like the player, and faded toward
	// ENEMY_MIN_OPACITY as its remaining health drops - replaces the old
	// per-movement-style shape (rect/circle/triangle) and the separate enemy
	// Health bar, which the fade now stands in for. Size reads the body's own
	// stamped ceiling rather than its Kind's current one, so a Kind retuned
	// mid-Run cannot shrink a body that is still carrying the health it
	// spawned with - only the next wave picks the change up, exactly as
	// ADR-0020 (Tunables) describes for everything else copied at spawn.
	draw_enemy :: proc(enemy: Enemy) {
		size := enemy_body_size(enemy.max_health)
		// a Kind authored with no health would divide by zero here; it reads
		// as a full bar rather than a NaN that propagates into rl.Fade
		health_frac := enemy.max_health > 0 ? clamp(enemy.health / enemy.max_health, 0, 1) : 1
		color := enemy_body_color(enemy_presets[enemy.kind].color, health_frac)
		// the body says *when*; the ground layer's zone or lane says *where*
		if progress, telling := enemy_tell_progress(enemy); telling {
			color = tell_flash_color(color, progress)
		}

		dest := Rect{enemy.x, enemy.y, size * enemy.squash.x, size * enemy.squash.y}
		origin := Vec2{dest.width / 2, dest.height}
		draw_rectangle(dest, color, origin, 0)
	}

	// flat fill for both floor and wall, walls get a darker inset bevel
	// border for thickness (art-revamp ticket 04) - Tile.collides is the only
	// signal used. Which colours those rules use is the Map's own business
	// (ADR-0024): it takes the whole Map rather than its Tilemap, and the
	// warm sand the three TILEMAP_* constants used to hold is now authored in
	// data/maps/desert_dungeon.json like any other property of that place.
	// The bevel is derived once here rather than per tile.
	//
	// Culled to the camera's visible rect: a ladder rung's map runs to tens of
	// thousands of tiles, of which a few hundred are ever on screen, and this
	// runs twice per frame once draw_blurred_world is compositing. Both paths
	// draw through game.camera, so one bounds query serves them.
	draw_tilemap :: proc(map_data: ^Map) {
		visible := camera_visible_world_rect(game.camera)
		tilemap := &map_data.tilemap
		bevel_color := map_bevel_color(map_data^)

		for tile in tilemap.tiles {
			world_rect := Rect {
				f32(tile.world_coords.x) * tilemap.tile_size.x,
				f32(tile.world_coords.y) * tilemap.tile_size.y,
				tilemap.tile_size.x,
				tilemap.tile_size.y,
			}

			if !world_rect_overlaps_bounds(world_rect, visible) {
				continue
			}

			color := map_data.wall_color if tile.collides else map_data.floor_color
			draw_rectangle(world_rect, color)

			if tile.collides {
				bevel := TILEMAP_WALL_BEVEL_INSET
				inset := Rect {
					world_rect.x + bevel,
					world_rect.y + bevel,
					world_rect.width - bevel * 2,
					world_rect.height - bevel * 2,
				}
				draw_rectangle_lines(inset, bevel_color, TILEMAP_WALL_BEVEL_THICKNESS)
			}
		}
	}

	// the flow field overlay's palette: a near->far ramp for the step stubs,
	// a brighter band every FLOW_FIELD_DEBUG_BAND cells of path distance, and
	// two distinct washes for the two reasons a cell can be unfilled
	FLOW_FIELD_DEBUG_BAND :: 8
	FLOW_FIELD_DEBUG_NEAR :: Color{255, 232, 120, 220}
	FLOW_FIELD_DEBUG_FAR :: Color{70, 120, 190, 160}
	FLOW_FIELD_DEBUG_BAND_TINT :: Color{255, 255, 255, 230}
	FLOW_FIELD_DEBUG_SOURCE :: Color{120, 255, 140, 230}
	FLOW_FIELD_DEBUG_INFLATED :: Color{200, 140, 60, 45}
	FLOW_FIELD_DEBUG_UNREACHED :: Color{220, 40, 40, 55}

	// F8 debug panel visualizer: the shared flow field itself. A filled cell
	// draws a stub toward the cell it steps to, shaded along the distance
	// ramp with a brighter band every FLOW_FIELD_DEBUG_BAND steps so that
	// distance visibly *wraps* walls rather than radiating through them. A
	// cell inside the inflation envelope that the flood never entered draws
	// faintly - that is what explains an enemy on the eight-neighbour
	// fallback - and an unfilled cell outside the envelope draws in the
	// unreachable tint, which is the on-screen proof that a sealed pocket is
	// never filled.
	//
	// Culled to the visible rect before anything else: draw_world_contents
	// runs a second time every frame draw_blurred_world is active, and a
	// map-sized loop twice a frame is not something a dev overlay may cost.
	draw_debug_flow_field :: proc() {
		field := &game.flow_field
		if !flow_field_is_usable(field) {
			return
		}

		visible := camera_visible_world_rect(game.camera)
		min_cell := world_to_cell_coord({visible.min_x, visible.min_y}, field.tile_size)
		max_cell := world_to_cell_coord({visible.max_x, visible.max_y}, field.tile_size)
		min_cell.x = max(min_cell.x, field.origin.x)
		min_cell.y = max(min_cell.y, field.origin.y)
		max_cell.x = min(max_cell.x, field.origin.x + field.size.x - 1)
		max_cell.y = min(max_cell.y, field.origin.y + field.size.y - 1)

		ramp := f32(max(field.max_distance, 1))

		for y in min_cell.y ..= max_cell.y {
			for x in min_cell.x ..= max_cell.x {
				coord := Vec2i{x, y}
				cell, in_bounds := flow_field_cell(field, coord)
				if !in_bounds || cell.collides {
					continue
				}

				center := cell_center_to_world(coord, field.tile_size)

				if cell.distance == FLOW_UNREACHED {
					tint := cell.inflated ? FLOW_FIELD_DEBUG_INFLATED : FLOW_FIELD_DEBUG_UNREACHED
					draw_rectangle(
						{
							center.x - field.tile_size.x / 2,
							center.y - field.tile_size.y / 2,
							field.tile_size.x,
							field.tile_size.y,
						},
						tint,
					)
					continue
				}

				tint :=
					(cell.distance / FLOW_COST_ORTHOGONAL) % FLOW_FIELD_DEBUG_BAND == 0 \
					? FLOW_FIELD_DEBUG_BAND_TINT \
					: color_lerp(FLOW_FIELD_DEBUG_NEAR, FLOW_FIELD_DEBUG_FAR, f32(cell.distance) / ramp)

				if cell.step == .None {
					rl.DrawCircleV(center, field.tile_size.x / 4, FLOW_FIELD_DEBUG_SOURCE)
					continue
				}

				offset := FLOW_STEP_OFFSET[cell.step]
				head := center + Vec2{f32(offset.x), f32(offset.y)} * (field.tile_size / 2)
				rl.DrawLineV(center, head, tint)
				rl.DrawCircleV(head, 1.5, tint)
			}
		}
	}

	// bullets reuse the streak shape (art-revamp ticket 03); tint unchanged
	// (player = gold/yellow, enemy = red)
	draw_bullets :: proc(bullets: []Bullet) {
		for bullet in bullets {
			if bullet.explosion_radius > 0 {
				draw_comet(
					bullet.position,
					bullet.velocity,
					BULLET_COMET_LENGTH,
					BULLET_COMET_WIDTH,
					rl.YELLOW,
				)
			} else {
				draw_streak(
					bullet.position,
					bullet.velocity,
					BULLET_STREAK_LENGTH,
					BULLET_STREAK_WIDTH,
					rl.YELLOW,
				)
			}
		}
	}

	draw_enemy_bullets :: proc(bullets: []Enemy_Bullet) {
		for bullet in bullets {
			draw_streak(
				bullet.position,
				bullet.velocity,
				BULLET_STREAK_LENGTH,
				BULLET_STREAK_WIDTH,
				rl.RED,
			)
		}
	}

	// SWORD_ECHO_COUNT stays here and stays a compile-time constant: it backs
	// the fixed-size echo_angles array below, so it can never be a Tunable.
	// The per-kind echo count that *is* tunable is Weapon_Visual.swing_echo_count,
	// which the min() further down clamps against this capacity.
	SWORD_ECHO_COUNT :: 3

	// draws the player's weapon as a shape by family (art-revamp ticket 02):
	// Gun = rod, Melee = blade, Magic = rod+orb; pivoting at roughly chest
	// height, rotated to face the player's current aim direction.
	//
	// For a Gun or a Magic weapon the Windup/Follow-through motion here is
	// transform-only animation, and the "punch" beyond transform comes from
	// particle effects spawned during update (spawn_muzzle_flash/
	// spawn_streak_burst, weapon.odin). For a melee weapon it is not
	// decoration at all: the pose this computes is the pose its Hit volume
	// rides (hit_volume.odin), so the blade the player watches and the blade
	// that damages are one object. Both read melee_swing_angle_offset and one
	// timer - draw_weapon used to reconstruct the swing's window here from
	// cooldown arithmetic, which is exactly how the two drifted apart.
	draw_weapon :: proc(player: Player) {
		weapon := player.weapon

		// same grip point weapon_muzzle_position measures from (weapon.odin),
		// so the drawn shape and the effects spawned off it stay in step
		pivot := weapon_pivot_position(Vec2{player.x, player.y})
		angle := math.to_degrees(math.atan2(player.aim_dir.y, player.aim_dir.x))
		pulse_scale: f32 = 1

		// Windup (Semi_Automatic): draw the telegraph ahead of Resolve - melee
		// sweeps its arc backward, everything else pulls back along -aim_dir
		if weapon.windup_timer > 0 {
			progress := weapon_windup_progress(weapon)

			switch v in weapon.variant {
			case Melee_Weapon:
				angle -= (weapon_visuals[weapon.kind].swing_arc_degrees / 2) * progress
			case Gun, Magic:
				pivot -= player.aim_dir * WEAPON_WINDUP_PULLBACK * progress
			}
		}

		// Melee's Resolve swing-through, plus its motion-trail echoes
		// (ticket 02): several fading copies of the same blade sampled at
		// slightly earlier points on the same swing curve, not a new
		// particle primitive - collected here, drawn behind the main blade
		// below. How many echoes a weapon leaves is per-kind now
		// (Weapon_Visual.swing_echo_count), so Dagger stays a quick jab and
		// Sword reads as a heavy sweep, rather than a hardcoded kind check.
		echo_angles: [SWORD_ECHO_COUNT]f32
		echo_count := 0

		// Follow-through, both fire modes: a melee weapon's swing (and the
		// window its Hit volume is live for), SMG's recoil-kick,
		// Flame_Staff's per-tick pulse
		if progress, swinging := weapon_follow_through_progress(weapon); swinging {
			switch v in weapon.variant {
			case Melee_Weapon:
				arc := weapon_visuals[weapon.kind].swing_arc_degrees
				base_angle := angle
				angle += melee_swing_angle_offset(arc, progress)

				// motion-trail echoes: the same blade sampled at slightly
				// earlier points on the same curve, not a new particle
				// primitive. How many a weapon leaves is per-kind, so Dagger
				// stays a quick jab and Sword reads as a heavy sweep.
				wanted := min(weapon_visuals[weapon.kind].swing_echo_count, SWORD_ECHO_COUNT)
				for i in 1 ..= wanted {
					p := progress - f32(i) * SWORD_ECHO_STEP
					if p < 0 {
						continue
					}
					echo_angles[echo_count] = base_angle + melee_swing_angle_offset(arc, p)
					echo_count += 1
				}
			case Gun:
				pivot -= player.aim_dir * WEAPON_RECOIL_KICK * (1 - progress)
			case Magic:
				pulse_scale += FLAME_STAFF_PULSE_SCALE * (1 - progress)
			}
		}

		// The weapon draws through the *same* glyph the Shop and Run Start
		// screens show (icon.odin's weapon_icons), mapped by a pivot frame
		// instead of a box frame - one geometry definition, two adapters, so
		// a Shop icon and the thing in your hands can't drift apart
		// (ADR-0018). All the pivot/angle/pulse work above is unchanged; it
		// just feeds the frame now instead of three hand-rolled shape calls.
		glyph := weapon_icons[weapon.kind]

		// echoes first, so the live blade draws over its own trail
		for i in 0 ..< echo_count {
			fade := 1 - f32(i + 1) / f32(SWORD_ECHO_COUNT + 1)
			glyph(
				weapon_pose_frame(weapon, pivot, echo_angles[i], pulse_scale),
				rl.Fade(WEAPON_MELEE_COLOR, fade * SWORD_ECHO_FADE),
				1,
			)
		}

		glyph(weapon_pose_frame(weapon, pivot, angle, pulse_scale), nil, 1)
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
	// attack_range for Melee (contact distance to land a hit), two
	// circles (min_range/max_range) for Ranged marking the band it holds
	// inside to fire rather than chase or retreat, or the engagement range
	// (reach + radius) for Tell_Area - the claimed disc itself is already on
	// the ground layer. Enemies with no Attack Style have no attack, so
	// nothing is drawn for them.
	draw_debug_attack_ranges :: proc() {
		for enemy in game.enemies {
			center := Vec2{enemy.x, enemy.y}
			switch a in enemy.attack {
			case Melee:
				rl.DrawCircleLinesV(center, a.attack_range, rl.ORANGE)
			case Ranged:
				rl.DrawCircleLinesV(center, a.min_range, rl.ORANGE)
				rl.DrawCircleLinesV(center, a.max_range, rl.ORANGE)
			case Tell_Area:
				rl.DrawCircleLinesV(center, tell_area_engagement_range(a), rl.ORANGE)
			case:
			}
		}
	}

	// F8 debug panel visualizer: each enemy's Separation neighbour radius (how close
	// same-Movement-Style enemies must be before they push apart), plus a
	// dedicated ring for Swarmer's surround distance, read from its own Attack
	// Style's engagement range (see swarmer_surround_radius), and one for a
	// Charger's dash distance - the range a Tell starts inside. The circle is
	// the nominal distance only - the contour a Swarmer actually drifts along
	// is a path distance that wraps geometry, which the .Flow_Field overlay
	// shows.
	draw_debug_movement_styles :: proc() {
		player_pos := Vec2{game.player.x, game.player.y}

		for enemy in game.enemies {
			center := Vec2{enemy.x, enemy.y}
			kind := movement_style_kind(enemy.movement)
			if kind == .Inert {
				continue
			}

			rl.DrawCircleLinesV(center, SEPARATION_RADIUS[kind], rl.PURPLE)

			switch m in enemy.movement {
			case Swarmer:
				rl.DrawCircleLinesV(player_pos, swarmer_surround_radius(enemy.attack), rl.PURPLE)
			case Charger:
				rl.DrawCircleLinesV(center, m.dash_distance, rl.PURPLE)
			case Grounded, Floater:
			}
		}
	}

	// F8 debug panel visualizer: the equipped weapon's hit area, shown continuously
	// (unlike Flamethrower's held-only cone particles) so tuning doesn't
	// require attacking to see it. Gun has no player-relative area to show;
	// fireball's AoE lands wherever it hits, not around the player, so it's
	// skipped too.
	//
	// A melee weapon's area is its Hit volume (hit_volume.odin) - the polygons
	// themselves, on the pose they actually ride, rather than a cone drawn from
	// the player's feet that nothing has measured from since ADR-0026. While a
	// swing is live it outlines the volume where it is; at rest it outlines
	// both ends of the arc the swing will travel, so the extent is still
	// readable without attacking. Magic keeps the cone, which is genuinely its
	// shape.
	draw_debug_weapon_area :: proc(player: Player) {
		center := Vec2{player.x, player.y}
		angle := aim_angle_degrees(player.aim_dir)

		draw_cone :: proc(center: Vec2, range, arc_degrees, angle: f32) {
			start := angle - arc_degrees / 2
			end := angle + arc_degrees / 2
			rl.DrawCircleSectorLines(center, range, start, end, 16, rl.SKYBLUE)
		}

		draw_volume :: proc(weapon: Weapon, pivot: Vec2, angle_deg: f32, color: Color) {
			frame := weapon_pose_frame(weapon, pivot, angle_deg, 1)
			points: [MAX_HIT_POLY_POINTS]Vec2
			for poly in weapon_hit_volumes[weapon.kind] {
				world := hit_poly_to_world(frame, poly, points[:])
				for i in 0 ..< len(world) {
					rl.DrawLineV(world[i], world[(i + 1) % len(world)], color)
				}
			}
		}

		switch v in player.weapon.variant {
		case Melee_Weapon:
			weapon := player.weapon
			pivot := weapon_pivot_position(center)
			arc := weapon_visuals[weapon.kind].swing_arc_degrees

			if progress, swinging := weapon_follow_through_progress(weapon); swinging {
				draw_volume(weapon, pivot, angle + melee_swing_angle_offset(arc, progress), rl.SKYBLUE)
				return
			}
			draw_volume(weapon, pivot, angle - arc / 2, rl.Fade(rl.SKYBLUE, 0.5))
			draw_volume(weapon, pivot, angle + arc / 2, rl.Fade(rl.SKYBLUE, 0.5))
		case Magic:
			switch v.spell_kind {
			case .Flamethrower:
				draw_cone(center, v.range, v.arc_degrees, angle)
			case .Poison_Cloud:
				rl.DrawCircleLinesV(center, v.cast_range, rl.SKYBLUE)
			case .Lightning_Bolt:
				// from the muzzle, not `center`: the cone above is drawn from
				// the player because cast_flamethrower_tick measures from
				// `origin`, and a bolt does not
				muzzle := weapon_muzzle_position(player.weapon, center, player.aim_dir)
				rl.DrawLineV(muzzle, muzzle + player.aim_dir * v.range, rl.SKYBLUE)
			case .Fireball:
			}
		case Gun:
		}
	}

}

program_should_exit :: proc() -> bool {
	return rl.WindowShouldClose()
}

// camera-follow feel. These were bare proc-local literals until the Tunable
// registry needed addresses for them - naming them changed no behaviour, but
// it's what makes camera follow tunable at all, and it's the highest-leverage
// feel knob in a twin-stick.
CAMERA_MIN_SPEED: f32 = 30.0 // px/s floor once the camera is chasing at all
CAMERA_MIN_EFFECT_LENGTH: f32 = 10.0 // deadzone radius - below this the camera doesn't move
CAMERA_FRACTION_SPEED: f32 = 0.8 // linear term of the catch-up speed
CAMERA_SPEED_CURVE: f32 = 0.1 // quadratic term: speed grows with distance^2, so a far camera snaps back hard
CAMERA_ZOOM_EASE_RATE: f32 = 8 // exp_approach rate back to GAMEPLAY_ZOOM, 1/s

update_camera_center_smooth_follow :: proc(
	camera: ^Camera,
	player: ^Player,
	delta: f32,
	width: int,
	height: int,
) {
	camera.offset = Vec2{f32(width) / 2.0, f32(height) / 2.0}
	diff := Vec2{player.rect.x, player.rect.y} - camera.target
	length := rl.Vector2Length(diff)

	if (length > CAMERA_MIN_EFFECT_LENGTH) {
		speed := max(CAMERA_FRACTION_SPEED * length * (CAMERA_SPEED_CURVE * length), CAMERA_MIN_SPEED)
		camera.target = camera.target + diff * (speed * delta / length)
	}

	// gameplay zoom is independent of the editor's: ease back to it, so
	// leaving the editor animates the zoom as well as the position
	camera.zoom = exp_approach(camera.zoom, GAMEPLAY_ZOOM, CAMERA_ZOOM_EASE_RATE, delta)
}
