package shooter

import "core:math"
import "core:math/linalg"
import "core:testing"

// update_actor_squash takes the body's squash and this frame's displacement
// explicitly, and never reads `game` - so every test here drives a throwaway
// Actor_Squash with fixed dt steps. Two regressions are pinned: art-revamp
// ticket 07's (actors used to stay squished for as long as they *wanted* to
// move, which for enemies was nearly always) and ticket 08's (the pulse used
// to squash the y axis whichever way the body went).

@(private = "file")
STEP :: f32(1.0 / 60)

// a frame's displacement at 60 px/s - comfortably a real step
@(private = "file")
RIGHT :: Vec2{1, 0}

@(private = "file")
UP :: Vec2{0, -1}

// enough frames at RIGHT (1px a frame) for the verdict to settle and the
// body to net ACTOR_PULSE_TRAVEL
@(private = "file")
START_FRAMES :: 12

// enough frames for a stop to settle
@(private = "file")
STOP_FRAMES :: 6

@(private = "file")
distance_from_rest :: proc(s: Actor_Squash) -> f32 {
	return math.abs(s.along - 1) + math.abs(s.across - 1)
}

@(private = "file")
hold :: proc(s: ^Actor_Squash, displacement: Vec2, frames: int) {
	for _ in 0 ..< frames {
		update_actor_squash(s, displacement, STEP)
	}
}

@(private = "file")
expect_peak :: proc(t: ^testing.T, s: Actor_Squash, along, across: f32, axis: Vec2, loc := #caller_location) {
	testing.expect_value(t, s.along, along, loc = loc)
	testing.expect_value(t, s.across, across, loc = loc)
	testing.expectf(t, linalg.distance(s.axis, axis) < 0.0001, "axis should be %v, got %v", axis, s.axis, loc = loc)
}

// the frame the settled verdict flips is the frame the peak lands: drive
// until it does and report how many frames that took
@(private = "file")
frames_until_peak :: proc(s: ^Actor_Squash, displacement: Vec2, limit := 60) -> (frames: int, peaked: bool) {
	for frames < limit {
		before := s.along
		update_actor_squash(s, displacement, STEP)
		frames += 1
		if s.along != before && (s.along == ACTOR_PULSE_ALONG || s.along == ACTOR_PULSE_ACROSS) {
			return frames, true
		}
	}
	return frames, false
}

@(test)
test_a_body_that_starts_moving_stretches_along_its_movement_axis_once_the_verdict_settles :: proc(t: ^testing.T) {
	s := actor_squash_at_rest()

	frames, peaked := frames_until_peak(&s, RIGHT * 2)

	testing.expect(t, peaked, "a steady run must pulse")
	testing.expectf(t, frames >= 2 && frames <= START_FRAMES, "the pulse should wait out the settle time and the travel gate, not fire on the first frame nor much later, took %d frames", frames)
	expect_peak(t, s, ACTOR_PULSE_ALONG, ACTOR_PULSE_ACROSS, RIGHT)
	testing.expect(t, s.moving, "the settled verdict must record the start so the next frame sees no edge")
}

@(test)
test_the_axis_follows_the_body_whichever_way_it_goes :: proc(t: ^testing.T) {
	s := actor_squash_at_rest()
	_, peaked := frames_until_peak(&s, UP * 3)
	testing.expect(t, peaked, "a steady run must pulse")
	expect_peak(t, s, ACTOR_PULSE_ALONG, ACTOR_PULSE_ACROSS, UP)

	// steering onto a diagonal while still moving turns the axis toward it
	// over a few frames without re-peaking
	before := distance_from_rest(s)
	hold(&s, {2, 2}, 30)
	diagonal := linalg.normalize(Vec2{1, 1})
	testing.expectf(t, linalg.distance(s.axis, diagonal) < 0.01, "axis should have turned onto the diagonal, got %v", s.axis)
	testing.expect(t, distance_from_rest(s) < before, "a turn mid-run is not an edge and must not re-peak")
}

@(test)
test_a_body_that_stops_squashes_along_the_axis_it_was_moving_on :: proc(t: ^testing.T) {
	s := actor_squash_at_rest()
	hold(&s, UP, 120)
	testing.expectf(t, distance_from_rest(s) < 0.01, "two seconds of steady motion should have settled the body, got %v", s)

	frames, peaked := frames_until_peak(&s, {})

	testing.expect(t, peaked, "a steady stop must pulse")
	testing.expectf(t, frames <= STOP_FRAMES, "the stop pulse should land once the rest settles, took %d frames", frames)
	// the swap: thin along the axis it was travelling, wide across it
	expect_peak(t, s, ACTOR_PULSE_ACROSS, ACTOR_PULSE_ALONG, UP)
	testing.expect(t, !s.moving, "the settled verdict must record the stop so the next frame sees no edge")
}

@(test)
test_a_body_that_keeps_moving_eases_back_to_rest_and_never_re_peaks :: proc(t: ^testing.T) {
	s := actor_squash_at_rest()
	_, peaked := frames_until_peak(&s, RIGHT)
	testing.expect(t, peaked, "a steady run must pulse")

	previous := distance_from_rest(s)
	for frame in 0 ..< 120 {
		update_actor_squash(&s, RIGHT, STEP)
		current := distance_from_rest(s)
		testing.expectf(t, current < previous, "frame %d: the squash should shrink every frame it keeps moving, went %v -> %v", frame, previous, current)
		previous = current
	}
	testing.expectf(t, previous < 0.01, "two seconds of steady motion should leave the body at rest, got %v", s)
}

@(test)
test_a_body_that_keeps_resting_eases_back_to_rest_and_never_re_peaks :: proc(t: ^testing.T) {
	s := actor_squash_at_rest()
	hold(&s, RIGHT, 30)
	_, peaked := frames_until_peak(&s, {})
	testing.expect(t, peaked, "a steady stop must pulse")
	expect_peak(t, s, ACTOR_PULSE_ACROSS, ACTOR_PULSE_ALONG, RIGHT)

	previous := distance_from_rest(s)
	for frame in 0 ..< 120 {
		update_actor_squash(&s, {}, STEP)
		current := distance_from_rest(s)
		testing.expectf(t, current < previous, "frame %d: the squash should shrink every frame it stays still, went %v -> %v", frame, previous, current)
		previous = current
	}
	testing.expectf(t, previous < 0.01, "two seconds at rest should leave the body at rest, got %v", s)
}

@(test)
test_a_body_at_rest_that_stays_at_rest_is_never_disturbed :: proc(t: ^testing.T) {
	s := actor_squash_at_rest()

	hold(&s, {}, 60)

	testing.expect_value(t, s, actor_squash_at_rest())
}

// the jitter fix (ticket 08 comments): a body pinned against a wall by the
// field, or jostled by separation, alternates a real step and none every
// frame. That must read as one steady state, not a pulse per flicker
@(test)
test_a_body_that_flickers_between_a_step_and_none_never_pulses :: proc(t: ^testing.T) {
	s := actor_squash_at_rest()

	pulses := 0
	for frame in 0 ..< 240 {
		displacement := frame % 2 == 0 ? RIGHT : Vec2{}
		update_actor_squash(&s, displacement, STEP)
		if s.along == ACTOR_PULSE_ALONG || s.along == ACTOR_PULSE_ACROSS do pulses += 1
	}

	testing.expect_value(t, pulses, 0)
	testing.expect_value(t, s, actor_squash_at_rest())
}

// a body whose flicker is a couple of frames each way still never lets a
// verdict hold for the settle time
@(test)
test_a_body_that_flickers_every_two_frames_never_pulses :: proc(t: ^testing.T) {
	s := actor_squash_at_rest()

	pulses := 0
	for frame in 0 ..< 240 {
		displacement := (frame / 2) % 2 == 0 ? UP : Vec2{}
		update_actor_squash(&s, displacement, STEP)
		if s.along == ACTOR_PULSE_ALONG || s.along == ACTOR_PULSE_ACROSS do pulses += 1
	}

	testing.expect_value(t, pulses, 0)
}

// a body shoved a few px one way and back moves at a real speed the whole
// time but goes nowhere: neither a start nor a stop pulse
@(test)
test_a_body_shoved_back_and_forth_never_pulses :: proc(t: ^testing.T) {
	s := actor_squash_at_rest()

	pulses := 0
	for cycle in 0 ..< 20 {
		// 3px right over 3 frames, 3px back over 3 frames, a beat of rest
		for _ in 0 ..< 3 {
			update_actor_squash(&s, RIGHT, STEP)
			if s.along == ACTOR_PULSE_ALONG || s.along == ACTOR_PULSE_ACROSS do pulses += 1
		}
		for _ in 0 ..< 3 {
			update_actor_squash(&s, -RIGHT, STEP)
			if s.along == ACTOR_PULSE_ALONG || s.along == ACTOR_PULSE_ACROSS do pulses += 1
		}
		for _ in 0 ..< 4 {
			update_actor_squash(&s, {}, STEP)
			if s.along == ACTOR_PULSE_ALONG || s.along == ACTOR_PULSE_ACROSS do pulses += 1
		}
	}

	testing.expect_value(t, pulses, 0)
}

// a short shuffle that stops before the travel gate ends quietly too
@(test)
test_a_stint_that_never_reaches_the_travel_gate_has_no_stop_pulse_either :: proc(t: ^testing.T) {
	s := actor_squash_at_rest()
	hold(&s, RIGHT * 0.5, 8) // 4px, under ACTOR_PULSE_TRAVEL, at a real speed

	pulses := 0
	for _ in 0 ..< 30 {
		update_actor_squash(&s, {}, STEP)
		if s.along == ACTOR_PULSE_ALONG || s.along == ACTOR_PULSE_ACROSS do pulses += 1
	}

	testing.expect_value(t, pulses, 0)
	testing.expect(t, !s.moving, "the body should still have settled to rest")
}

// separation nudging a pinned body a fraction of a pixel a frame is not travel
@(test)
test_a_body_creeping_below_the_speed_floor_is_at_rest :: proc(t: ^testing.T) {
	s := actor_squash_at_rest()
	creep := Vec2{ACTOR_MOVE_MIN_SPEED * STEP * 0.5, 0}

	hold(&s, creep, 120)

	testing.expect_value(t, s, actor_squash_at_rest())
}

@(test)
test_actor_moved_is_a_speed_floor_not_a_pixel_count :: proc(t: ^testing.T) {
	floor := ACTOR_MOVE_MIN_SPEED * STEP
	testing.expect(t, !actor_moved({}, STEP), "no displacement is not a move")
	testing.expect(t, !actor_moved({floor * 0.9, 0}, STEP), "under the floor for this dt is not a move")
	testing.expect(t, actor_moved({floor * 1.1, 0}, STEP), "over the floor for this dt is a move")
	testing.expect(t, actor_moved({0, -1}, STEP), "a 1px step in any axis at 60 fps is a move")
	// the same displacement over a longer frame is a slower body
	testing.expect(t, !actor_moved({floor * 1.1, 0}, STEP * 2), "the same step over two frames' worth of time is under the floor")
}

// -- the axis matrix ---------------------------------------------------------

@(private = "file")
expect_matrix :: proc(t: ^testing.T, got, want: matrix[2, 2]f32, loc := #caller_location) {
	for i in 0 ..< 2 {
		for j in 0 ..< 2 {
			testing.expectf(t, math.abs(got[i, j] - want[i, j]) < 0.0001, "matrix should be %v, got %v", want, got, loc = loc)
		}
	}
}

@(test)
test_a_rested_body_has_the_identity_matrix_whatever_its_axis :: proc(t: ^testing.T) {
	for axis in ([]Vec2{RIGHT, UP, linalg.normalize(Vec2{1, 1}), linalg.normalize(Vec2{-3, 1}), {}}) {
		s := Actor_Squash{along = 1, across = 1, axis = axis}
		expect_matrix(t, actor_squash_matrix(s), 1)
	}
}

@(test)
test_a_horizontal_axis_scales_x_along_and_y_across :: proc(t: ^testing.T) {
	s := Actor_Squash{along = 1.5, across = 0.5, axis = RIGHT}
	expect_matrix(t, actor_squash_matrix(s), {1.5, 0, 0, 0.5})
}

@(test)
test_a_vertical_axis_scales_y_along_and_x_across :: proc(t: ^testing.T) {
	s := Actor_Squash{along = 1.5, across = 0.5, axis = UP}
	expect_matrix(t, actor_squash_matrix(s), {0.5, 0, 0, 1.5})
}

@(test)
test_a_diagonal_axis_stretches_the_diagonal_without_rotating_the_body :: proc(t: ^testing.T) {
	d := linalg.normalize(Vec2{1, 1})
	m := actor_squash_matrix(Actor_Squash{along = 2, across = 1, axis = d})

	// the axis itself is scaled by `along`, its perpendicular by `across`
	testing.expectf(t, linalg.distance(m * d, d * 2) < 0.0001, "the axis should scale by along, got %v", m * d)
	perp := Vec2{-d.y, d.x}
	testing.expectf(t, linalg.distance(m * perp, perp) < 0.0001, "the perpendicular should scale by across, got %v", m * perp)
	// symmetric, so no rotation is folded in
	testing.expectf(t, math.abs(m[0, 1] - m[1, 0]) < 0.0001, "an axis scale is symmetric, got %v", m)
}
