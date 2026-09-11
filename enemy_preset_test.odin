package shooter

import "core:testing"
import rl "vendor:raylib"

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

// Hue means Movement Style family (see the palette in enemy.odin), and it is
// only true for as long as every row keeps taking its colour from the family
// constants. The assertion is on *hue* rather than on the whole colour on
// purpose: the roster distinguishes Kinds inside one family by value (a pale
// green Spitter beside a green Grunt), so pinning exact equality here would
// forbid the thing the palette is supposed to leave room for.
ENEMY_FAMILY_HUE_TOLERANCE :: f32(12) // degrees; the five family hues sit ~50 degrees apart at their closest

@(test)
test_every_presets_hue_is_its_movement_familys :: proc(t: ^testing.T) {
	family_color := [Movement_Style_Kind]Color {
		.Grounded = ENEMY_GROUNDED_COLOR,
		.Floater  = ENEMY_FLOATER_COLOR,
		.Swarmer  = ENEMY_SWARMER_COLOR,
		.Charger  = ENEMY_CHARGER_COLOR,
		.Inert    = ENEMY_INERT_COLOR,
	}

	for kind in Enemy_Kind {
		preset := enemy_presets[kind]
		family := movement_style_kind(preset.movement)
		drift := hue_degrees_apart(preset.color, family_color[family])
		testing.expectf(
			t,
			drift <= ENEMY_FAMILY_HUE_TOLERANCE,
			"%v moves as a %v but its hue is %.0f degrees off its family's",
			kind,
			family,
			drift,
		)
	}
}

// the five family hues must stay far enough apart that the check above can
// tell them apart at all - a repaint that quietly moved two together would
// otherwise leave every row passing while the screen stopped being readable
@(test)
test_the_movement_family_hues_stay_apart :: proc(t: ^testing.T) {
	palette := []Color {
		ENEMY_GROUNDED_COLOR,
		ENEMY_FLOATER_COLOR,
		ENEMY_SWARMER_COLOR,
		ENEMY_CHARGER_COLOR,
		ENEMY_INERT_COLOR,
	}

	for a, i in palette {
		for b in palette[i + 1:] {
			drift := hue_degrees_apart(a, b)
			testing.expectf(
				t,
				drift > ENEMY_FAMILY_HUE_TOLERANCE * 2,
				"two family hues (%v, %v) are only %.0f degrees apart, which is inside what a Kind is allowed to drift",
				a,
				b,
				drift,
			)
		}
	}
}

@(private = "file")
hue_degrees_apart :: proc(a, b: Color) -> f32 {
	drift := abs(rl.ColorToHSV(a).x - rl.ColorToHSV(b).x)
	return min(drift, 360 - drift) // hue wraps, so red at 359 is 2 degrees from red at 1
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
		testing.expect_value(t, enemy.max_health, preset.max_health)
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

// a Tell_Area whose rotation is empty is inert (update_tell_area guards the
// modulo), and one whose entry has a zero radius or damage telegraphs nothing
// worth dodging - either is an authoring slip with no second place to catch
// it. The "at least one" clause keeps the variant from silently falling off
// the roster when the eight Kinds are re-authored (ticket 11).
@(test)
test_every_tell_area_preset_authors_a_playable_rotation :: proc(t: ^testing.T) {
	carriers := 0
	for kind in Enemy_Kind {
		a, is_tell := enemy_presets[kind].attack.(Tell_Area)
		if !is_tell {
			continue
		}
		carriers += 1
		testing.expectf(
			t,
			a.rotation_count >= 1 && a.rotation_count <= TELL_AREA_MAX_ROTATION,
			"%v's rotation has %d live entries, outside 1..%d",
			kind,
			a.rotation_count,
			TELL_AREA_MAX_ROTATION,
		)
		testing.expectf(t, a.cooldown_seconds > 0, "%v would Tell again the frame it resolved", kind)
		for i in 0 ..< min(a.rotation_count, TELL_AREA_MAX_ROTATION) {
			attack := a.rotation[i]
			testing.expectf(t, attack.radius > 0, "%v's attack %d claims no ground", kind, i)
			testing.expectf(t, attack.damage > 0, "%v's attack %d lands for nothing", kind, i)
			testing.expectf(t, attack.tell_seconds > 0, "%v's attack %d has no Tell to read", kind, i)
		}
	}
	testing.expect(t, carriers > 0, "no Kind carries a Tell_Area, so nothing in the game ever telegraphs")
}

// the roster's speed rule (content-expansion's Enemy catalog): nothing
// sustains a pace the player cannot walk away from, and the one thing that
// exceeds it does so only for its dash. Both halves are checked against the
// player's base speed, since a Charger authored between the two would be
// either a footrace or a dash that never catches anyone. The "at least one"
// clause keeps the Movement Style from silently falling off the roster when
// the eight Kinds are re-authored (ticket 11).
@(test)
test_every_charger_preset_outruns_the_player_only_while_dashing :: proc(t: ^testing.T) {
	carriers := 0
	for kind in Enemy_Kind {
		c, is_charger := enemy_presets[kind].movement.(Charger)
		if !is_charger {
			continue
		}
		carriers += 1
		testing.expectf(t, c.speed > 0 && c.speed < PLAYER_BASE_MOVE_SPEED, "%v sustains %v against the player's %v - a footrace", kind, c.speed, PLAYER_BASE_MOVE_SPEED)
		testing.expectf(t, c.dash_speed > PLAYER_BASE_MOVE_SPEED, "%v dashes at %v, which the player outruns", kind, c.dash_speed)
		testing.expectf(t, c.dash_distance > 0, "%v's dash goes nowhere", kind)
		testing.expectf(t, c.tell_seconds > 0, "%v's lane has no Tell to read", kind)
		testing.expectf(t, c.recovery_seconds > 0 && c.cooldown_seconds > 0, "%v would dash again the frame its dash ended", kind)
	}
	testing.expect(t, carriers > 0, "no Kind is a Charger, so nothing in the game can catch a running player")
}
