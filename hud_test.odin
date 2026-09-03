package shooter

import "core:testing"

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
