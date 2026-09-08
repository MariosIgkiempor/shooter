package shooter

import "core:testing"

// God Mode (debug.odin) touches two existing damage seams -
// apply_hit_to_enemy (bullet.odin) and damage_player (main.odin) - rather
// than adding a new one, so these tests exercise those seams directly with
// game.debug.god_mode flipped, same snapshot/restore discipline as
// shop_test.odin's suite applies to game.player (see that file's header
// comment on ODIN_TEST_THREADS=1 - this suite mutates game.enemies/
// game.particles the same way and races the same way if run in parallel).
// damage_player's normal (non-god-mode) path also spawns a particle burst
// and nudges screen_shake_trauma (main.odin/shake.odin), so those are reset
// here too - left dirty, they'd bleed into whichever unrelated test runs
// next in the suite.

@(test)
test_apply_hit_to_enemy_god_mode_kills_in_one_hit_regardless_of_damage :: proc(t: ^testing.T) {
	previous_god_mode := game.debug.god_mode
	previous_enemies := game.enemies
	previous_pickups := game.pickups
	previous_particles := game.particles
	previous_kills := game.player.kills
	defer {
		game.debug.god_mode = previous_god_mode
		game.enemies = previous_enemies
		game.pickups = previous_pickups
		game.particles = previous_particles
		game.player.kills = previous_kills
	}

	game.enemies = {}
	game.pickups = {}
	game.particles = {}
	game.debug.god_mode = true

	append(&game.enemies, Enemy{rect = {x = 0, y = 0}, health = 9999})

	apply_hit_to_enemy(0, 1, Vec2{0, 0})

	testing.expect(t, len(game.enemies) == 0, "a god-mode hit should kill the enemy outright, however small the incoming damage")

	clear(&game.enemies)
	clear(&game.pickups)
	clear(&game.particles)
}

@(test)
test_apply_hit_to_enemy_normal_mode_only_applies_actual_damage :: proc(t: ^testing.T) {
	previous_god_mode := game.debug.god_mode
	previous_enemies := game.enemies
	previous_particles := game.particles
	previous_kills := game.player.kills
	defer {
		game.debug.god_mode = previous_god_mode
		game.enemies = previous_enemies
		game.particles = previous_particles
		game.player.kills = previous_kills
	}

	game.enemies = {}
	game.particles = {}
	game.debug.god_mode = false

	append(&game.enemies, Enemy{rect = {x = 0, y = 0}, health = 100})

	apply_hit_to_enemy(0, 1, Vec2{0, 0})

	testing.expect(t, len(game.enemies) == 1, "outside god mode, a small hit should not kill the enemy")
	testing.expectf(t, game.enemies[0].health == 99, "outside god mode, only the actual damage should be applied, got %v", game.enemies[0].health)

	clear(&game.enemies)
	clear(&game.particles)
}

@(test)
test_damage_player_god_mode_prevents_all_damage :: proc(t: ^testing.T) {
	previous_god_mode := game.debug.god_mode
	previous_health := game.player.health
	previous_run_ended := game.run_ended
	defer {
		game.debug.god_mode = previous_god_mode
		game.player.health = previous_health
		game.run_ended = previous_run_ended
	}

	game.debug.god_mode = true
	game.player.health = 50
	game.run_ended = false

	damage_player(9999)

	testing.expect(t, game.player.health == 50, "God Mode should leave the player's health untouched")
	testing.expect(t, !game.run_ended, "God Mode should never trigger the Run End screen")
}

@(test)
test_damage_player_normal_mode_still_applies_damage :: proc(t: ^testing.T) {
	previous_god_mode := game.debug.god_mode
	previous_health := game.player.health
	previous_particles := game.particles
	previous_trauma := game.screen_shake_trauma
	previous_run_ended := game.run_ended
	defer {
		game.debug.god_mode = previous_god_mode
		game.player.health = previous_health
		game.particles = previous_particles
		game.screen_shake_trauma = previous_trauma
		game.run_ended = previous_run_ended
	}

	game.debug.god_mode = false
	game.player.health = 50
	game.particles = {}
	game.screen_shake_trauma = 0
	game.run_ended = false

	damage_player(10)

	testing.expect(t, game.player.health == 40, "outside God Mode, damage should still apply as normal")

	clear(&game.particles)
}

// a twin-stick shooter routinely lands more than one hit on the player in a
// single frame (e.g. two Melee enemies whose attack_timers both expire that
// frame - enemy.odin's update_enemies calls damage_player once per attacker)
// - without a re-entrancy guard, every hit after the killing one would
// re-enter the health <= 0 branch and bank this Run's Gold again
@(test)
test_damage_player_does_not_double_bank_gold_on_repeated_hits_after_death :: proc(t: ^testing.T) {
	previous_god_mode := game.debug.god_mode
	previous_health := game.player.health
	previous_particles := game.particles
	previous_trauma := game.screen_shake_trauma
	previous_run_ended := game.run_ended
	previous_transition := game.menu_transition
	previous_gold := game.player.gold
	previous_run_start_gold := game.player.run_start_gold
	previous_banked := game.player.banked_progress
	previous_level := game.player.level
	previous_kills := game.player.kills
	previous_survival := game.player.survival_seconds
	previous_gold_earned := game.player.gold_earned
	defer {
		game.debug.god_mode = previous_god_mode
		game.player.health = previous_health
		game.particles = previous_particles
		game.screen_shake_trauma = previous_trauma
		game.run_ended = previous_run_ended
		game.menu_transition = previous_transition
		game.player.gold = previous_gold
		game.player.run_start_gold = previous_run_start_gold
		game.player.banked_progress = previous_banked
		game.player.level = previous_level
		game.player.kills = previous_kills
		game.player.survival_seconds = previous_survival
		game.player.gold_earned = previous_gold_earned
	}

	game.debug.god_mode = false
	game.particles = {}
	game.screen_shake_trauma = 0
	game.run_ended = false
	// run_ended itself only flips once update_menu_transition applies the
	// pending change (hud.odin's apply_screen_kind), which nothing pumps in
	// a unit test - so this asserts on the pending request instead, which is
	// also exactly what end_run's own re-entrancy guard reads.
	game.menu_transition = {}
	game.player.run_start_gold = 0
	game.player.gold = 300
	game.player.gold_earned = 300
	game.player.banked_progress = 0
	game.player.level = 1
	game.player.kills = {}
	game.player.kills[.Basic] = 1
	game.player.survival_seconds = 0

	// the killing hit, then a second hit landing the same "frame" - as if two
	// attackers both connected before update_game_state's next-frame
	// run_ended guard could take effect
	game.player.health = 5
	damage_player(10)
	banked_after_first_hit := game.player.banked_progress

	damage_player(10)

	testing.expect(t, screen_change_pending_to(.Run_End), "sanity check: the first hit should have ended the Run")
	testing.expectf(
		t,
		game.player.banked_progress == banked_after_first_hit,
		"a second hit landing after death should not bank the Run again, got %v then %v",
		banked_after_first_hit,
		game.player.banked_progress,
	)

	clear(&game.particles)
}

// The panel no longer pauses the simulation (ADR-0021), so a Run can end or
// the Shop can open while it's still up, and a dev panel sitting on top of the
// Run End modal would obscure it. apply_screen_kind is the one place that
// writes run_ended/shopping for a Screen change, so it's also where the panel
// is closed; tested there directly for the same reason hud_test.odin tests it
// there - it's a plain proc over global state with no rendering and none of
// request_screen_change's Dismiss-window wait.

@(test)
test_apply_screen_kind_run_end_closes_the_debug_panel :: proc(t: ^testing.T) {
	previous_panel_open := game.debug.panel_open
	previous_run_ended := game.run_ended
	previous_program_mode := game.program_mode
	defer {
		game.debug.panel_open = previous_panel_open
		game.run_ended = previous_run_ended
		game.program_mode = previous_program_mode
	}

	game.debug.panel_open = true

	apply_screen_kind(.Run_End)

	testing.expect(
		t,
		!game.debug.panel_open,
		"a Run ending should close the debug panel rather than let it draw over the Run End modal",
	)
}

@(test)
test_apply_screen_kind_shop_closes_the_debug_panel :: proc(t: ^testing.T) {
	previous_panel_open := game.debug.panel_open
	previous_shopping := game.shopping
	previous_program_mode := game.program_mode
	defer {
		game.debug.panel_open = previous_panel_open
		game.shopping = previous_shopping
		game.program_mode = previous_program_mode
	}

	game.debug.panel_open = true

	apply_screen_kind(.Shop)

	testing.expect(
		t,
		!game.debug.panel_open,
		"opening the Shop should close the debug panel rather than let both drive the ui in one frame",
	)
}

@(test)
test_apply_screen_kind_nil_leaves_the_debug_panel_alone :: proc(t: ^testing.T) {
	previous_panel_open := game.debug.panel_open
	previous_program_mode := game.program_mode
	previous_current := game.menu_transition.current
	defer {
		game.debug.panel_open = previous_panel_open
		game.program_mode = previous_program_mode
		game.menu_transition.current = previous_current
	}

	game.program_mode = .Playing
	game.menu_transition.current = .Shop
	game.debug.panel_open = true

	apply_screen_kind(nil)

	testing.expect(
		t,
		game.debug.panel_open,
		"returning to Playing is not a reason to close the panel - only a Screen opening over it is",
	)
}
