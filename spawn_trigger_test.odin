package shooter

import "core:slice"
import "core:testing"

// update_spawn_triggers/fire_spawn_composition read/mutate game.current_map,
// game.player, game.enemies and game.camera - reset/restore each around
// every test, same discipline weapon_test.odin's suite documents. Run with
// `odin test . -define:ODIN_TEST_THREADS=1` for deterministic results.

// a `composition = {{...}}` slice literal embedded directly in a struct
// literal is backed by static/constant data, not a context.allocator heap
// allocation (confirmed directly: deleting one trips the tracking
// allocator's bad-free check) - exactly like maps.odin's own baked
// Spawn_Trigger literals, which is why clone_map always runs every trigger's
// composition through slice.clone before it's ever mutated or freed. Tests
// that want a composition they can legitimately delete() in teardown need
// the same real allocation, so this helper always goes through slice.clone
// too rather than assigning a bare literal.
single_entry_composition :: proc(movement: Movement_Style, attack: Attack_Style, count: int) -> []Spawn_Composition_Entry {
	return slice.clone([]Spawn_Composition_Entry{{movement_template = movement, attack_template = attack, count = count}})
}

spawn_trigger_test_setup :: proc() -> (previous_map: Map, previous_player: Player, previous_enemies: [dynamic]Enemy, previous_camera: Camera) {
	previous_map = game.current_map
	previous_player = game.player
	previous_enemies = game.enemies
	previous_camera = game.camera

	game.current_map = Map{}
	append(&game.current_map.tilemap.tiles, Tile{world_coords = {0, 0}})
	game.current_map.tilemap.tile_size = {16, 16}
	game.player = Player{}
	game.enemies = {}
	game.camera = Camera{zoom = 1} // avoid a zero zoom's divide-by-zero in camera_visible_world_rect

	return
}

spawn_trigger_test_teardown :: proc(previous_map: Map, previous_player: Player, previous_enemies: [dynamic]Enemy, previous_camera: Camera) {
	for trigger in game.current_map.spawn_triggers {
		delete(trigger.composition)
	}
	delete(game.current_map.spawn_triggers)
	delete(game.current_map.tilemap.tiles)
	delete(game.enemies)

	game.current_map = previous_map
	game.player = previous_player
	game.enemies = previous_enemies
	game.camera = previous_camera
}

@(test)
test_update_spawn_triggers_one_shot_fires_exactly_once_when_condition_crosses :: proc(t: ^testing.T) {
	previous_map, previous_player, previous_enemies, previous_camera := spawn_trigger_test_setup()
	defer spawn_trigger_test_teardown(previous_map, previous_player, previous_enemies, previous_camera)

	append(
		&game.current_map.spawn_triggers,
		Spawn_Trigger {
			condition = Time_Elapsed{seconds = 5},
			mode = One_Shot{},
			composition = single_entry_composition(Grounded{speed = 40}, nil, 1),
		},
	)

	game.player.survival_seconds = 4
	update_spawn_triggers(0)
	testing.expect(t, len(game.enemies) == 0, "a trigger whose condition hasn't crossed yet should not fire")

	game.player.survival_seconds = 5
	update_spawn_triggers(0)
	testing.expect(t, len(game.enemies) == 1, "a One_Shot trigger should fire its whole composition once the condition crosses")
	testing.expect(t, game.current_map.spawn_triggers[0].fired, "a fired trigger should be marked fired")

	update_spawn_triggers(0)
	testing.expect(t, len(game.enemies) == 1, "an already-fired One_Shot trigger should never fire again (edge-triggered)")
}

@(test)
test_update_spawn_triggers_kills_reached_checks_cumulative_total_kills :: proc(t: ^testing.T) {
	previous_map, previous_player, previous_enemies, previous_camera := spawn_trigger_test_setup()
	defer spawn_trigger_test_teardown(previous_map, previous_player, previous_enemies, previous_camera)

	append(
		&game.current_map.spawn_triggers,
		Spawn_Trigger {
			condition = Kills_Reached{count = 3},
			mode = One_Shot{},
			composition = single_entry_composition(Grounded{speed = 40}, nil, 1),
		},
	)

	game.player.kills[.Basic] = 2
	update_spawn_triggers(0)
	testing.expect(t, len(game.enemies) == 0, "total_kills below the threshold should not fire the trigger")

	game.player.kills[.Basic] = 3
	update_spawn_triggers(0)
	testing.expect(t, len(game.enemies) == 1, "total_kills reaching the threshold should fire the trigger")
}

@(test)
test_update_spawn_triggers_repeating_fires_on_activation_then_every_interval_until_duration :: proc(t: ^testing.T) {
	previous_map, previous_player, previous_enemies, previous_camera := spawn_trigger_test_setup()
	defer spawn_trigger_test_teardown(previous_map, previous_player, previous_enemies, previous_camera)

	append(
		&game.current_map.spawn_triggers,
		Spawn_Trigger {
			condition = Time_Elapsed{seconds = 0},
			mode = Repeating{interval = 2, duration = 5},
			composition = single_entry_composition(Grounded{speed = 40}, nil, 1),
		},
	)

	// activation fires on call 1 and skips straight to the next frame
	// (timer seeded to the full interval, no same-frame tick) - so ticking
	// genuinely starts counting from call 2: the next fire lands once
	// elapsed-since-call-2 reaches the 2s interval, i.e. call 3, then call 5.
	// Call 6 pushes elapsed past duration=5, so no fourth fire.
	expected_after_second: [6]int = {1, 1, 2, 2, 3, 3}
	for i in 0 ..< 6 {
		update_spawn_triggers(1)
		testing.expectf(
			t,
			len(game.enemies) == expected_after_second[i],
			"after %v whole seconds, expected %v enemies spawned, got %v",
			i + 1,
			expected_after_second[i],
			len(game.enemies),
		)
	}
}

@(test)
test_update_spawn_triggers_repeating_with_no_duration_runs_indefinitely :: proc(t: ^testing.T) {
	previous_map, previous_player, previous_enemies, previous_camera := spawn_trigger_test_setup()
	defer spawn_trigger_test_teardown(previous_map, previous_player, previous_enemies, previous_camera)

	append(
		&game.current_map.spawn_triggers,
		Spawn_Trigger {
			condition = Time_Elapsed{seconds = 0},
			mode = Repeating{interval = 2, duration = 0},
			composition = single_entry_composition(Grounded{speed = 40}, nil, 1),
		},
	)

	// activation fires on call 1 and skips to the next frame clean (no
	// same-frame tick - see update_spawn_triggers), so ticking starts
	// counting from call 2: with interval=2 > dt=1, that lands a fire every
	// other call after activation (3, 5, 7, 9) - 5 fires total across 10
	// one-second calls, indefinitely (duration<=0 never cuts it off).
	for _ in 0 ..< 10 {
		update_spawn_triggers(1)
	}
	testing.expectf(t, len(game.enemies) == 5, "a duration <= 0 Repeating trigger should keep firing every interval for the whole test, got %v enemies", len(game.enemies))
}

@(test)
test_update_spawn_triggers_repeating_does_not_double_fire_on_a_large_lag_spike_frame :: proc(t: ^testing.T) {
	previous_map, previous_player, previous_enemies, previous_camera := spawn_trigger_test_setup()
	defer spawn_trigger_test_teardown(previous_map, previous_player, previous_enemies, previous_camera)

	append(
		&game.current_map.spawn_triggers,
		Spawn_Trigger {
			condition = Time_Elapsed{seconds = 0},
			mode = Repeating{interval = 1, duration = 0},
			composition = single_entry_composition(Grounded{speed = 40}, nil, 1),
		},
	)

	// a single huge dt (e.g. a hitch/breakpoint/alt-tab resume) on the very
	// frame a Repeating trigger activates must not also satisfy that same
	// frame's interval tick - activation and its first repeat are always at
	// least one frame apart, regardless of dt size.
	update_spawn_triggers(100)
	testing.expectf(t, len(game.enemies) == 1, "a large dt on the activation frame should fire the composition exactly once, got %v enemies", len(game.enemies))
}

@(test)
test_fire_spawn_composition_silently_skips_spawns_past_max_enemies :: proc(t: ^testing.T) {
	previous_map, previous_player, previous_enemies, previous_camera := spawn_trigger_test_setup()
	defer spawn_trigger_test_teardown(previous_map, previous_player, previous_enemies, previous_camera)

	for _ in 0 ..< MAX_ENEMIES - 1 {
		append(&game.enemies, Enemy{})
	}

	composition := []Spawn_Composition_Entry {
		{movement_template = Grounded{speed = 40}, attack_template = nil, count = 3},
	}
	fire_spawn_composition(composition)

	testing.expectf(
		t,
		len(game.enemies) == MAX_ENEMIES,
		"a composition batch that would exceed MAX_ENEMIES should spawn only up to the cap, got %v",
		len(game.enemies),
	)
}
