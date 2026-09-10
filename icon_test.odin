package shooter

import "core:math"
import "core:testing"

// icon.odin's unit-square -> screen mapping, and the world frame draw_weapon
// builds from it. Only the pure geometry is tested: glyph shapes have no
// assertable output, and pinning menu row heights would make every future
// visual tweak fail the suite without catching anything real. Run with
// `odin test . -define:ODIN_TEST_THREADS=1` per weapon_test.odin's note.

@(test)
test_icon_square_is_identity_on_a_square :: proc(t: ^testing.T) {
	testing.expect_value(t, icon_square({10, 20, 32, 32}), Rect{10, 20, 32, 32})
}

@(test)
test_icon_square_letterboxes_rather_than_stretching :: proc(t: ^testing.T) {
	// a stretched circle stops reading as Gold's circle, so a non-square
	// slot centers the glyph instead of distorting it
	testing.expect_value(t, icon_square({0, 0, 100, 40}), Rect{30, 0, 40, 40})
	testing.expect_value(t, icon_square({0, 0, 40, 100}), Rect{0, 30, 40, 40})
}

@(test)
test_icon_frame_rect_is_upright_and_fills_the_square :: proc(t: ^testing.T) {
	f := icon_frame_rect({5, 5, 20, 20})
	testing.expect_value(t, f.origin, Vec2{5, 5})
	testing.expect_value(t, f.x_axis, Vec2{20, 0})
	testing.expect_value(t, f.y_axis, Vec2{0, 20})
	testing.expect_value(t, f.size, f32(20))
	testing.expect(t, !f.flip_v, "a menu frame never mirrors")
}

@(test)
test_icon_at_maps_the_unit_square :: proc(t: ^testing.T) {
	f := icon_frame_rect({5, 5, 20, 20})
	testing.expect_value(t, icon_at(f, 0, 0), Vec2{5, 5})
	testing.expect_value(t, icon_at(f, 1, 1), Vec2{25, 25})
	testing.expect_value(t, icon_at(f, 0.5, 0.5), Vec2{15, 15})
}

@(test)
test_icon_at_respects_the_letterbox :: proc(t: ^testing.T) {
	// in a wide slot, unit coords land inside the centered square - without
	// this, glyphs would drift left as slots widened
	f := icon_frame_rect({0, 0, 100, 40})
	testing.expect_value(t, icon_at(f, 0, 0), Vec2{30, 0})
	testing.expect_value(t, icon_at(f, 1, 1), Vec2{70, 40})
}

@(test)
test_icon_frame_pivot_anchors_the_grip_on_the_pivot :: proc(t: ^testing.T) {
	// the contract draw_weapon relies on: unit (0, 0.5) - the middle of the
	// glyph's back edge, where every weapon's grip sits - lands exactly on
	// the pivot, so a weapon is held rather than floating near the hand
	f := icon_frame_pivot({100, 50}, 0, 30)
	testing.expect_value(t, icon_at(f, 0, 0.5), Vec2{100, 50})
	// and it extends `size` along the aim
	testing.expect_value(t, icon_at(f, 1, 0.5), Vec2{130, 50})
}

@(test)
test_icon_frame_pivot_mirrors_only_when_aiming_leftward :: proc(t: ^testing.T) {
	// an asymmetric silhouette (a pistol's grip hangs below its barrel) must
	// flip when aiming left, not rotate past vertical and hang its grip in
	// the air. Straight up and straight down are the boundary and stay
	// unmirrored, so the flip happens once, past the vertical.
	testing.expect(t, !icon_frame_pivot({0, 0}, 0, 10).flip_v, "aiming right does not mirror")
	testing.expect(t, !icon_frame_pivot({0, 0}, 89, 10).flip_v, "just short of straight down does not mirror")
	testing.expect(t, !icon_frame_pivot({0, 0}, 90, 10).flip_v, "straight down does not mirror")
	testing.expect(t, icon_frame_pivot({0, 0}, 91, 10).flip_v, "past vertical mirrors")
	testing.expect(t, icon_frame_pivot({0, 0}, 180, 10).flip_v, "aiming left mirrors")
	testing.expect(t, icon_frame_pivot({0, 0}, -135, 10).flip_v, "up-and-left mirrors")
	// atan2 hands out angles in (-180, 180], but a caller accumulating
	// offsets can hand over anything - 270 is the same aim as -90
	testing.expect(t, !icon_frame_pivot({0, 0}, 270, 10).flip_v, "270 normalizes to straight up")
	testing.expect(t, icon_frame_pivot({0, 0}, 540, 10).flip_v, "540 normalizes to leftward")
}

@(test)
test_icon_frame_pivot_mirror_reflects_across_the_aim_axis :: proc(t: ^testing.T) {
	// mirroring must be a reflection, not a translation: a point above the
	// aim axis lands the same distance below it
	f := icon_frame_pivot({0, 0}, 180, 10)
	testing.expect_value(t, icon_at(f, 0, 0.5), Vec2{0, 0}) // the grip still anchors
	above := icon_at(f, 0, 0.2)
	below := icon_at(f, 0, 0.8)
	testing.expect(t, math.abs(above.y + below.y) < 0.001, "mirrored points straddle the aim axis evenly")
}

@(test)
test_triangle_winding_matches_what_raylib_actually_renders :: proc(t: ^testing.T) {
	// These two triangles were rendered and read back off the framebuffer to
	// establish the sign: rl.DrawTriangle renders the NEGATIVE cross product
	// and culls the positive one. raylib's "vertices in counter-clockwise
	// order" docs are ambiguous about y-down screen space, and reading them
	// the other way is what left the retired draw_wedge's melee blade
	// invisible. Do not flip this to match the docs.
	testing.expect(
		t,
		icon_triangle_front_facing({160, 15}, {160, 45}, {190, 30}),
		"negative-cross winding is the one raylib renders",
	)
	testing.expect(
		t,
		!icon_triangle_front_facing({80, 15}, {110, 30}, {80, 45}),
		"positive-cross winding is culled and must be reversed before drawing",
	)
}

@(test)
test_icon_stroke_scales_with_the_frame :: proc(t: ^testing.T) {
	testing.expect_value(t, icon_stroke(icon_frame_rect({0, 0, 100, 100}), 0.2), f32(20))
	// a wide slot's stroke follows the square's size, not its width -
	// otherwise strokes would fatten as a slot got wider while the glyph
	// around them stayed put
	testing.expect_value(t, icon_stroke(icon_frame_rect({0, 0, 100, 40}), 0.5), f32(20))
}

@(test)
test_icon_stroke_floors_at_one_pixel :: proc(t: ^testing.T) {
	// the case this floor exists for: the 9px Resource indicator slot, where
	// a 0.1 unit stroke would scale to 0.9px and effectively vanish
	testing.expect_value(t, icon_stroke(icon_frame_rect({0, 0, 9, 9}), 0.1), f32(ICON_STROKE_MIN))
	// and a degenerate slot still yields something drawable rather than 0
	testing.expect_value(t, icon_stroke(icon_frame_rect({0, 0, 0, 0}), 0.5), f32(ICON_STROKE_MIN))
}

@(test)
test_icon_color_uses_its_own_color_when_untinted :: proc(t: ^testing.T) {
	own := Color{10, 20, 30, 200}
	testing.expect_value(t, icon_color(own, nil, 1), own)
}

@(test)
test_icon_color_replaces_rather_than_multiplies :: proc(t: ^testing.T) {
	// tint replaces outright: gray multiplied over the magic rod's purple
	// would still read purple, and a disabled row whose icon still looks
	// live is the bug this prevents
	tinted := icon_color(Color{160, 40, 200, 255}, Color{130, 130, 130, 255}, 1)
	testing.expect_value(t, tinted, Color{130, 130, 130, 255})
}

@(test)
test_icon_color_applies_alpha_independently_of_tint :: proc(t: ^testing.T) {
	// alpha carries Reveal/Dismiss motion, so it folds in whether or not the
	// glyph is tinted
	own := Color{100, 100, 100, 200}
	testing.expect_value(t, icon_color(own, nil, 0.5), Color{100, 100, 100, 100})
	testing.expect_value(t, icon_color(own, Color{10, 20, 30, 100}, 0.5), Color{10, 20, 30, 50})
}

@(test)
test_every_dispatch_table_entry_is_populated :: proc(t: ^testing.T) {
	// a missing [Enum]Icon_Proc entry is a nil proc that crashes at draw
	// time on a screen that may be rarely reached - and for weapon_icons,
	// on the *world* draw of whichever weapon is equipped
	for kind in Weapon_Kind {
		testing.expect(t, weapon_icons[kind] != nil, "weapon_icons has no entry for a Weapon_Kind")
		testing.expect(t, weapon_icon_reach[kind] > 0, "weapon_icon_reach has no entry for a Weapon_Kind")
	}
	for kind in Upgrade_Kind {
		testing.expect(t, upgrade_icons[kind] != nil, "upgrade_icons has no entry for an Upgrade_Kind")
	}
	for stat in Account_Stat {
		testing.expect(t, account_stat_icons[stat] != nil, "account_stat_icons has no entry for an Account_Stat")
	}
}

@(test)
test_melee_world_frame_puts_the_blade_tip_at_its_actual_range :: proc(t: ^testing.T) {
	// a blade's drawn length reports its real reach - if the frame were
	// sized to `range` directly, the tip would land short of it by whatever
	// fraction of the glyph the blade occupies, and the silhouette would lie
	// about the hit arc
	for kind in weapon_family_kinds[.Melee] {
		weapon := weapon_create(kind)
		melee, is_melee := weapon.variant.(Melee_Weapon)
		testing.expect(t, is_melee, "expected a Melee_Weapon variant")

		size := weapon_world_frame_size(weapon)
		tip := size * weapon_icon_reach[kind]
		testing.expectf(
			t,
			math.abs(tip - melee.range) < 0.01,
			"%v's blade tip lands at %v, expected its range %v",
			kind,
			tip,
			melee.range,
		)
	}
}

@(test)
test_melee_world_frame_ignores_the_global_visual_scale :: proc(t: ^testing.T) {
	// the debug slider must not decouple a blade from the reach it reports
	previous := weapon_visual_scale
	defer weapon_visual_scale = previous

	weapon := weapon_create(.Sword)
	unscaled := weapon_world_frame_size(weapon)
	weapon_visual_scale = 2
	testing.expect_value(t, weapon_world_frame_size(weapon), unscaled)
}

@(test)
test_gun_and_magic_world_frames_follow_the_global_visual_scale :: proc(t: ^testing.T) {
	previous := weapon_visual_scale
	defer weapon_visual_scale = previous

	for kind in ([]Weapon_Kind{.Pistol, .Shotgun, .Fire_Wand}) {
		weapon := weapon_create(kind)
		weapon_visual_scale = 1
		base := weapon_world_frame_size(weapon)
		testing.expect_value(t, base, weapon_visuals[kind].length)

		weapon_visual_scale = 1.5
		testing.expectf(
			t,
			math.abs(weapon_world_frame_size(weapon) - base * 1.5) < 0.01,
			"%v's frame did not follow the global scale",
			kind,
		)
	}
}
