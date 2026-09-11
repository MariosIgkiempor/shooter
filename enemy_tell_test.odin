package shooter

import "core:math/linalg"
import "core:testing"

// A Tell_Area's state machine (update_tell_area) takes the body's position,
// the player's rect and a dt explicitly and never reads `game`, so nearly
// everything here drives throwaway values with fixed dt steps and needs no
// ODIN_TEST_THREADS=1 pinning - the enemy_separation_test.odin shape. The
// two exceptions are at the bottom: the "unchanged by scalers" test flips
// the player's Action_Rate stacks to prove the only scaler in the game is
// live, and the wiring test drives update_enemies against `game` to prove
// the tick's shake and damage actually reach it. Both snapshot and restore,
// and both are why this file is still run with
// `odin test . -define:ODIN_TEST_THREADS=1`.
//
// Rendering (the ground zone, the body flash) is deliberately untested, per
// the content-expansion spec.

@(private = "file")
a_tell :: proc(radius, reach, tell_seconds, cooldown: f32, damage: f32 = 10) -> Tell_Area {
	return Tell_Area {
		rotation = {0 = {radius = radius, reach = reach, damage = damage, tell_seconds = tell_seconds}},
		rotation_count = 1,
		cooldown_seconds = cooldown,
	}
}

// a feet-anchored player rect, the same convention Enemy.rect and
// Player.rect share - the collision box hangs above and around this point
@(private = "file")
player_at :: proc(pos: Vec2) -> Rect {
	return {pos.x, pos.y, 0, 0}
}

@(private = "file")
STEP :: f32(0.1)

// drives the machine until the Tell resolves or `max_ticks` pass; returns
// the resolving tick and how many ticks it took (0 if it never resolved)
@(private = "file")
tick_until_resolved :: proc(a: ^Tell_Area, enemy_pos: Vec2, player: Rect, max_ticks: int) -> (Tell_Area_Tick, int) {
	for i in 1 ..= max_ticks {
		tick := update_tell_area(a, enemy_pos, player, STEP)
		if tick.resolved {
			return tick, i
		}
	}
	return {}, 0
}

@(test)
test_a_tell_starts_only_when_standing_still_would_be_hit :: proc(t: ^testing.T) {
	enemy_pos := Vec2{0, 0}

	far := a_tell(28, 40, 0.6, 1)
	tick := update_tell_area(&far, enemy_pos, player_at({200, 0}), STEP)
	testing.expect(t, far.tell_remaining == 0, "a player well outside reach + radius should start no Tell")
	testing.expect(t, !tick.planted, "a body with nothing to claim keeps walking")

	near := a_tell(28, 40, 0.6, 1)
	tick = update_tell_area(&near, enemy_pos, player_at({30, 0}), STEP)
	testing.expect_value(t, near.tell_remaining, f32(0.6))
	testing.expect(t, tick.planted, "a body that has just claimed ground plants")
}

@(test)
test_a_telling_enemy_plants_for_the_whole_tell :: proc(t: ^testing.T) {
	a := a_tell(28, 40, 0.55, 0)
	enemy_pos := Vec2{0, 0}
	player := player_at({30, 0})

	resolved := false
	for i in 1 ..= 10 {
		tick := update_tell_area(&a, enemy_pos, player, STEP)
		testing.expectf(t, tick.planted, "tick %d of a running Tell should plant the body", i)
		if tick.resolved {
			resolved = true
			break
		}
	}
	testing.expect(t, resolved, "the Tell should have resolved within the loop")

	// once resolved with the player out of reach, the body is free to move again
	tick := update_tell_area(&a, enemy_pos, player_at({300, 0}), STEP)
	testing.expect(t, !tick.planted, "after the resolve, a body with nothing in reach should walk")
}

@(test)
test_a_tell_resolves_after_exactly_its_authored_seconds_and_only_once :: proc(t: ^testing.T) {
	a := a_tell(28, 40, 0.55, 5)
	enemy_pos := Vec2{0, 0}
	player := player_at({30, 0})

	// tick 1 starts the Tell (0.55 remaining); ticks 2..6 count 0.5s off it;
	// tick 7 crosses zero
	for i in 1 ..= 6 {
		tick := update_tell_area(&a, enemy_pos, player, STEP)
		testing.expectf(t, !tick.resolved, "tick %d is inside the 0.55s Tell and should not resolve", i)
	}
	tick := update_tell_area(&a, enemy_pos, player, STEP)
	testing.expect(t, tick.resolved, "the tick that crosses the authored seconds should resolve")

	for i in 1 ..= 3 {
		tick = update_tell_area(&a, enemy_pos, player, STEP)
		testing.expectf(t, !tick.resolved, "a resolved Tell should not resolve again on tick %d of the cooldown", i)
	}
}

@(test)
test_the_claimed_centre_is_locked_at_tell_start :: proc(t: ^testing.T) {
	a := a_tell(28, 40, 0.3, 0)
	enemy_pos := Vec2{0, 0}
	start := Vec2{30, 0}

	update_tell_area(&a, enemy_pos, player_at(start), STEP)
	testing.expect_value(t, a.tell_centre, start)

	// the player walks every remaining frame; the disc does not follow
	moved := Vec2{-30, 40}
	resolved_tick: Tell_Area_Tick
	for i in 1 ..= 5 {
		resolved_tick = update_tell_area(&a, enemy_pos, player_at(moved), STEP)
		testing.expectf(t, a.tell_centre == start, "tick %d should leave the locked centre at %v, got %v", i, start, a.tell_centre)
		if resolved_tick.resolved {
			break
		}
	}
	testing.expect(t, resolved_tick.resolved, "the Tell should have resolved within the loop")
}

@(test)
test_the_claimed_centre_is_clamped_to_reach :: proc(t: ^testing.T) {
	reach := f32(40)
	a := a_tell(28, reach, 0.6, 0)
	enemy_pos := Vec2{0, 0}
	// beyond reach, but the disc placed at reach still covers the player
	player_pos := Vec2{reach + 10, 0}

	update_tell_area(&a, enemy_pos, player_at(player_pos), STEP)

	testing.expect(t, a.tell_remaining > 0, "the disc at full reach covers the player, so a Tell should start")
	dist := linalg.distance(a.tell_centre, enemy_pos)
	testing.expectf(t, abs(dist - reach) < 0.001, "the centre should sit exactly reach (%v) from the body, got %v", reach, dist)
	testing.expectf(t, a.tell_centre.y == 0 && a.tell_centre.x > 0, "the centre should lie along the bearing to the player, got %v", a.tell_centre)
}

@(test)
test_walking_out_of_the_claimed_area_avoids_the_hit_but_not_the_resolve :: proc(t: ^testing.T) {
	a := a_tell(28, 40, 0.3, 0, damage = 18)
	enemy_pos := Vec2{0, 0}

	update_tell_area(&a, enemy_pos, player_at({30, 0}), STEP)
	tick, ticks := tick_until_resolved(&a, enemy_pos, player_at({130, 0}), 10)

	testing.expect(t, ticks > 0, "a committed Tell resolves whether or not anyone is still there")
	testing.expect_value(t, tick.damage, f32(0))
}

@(test)
test_standing_in_the_claimed_area_takes_the_hit :: proc(t: ^testing.T) {
	a := a_tell(28, 40, 0.3, 0, damage = 18)
	enemy_pos := Vec2{0, 0}
	player := player_at({30, 0})

	update_tell_area(&a, enemy_pos, player, STEP)
	tick, ticks := tick_until_resolved(&a, enemy_pos, player, 10)

	testing.expect(t, ticks > 0, "the Tell should resolve")
	testing.expect_value(t, tick.damage, f32(18))
}

@(test)
test_the_rotation_advances_on_resolve_and_wraps :: proc(t: ^testing.T) {
	a := Tell_Area {
		rotation = {
			0 = {radius = 28, reach = 40, damage = 5, tell_seconds = 0.3},
			1 = {radius = 28, reach = 40, damage = 5, tell_seconds = 0.6},
		},
		rotation_count = 2,
	}
	enemy_pos := Vec2{0, 0}
	player := player_at({30, 0})

	update_tell_area(&a, enemy_pos, player, STEP)
	testing.expect_value(t, a.tell_remaining, f32(0.3))
	_, ticks := tick_until_resolved(&a, enemy_pos, player, 10)
	testing.expect(t, ticks > 0, "the first Tell should resolve")
	testing.expect_value(t, a.rotation_index, 1)

	update_tell_area(&a, enemy_pos, player, STEP)
	testing.expect_value(t, a.tell_remaining, f32(0.6))
	_, ticks = tick_until_resolved(&a, enemy_pos, player, 10)
	testing.expect(t, ticks > 0, "the second Tell should resolve")
	testing.expect_value(t, a.rotation_index, 0)
}

@(test)
test_the_cooldown_gates_the_next_tell_while_the_body_holds_its_ground :: proc(t: ^testing.T) {
	a := a_tell(28, 40, 0.1, 0.45)
	enemy_pos := Vec2{0, 0}
	player := player_at({30, 0})

	update_tell_area(&a, enemy_pos, player, STEP)
	_, ticks := tick_until_resolved(&a, enemy_pos, player, 10)
	testing.expect(t, ticks > 0, "the first Tell should resolve")

	// 0.45s of cooldown at 0.1s steps: four ticks inside it, the fifth
	// crosses (0.45 rather than 0.5 so f32 accumulation cannot leave a sliver)
	for i in 1 ..= 4 {
		tick := update_tell_area(&a, enemy_pos, player, STEP)
		testing.expectf(t, tick.planted, "cooldown tick %d should still hold the body with the player in reach", i)
		testing.expectf(t, a.tell_remaining == 0, "cooldown tick %d should start no Tell", i)
	}
	update_tell_area(&a, enemy_pos, player, STEP)
	testing.expect(t, a.tell_remaining > 0, "the first tick past the cooldown should start the next Tell")
}

@(test)
test_a_zero_length_tell_resolves_the_instant_it_starts :: proc(t: ^testing.T) {
	a := a_tell(28, 40, 0, 1, damage = 7)
	tick := update_tell_area(&a, {0, 0}, player_at({30, 0}), STEP)

	testing.expect(t, tick.resolved, "a zero-second Tell has no frame of dead time")
	testing.expect_value(t, tick.damage, f32(7))
}

@(test)
test_an_empty_rotation_never_tells :: proc(t: ^testing.T) {
	a := Tell_Area{rotation_count = 0, cooldown_seconds = 1}
	for _ in 1 ..= 5 {
		tick := update_tell_area(&a, {0, 0}, player_at({0, 0}), STEP)
		testing.expect(t, tick == {}, "an unauthored rotation should do nothing at all")
	}
	testing.expect_value(t, a.tell_remaining, f32(0))
}

// ADR-0023: a Tell is absolute seconds, so the number an author tunes is the
// number the player gets. Two things could plausibly scale it and neither
// does. (a) the attack's own pacing - Ranged derives its cadence from
// fire_rate, and a Tell must not derive anything from cooldown_seconds. (b)
// the one scaler in the game, the weapon's Action_Rate upgrade, which
// shrinks a Windup (weapon.odin: windup_fraction / action_rate) and must have
// no path to the enemy side. There is no global time scale to assert
// against; if one ever appears, this is the test to extend.
@(test)
test_tell_duration_is_unchanged_by_anything_that_scales_other_timings :: proc(t: ^testing.T) {
	enemy_pos := Vec2{0, 0}
	player := player_at({30, 0})

	resolve_ticks :: proc(cooldown: f32) -> (first_remaining: f32, ticks: int) {
		a := a_tell(28, 40, 0.55, cooldown)
		update_tell_area(&a, {0, 0}, {30, 0, 0, 0}, STEP)
		first_remaining = a.tell_remaining
		_, ticks = tick_until_resolved(&a, {0, 0}, {30, 0, 0, 0}, 20)
		return
	}

	// (a) pacing
	quick_remaining, quick_ticks := resolve_ticks(0.5)
	slow_remaining, slow_ticks := resolve_ticks(5)
	testing.expect_value(t, quick_remaining, f32(0.55))
	testing.expect_value(t, slow_remaining, f32(0.55))
	testing.expect_value(t, slow_ticks, quick_ticks)

	// (b) the weapon scaler
	previous_stacks := game.player.upgrade_stacks
	defer game.player.upgrade_stacks = previous_stacks
	game.player.upgrade_stacks = {}
	unscaled := weapon_create(.Pistol)
	game.player.upgrade_stacks[.Action_Rate] = upgrade_presets[.Action_Rate].max_stack
	scaled := weapon_create(.Pistol)
	testing.expect(
		t,
		scaled.windup_fraction / scaled.action_rate < unscaled.windup_fraction / unscaled.action_rate,
		"the Action_Rate scaler should visibly shrink a Windup in this process, or the assertion below proves nothing",
	)

	scaled_remaining, scaled_ticks := resolve_ticks(0.5)
	testing.expect_value(t, scaled_remaining, f32(0.55))
	testing.expect_value(t, scaled_ticks, quick_ticks)
}

// the one test that proves the Tell_Area case in update_enemies is wired:
// the pure tests above cannot see the shake or the damage_player call.
@(test)
test_update_enemies_shakes_on_a_tell_resolve_and_damages_only_a_player_still_inside :: proc(t: ^testing.T) {
	previous_enemies := game.enemies
	previous_player := game.player
	previous_trauma := game.screen_shake_trauma
	previous_particles := game.particles
	previous_damage_numbers := game.damage_numbers
	previous_run_ended := game.run_ended
	previous_god_mode := game.debug.god_mode
	defer {
		delete(game.enemies)
		game.enemies = previous_enemies
		game.player = previous_player
		game.screen_shake_trauma = previous_trauma
		delete(game.particles)
		game.particles = previous_particles
		delete(game.damage_numbers)
		game.damage_numbers = previous_damage_numbers
		game.run_ended = previous_run_ended
		game.debug.god_mode = previous_god_mode
	}
	game.enemies = {}
	game.particles = {}
	game.damage_numbers = {}
	game.run_ended = false
	game.debug.god_mode = false
	game.player.health = 100
	game.player.max_health = 100

	run_one_tell :: proc(player_stays: bool) -> (trauma: f32, health: f32) {
		clear(&game.enemies)
		game.player.rect = {30, 0, 0, 0}
		game.player.health = 100
		game.screen_shake_trauma = 0
		append(&game.enemies, Enemy{rect = {0, 0, 0, 0}, squash = {1, 1}, attack = a_tell(28, 40, 0.3, 1, damage = 18)})

		update_enemies(STEP) // starts the Tell, locks the disc on {30, 0}
		if !player_stays {
			game.player.rect = {130, 0, 0, 0}
		}
		for _ in 1 ..= 6 {
			update_enemies(STEP)
		}
		return game.screen_shake_trauma, game.player.health
	}

	trauma, health := run_one_tell(player_stays = false)
	testing.expect(t, trauma > 0, "a dodged resolve should still shake the screen")
	testing.expect_value(t, health, f32(100))

	trauma, health = run_one_tell(player_stays = true)
	testing.expect(t, trauma > 0, "a landed resolve should shake the screen")
	testing.expect_value(t, health, f32(82))
}
