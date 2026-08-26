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
	previous_xp_orbs := game.xp_orbs
	previous_pickups := game.pickups
	previous_particles := game.particles
	defer {
		game.debug.god_mode = previous_god_mode
		game.enemies = previous_enemies
		game.xp_orbs = previous_xp_orbs
		game.pickups = previous_pickups
		game.particles = previous_particles
	}

	game.enemies = {}
	game.xp_orbs = {}
	game.pickups = {}
	game.particles = {}
	game.debug.god_mode = true

	append(&game.enemies, Enemy{rect = {x = 0, y = 0}, health = 9999})

	apply_hit_to_enemy(0, 1, Vec2{0, 0})

	testing.expect(t, len(game.enemies) == 0, "a god-mode hit should kill the enemy outright, however small the incoming damage")

	clear(&game.enemies)
	clear(&game.xp_orbs)
	clear(&game.pickups)
	clear(&game.particles)
}

@(test)
test_apply_hit_to_enemy_normal_mode_only_applies_actual_damage :: proc(t: ^testing.T) {
	previous_god_mode := game.debug.god_mode
	previous_enemies := game.enemies
	previous_particles := game.particles
	defer {
		game.debug.god_mode = previous_god_mode
		game.enemies = previous_enemies
		game.particles = previous_particles
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
	previous_game_over := game.game_over
	defer {
		game.debug.god_mode = previous_god_mode
		game.player.health = previous_health
		game.game_over = previous_game_over
	}

	game.debug.god_mode = true
	game.player.health = 50
	game.game_over = false

	damage_player(9999)

	testing.expect(t, game.player.health == 50, "God Mode should leave the player's health untouched")
	testing.expect(t, !game.game_over, "God Mode should never trigger game-over")
}

@(test)
test_damage_player_normal_mode_still_applies_damage :: proc(t: ^testing.T) {
	previous_god_mode := game.debug.god_mode
	previous_health := game.player.health
	previous_particles := game.particles
	previous_trauma := game.screen_shake_trauma
	defer {
		game.debug.god_mode = previous_god_mode
		game.player.health = previous_health
		game.particles = previous_particles
		game.screen_shake_trauma = previous_trauma
	}

	game.debug.god_mode = false
	game.player.health = 50
	game.particles = {}
	game.screen_shake_trauma = 0

	damage_player(10)

	testing.expect(t, game.player.health == 40, "outside God Mode, damage should still apply as normal")

	clear(&game.particles)
}
