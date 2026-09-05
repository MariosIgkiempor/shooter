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
