package shooter

import "core:testing"

// spawn_timeline_exhausted/check_run_objectives read game.current_map,
// game.enemies and game.player, and end_run additionally writes
// game.menu_transition - reset/restore each around every test, the same
// discipline weapon_test.odin's suite documents. Reuses
// spawn_trigger_test.odin's setup/teardown pair for the map/player/enemy
// scaffolding. Run with `odin test . -define:ODIN_TEST_THREADS=1`.

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

	game.menu_transition = {}
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
