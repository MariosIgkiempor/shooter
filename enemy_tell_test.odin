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
// the content-expansion spec - except for the one property of the flash that
// is a correctness fact rather than a look: it has to move a body of any
// value, or the Boss's Tell has no "when" half.

@(private = "file")
a_tell :: proc(radius, reach, tell_seconds, cooldown: f32, damage: f32 = 10) -> Tell_Area {
	return Tell_Area {
		phases = {
			0 = {
				rotation = {0 = {radius = radius, reach = reach, damage = damage, tell_seconds = tell_seconds}},
				rotation_count = 1,
				cooldown_seconds = cooldown,
			},
		},
		phase_count = 1,
	}
}

// three phases whose Tells differ in length, so which phase a body is in
// can be read off tell_remaining alone. Thresholds are the Warden's
// (0.66 / 0.33); recovery quickens phase by phase, per boss-telegraph-and-
// phase-feel.
@(private = "file")
a_phased_tell :: proc() -> Tell_Area {
	return Tell_Area {
		phases = {
			0 = {
				rotation = {0 = {radius = 28, reach = 40, damage = 5, tell_seconds = 0.3}, 1 = {radius = 28, reach = 40, damage = 6, tell_seconds = 0.3}},
				rotation_count = 2,
				cooldown_seconds = 1.5,
			},
			1 = {
				enter_below = 0.66,
				rotation = {0 = {radius = 28, reach = 40, damage = 7, tell_seconds = 0.5}},
				rotation_count = 1,
				cooldown_seconds = 1.15,
			},
			2 = {
				enter_below = 0.33,
				rotation = {0 = {radius = 28, reach = 40, damage = 9, tell_seconds = 0.7}},
				rotation_count = 1,
				cooldown_seconds = 0.8,
			},
		},
		phase_count = 3,
	}
}

// update_tell_area with the body at full health unless a test says
// otherwise - the health fraction is the phase machine's only input, and
// every test that is not about phases wants it out of the way
@(private = "file")
step_tell :: proc(a: ^Tell_Area, enemy_pos: Vec2, player: Rect, dt: f32, health: f32 = 1) -> Tell_Area_Tick {
	return update_tell_area(a, enemy_pos, player, health, dt)
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
tick_until_resolved :: proc(a: ^Tell_Area, enemy_pos: Vec2, player: Rect, max_ticks: int, health: f32 = 1) -> (Tell_Area_Tick, int) {
	for i in 1 ..= max_ticks {
		tick := step_tell(a, enemy_pos, player, STEP, health)
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
	tick := step_tell(&far, enemy_pos, player_at({200, 0}), STEP)
	testing.expect(t, far.tell_remaining == 0, "a player well outside reach + radius should start no Tell")
	testing.expect(t, !tick.planted, "a body with nothing to claim keeps walking")

	near := a_tell(28, 40, 0.6, 1)
	tick = step_tell(&near, enemy_pos, player_at({30, 0}), STEP)
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
		tick := step_tell(&a, enemy_pos, player, STEP)
		testing.expectf(t, tick.planted, "tick %d of a running Tell should plant the body", i)
		if tick.resolved {
			resolved = true
			break
		}
	}
	testing.expect(t, resolved, "the Tell should have resolved within the loop")

	// once resolved with the player out of reach, the body is free to move again
	tick := step_tell(&a, enemy_pos, player_at({300, 0}), STEP)
	testing.expect(t, !tick.planted, "after the resolve, a body with nothing in reach should walk")
}

@(test)
test_a_tell_resolves_once_its_authored_seconds_have_run_and_only_once :: proc(t: ^testing.T) {
	a := a_tell(28, 40, 0.55, 5)
	enemy_pos := Vec2{0, 0}
	player := player_at({30, 0})

	// tick 1 starts the Tell (0.55 remaining) and, like a Windup's start
	// frame (weapon.odin), does not count against it; ticks 2..6 take 0.5s
	// off; tick 7 crosses zero
	for i in 1 ..= 6 {
		tick := step_tell(&a, enemy_pos, player, STEP)
		testing.expectf(t, !tick.resolved, "tick %d is inside the 0.55s Tell and should not resolve", i)
	}
	tick := step_tell(&a, enemy_pos, player, STEP)
	testing.expect(t, tick.resolved, "the tick that crosses the authored seconds should resolve")

	for i in 1 ..= 3 {
		tick = step_tell(&a, enemy_pos, player, STEP)
		testing.expectf(t, !tick.resolved, "a resolved Tell should not resolve again on tick %d of the cooldown", i)
	}
}

@(test)
test_the_claimed_centre_is_locked_at_tell_start :: proc(t: ^testing.T) {
	a := a_tell(28, 40, 0.3, 0)
	enemy_pos := Vec2{0, 0}
	start := Vec2{30, 0}

	step_tell(&a, enemy_pos, player_at(start), STEP)
	testing.expect_value(t, a.tell_centre, start)

	// the player walks every remaining frame; the disc does not follow
	moved := Vec2{-30, 40}
	resolved_tick: Tell_Area_Tick
	for i in 1 ..= 5 {
		resolved_tick = step_tell(&a, enemy_pos, player_at(moved), STEP)
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

	step_tell(&a, enemy_pos, player_at(player_pos), STEP)

	testing.expect(t, a.tell_remaining > 0, "the disc at full reach covers the player, so a Tell should start")
	dist := linalg.distance(a.tell_centre, enemy_pos)
	testing.expectf(t, abs(dist - reach) < 0.001, "the centre should sit exactly reach (%v) from the body, got %v", reach, dist)
	testing.expectf(t, a.tell_centre.y == 0 && a.tell_centre.x > 0, "the centre should lie along the bearing to the player, got %v", a.tell_centre)
}

@(test)
test_walking_out_of_the_claimed_area_avoids_the_hit_but_not_the_resolve :: proc(t: ^testing.T) {
	a := a_tell(28, 40, 0.3, 0, damage = 18)
	enemy_pos := Vec2{0, 0}

	step_tell(&a, enemy_pos, player_at({30, 0}), STEP)
	tick, ticks := tick_until_resolved(&a, enemy_pos, player_at({130, 0}), 10)

	testing.expect(t, ticks > 0, "a committed Tell resolves whether or not anyone is still there")
	testing.expect_value(t, tick.damage, f32(0))
}

@(test)
test_standing_in_the_claimed_area_takes_the_hit :: proc(t: ^testing.T) {
	a := a_tell(28, 40, 0.3, 0, damage = 18)
	enemy_pos := Vec2{0, 0}
	player := player_at({30, 0})

	step_tell(&a, enemy_pos, player, STEP)
	tick, ticks := tick_until_resolved(&a, enemy_pos, player, 10)

	testing.expect(t, ticks > 0, "the Tell should resolve")
	testing.expect_value(t, tick.damage, f32(18))
}

@(test)
test_the_rotation_advances_on_resolve_and_wraps :: proc(t: ^testing.T) {
	a := Tell_Area {
		phases = {
			0 = {
				rotation = {
					0 = {radius = 28, reach = 40, damage = 5, tell_seconds = 0.3},
					1 = {radius = 28, reach = 40, damage = 5, tell_seconds = 0.6},
				},
				rotation_count = 2,
			},
		},
		phase_count = 1,
	}
	enemy_pos := Vec2{0, 0}
	player := player_at({30, 0})

	step_tell(&a, enemy_pos, player, STEP)
	testing.expect_value(t, a.tell_remaining, f32(0.3))
	_, ticks := tick_until_resolved(&a, enemy_pos, player, 10)
	testing.expect(t, ticks > 0, "the first Tell should resolve")
	testing.expect_value(t, a.rotation_index, 1)

	step_tell(&a, enemy_pos, player, STEP)
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

	step_tell(&a, enemy_pos, player, STEP)
	_, ticks := tick_until_resolved(&a, enemy_pos, player, 10)
	testing.expect(t, ticks > 0, "the first Tell should resolve")

	// 0.45s of cooldown at 0.1s steps: four ticks inside it, the fifth
	// crosses (0.45 rather than 0.5 so f32 accumulation cannot leave a sliver)
	for i in 1 ..= 4 {
		tick := step_tell(&a, enemy_pos, player, STEP)
		testing.expectf(t, tick.planted, "cooldown tick %d should still hold the body with the player in reach", i)
		testing.expectf(t, a.tell_remaining == 0, "cooldown tick %d should start no Tell", i)
	}
	step_tell(&a, enemy_pos, player, STEP)
	testing.expect(t, a.tell_remaining > 0, "the first tick past the cooldown should start the next Tell")
}

@(test)
test_a_zero_length_tell_resolves_the_instant_it_starts :: proc(t: ^testing.T) {
	a := a_tell(28, 40, 0, 1, damage = 7)
	tick := step_tell(&a, {0, 0}, player_at({30, 0}), STEP)

	testing.expect(t, tick.resolved, "a zero-second Tell has no frame of dead time")
	testing.expect_value(t, tick.damage, f32(7))
}

@(test)
test_an_empty_rotation_never_tells :: proc(t: ^testing.T) {
	no_rotation := Tell_Area{phases = {0 = {rotation_count = 0, cooldown_seconds = 1}}, phase_count = 1}
	no_phase := Tell_Area{phases = {0 = {rotation_count = 1, cooldown_seconds = 1}}, phase_count = 0}
	for a in ([]^Tell_Area{&no_rotation, &no_phase}) {
		for _ in 1 ..= 5 {
			tick := step_tell(a, {0, 0}, player_at({0, 0}), STEP)
			testing.expect(t, tick == {}, "an unauthored rotation or phase list should do nothing at all")
		}
		testing.expect_value(t, a.tell_remaining, f32(0))
	}
}

// -- phases ----------------------------------------------------------------

@(test)
test_a_phase_is_entered_only_strictly_below_its_threshold :: proc(t: ^testing.T) {
	phase_at :: proc(health: f32) -> int {
		a := a_phased_tell()
		step_tell(&a, {0, 0}, player_at({300, 0}), STEP, health) // nothing in reach: only the phase read happens
		return a.phase_index
	}
	testing.expect_value(t, phase_at(1), 0)
	testing.expect_value(t, phase_at(0.66), 0)
	testing.expect_value(t, phase_at(0.65), 1)
	testing.expect_value(t, phase_at(0.33), 1)
	testing.expect_value(t, phase_at(0.2), 2) // one hit through two thresholds lands in the last, not the middle
}

@(test)
test_a_phase_advance_waits_for_the_running_tell_to_resolve :: proc(t: ^testing.T) {
	a := a_phased_tell()
	enemy_pos := Vec2{0, 0}
	player := player_at({30, 0})

	step_tell(&a, enemy_pos, player, STEP) // phase 0's 0.3s Tell starts
	testing.expect_value(t, a.tell_remaining, f32(0.3))

	tick, ticks := tick_until_resolved(&a, enemy_pos, player, 10, health = 0.2)
	testing.expect(t, ticks > 0, "the committed Tell should still resolve")
	testing.expect_value(t, a.phase_index, 0)
	testing.expect_value(t, tick.damage, f32(5)) // phase 0's attack landed, not phase 2's

	step_tell(&a, enemy_pos, player_at({300, 0}), STEP, 0.2)
	testing.expect_value(t, a.phase_index, 2)
}

@(test)
test_a_phase_never_goes_back :: proc(t: ^testing.T) {
	a := a_phased_tell()
	far := player_at({300, 0})
	step_tell(&a, {0, 0}, far, STEP, 0.5)
	testing.expect_value(t, a.phase_index, 1)
	step_tell(&a, {0, 0}, far, STEP, 1)
	testing.expect_value(t, a.phase_index, 1)
}

@(test)
test_a_phase_advance_restarts_the_rotation_and_keeps_the_cooldown :: proc(t: ^testing.T) {
	a := a_phased_tell()
	enemy_pos := Vec2{0, 0}
	player := player_at({30, 0})

	step_tell(&a, enemy_pos, player, STEP)
	_, ticks := tick_until_resolved(&a, enemy_pos, player, 10)
	testing.expect(t, ticks > 0, "phase 0's first Tell should resolve")
	testing.expect_value(t, a.rotation_index, 1)
	testing.expect_value(t, a.cooldown_timer, f32(1.5))

	step_tell(&a, enemy_pos, player, STEP, 0.5)
	testing.expect_value(t, a.phase_index, 1)
	testing.expect_value(t, a.rotation_index, 0)
	testing.expect(t, a.tell_remaining == 0, "the new phase does not get a free Tell: phase 0's recovery is still owed")
	testing.expectf(t, abs(a.cooldown_timer - 1.4) < 0.001, "the running cooldown carries across the phase change, got %v", a.cooldown_timer)

	// once it expires, the Tell that starts is the new phase's
	for _ in 1 ..= 14 {
		step_tell(&a, enemy_pos, player, STEP, 0.5)
	}
	testing.expect_value(t, a.tell_remaining, f32(0.5))
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
	resolve_ticks :: proc(cooldown: f32) -> (first_remaining: f32, ticks: int) {
		a := a_tell(28, 40, 0.55, cooldown)
		enemy_pos := Vec2{0, 0}
		player := player_at({30, 0})
		step_tell(&a, enemy_pos, player, STEP)
		first_remaining = a.tell_remaining
		_, ticks = tick_until_resolved(&a, enemy_pos, player, 20)
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

// the second wiring proof: update_enemies hands a body's own health
// fraction to its Tell, so a phase is a thing a body enters by being shot
@(test)
test_update_enemies_feeds_a_bodys_health_fraction_to_its_tell :: proc(t: ^testing.T) {
	previous_enemies := game.enemies
	previous_player := game.player
	defer {
		delete(game.enemies)
		game.enemies = previous_enemies
		game.player = previous_player
	}
	game.enemies = {}
	game.player.rect = {300, 0, 0, 0}
	append(&game.enemies, Enemy{rect = {0, 0, 0, 0}, squash = {1, 1}, max_health = 100, health = 30, attack = a_phased_tell()})

	update_enemies(STEP)

	testing.expect_value(t, game.enemies[0].attack.(Tell_Area).phase_index, 2)
}

// the flash is a swing in value away from the body's own; toward white for
// the roster, and toward dark for a near-white body, which a pulse toward
// white would not visibly move at all
@(test)
test_the_tell_flash_visibly_moves_a_dark_body_and_a_near_white_one :: proc(t: ^testing.T) {
	swing :: proc(base: Color) -> f32 {
		return abs(color_luma(tell_flash_color(base, 1)) - color_luma(base))
	}
	VISIBLE :: f32(30) // 0..255 luma, at the mid-pulse mix progress 1 lands on

	testing.expectf(t, swing(ENEMY_GROUNDED_COLOR) > VISIBLE, "a green body should visibly lighten, moved %.0f", swing(ENEMY_GROUNDED_COLOR))
	testing.expectf(t, swing(ENEMY_GROUNDED_PALE_COLOR) > VISIBLE, "the palest roster body should still visibly lighten, moved %.0f", swing(ENEMY_GROUNDED_PALE_COLOR))
	boss := enemy_presets[.Warden].color
	testing.expectf(t, swing(boss) > VISIBLE, "the Boss's near-white should visibly darken, moved %.0f", swing(boss))
	testing.expect(t, color_luma(tell_flash_color(boss, 1)) < color_luma(boss), "and the direction on a near-white body is down")

	faded := Color{boss.r, boss.g, boss.b, 90}
	testing.expect_value(t, tell_flash_color(faded, 0.5).a, u8(90))
}
