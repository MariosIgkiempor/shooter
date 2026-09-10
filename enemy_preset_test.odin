package shooter

import "core:testing"

// The preset table is the whole of what an enemy is: a Map's composition can
// only name a Kind and a count, so anything an author forgets here has no
// second place to be supplied from. These tests are that backstop - and the
// stamping ones pin ADR-0020's rule that a spawned Enemy is a *pure* copy of
// its preset, since a lookup-at-read-time implementation would pass a
// shallower check.
//
// spawn_enemy_at appends to game.enemies, so those tests reset/restore it -
// run with `odin test . -define:ODIN_TEST_THREADS=1`.

@(test)
test_every_enemy_kind_has_an_authored_preset :: proc(t: ^testing.T) {
	for kind in Enemy_Kind {
		preset := enemy_presets[kind]
		testing.expectf(t, preset.max_health > 0, "%v has no max health, so it would spawn already dead", kind)
		testing.expectf(t, preset.gold > 0, "%v pays nothing for killing it", kind)
		testing.expectf(t, preset.color.a > 0, "%v has no body colour, so it would draw invisible", kind)
	}
}

// hue means Movement Style family (see the palette in enemy.odin), and it is
// only true for as long as every row keeps reading the constants rather than
// picking a colour of its own
@(test)
test_every_presets_colour_is_its_movement_familys :: proc(t: ^testing.T) {
	expected_for_family := [Movement_Style_Kind]Color {
		.Grounded = ENEMY_GROUNDED_COLOR,
		.Floater  = ENEMY_FLOATER_COLOR,
		.Swarmer  = ENEMY_SWARMER_COLOR,
		.Inert    = ENEMY_INERT_COLOR,
	}

	for kind in Enemy_Kind {
		preset := enemy_presets[kind]
		family := movement_style_kind(preset.movement)
		testing.expectf(
			t,
			preset.color == expected_for_family[family],
			"%v moves as a %v but is not painted its family's hue",
			kind,
			family,
		)
	}
}

@(test)
test_spawn_enemy_at_stamps_the_kinds_whole_preset_onto_the_body :: proc(t: ^testing.T) {
	previous_enemies := game.enemies
	game.enemies = {}
	defer {
		delete(game.enemies)
		game.enemies = previous_enemies
	}

	for kind in Enemy_Kind {
		clear(&game.enemies)
		spawn_enemy_at({12, 34}, kind)

		testing.expectf(t, len(game.enemies) == 1, "spawning a %v should append exactly one body", kind)
		if len(game.enemies) != 1 {
			continue
		}

		enemy := game.enemies[0]
		preset := enemy_presets[kind]
		testing.expect_value(t, enemy.kind, kind)
		testing.expect_value(t, enemy.health, preset.max_health)
		testing.expect_value(t, enemy.x, f32(12))
		testing.expect_value(t, enemy.y, f32(34))
		testing.expectf(
			t,
			movement_style_kind(enemy.movement) == movement_style_kind(preset.movement),
			"a spawned %v should move the way its preset says",
			kind,
		)
		testing.expectf(
			t,
			enemy.attack == preset.attack,
			"a spawned %v should attack the way its preset says",
			kind,
		)
	}
}

// the two runtime fields spawn_enemy_at randomizes are the reason a body
// copies its preset's unions rather than reading them back out of the table:
// two Floaters spawned from the same preset must not wobble in lockstep, and
// a pack of Swarmers must close its ring from both sides
@(test)
test_spawn_enemy_at_randomizes_the_per_body_runtime_fields :: proc(t: ^testing.T) {
	previous_enemies := game.enemies
	game.enemies = {}
	defer {
		delete(game.enemies)
		game.enemies = previous_enemies
	}

	floater_kind, floater_found := a_kind_moving_as(.Floater)
	testing.expect(t, floater_found, "the roster should still have a Floater to exercise")
	if floater_found {
		for _ in 0 ..< 12 {
			spawn_enemy_at({0, 0}, floater_kind)
		}
		distinct_phases := false
		first := game.enemies[0].movement.(Floater).wobble_phase
		for enemy in game.enemies {
			if enemy.movement.(Floater).wobble_phase != first {
				distinct_phases = true
			}
		}
		testing.expect(t, distinct_phases, "Floaters spawned from one preset should not share a wobble phase")
	}

	clear(&game.enemies)
	swarmer_kind, swarmer_found := a_kind_moving_as(.Swarmer)
	testing.expect(t, swarmer_found, "the roster should still have a Swarmer to exercise")
	if swarmer_found {
		for _ in 0 ..< 24 {
			spawn_enemy_at({0, 0}, swarmer_kind)
		}
		saw_left, saw_right := false, false
		for enemy in game.enemies {
			switch enemy.movement.(Swarmer).drift_sign {
			case -1:
				saw_left = true
			case 1:
				saw_right = true
			}
		}
		testing.expect(t, saw_left && saw_right, "a pack of Swarmers should turn both ways round the contour")
	}
}

@(private = "file")
a_kind_moving_as :: proc(family: Movement_Style_Kind) -> (kind: Enemy_Kind, found: bool) {
	for candidate in Enemy_Kind {
		if movement_style_kind(enemy_presets[candidate].movement) == family {
			return candidate, true
		}
	}
	return {}, false
}
