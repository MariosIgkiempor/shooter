package shooter

import "core:testing"
import rl "vendor:raylib"

// apply_screen_kind is a plain proc on the global game state (no rendering,
// no timing) so it's tested directly rather than through
// request_screen_change/update_menu_transition's Dismiss-window wait - see
// shop_test.odin's header for the snapshot/restore discipline this follows,
// and run with `odin test . -define:ODIN_TEST_THREADS=1` per
// weapon_test.odin's note on why threads are pinned to 1.

@(test)
test_apply_screen_kind_nil_from_map_selection_starts_playing :: proc(t: ^testing.T) {
	previous_program_mode := game.program_mode
	previous_current := game.menu_transition.current
	defer {
		game.program_mode = previous_program_mode
		game.menu_transition.current = previous_current
	}

	game.program_mode = .Selecting
	game.menu_transition.current = .Map_Selection

	apply_screen_kind(nil)

	testing.expect(
		t,
		game.program_mode == .Playing,
		"picking a map should leave .Selecting for .Playing, not stay stuck showing Map_Selection",
	)
}

@(test)
test_apply_screen_kind_nil_from_shop_stays_playing :: proc(t: ^testing.T) {
	previous_program_mode := game.program_mode
	previous_shopping := game.shopping
	previous_current := game.menu_transition.current
	defer {
		game.program_mode = previous_program_mode
		game.shopping = previous_shopping
		game.menu_transition.current = previous_current
	}

	game.program_mode = .Playing
	game.shopping = true
	game.menu_transition.current = .Shop

	apply_screen_kind(nil)

	testing.expect(t, game.program_mode == .Playing, "closing the Shop overlay should leave program_mode untouched")
	testing.expect(t, !game.shopping, "closing the Shop overlay should clear shopping")
}

@(test)
test_blurred_backdrop_strength_zero_when_no_screen :: proc(t: ^testing.T) {
	previous_run_ended := game.run_ended
	previous_shopping := game.shopping
	previous_program_mode := game.program_mode
	defer {
		game.run_ended = previous_run_ended
		game.shopping = previous_shopping
		game.program_mode = previous_program_mode
	}

	game.run_ended = false
	game.shopping = false
	game.program_mode = .Playing

	testing.expect(
		t,
		blurred_backdrop_strength() == 0,
		"plain Playing (no Shop/Run_End layered on top) should still be current_screen() == nil, so strength must stay 0",
	)
}

@(test)
test_blurred_backdrop_strength_zero_before_world_populated :: proc(t: ^testing.T) {
	previous_program_mode := game.program_mode
	defer {
		game.program_mode = previous_program_mode
	}

	game.program_mode = .Splash

	testing.expect(
		t,
		blurred_backdrop_strength() == 0,
		"Splash has a non-nil current_screen() but program_mode != .Playing (no world yet), so strength must stay 0",
	)
}

@(test)
test_blurred_backdrop_strength_zero_on_main_menu_with_stale_current_map :: proc(t: ^testing.T) {
	previous_program_mode := game.program_mode
	previous_map_name := game.current_map.name
	defer {
		game.program_mode = previous_program_mode
		game.current_map.name = previous_map_name
	}

	// simulates the real post-run state: current_map is never reset once a
	// map's been played (see hud.odin's clone_map call site), so it's still
	// non-empty here even though we're back on Main_Menu - strength must not
	// key off current_map.name, or this would incorrectly blur Main_Menu
	game.program_mode = .Main_Menu
	game.current_map.name = "test_map"

	testing.expect(
		t,
		blurred_backdrop_strength() == 0,
		"Main_Menu must never blur, even with a stale non-empty current_map.name left over from a finished Run",
	)
}

@(test)
test_blurred_backdrop_strength_positive_during_shop :: proc(t: ^testing.T) {
	previous_shopping := game.shopping
	previous_program_mode := game.program_mode
	previous_transition := game.menu_transition
	defer {
		game.shopping = previous_shopping
		game.program_mode = previous_program_mode
		game.menu_transition = previous_transition
	}

	game.shopping = true
	game.program_mode = .Playing
	game.menu_transition.transitioning = false
	// far enough in the past that Reveal is fully complete regardless of
	// exactly when rl.GetTime() is read inside blurred_backdrop_strength
	game.menu_transition.current_entered_at = f32(rl.GetTime()) - 10

	testing.expect(t, blurred_backdrop_strength() > 0, "strength should be positive while shopping over a populated world")
}

@(test)
test_blurred_backdrop_strength_positive_during_run_end :: proc(t: ^testing.T) {
	previous_run_ended := game.run_ended
	previous_program_mode := game.program_mode
	previous_transition := game.menu_transition
	defer {
		game.run_ended = previous_run_ended
		game.program_mode = previous_program_mode
		game.menu_transition = previous_transition
	}

	game.run_ended = true
	game.program_mode = .Playing
	game.menu_transition.transitioning = false
	game.menu_transition.current_entered_at = f32(rl.GetTime()) - 10

	testing.expect(t, blurred_backdrop_strength() > 0, "strength should be positive while run_ended over a populated world")
}

@(test)
test_blurred_backdrop_strength_matches_menu_element_anim_reveal_complete :: proc(t: ^testing.T) {
	previous_shopping := game.shopping
	previous_program_mode := game.program_mode
	previous_transition := game.menu_transition
	defer {
		game.shopping = previous_shopping
		game.program_mode = previous_program_mode
		game.menu_transition = previous_transition
	}

	game.shopping = true
	game.program_mode = .Playing
	game.menu_transition.transitioning = false
	game.menu_transition.current_entered_at = f32(rl.GetTime()) - 10

	// Reveal is long past MENU_THEME.duration here, so menu_element_anim's
	// internal clamp(t, 0, 1) saturates to exactly 1.0 on every call
	// regardless of exactly when each call reads rl.GetTime() - safe to
	// assert bit-exact equality (unlike a genuinely mid-Reveal/mid-Dismiss
	// state, where two independent rl.GetTime() reads a few CPU cycles apart
	// are not guaranteed to be bit-identical - see the tolerance-based test
	// below for that case).
	expected := menu_element_anim(0, 0).alpha
	actual := blurred_backdrop_strength()
	testing.expectf(
		t,
		actual == expected,
		"expected strength to exactly match menu_element_anim(0, 0).alpha (%v), got %v",
		expected,
		actual,
	)
}

@(test)
test_blurred_backdrop_strength_matches_menu_element_anim_mid_dismiss :: proc(t: ^testing.T) {
	previous_shopping := game.shopping
	previous_program_mode := game.program_mode
	previous_transition := game.menu_transition
	defer {
		game.shopping = previous_shopping
		game.program_mode = previous_program_mode
		game.menu_transition = previous_transition
	}

	game.shopping = true
	game.program_mode = .Playing
	game.menu_transition.transitioning = true
	game.menu_transition.dismiss_started_at = f32(rl.GetTime()) - MENU_THEME.duration / 2

	// mid-Dismiss is a genuinely non-clamped point on the ease curve, so two
	// independent rl.GetTime() reads (one inside blurred_backdrop_strength,
	// one here) are not guaranteed bit-identical - compare with a small
	// tolerance rather than ==, same intent as the exact-match test above
	// (driven by the same alpha, not a parallel calculation) without being
	// sensitive to clock-read jitter between the two calls.
	expected := menu_element_anim(0, 0).alpha
	actual := blurred_backdrop_strength()
	testing.expectf(
		t,
		abs(actual - expected) < 0.0001,
		"expected strength to track menu_element_anim(0, 0).alpha (%v), got %v",
		expected,
		actual,
	)
}
