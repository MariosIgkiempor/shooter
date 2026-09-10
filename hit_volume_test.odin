package shooter

import "core:math"
import "core:math/linalg"
import "core:testing"

// Same conventions as weapon_test.odin: drive try_use_weapon/update_weapon
// directly with controlled dt steps, no game loop and no raylib window, and
// assert on observable side effects (an enemy's health dropped) rather than on
// draw_weapon's rendering math. Run with -define:ODIN_TEST_THREADS=1; these
// mutate game.enemies via the same globals every other hit source does.
//
// The geometry assertions are the exception, and deliberately so: a Hit volume
// is authored data whose whole promise is that it matches the silhouette, and
// nothing observable at the damage seam can check that promise.

// puts `kind`'s hit volume in the world at `progress` through its swing, with
// the player at TEST_ORIGIN aiming along TEST_AIM. Re-derived from the pose
// pieces rather than by calling swing_hit_check, which would assert nothing
// about itself.
test_volume_at :: proc(weapon: Weapon, progress: f32, out: []Vec2) -> []Vec2 {
	arc := weapon_visuals[weapon.kind].swing_arc_degrees
	angle := aim_angle_degrees(TEST_AIM) + melee_swing_angle_offset(arc, progress)
	frame := weapon_pose_frame(weapon, weapon_pivot_position(TEST_ORIGIN), angle, 1)
	return hit_poly_to_world(frame, weapon_hit_volumes[weapon.kind][0], out)
}

// the furthest `weapon`'s hit volume reaches from the grip, posed at rest.
// Shared so the "a volume stops exactly at range" and "Reach grows the volume"
// assertions measure the same way rather than each folding the polygons again.
test_volume_extent :: proc(weapon: Weapon, pivot: Vec2) -> (furthest: f32) {
	points: [MAX_HIT_POLY_POINTS]Vec2
	frame := weapon_pose_frame(weapon, pivot, aim_angle_degrees(TEST_AIM), 1)
	for poly in weapon_hit_volumes[weapon.kind] {
		for p in hit_poly_to_world(frame, poly, points[:]) {
			furthest = max(furthest, linalg.length(p - pivot))
		}
	}
	return
}

// an Enemy whose *body centre* lands on `center` - the point the blade is
// tested against, ACTOR_SIZE.y/2 above its feet anchor
test_enemy_centered_at :: proc(center: Vec2, health: f32 = 100) -> Enemy {
	return Enemy{rect = {x = center.x, y = center.y + ACTOR_SIZE.y / 2}, health = health}
}

@(test)
test_only_weapons_that_swing_carry_a_hit_volume :: proc(t: ^testing.T) {
	// a Gun's reach is its bullet and Magic's is its cone or its cast - a
	// volume on either would be a second, silently disagreeing hit-check
	for kind in Weapon_Kind {
		has_volume := len(weapon_hit_volumes[kind]) > 0
		swings := weapon_kind_family[kind] == .Melee
		testing.expectf(
			t,
			has_volume == swings,
			"%v: weapon_hit_volumes should be populated for Melee kinds and empty for everything else",
			kind,
		)
	}
}

@(test)
test_a_hit_volume_stays_inside_the_glyph_it_is_drawn_as :: proc(t: ^testing.T) {
	// the volume is authored beside the glyph rather than emitted by it
	// (ADR-0026), so this is the assertion standing in for that guarantee: it
	// lives in the unit square the glyph is drawn in, and it reaches exactly
	// the kind's declared business end - no further, so a blade cannot damage
	// past its own tip, and no less, so it cannot fall short of the reach it
	// reports.
	for kind in Weapon_Kind {
		volume := weapon_hit_volumes[kind]
		if len(volume) == 0 {
			continue
		}

		furthest: f32 = 0
		for poly in volume {
			testing.expectf(t, len(poly) >= 3, "%v: a hit volume polygon needs at least three points", kind)
			testing.expectf(
				t,
				len(poly) <= MAX_HIT_POLY_POINTS,
				"%v: a hit volume polygon may hold at most MAX_HIT_POLY_POINTS points",
				kind,
			)
			for p in poly {
				testing.expectf(t, p.x >= 0 && p.x <= 1, "%v: hit volume u %v is outside the glyph's unit square", kind, p.x)
				testing.expectf(t, p.y >= 0 && p.y <= 1, "%v: hit volume v %v is outside the glyph's unit square", kind, p.y)
				furthest = max(furthest, p.x)
			}
		}

		testing.expectf(
			t,
			math.abs(furthest - weapon_icon_reach[kind]) < 0.001,
			"%v's hit volume reaches u=%v, but its glyph's business end is at %v",
			kind,
			furthest,
			weapon_icon_reach[kind],
		)
	}
}

@(test)
test_a_hit_volume_reaches_exactly_the_weapons_range :: proc(t: ^testing.T) {
	// the world-space counterpart of the assertion above, and the analogue of
	// icon_test's test_melee_world_frame_puts_the_blade_tip_at_its_actual_range:
	// what the weapon says its reach is, is where its volume stops
	pivot := weapon_pivot_position(TEST_ORIGIN)

	for kind in Weapon_Kind {
		if len(weapon_hit_volumes[kind]) == 0 {
			continue
		}

		weapon := weapon_create(kind)
		melee, is_melee := weapon.variant.(Melee_Weapon)
		testing.expect(t, is_melee, "a kind with a hit volume should be a Melee_Weapon variant")

		furthest := test_volume_extent(weapon, pivot)

		testing.expectf(
			t,
			math.abs(furthest - melee.range) < 0.01,
			"%v's hit volume reaches %v px from the grip, expected its range %v",
			kind,
			furthest,
			melee.range,
		)
	}
}

@(test)
test_reach_stacks_grow_the_hit_volume_along_with_the_blade :: proc(t: ^testing.T) {
	// Reach replaced an upgrade that widened the retired arc, and the reason it
	// can (ADR-0026) is that scaling Melee_Weapon.range scales
	// weapon_world_frame_size, which the volume rides. The test above already
	// pins the volume to whatever `range` says; what is unproven without this
	// is that a Reach stack moves `range` in the first place, so a stack that
	// bought a longer number and no longer blade would pass both halves.
	previous_stacks := game.player.upgrade_stacks
	defer game.player.upgrade_stacks = previous_stacks

	pivot := weapon_pivot_position(TEST_ORIGIN)

	for kind in Weapon_Kind {
		if len(weapon_hit_volumes[kind]) == 0 {
			continue
		}

		game.player.upgrade_stacks = {}
		unstacked := test_volume_extent(weapon_create(kind), pivot)

		game.player.upgrade_stacks[.Reach] = 3
		stacked_weapon := weapon_create(kind)
		_, is_melee := stacked_weapon.variant.(Melee_Weapon)
		testing.expect(t, is_melee, "a kind with a hit volume should be a Melee_Weapon variant")

		testing.expectf(
			t,
			test_volume_extent(stacked_weapon, pivot) > unstacked,
			"%v's hit volume should reach further with Reach stacks, stayed at %v",
			kind,
			unstacked,
		)
	}
}

@(test)
test_a_blade_does_not_damage_where_it_is_not_drawn :: proc(t: ^testing.T) {
	// The complaint that started all of this. A Sword resolves with its blade
	// drawn back at -arc/2, pointing away from what the retired cone was busy
	// killing straight ahead. Nothing in front of the player may be damaged on
	// the frame the swing starts - only once the blade has actually swept
	// there.
	clear(&game.enemies)
	defer clear(&game.enemies)
	clear(&game.particles)
	defer clear(&game.particles)
	clear(&game.damage_numbers)
	defer clear(&game.damage_numbers)

	weapon := weapon_create(.Sword)
	melee := weapon.variant.(Melee_Weapon)

	// straight along the aim line, well within the old cone's reach
	append(&game.enemies, test_enemy_centered_at(weapon_pivot_position(TEST_ORIGIN) + TEST_AIM * (melee.range * 0.8)))

	try_use_weapon(&weapon, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
	testing.expect(t, game.enemies[0].health == 100, "a Trigger alone should damage nothing - Resolve is not the hit-check")

	windup_duration := weapon.windup_fraction / weapon.action_rate
	update_weapon(&weapon, windup_duration + 0.001, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
	testing.expect(
		t,
		game.enemies[0].health == 100,
		"nothing in front of the player should be damaged at Resolve, where the blade is drawn back behind them",
	)
	testing.expect(t, weapon.follow_through_timer > 0, "sanity check: Resolve should have started the swing's window")

	// now let the blade actually sweep across it
	for _ in 0 ..< 20 {
		update_weapon(&weapon, 1.0 / 60.0, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
	}
	testing.expect(t, game.enemies[0].health < 100, "the body the blade sweeps across should be damaged once it gets there")
}

@(test)
test_one_swing_damages_a_body_at_most_once :: proc(t: ^testing.T) {
	// the volume is live for the whole Follow-through and re-tested every
	// frame, so without a per-swing identity a body parked in the arc would be
	// damaged once per frame
	clear(&game.enemies)
	defer clear(&game.enemies)
	clear(&game.particles)
	defer clear(&game.particles)
	clear(&game.damage_numbers)
	defer clear(&game.damage_numbers)

	weapon := weapon_create(.Sword)
	melee := weapon.variant.(Melee_Weapon)
	append(&game.enemies, test_enemy_centered_at(weapon_pivot_position(TEST_ORIGIN) + TEST_AIM * (melee.range * 0.7), 500))

	try_use_weapon(&weapon, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
	for _ in 0 ..< 40 {
		update_weapon(&weapon, 1.0 / 60.0, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
	}

	testing.expectf(
		t,
		game.enemies[0].health == 500 - weapon.damage,
		"one swing should take exactly one weapon's damage (%v) off a body it sweeps, got %v lost",
		weapon.damage,
		500 - game.enemies[0].health,
	)
}

@(test)
test_a_second_swing_damages_the_same_body_again :: proc(t: ^testing.T) {
	// the dedupe is per swing, not per body: standing in front of a swinging
	// weapon has to keep costing
	clear(&game.enemies)
	defer clear(&game.enemies)
	clear(&game.particles)
	defer clear(&game.particles)
	clear(&game.damage_numbers)
	defer clear(&game.damage_numbers)

	weapon := weapon_create(.Dagger) // Automatic - two swings need no Windup
	melee := weapon.variant.(Melee_Weapon)
	append(&game.enemies, test_enemy_centered_at(weapon_pivot_position(TEST_ORIGIN) + TEST_AIM * (melee.range * 0.7), 500))

	for _ in 0 ..< 2 {
		weapon.cooldown_timer = 0 // force-ready, same shortcut the flamethrower test uses
		try_use_weapon(&weapon, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
		for _ in 0 ..< 20 {
			update_weapon(&weapon, 1.0 / 60.0, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
		}
	}

	testing.expectf(
		t,
		game.enemies[0].health == 500 - weapon.damage * 2,
		"two swings should land twice, got %v lost against a damage of %v",
		500 - game.enemies[0].health,
		weapon.damage,
	)
}

@(test)
test_a_swing_catches_a_body_between_two_frames :: proc(t: ^testing.T) {
	// Tunnelling. A blade crosses its arc in a handful of frames, front-loaded
	// by ease_out_cubic, and a body can sit in the gap between two poses and be
	// touched by neither. The sweep between poses is what catches it - so this
	// asserts both that the body is damaged, and that neither end pose alone
	// would have found it.
	clear(&game.enemies)
	defer clear(&game.enemies)
	clear(&game.particles)
	defer clear(&game.particles)
	clear(&game.damage_numbers)
	defer clear(&game.damage_numbers)

	weapon := weapon_create(.Sword)
	melee := weapon.variant.(Melee_Weapon)

	// midway along the arc the swing sweeps through, out near the tip
	half_arc := math.to_radians(weapon_visuals[.Sword].swing_arc_degrees / 2)
	bearing := Vec2{math.cos(-half_arc / 2), math.sin(-half_arc / 2)}
	center := weapon_pivot_position(TEST_ORIGIN) + bearing * (melee.range * 0.92)
	append(&game.enemies, test_enemy_centered_at(center))

	_, radius := enemy_body_circle(game.enemies[0])
	points: [MAX_HIT_POLY_POINTS]Vec2
	testing.expect(
		t,
		!polygon_circle_overlap(test_volume_at(weapon, 0, points[:]), center, radius),
		"sanity check: the body must not be touching the blade at the start of the swing",
	)
	testing.expect(
		t,
		!polygon_circle_overlap(test_volume_at(weapon, 1, points[:]), center, radius),
		"sanity check: the body must not be touching the blade at the end of the swing either",
	)

	// the whole swing in one step, so the two poses tested are exactly the two
	// the sanity checks above just showed miss it
	try_use_weapon(&weapon, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
	windup_duration := weapon.windup_fraction / weapon.action_rate
	update_weapon(&weapon, windup_duration + 0.001, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
	update_weapon(&weapon, weapon.follow_through_time, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])

	testing.expect(
		t,
		game.enemies[0].health < 100,
		"a body the blade passed through between two frames should still be caught - it is touched by neither pose",
	)
}

@(test)
test_a_swing_misses_what_the_blade_never_reaches :: proc(t: ^testing.T) {
	clear(&game.enemies)
	defer clear(&game.enemies)
	clear(&game.particles)
	defer clear(&game.particles)
	clear(&game.damage_numbers)
	defer clear(&game.damage_numbers)

	weapon := weapon_create(.Sword)
	melee := weapon.variant.(Melee_Weapon)
	pivot := weapon_pivot_position(TEST_ORIGIN)

	append(&game.enemies, test_enemy_centered_at(pivot - TEST_AIM * (melee.range * 0.5))) // behind
	append(&game.enemies, test_enemy_centered_at(pivot + TEST_AIM * (melee.range * 3))) // out of reach

	try_use_weapon(&weapon, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
	for _ in 0 ..< 40 {
		update_weapon(&weapon, 1.0 / 60.0, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
	}

	testing.expect(t, game.enemies[0].health == 100, "a body behind the player should never be touched by the swing")
	testing.expect(t, game.enemies[1].health == 100, "a body past the blade's reach should never be touched by the swing")
}

@(test)
test_both_fire_modes_carry_a_follow_through :: proc(t: ^testing.T) {
	// Fire mode used to decide this: Windup for Semi_Automatic, Follow-through
	// for Automatic, never both. A swinging weapon needs one whatever its fire
	// mode, because Follow-through is the window its Hit volume is live for
	// (ADR-0026).
	for kind in weapon_family_kinds[.Melee] {
		preset := weapon_presets[kind]
		testing.expectf(t, preset.follow_through_time > 0, "%v swings, so it needs a Follow-through to swing through", kind)

		weapon := weapon_create(kind)
		try_use_weapon(&weapon, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
		if preset.fire_mode == .Semi_Automatic {
			testing.expectf(t, weapon.windup_timer > 0, "%v is Semi_Automatic, so it should Windup first", kind)
			windup_duration := weapon.windup_fraction / weapon.action_rate
			update_weapon(&weapon, windup_duration + 0.001, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
		}
		testing.expectf(t, weapon.follow_through_timer > 0, "%v should be swinging once it has Resolved", kind)
	}
}

@(test)
test_the_swing_curve_starts_drawn_back_and_ends_neutral :: proc(t: ^testing.T) {
	// the property the volume's motion and the drawn blade both rest on: the
	// swing is a real traversal of the arc, not a jump to its middle
	arc: f32 = 110
	testing.expect(t, math.abs(melee_swing_angle_offset(arc, 0) - (-arc / 2)) < 0.001, "a swing starts drawn back at -arc/2")
	testing.expect(
		t,
		math.abs(melee_swing_angle_offset(arc, SWING_OUT_FRACTION) - arc / 2) < 0.001,
		"a swing reaches +arc/2 at the end of its out phase",
	)
	testing.expect(t, math.abs(melee_swing_angle_offset(arc, 1)) < 0.001, "a swing returns to neutral")
}

// -- geometry ---------------------------------------------------------------

@(test)
test_polygon_circle_overlap_finds_bodies_inside_and_on_the_edge :: proc(t: ^testing.T) {
	square := [][2]f32{{0, 0}, {10, 0}, {10, 10}, {0, 10}}
	poly := transmute([]Vec2)square

	testing.expect(t, polygon_circle_overlap(poly, Vec2{5, 5}, 1), "a circle wholly inside the polygon overlaps it")
	testing.expect(t, polygon_circle_overlap(poly, Vec2{12, 5}, 3), "a circle clipping an edge from outside overlaps it")
	testing.expect(t, !polygon_circle_overlap(poly, Vec2{20, 5}, 3), "a circle clear of the polygon does not overlap it")
	testing.expect(
		t,
		polygon_circle_overlap(poly, Vec2{-1, -1}, 2),
		"a circle reaching a corner from outside overlaps it",
	)
}

@(test)
test_the_swept_test_catches_what_neither_pose_does :: proc(t: ^testing.T) {
	// two thin poses either side of a gap, and a body sitting in it - the
	// tunnelling case, isolated from any weapon
	prev := []Vec2{{0, 0}, {2, 0}, {2, 10}, {0, 10}}
	cur := []Vec2{{20, 0}, {22, 0}, {22, 10}, {20, 10}}
	center := Vec2{11, 5}
	radius: f32 = 1

	testing.expect(t, !polygon_circle_overlap(prev, center, radius), "sanity check: the previous pose misses")
	testing.expect(t, !polygon_circle_overlap(cur, center, radius), "sanity check: the current pose misses")
	testing.expect(
		t,
		polygon_swept_circle_overlap(prev, cur, center, radius),
		"the region between two poses should catch a body neither pose touches",
	)
	testing.expect(
		t,
		!polygon_swept_circle_overlap(prev, cur, Vec2{11, 40}, radius),
		"a body clear of the swept region is still missed",
	)
}

@(test)
test_a_thrusting_weapon_still_reaches_what_it_points_at :: proc(t: ^testing.T) {
	// the Spear's arc is 18 degrees, barely a sweep, so almost nothing about
	// it is proven by the tests written against a Sword's 110. What has to
	// hold is that a body straight ahead of a thrust is still touched by it -
	// the volume is a small head at the far end of a long haft, and if the
	// pose or the arc were wrong it would simply miss everything.
	clear(&game.enemies)
	defer clear(&game.enemies)
	clear(&game.particles)
	defer clear(&game.particles)
	clear(&game.damage_numbers)
	defer clear(&game.damage_numbers)

	weapon := weapon_create(.Spear)
	melee := weapon.variant.(Melee_Weapon)
	append(&game.enemies, test_enemy_centered_at(weapon_pivot_position(TEST_ORIGIN) + TEST_AIM * (melee.range * 0.9), 500))

	try_use_weapon(&weapon, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
	for _ in 0 ..< 40 {
		update_weapon(&weapon, 1.0 / 60.0, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
	}

	testing.expect(t, game.enemies[0].health == 500 - weapon.damage, "a thrust should hit the body it is pointed at, exactly once")
}

@(test)
test_the_widest_swing_still_catches_a_body_at_its_outer_edge :: proc(t: ^testing.T) {
	// The Greatsword's whole purchase is space: a 140 degree arc at 80px is
	// the widest ground any weapon covers, and every other melee test aims
	// straight down TEST_AIM, where a Dagger would also connect. This is the
	// one that says the far end of that sweep is real - a body 70 degrees off
	// the aim line, out near the tip, is inside what this weapon damages.
	//
	// It does not pin ADR-0026's chord bound: at this blade's 20px half-width
	// against a 12px body the swept quads cover the arc's outside with room to
	// spare, and the tunnelling case itself is already held by
	// test_a_swing_catches_a_body_it_crosses_between_two_frames. The arithmetic
	// behind 140/0.26 is recorded on the preset instead.
	clear(&game.enemies)
	defer clear(&game.enemies)
	clear(&game.particles)
	defer clear(&game.particles)
	clear(&game.damage_numbers)
	defer clear(&game.damage_numbers)

	weapon := weapon_create(.Greatsword)
	melee := weapon.variant.(Melee_Weapon)
	arc := weapon_visuals[.Greatsword].swing_arc_degrees

	// on the far end of the sweep, out near the blade's tip
	edge := math.to_radians(aim_angle_degrees(TEST_AIM) + arc / 2)
	direction := Vec2{math.cos(edge), math.sin(edge)}
	append(&game.enemies, test_enemy_centered_at(weapon_pivot_position(TEST_ORIGIN) + direction * (melee.range * 0.85), 500))

	try_use_weapon(&weapon, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
	for _ in 0 ..< 60 {
		update_weapon(&weapon, 1.0 / 60.0, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
	}

	testing.expect(
		t,
		game.enemies[0].health == 500 - weapon.damage,
		"a body on the outer edge of the widest swing should be caught by the sweep, not tunnelled past",
	)
}
