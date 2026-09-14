package shooter

import "core:testing"

// spawn_timeline_exhausted/check_run_objectives read game.current_map,
// game.enemies and game.player, and end_run additionally writes
// game.menu_transition - reset/restore each around every test, the same
// discipline weapon_test.odin's suite documents. The unit tests reuse
// spawn_trigger_test.odin's setup/teardown pair for the map/player/enemy
// scaffolding; the last test in the file drives every baked Map's real
// timeline through the frame loop's pieces and so snapshots everything they
// write itself (ticket 23 of the content-expansion build). Run with
// `odin test . -define:ODIN_TEST_THREADS=1`.

@(private = "file")
one_shot_trigger :: proc(fired: bool) -> Spawn_Trigger {
	return {condition = Time_Elapsed{seconds = 0}, mode = One_Shot{}, fired = fired}
}

@(private = "file")
repeating_trigger :: proc(duration, elapsed: f32, fired: bool) -> Spawn_Trigger {
	return {
		condition = Time_Elapsed{seconds = 0},
		mode = Repeating{interval = 1, duration = duration},
		fired = fired,
		elapsed = elapsed,
	}
}

@(test)
test_spawn_timeline_exhausted_waits_for_every_trigger_to_fire :: proc(t: ^testing.T) {
	previous_map, previous_player, previous_enemies, previous_camera := spawn_trigger_test_setup()
	defer spawn_trigger_test_teardown(previous_map, previous_player, previous_enemies, previous_camera)

	append(&game.current_map.spawn_triggers, one_shot_trigger(true))
	append(&game.current_map.spawn_triggers, one_shot_trigger(false))

	testing.expect(t, !spawn_timeline_exhausted(), "a timeline with an unfired trigger left is not exhausted")

	game.current_map.spawn_triggers[1].fired = true

	testing.expect(t, spawn_timeline_exhausted(), "once every One_Shot trigger has fired the timeline is exhausted")
}

@(test)
test_spawn_timeline_exhausted_waits_out_a_repeating_triggers_duration :: proc(t: ^testing.T) {
	previous_map, previous_player, previous_enemies, previous_camera := spawn_trigger_test_setup()
	defer spawn_trigger_test_teardown(previous_map, previous_player, previous_enemies, previous_camera)

	append(&game.current_map.spawn_triggers, repeating_trigger(10, 4, true))

	testing.expect(t, !spawn_timeline_exhausted(), "a Repeating trigger still inside its duration is not done")

	game.current_map.spawn_triggers[0].elapsed = 11

	testing.expect(t, spawn_timeline_exhausted(), "a Repeating trigger past its duration is done")
}

// the authoring constraint ADR-0017 introduces: duration <= 0 means
// indefinite, so a Map containing one can never be Cleared
@(test)
test_spawn_timeline_exhausted_is_never_true_for_an_unbounded_repeating_trigger :: proc(t: ^testing.T) {
	previous_map, previous_player, previous_enemies, previous_camera := spawn_trigger_test_setup()
	defer spawn_trigger_test_teardown(previous_map, previous_player, previous_enemies, previous_camera)

	append(&game.current_map.spawn_triggers, repeating_trigger(0, 99999, true))

	testing.expect(
		t,
		!spawn_timeline_exhausted(),
		"an unbounded Repeating trigger should never let the timeline exhaust, however long it has run",
	)
}

@(test)
test_check_run_objectives_clears_only_once_the_field_is_empty :: proc(t: ^testing.T) {
	previous_map, previous_player, previous_enemies, previous_camera := spawn_trigger_test_setup()
	defer spawn_trigger_test_teardown(previous_map, previous_player, previous_enemies, previous_camera)
	previous_transition := game.menu_transition
	defer game.menu_transition = previous_transition
	// a Run always plays a named Map (Selecting precedes Playing), and a
	// clear records that name on the Account - so name one (the cleared
	// set it writes to goes back with the player in teardown)
	previous_pointer := game.active_map_pointer
	defer game.active_map_pointer = previous_pointer

	game.menu_transition = {}
	game.active_map_pointer = enum_identity_string(Map_Name.Desert_Dungeon)
	game.current_map.victory_multiplier = 1.5
	append(&game.current_map.spawn_triggers, one_shot_trigger(true))
	append(&game.enemies, Enemy{})

	check_run_objectives()
	testing.expect(
		t,
		!screen_change_pending_to(.Run_End),
		"an exhausted timeline with enemies still alive should not end the Run",
	)

	clear(&game.enemies)
	check_run_objectives()

	testing.expect(t, screen_change_pending_to(.Run_End), "an exhausted timeline over an empty field should end the Run")
	testing.expect(t, game.last_run_outcome == .Cleared, "clearing the field should settle as Cleared")
}

@(test)
test_check_run_objectives_times_out_once_the_limit_is_reached :: proc(t: ^testing.T) {
	previous_map, previous_player, previous_enemies, previous_camera := spawn_trigger_test_setup()
	defer spawn_trigger_test_teardown(previous_map, previous_player, previous_enemies, previous_camera)
	previous_transition := game.menu_transition
	defer game.menu_transition = previous_transition

	game.menu_transition = {}
	game.current_map.time_limit = 60
	game.current_map.victory_multiplier = 1.5
	// unbounded, so the Run can never clear - only the clock can end it
	append(&game.current_map.spawn_triggers, repeating_trigger(0, 0, true))

	game.player.survival_seconds = 59
	check_run_objectives()
	testing.expect(t, !screen_change_pending_to(.Run_End), "the Run should still be live below the time limit")

	game.player.survival_seconds = 60
	check_run_objectives()

	testing.expect(t, screen_change_pending_to(.Run_End), "reaching the time limit should end the Run")
	testing.expect(t, game.last_run_outcome == .Timed_Out, "running the clock out should settle as Timed_Out")
}

// an untimed Map (time_limit <= 0) is only sane alongside a finite timeline,
// but must never end the Run on the clock alone
@(test)
test_check_run_objectives_never_times_out_an_untimed_map :: proc(t: ^testing.T) {
	previous_map, previous_player, previous_enemies, previous_camera := spawn_trigger_test_setup()
	defer spawn_trigger_test_teardown(previous_map, previous_player, previous_enemies, previous_camera)
	previous_transition := game.menu_transition
	defer game.menu_transition = previous_transition

	game.menu_transition = {}
	game.current_map.time_limit = 0
	append(&game.current_map.spawn_triggers, repeating_trigger(0, 0, true))
	game.player.survival_seconds = 99999

	check_run_objectives()

	testing.expect(t, !screen_change_pending_to(.Run_End), "a time_limit of 0 means untimed, not instantly expired")
}

// first checkbox of ticket 16, the write side: a Cleared Run is the one
// outcome that leaves a permanent mark on the Account (ADR-0022). Names the
// Map through game.active_map_pointer, the way end_run does - current_map
// is a clone with no Map_Name on it.
@(test)
test_a_cleared_run_records_its_map_on_the_account :: proc(t: ^testing.T) {
	previous_map, previous_player, previous_enemies, previous_camera := spawn_trigger_test_setup()
	defer spawn_trigger_test_teardown(previous_map, previous_player, previous_enemies, previous_camera)
	previous_transition := game.menu_transition
	defer game.menu_transition = previous_transition
	previous_pointer := game.active_map_pointer
	defer game.active_map_pointer = previous_pointer

	game.menu_transition = {}
	game.run_ended = false
	game.active_map_pointer = enum_identity_string(Map_Name.Desert_Dungeon)

	end_run(.Cleared)

	testing.expect(t, game.player.maps_cleared[.Desert_Dungeon], "a Cleared Run should record its Map on the Account")
}

// pins the `outcome == .Cleared` condition: the other two outcomes bank
// but leave the ladder alone
@(test)
test_a_killed_run_records_no_clear :: proc(t: ^testing.T) {
	previous_map, previous_player, previous_enemies, previous_camera := spawn_trigger_test_setup()
	defer spawn_trigger_test_teardown(previous_map, previous_player, previous_enemies, previous_camera)
	previous_transition := game.menu_transition
	defer game.menu_transition = previous_transition
	previous_pointer := game.active_map_pointer
	defer game.active_map_pointer = previous_pointer

	game.menu_transition = {}
	game.run_ended = false
	game.active_map_pointer = enum_identity_string(Map_Name.Desert_Dungeon)

	end_run(.Killed)

	testing.expect(t, game.player.maps_cleared == {}, "a Killed Run should leave the cleared set empty")
}

// -- a rung driven headless (ticket 23) --------------------------------------

// how long a body lives before the test's stand-in for the player's aim kills
// it. Long enough that a body crosses the Map on foot (the widened ring below
// puts a spawn ~490px out, a Grunt covers that in ~12 s) so the stranded
// check watches bodies walk rather than stand where the spawn filter already
// vouched for them; short enough that the last batch of every timeline dies
// inside the shortest slack between a timeline's end and its time_limit
// (Pale Keep: 30 s). A per-frame kill budget was rejected: the field is
// empty most of the time, so an unspent budget wipes each batch on its own
// spawn frame and nothing ever moves.
@(private = "file")
HEADLESS_KILL_AFTER_SECONDS :: f32(15)

// how long a Boss has to walk from where the shared-radius spawn filter put it
// into the flood at its own radius before it counts as stranded: the Warden
// takes ~6 s on Pale Keep, and covers 420px in 15 at its 28px/s
@(private = "file")
HEADLESS_BOSS_WALK_IN_SECONDS :: f32(15)

// The integration seam the spec asks for: every baked Map played through as a
// Run, headlessly, in rung order - the Map is cloned, its Spawn Trigger
// timeline ticked through the frame loop's pieces in the order
// update_game_state calls them (minus input, the weapon and the player's
// move), and the Run must settle as Cleared before time_limit with no body
// ever standing where the flood from player_start cannot reach. The two
// failures this exists to catch only appear once the pieces are assembled: a
// spawn landing in a sealed pocket and holding Cleared open forever, and a
// Kind arriving before the field it steers by exists.
//
// The player never moves and cannot die (god mode - the Run is the Map's,
// not the player's), so "reachable" is a probe field flooded from
// player_start per Map: one at the shared radius for the roster, one at the
// Boss's own radius for the Boss, which is what each steers by. Probes rather
// than the live fields, since the shared one is unfilled under the Warden's
// stamp - "no step this frame", not "cannot get to the player". Bodies are
// sampled at their collision box's centre, the point enemy_flow_obstacles
// uses: move_actor parks a body's feet exactly on a wall's top edge, which
// floors into the wall's own row.
//
// Drives `game`, so it needs ODIN_TEST_THREADS=1 like the other wiring tests.
@(test)
test_every_baked_map_is_cleared_by_a_headless_run_that_strands_no_enemy :: proc(t: ^testing.T) {
	previous_map := game.current_map
	previous_player := game.player
	previous_enemies := game.enemies
	previous_enemy_bullets := game.enemy_bullets
	previous_pickups := game.pickups
	previous_particles := game.particles
	previous_damage_numbers := game.damage_numbers
	previous_camera := game.camera
	previous_god_mode := game.debug.god_mode
	previous_field := game.flow_field
	previous_boss_field := game.boss_flow_field
	previous_shake := game.screen_shake_trauma
	previous_transition := game.menu_transition
	previous_pointer := game.active_map_pointer
	previous_run_ended := game.run_ended
	previous_outcome := game.last_run_outcome
	previous_receipt := game.last_run_receipt
	previous_margin := OFFSCREEN_SPAWN_MARGIN
	probe, boss_probe: Flow_Field
	ages: [dynamic]f32
	defer {
		delete_map(game.current_map)
		delete(game.enemies)
		delete(game.enemy_bullets)
		delete(game.pickups)
		delete(game.particles)
		delete(game.damage_numbers)
		flow_field_destroy(&game.flow_field)
		flow_field_destroy(&game.boss_flow_field)
		flow_field_destroy(&probe)
		flow_field_destroy(&boss_probe)
		delete(ages)
		game.current_map = previous_map
		game.player = previous_player
		game.enemies = previous_enemies
		game.enemy_bullets = previous_enemy_bullets
		game.pickups = previous_pickups
		game.particles = previous_particles
		game.damage_numbers = previous_damage_numbers
		game.camera = previous_camera
		game.debug.god_mode = previous_god_mode
		game.flow_field = previous_field
		game.boss_flow_field = previous_boss_field
		game.screen_shake_trauma = previous_shake
		game.menu_transition = previous_transition
		game.active_map_pointer = previous_pointer
		game.run_ended = previous_run_ended
		game.last_run_outcome = previous_outcome
		game.last_run_receipt = previous_receipt
		OFFSCREEN_SPAWN_MARGIN = previous_margin
	}
	game.current_map = {}
	game.enemies = {}
	game.enemy_bullets = {}
	game.pickups = {}
	game.particles = {}
	game.damage_numbers = {}
	game.debug.god_mode = true
	game.flow_field = {}
	game.boss_flow_field = {}

	// headless there is no window, so camera_visible_world_rect is a point and
	// the ring collapses to bare OFFSCREEN_SPAWN_MARGIN beside the player.
	// Widened to the shipped window's ring (map_test.odin's sweep) so bodies
	// spawn where they would in play and have a Map to cross.
	OFFSCREEN_SPAWN_MARGIN = shipped_spawn_ring_radius()

	STEP :: f32(1.0 / 60)

	for name in maps_in_rung_order() {
		delete_map(game.current_map)
		game.current_map = clone_map(maps[name])
		game.active_map_pointer = enum_identity_string(name)
		map_name := game.current_map.name
		tilemap := &game.current_map.tilemap
		start := game.current_map.player_start
		time_limit := game.current_map.time_limit

		game.player = Player{}
		game.player.rect = {start.x, start.y, 0, 0}
		game.player.health = 100
		game.player.max_health = 100
		game.camera = Camera{zoom = 1, target = start}
		clear(&game.enemies)
		clear(&game.enemy_bullets)
		clear(&game.pickups)
		clear(&game.particles)
		clear(&game.damage_numbers)
		game.screen_shake_trauma = 0
		// request_screen_change is a no-op while a change is pending, and the
		// previous Map's end_run left one
		game.menu_transition = {}
		game.run_ended = false
		flow_field_invalidate(&game.flow_field)
		flow_field_invalidate(&game.boss_flow_field)
		clear(&ages)

		flow_field_rebuild(&probe, tilemap, start, i32(FLOW_FIELD_INFLATION_RADIUS))
		// flooded on demand, at the radius of the Boss that shows up
		flow_field_invalidate(&boss_probe)
		if !testing.expectf(
			t,
			probe.filled_count > 0,
			"%v: the flood from player_start filled nothing, and an empty field reaches everywhere",
			map_name,
		) {
			continue
		}

		peak := 0
		stranded := false
		// one frame past the limit, so Timed_Out has its frame to fire and the
		// assertion below can name it
		last_frame := int(time_limit / STEP) + 1
		for frame := 0; frame <= last_frame && !screen_change_pending_to(.Run_End); frame += 1 {
			game.player.survival_seconds += STEP
			player_pos := Vec2{game.player.x, game.player.y}

			obstacles := enemy_flow_obstacles(game.enemies[:])
			flow_field_ensure(&game.flow_field, tilemap, player_pos, i32(FLOW_FIELD_INFLATION_RADIUS), obstacles)

			update_enemy_bullets(STEP)
			update_pickups(STEP)
			update_particles(STEP)
			update_damage_numbers(STEP)

			update_spawn_triggers(STEP)
			for _ in len(ages) ..< len(game.enemies) {
				append(&ages, 0)
			}

			ensure_boss_flow_field()
			update_enemies(STEP)
			peak = max(peak, len(game.enemies))

			for enemy, i in game.enemies {
				if !movement_style_collides_with_terrain[movement_style_kind(enemy.movement)] {
					continue
				}
				box := actor_collision_rect(enemy.rect)
				centre := Vec2{box.x + box.width / 2, box.y + box.height / 2}
				field := &probe
				grace := f32(0)
				if enemy_is_boss(enemy) {
					// the Boss steers by a flood at its own radius, and is
					// placed by one at the shared radius (ticket 21) - so it
					// lands outside its own and walks in by the straight-line
					// fallback, ~6 s on Pale Keep. Held to its own flood once
					// that walk-in is over, so a Boss that never gets there is
					// caught, and a Boss that does is not reported for the walk.
					if !boss_probe.built {
						flow_field_rebuild(
							&boss_probe,
							tilemap,
							start,
							flow_field_radius_for_body(enemy_body_size(enemy.max_health), tilemap.tile_size.x),
						)
					}
					field = &boss_probe
					grace = HEADLESS_BOSS_WALK_IN_SECONDS
				}
				if flow_field_reaches(field, centre) || ages[i] < grace {
					continue
				}
				testing.expectf(
					t,
					false,
					"%v: a %v stands stranded at cell %v (%.1f s, frame %v) where the flood from player_start at its radius %v never reaches",
					map_name,
					enemy.kind,
					world_to_cell_coord(centre, tilemap.tile_size),
					game.player.survival_seconds,
					frame,
					field.radius,
				)
				stranded = true
				break
			}
			if stranded {
				break
			}

			// the player's aim, stood in for: a body dies once it has lived
			// its span. The Boss is spared until the timeline is spent, so its
			// stamp and its own field stay live for the whole of Pale Keep.
			// Reverse, since apply_hit_to_enemy swaps the tail into the hole;
			// `ages` mirrors game.enemies and is removed the same way.
			timeline_spent := spawn_timeline_exhausted()
			for &age in ages {
				age += STEP
			}
			#reverse for enemy, i in game.enemies {
				if ages[i] < HEADLESS_KILL_AFTER_SECONDS {
					continue
				}
				if enemy_is_boss(enemy) && !timeline_spent {
					continue
				}
				apply_hit_to_enemy(i, enemy.health, {enemy.x, enemy.y})
				unordered_remove(&ages, i)
			}

			check_run_objectives()
			free_all(context.temp_allocator)
		}
		if stranded {
			continue
		}

		testing.expectf(
			t,
			screen_change_pending_to(.Run_End),
			"%v: the Run never ended inside its time_limit of %v s (timeline exhausted: %v, %v bodies alive)",
			map_name,
			time_limit,
			spawn_timeline_exhausted(),
			len(game.enemies),
		)
		testing.expectf(
			t,
			game.last_run_outcome == .Cleared,
			"%v: the Run ended %v at %.1f s, not Cleared",
			map_name,
			game.last_run_outcome,
			game.player.survival_seconds,
		)
		testing.expectf(t, game.player.maps_cleared[name], "%v: a Cleared Run should record its rung", map_name)
		// ticket 17 deferred the rung-4 concurrency reading to this Run
		log_info("%v: Cleared at %.1f s of %v, peak %v bodies alive", map_name, game.player.survival_seconds, time_limit, peak)
	}
}
