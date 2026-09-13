package shooter

import "core:os"
import "core:strings"
import "core:testing"

// The roster persists as Odin source and nothing else (ADR-0027): the
// editor's Presets mode edits the live table and Export writes it back as
// enemy_presets.odin. These tests pin the generator to that file, so the two
// cannot drift - a hand edit that changes the shape, or a new authored field
// the generator forgot, fails here rather than at the next Export.

@(test)
test_the_checked_in_preset_table_is_what_the_exporter_writes :: proc(t: ^testing.T) {
	on_disk, read_err := os.read_entire_file(ENEMY_PRESETS_SOURCE_PATH, context.temp_allocator)
	testing.expectf(t, read_err == nil, "`%s` should exist - it is the roster: %v", ENEMY_PRESETS_SOURCE_PATH, read_err)

	generated := enemy_presets_source(enemy_presets, context.temp_allocator)
	testing.expectf(
		t,
		string(on_disk) == generated,
		"`%s` is not what the exporter writes for the live table - regenerate it from the editor's Presets mode, or teach the generator the field that moved",
		ENEMY_PRESETS_SOURCE_PATH,
	)
}

// a body's runtime half (timers, phases, the Tell's locked centre) is never
// authored, so it must not reach the literal - the table stamps it zero
@(test)
test_the_exporter_writes_only_a_variants_authored_fields :: proc(t: ^testing.T) {
	clean := enemy_presets
	dirty := enemy_presets

	// every variant's runtime fields, set to something a zero stamp never is
	dirty[.Wraith].movement = Floater {
		speed            = 45,
		wobble_amplitude = 80,
		wobble_frequency = 3,
		pull_strength    = 0.35,
		wobble_phase     = 2.5,
	}
	clean[.Wraith].movement = Floater{speed = 45, wobble_amplitude = 80, wobble_frequency = 3, pull_strength = 0.35}
	dirty[.Mite].movement = Swarmer{speed = 65, drift_sign = -1}
	clean[.Mite].movement = Swarmer{speed = 65}
	dirty[.Lancer].movement = Charger {
		speed            = 55,
		dash_speed       = 260,
		dash_distance    = 140,
		tell_seconds     = 0.5,
		recovery_seconds = 0.5,
		cooldown_seconds = 1.5,
		phase            = .Dashing,
		timer            = 0.2,
		dash_remaining   = 30,
		lane_origin      = {10, 10},
		lane_dir         = {0, 1},
	}
	clean[.Lancer].movement = Charger {
		speed            = 55,
		dash_speed       = 260,
		dash_distance    = 140,
		tell_seconds     = 0.5,
		recovery_seconds = 0.5,
		cooldown_seconds = 1.5,
	}
	dirty[.Grunt].attack = Melee{attack_damage = 10, attack_range = 10, attack_cooldown = 1, attack_timer = 0.7}
	clean[.Grunt].attack = Melee{attack_damage = 10, attack_range = 10, attack_cooldown = 1}
	dirty[.Spitter].attack = Ranged {
		min_range        = 60,
		max_range        = 120,
		attack_damage    = 8,
		projectile_speed = 200,
		fire_rate        = 1,
		bullet_lifetime  = 2,
		fire_timer       = 0.3,
	}
	clean[.Spitter].attack = Ranged {
		min_range        = 60,
		max_range        = 120,
		attack_damage    = 8,
		projectile_speed = 200,
		fire_rate        = 1,
		bullet_lifetime  = 2,
	}
	dirty[.Breaker].attack = Tell_Area {
		phases = {
			0 = {
				rotation = {0 = {radius = 28, reach = 40, damage = 18, tell_seconds = 0.6}, 1 = {radius = 99, reach = 99, damage = 99, tell_seconds = 9}},
				rotation_count = 1,
				cooldown_seconds = 1.5,
			},
			1 = {enter_below = 0.5, rotation = {0 = {radius = 99, reach = 99, damage = 99, tell_seconds = 9}}, rotation_count = 1, cooldown_seconds = 9},
		},
		phase_count = 1,
		phase_index = 2,
		rotation_index = 3,
		tell_remaining = 0.4,
		tell_centre = {50, 50},
		cooldown_timer = 1,
	}
	clean[.Breaker].attack = Tell_Area {
		phases = {
			0 = {
				rotation = {0 = {radius = 28, reach = 40, damage = 18, tell_seconds = 0.6}},
				rotation_count = 1,
				cooldown_seconds = 1.5,
			},
		},
		phase_count = 1,
	}

	testing.expect(
		t,
		enemy_presets_source(dirty, context.temp_allocator) == enemy_presets_source(clean, context.temp_allocator),
		"runtime fields, rotation entries past rotation_count and phases past phase_count should not reach the literal",
	)
}

@(test)
test_the_exporter_writes_every_live_rotation_entry_and_phase :: proc(t: ^testing.T) {
	presets := enemy_presets
	presets[.Breaker].attack = Tell_Area {
		phases = {
			0 = {
				rotation = {0 = {radius = 28, reach = 40, damage = 18, tell_seconds = 0.6}, 1 = {radius = 60, reach = 0, damage = 30, tell_seconds = 1.2}},
				rotation_count = 2,
				cooldown_seconds = 1.5,
			},
			1 = {enter_below = 0.5, rotation = {0 = {radius = 70, reach = 10, damage = 31, tell_seconds = 0.8}}, rotation_count = 1, cooldown_seconds = 1.15},
		},
		phase_count = 2,
	}

	source := enemy_presets_source(presets, context.temp_allocator)
	testing.expect(t, strings.contains(source, "1 = {radius = 60, reach = 0, damage = 30, tell_seconds = 1.2}"), "the second rotation entry should be written")
	testing.expect(t, strings.contains(source, "rotation_count = 2"), "the rotation count should be written")
	testing.expect(
		t,
		strings.contains(source, "1 = {enter_below = 0.5, rotation = {0 = {radius = 70, reach = 10, damage = 31, tell_seconds = 0.8}}, rotation_count = 1, cooldown_seconds = 1.15}"),
		"the second phase should be written whole",
	)
	testing.expect(t, strings.contains(source, "phase_count = 2"), "the phase count should be written")
}

// the Boss flag is authored like any other preset field, so the literal
// carries it for every Kind - false is written rather than omitted, because
// an omitted field is one a reader has to know the default of
@(test)
test_the_exporter_writes_the_boss_flag_for_every_kind :: proc(t: ^testing.T) {
	presets := enemy_presets
	for &preset in presets {
		preset.boss = false
	}
	presets[.Grunt].boss = true

	source := enemy_presets_source(presets, context.temp_allocator)
	testing.expect_value(t, strings.count(source, "boss = true,"), 1)
	testing.expect_value(t, strings.count(source, "boss = false,"), len(Enemy_Kind) - 1)
}

// a family colour is the named constant, so the literal keeps saying which
// family the Kind belongs to (the hue test's whole premise); anything else is
// still valid source, just a colour the hue test will have an opinion about
@(test)
test_a_family_colour_exports_by_name_and_any_other_as_a_literal :: proc(t: ^testing.T) {
	presets := enemy_presets
	presets[.Grunt].color = ENEMY_GROUNDED_COLOR
	presets[.Spitter].color = Color{1, 2, 3, 255}

	source := enemy_presets_source(presets, context.temp_allocator)
	testing.expect(t, strings.contains(source, "color = ENEMY_GROUNDED_COLOR,"), "a family colour should export as its constant's name")
	testing.expect(t, strings.contains(source, "color = Color{1, 2, 3, 255},"), "an off-family colour should export as a literal")
}

// the editor moves numbers by slider, so what lands is whatever f32 the drag
// stopped on - the literal should read back as that exact value, and read
// like a number a person typed rather than its 8-digit expansion
@(test)
test_a_slid_number_exports_as_the_shortest_literal_that_reads_back_exactly :: proc(t: ^testing.T) {
	presets := enemy_presets
	presets[.Grunt].movement = Grounded{speed = 0.35}
	presets[.Grunt].max_health = 12345.678

	source := enemy_presets_source(presets, context.temp_allocator)
	testing.expect(t, strings.contains(source, "Grounded{speed = 0.35}"), "0.35 should not export as 0.34999999")
	testing.expect(t, strings.contains(source, "max_health = 12345.678,"), "a number should keep every digit it needs")
}

EXPORTED_PRESETS_TEST_PATH :: "data/enemy_presets_export_test.odin.txt"

@(test)
test_export_writes_the_file_it_would_generate :: proc(t: ^testing.T) {
	testing.expect(t, export_enemy_presets(EXPORTED_PRESETS_TEST_PATH), "export should write")
	defer os.remove(EXPORTED_PRESETS_TEST_PATH)

	written, read_err := os.read_entire_file(EXPORTED_PRESETS_TEST_PATH, context.temp_allocator)
	testing.expectf(t, read_err == nil, "the exported file should read back: %v", read_err)
	testing.expect(
		t,
		string(written) == enemy_presets_source(enemy_presets, context.temp_allocator),
		"export should write exactly the generated source",
	)
}

// switching a Kind's family in the editor stamps a template; that template
// must be of the family asked for and already obey the roster's rules, so a
// fresh switch never starts from something the preset tests would reject
@(test)
test_every_family_has_a_default_style_of_its_kind :: proc(t: ^testing.T) {
	for family in Movement_Style_Kind {
		movement := default_movement_style(family)
		testing.expectf(t, movement_style_kind(movement) == family, "the default %v movement is a %v", family, movement_style_kind(movement))
		speed := movement_sustained_speed(movement)
		testing.expectf(t, speed < ENEMY_SUSTAINED_SPEED_CEILING, "the default %v sustains %v, over the roster's ceiling", family, speed)
	}
	for family in Attack_Style_Kind {
		attack := default_attack_style(family)
		testing.expectf(t, attack_style_kind(attack) == family, "the default %v attack is a %v", family, attack_style_kind(attack))
		if area, is_area := attack.(Tell_Area); is_area {
			testing.expect(t, area.phase_count >= 1 && area.phases[0].rotation_count >= 1, "a default Tell_Area should have a phase with a rotation to run")
		}
	}
}

// the swatch picker offers a Kind only its family's named colours, and a
// family switch repaints with the family's base hue - both stand on every
// family having an entry in the palette table
@(test)
test_every_movement_family_has_a_named_colour_to_be_painted_with :: proc(t: ^testing.T) {
	for family in Movement_Style_Kind {
		base := enemy_family_base_color(family)
		testing.expectf(t, enemy_color_is_familys(base, family), "%v's base colour is not one of its own named colours", family)
	}
	testing.expect(t, !enemy_color_is_familys(ENEMY_CHARGER_COLOR, .Grounded), "a family's colour should not pass as another's")
}
