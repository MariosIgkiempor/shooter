package shooter

import "core:math/linalg"
import "core:testing"

// A Charger's state machine (update_charger) takes the body's position, the
// player's, the direction its approach would take and a dt explicitly, and
// never reads `game` or the flow field - so, like enemy_tell_test.odin,
// nearly everything here drives throwaway values with fixed dt steps. The
// exception is the wiring test at the bottom, which drives update_enemies
// against `game` to prove the dash survives Melee's hold and that a wall
// ends it; it snapshots and restores, and is why this file is still run
// with `odin test . -define:ODIN_TEST_THREADS=1`.
//
// Rendering (the lane, the body flash) is deliberately untested, per the
// content-expansion spec.

@(private = "file")
a_charger :: proc(
	speed, dash_speed, dash_distance, tell_seconds: f32,
	recovery_seconds: f32 = 0.5,
	cooldown_seconds: f32 = 1,
) -> Charger {
	return Charger {
		speed = speed,
		dash_speed = dash_speed,
		dash_distance = dash_distance,
		tell_seconds = tell_seconds,
		recovery_seconds = recovery_seconds,
		cooldown_seconds = cooldown_seconds,
	}
}

@(private = "file")
STEP :: f32(0.1)

@(private = "file")
RIGHT :: Vec2{1, 0}

@(test)
test_a_charger_approaches_until_the_player_is_within_its_dash :: proc(t: ^testing.T) {
	c := a_charger(55, 260, 140, 0.5)
	enemy_pos := Vec2{0, 0}

	tick := update_charger(&c, enemy_pos, {300, 0}, RIGHT, STEP)
	testing.expect_value(t, c.phase, Charger_Phase.Approaching)
	testing.expect(t, !tick.committed, "a body still closing is free to be steered")
	testing.expectf(t, linalg.distance(tick.delta, RIGHT * 55 * STEP) < 0.001, "the approach should move at `speed` along the approach direction, got %v", tick.delta)

	tick = update_charger(&c, enemy_pos, {100, 0}, RIGHT, STEP)
	testing.expect_value(t, c.phase, Charger_Phase.Telling)
	testing.expect(t, tick.committed, "a body that has claimed a lane is committed to it")
	testing.expect_value(t, tick.delta, Vec2{})
}

@(test)
test_the_lane_is_locked_at_tell_start_and_the_body_plants_for_the_whole_tell :: proc(t: ^testing.T) {
	// 0.45 rather than 0.5 so f32 accumulation cannot leave a sliver
	c := a_charger(55, 260, 140, 0.45)
	enemy_pos := Vec2{10, 20}

	update_charger(&c, enemy_pos, {110, 20}, RIGHT, STEP)
	testing.expect_value(t, c.lane_origin, enemy_pos)
	testing.expect_value(t, c.lane_dir, RIGHT)

	// the player walks off the lane every remaining frame; the lane does
	// not follow, and the body does not move. Tick 1 started the Tell (0.45
	// remaining) and did not count against it; ticks 2..5 take 0.4s off;
	// tick 6 crosses zero into the dash.
	for i in 2 ..= 5 {
		tick := update_charger(&c, enemy_pos, {60, 120}, {0, 1}, STEP)
		testing.expectf(t, c.phase == .Telling, "tick %d is inside the 0.45s Tell, got %v", i, c.phase)
		testing.expectf(t, tick.delta == {}, "tick %d of a Tell should plant the body, got %v", i, tick.delta)
		testing.expectf(t, c.lane_dir == RIGHT, "tick %d should leave the locked bearing alone, got %v", i, c.lane_dir)
	}
	update_charger(&c, enemy_pos, {60, 120}, {0, 1}, STEP)
	testing.expect_value(t, c.phase, Charger_Phase.Dashing)
	testing.expect_value(t, c.lane_dir, RIGHT)
}

// drives the machine until it enters `phase` or `max_ticks` pass; returns the
// deltas summed along the way and how many ticks it took (0 if it never did)
@(private = "file")
tick_until_phase :: proc(c: ^Charger, enemy_pos, player_pos: Vec2, phase: Charger_Phase, max_ticks: int) -> (travelled: Vec2, ticks: int) {
	for i in 1 ..= max_ticks {
		tick := update_charger(c, enemy_pos, player_pos, RIGHT, STEP)
		travelled += tick.delta
		if c.phase == phase {
			return travelled, i
		}
	}
	return travelled, 0
}

@(test)
test_the_dash_runs_the_locked_lane_at_dash_speed_for_exactly_its_distance :: proc(t: ^testing.T) {
	c := a_charger(55, 260, 140, 0.45)
	enemy_pos := Vec2{0, 0}
	player := Vec2{100, 0}

	_, ticks := tick_until_phase(&c, enemy_pos, player, .Dashing, 10)
	testing.expect(t, ticks > 0, "the Tell should have run out into a dash")

	// the player has stepped off the lane; the dash does not care
	off_lane := Vec2{100, 90}
	tick := update_charger(&c, enemy_pos, off_lane, {0, 1}, STEP)
	testing.expect(t, tick.committed, "a dashing body is committed")
	testing.expectf(t, linalg.distance(tick.delta, RIGHT * 260 * STEP) < 0.001, "a full dash tick should move dash_speed * dt along the lane, got %v", tick.delta)

	travelled, more := tick_until_phase(&c, enemy_pos, off_lane, .Recovering, 20)
	testing.expect(t, more > 0, "the dash should have ended in recovery")
	total := tick.delta + travelled
	testing.expectf(t, abs(total.x - 140) < 0.001 && total.y == 0, "the dash should cover exactly dash_distance along the lane, got %v", total)
}

@(test)
test_recovery_plants_the_body_and_the_cooldown_gates_the_next_tell :: proc(t: ^testing.T) {
	c := a_charger(55, 260, 140, 0, recovery_seconds = 0.45, cooldown_seconds = 0.45)
	enemy_pos := Vec2{0, 0}
	player := Vec2{100, 0}

	_, ticks := tick_until_phase(&c, enemy_pos, player, .Recovering, 20)
	testing.expect(t, ticks > 0, "the dash should have ended in recovery")

	// 0.45s of recovery at 0.1s steps: four ticks inside it, the fifth crosses
	for i in 1 ..= 4 {
		tick := update_charger(&c, enemy_pos, player, RIGHT, STEP)
		testing.expectf(t, c.phase == .Recovering && tick.delta == {} && tick.committed, "recovery tick %d should plant the body, got %v / %v", i, c.phase, tick.delta)
	}
	update_charger(&c, enemy_pos, player, RIGHT, STEP)
	testing.expect_value(t, c.phase, Charger_Phase.Approaching)

	// the player is still within dash_distance, but the cooldown holds the
	// next Tell: four ticks approach, the fifth claims a lane
	for i in 1 ..= 4 {
		tick := update_charger(&c, enemy_pos, player, RIGHT, STEP)
		testing.expectf(t, c.phase == .Approaching && !tick.committed, "cooldown tick %d should keep approaching, got %v", i, c.phase)
		testing.expectf(t, tick.delta != {}, "cooldown tick %d should walk, not plant", i)
	}
	update_charger(&c, enemy_pos, player, RIGHT, STEP)
	testing.expect(t, c.phase != .Approaching, "the first tick past the cooldown should start the next Tell")
}

@(test)
test_a_wall_ends_the_dash_early_into_recovery :: proc(t: ^testing.T) {
	c := a_charger(55, 260, 140, 0, recovery_seconds = 0.5)
	enemy_pos := Vec2{0, 0}
	player := Vec2{100, 0}

	_, ticks := tick_until_phase(&c, enemy_pos, player, .Dashing, 10)
	testing.expect_value(t, ticks, 1) // a zero-second Tell dashes on the tick it starts
	update_charger(&c, enemy_pos, player, RIGHT, STEP) // one tick of the dash, 26px of 140

	charger_end_dash(&c)
	testing.expect_value(t, c.phase, Charger_Phase.Recovering)

	tick := update_charger(&c, enemy_pos, player, RIGHT, STEP)
	testing.expect_value(t, tick.delta, Vec2{})
	testing.expect(t, tick.committed, "a body stopped by a wall recovers in place")
}

@(test)
test_the_tell_reads_0_to_1_across_its_run_and_nowhere_else :: proc(t: ^testing.T) {
	c := a_charger(55, 260, 140, 0.45)
	enemy_pos := Vec2{0, 0}
	player := Vec2{100, 0}

	_, telling := charger_tell_progress(c)
	testing.expect(t, !telling, "an approaching body has no Tell to show")

	update_charger(&c, enemy_pos, player, RIGHT, STEP)
	progress, now_telling := charger_tell_progress(c)
	testing.expect(t, now_telling, "the tick that claims a lane starts the Tell")
	testing.expect_value(t, progress, f32(0))

	last := progress
	for c.phase == .Telling {
		update_charger(&c, enemy_pos, player, RIGHT, STEP)
		if p, still := charger_tell_progress(c); still {
			testing.expectf(t, p > last && p <= 1, "progress should climb toward 1, got %v after %v", p, last)
			last = p
		}
	}
	_, after := charger_tell_progress(c)
	testing.expect(t, !after, "a dashing body's Tell is over")
}

// ADR-0023: a Tell is absolute seconds. The Charger's other timings are the
// plausible scalers - recovery and cooldown pace the body, and neither may
// touch how long the player has to read the lane.
@(test)
test_charger_tell_duration_is_unchanged_by_its_pacing :: proc(t: ^testing.T) {
	ticks_to_dash :: proc(recovery, cooldown: f32) -> int {
		c := a_charger(55, 260, 140, 0.45, recovery_seconds = recovery, cooldown_seconds = cooldown)
		_, ticks := tick_until_phase(&c, {0, 0}, {100, 0}, .Dashing, 20)
		return ticks
	}
	quick := ticks_to_dash(0.1, 0.1)
	slow := ticks_to_dash(5, 5)
	testing.expect(t, quick > 0, "the quick-paced Tell should reach its dash")
	testing.expect_value(t, slow, quick)
}

// the one test that proves the Charger case in update_enemies is wired: the
// pure tests above cannot see Melee's hold or move_actor's wall.
@(test)
test_update_enemies_lets_a_dash_through_melees_hold_and_ends_it_on_a_wall :: proc(t: ^testing.T) {
	previous_map := game.current_map
	previous_player := game.player
	previous_enemies := game.enemies
	previous_particles := game.particles
	previous_damage_numbers := game.damage_numbers
	previous_run_ended := game.run_ended
	previous_god_mode := game.debug.god_mode
	defer {
		delete(game.current_map.tilemap.tiles)
		game.current_map = previous_map
		game.player = previous_player
		delete(game.enemies)
		game.enemies = previous_enemies
		delete(game.particles)
		game.particles = previous_particles
		delete(game.damage_numbers)
		game.damage_numbers = previous_damage_numbers
		game.run_ended = previous_run_ended
		game.debug.god_mode = previous_god_mode
	}
	// a 10-cell corridor with a wall at its right end; the field is left
	// empty, which every field lookup falls back from to a straight line
	game.current_map = Map{}
	game.current_map.tilemap = fixture_room({".........#"})
	game.player = Player{}
	game.player.health = 100
	game.player.max_health = 100
	game.enemies = {}
	game.particles = {}
	game.damage_numbers = {}
	game.run_ended = false
	game.debug.god_mode = true // the hit is not what is under test; only that the dash keeps moving through it

	// dashing already, with the player in Melee reach: Melee's hold must
	// not stop it
	charger := a_charger(55, 260, 140, 0, recovery_seconds = 1)
	charger.phase = .Dashing
	charger.dash_remaining = 140
	charger.lane_dir = RIGHT
	game.player.rect = {40, 16, 0, 0}
	append(
		&game.enemies,
		Enemy {
			rect = {24, 16, 0, 0},
			squash = {1, 1},
			movement = charger,
			attack = Melee{attack_damage = 10, attack_range = 10, attack_cooldown = 1},
			max_health = 60,
			health = 60,
		},
	)

	update_enemies(STEP)
	testing.expectf(t, game.enemies[0].x > 24, "a dash arriving in Melee reach should keep moving, got x = %v", game.enemies[0].x)

	// the wall at x = 144 (cell 9) is 140px short of nothing: keep dashing
	// and the wall, not the distance, ends it
	for _ in 1 ..= 5 {
		update_enemies(STEP)
	}
	c := game.enemies[0].movement.(Charger)
	testing.expect_value(t, c.phase, Charger_Phase.Recovering)
	testing.expectf(t, c.dash_remaining == 0 && game.enemies[0].x < 144, "the wall should have stopped the body short of it with distance unspent, got x = %v", game.enemies[0].x)
}
