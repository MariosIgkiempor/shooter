package shooter

import "core:math"
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
// it. Phases add their own: a threshold outside (0, 1) is never or always
// crossed, and thresholds that do not fall strictly with the phase index
// would skip or shadow a stretch. The Tell floor is boss-telegraph-and-
// phase-feel's finding that 0.35s was unreadable when caught adjacent. The
// "at least one" clause keeps the variant from silently falling off the
// roster when the Kinds are re-authored (ticket 11).
TELL_AREA_MIN_TELL_SECONDS :: f32(0.45)

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
			a.phase_count >= 1 && a.phase_count <= TELL_AREA_MAX_PHASES,
			"%v has %d live phases, outside 1..%d",
			kind,
			a.phase_count,
			TELL_AREA_MAX_PHASES,
		)
		for p in 0 ..< min(a.phase_count, TELL_AREA_MAX_PHASES) {
			phase := a.phases[p]
			if p >= 1 {
				testing.expectf(t, phase.enter_below > 0 && phase.enter_below < 1, "%v's phase %d is entered below %v, which is never or always", kind, p, phase.enter_below)
			}
			if p >= 2 {
				testing.expectf(t, phase.enter_below < a.phases[p - 1].enter_below, "%v's phase %d threshold does not fall below phase %d's", kind, p, p - 1)
			}
			testing.expectf(
				t,
				phase.rotation_count >= 1 && phase.rotation_count <= TELL_AREA_MAX_ROTATION,
				"%v's phase %d rotation has %d live entries, outside 1..%d",
				kind,
				p,
				phase.rotation_count,
				TELL_AREA_MAX_ROTATION,
			)
			testing.expectf(t, phase.cooldown_seconds > 0, "%v's phase %d would Tell again the frame it resolved", kind, p)
			for i in 0 ..< min(phase.rotation_count, TELL_AREA_MAX_ROTATION) {
				attack := phase.rotation[i]
				testing.expectf(t, attack.radius > 0, "%v's phase %d attack %d claims no ground", kind, p, i)
				testing.expectf(t, attack.damage > 0, "%v's phase %d attack %d lands for nothing", kind, p, i)
				testing.expectf(
					t,
					attack.tell_seconds >= TELL_AREA_MIN_TELL_SECONDS,
					"%v's phase %d attack %d Tells for %vs, under the %vs a player can read",
					kind,
					p,
					i,
					attack.tell_seconds,
					TELL_AREA_MIN_TELL_SECONDS,
				)
			}
		}
	}
	testing.expect(t, carriers > 0, "no Kind carries a Tell_Area, so nothing in the game ever telegraphs")
}

// the roster's speed rule (content-expansion's Enemy catalog): nothing
// sustains a pace the player cannot walk away from, and the one thing that
// exceeds it does so only for its dash. The sustained half is the roster-
// wide rule below and covers a Charger's approach with everything else;
// this pins the other half, that the dash itself does catch the player.
// The "at least one" clause keeps the Movement Style from silently falling
// off the roster.
@(test)
test_every_charger_preset_outruns_the_player_only_while_dashing :: proc(t: ^testing.T) {
	carriers := 0
	for kind in Enemy_Kind {
		c, is_charger := enemy_presets[kind].movement.(Charger)
		if !is_charger {
			continue
		}
		carriers += 1
		testing.expectf(t, c.speed > 0, "%v never approaches", kind)
		testing.expectf(t, c.dash_speed > PLAYER_BASE_MOVE_SPEED, "%v dashes at %v, which the player outruns", kind, c.dash_speed)
		testing.expectf(t, c.dash_distance > 0, "%v's dash goes nowhere", kind)
		testing.expectf(t, c.tell_seconds > 0, "%v's lane has no Tell to read", kind)
		testing.expectf(t, c.recovery_seconds > 0 && c.cooldown_seconds > 0, "%v would dash again the frame its dash ended", kind)
	}
	testing.expect(t, carriers > 0, "no Kind is a Charger, so nothing in the game can catch a running player")
}

// -- the roster's rulebook (ticket 11) --------------------------------------
//
// The rules below are the content-expansion catalog's authoring conventions
// turned into checks. Each is a rule an author would otherwise have to
// remember, and each has a failure mode that nothing else catches: a body
// past the envelope routes through walls it visibly overlaps, a footrace
// enemy makes kiting stop working everywhere at once, a mispriced Kind
// bends the ladder's economy, and a Kind no Map places is dead content.

// size derives from health (enemy_body_size) and reads as toughness only
// while the clamp never bites an ordinary Kind - a body pinned at the clamp
// would draw the same at 200 health as at 136. And every ordinary Kind
// shares one flow field inflated by FLOW_FIELD_INFLATION_RADIUS, so its
// drawn body must fit the corridor that field keeps clear of walls:
// ADR-0020's amendment puts that at 48px (~136 health) for a one-tile
// radius. The boss is the one body allowed past it, and it gets its own
// field (ticket 21) rather than a licence here.
@(test)
test_every_presets_body_fits_the_clamp_and_the_inflation_envelope :: proc(t: ^testing.T) {
	tile := max(f32)
	for name in Map_Name {
		tile = min(tile, maps[name].tilemap.tile_size.x)
	}
	envelope := 2 * (f32(FLOW_FIELD_INFLATION_RADIUS) * tile + tile / 2)

	for kind in Enemy_Kind {
		preset := enemy_presets[kind]
		unclamped := ENEMY_SIZE_MIN + preset.max_health * ENEMY_SIZE_PER_MAX_HEALTH
		testing.expectf(
			t,
			unclamped <= ENEMY_SIZE_MAX,
			"%v's %.0f health derives a %.0fpx body, which the %.0fpx clamp would hide",
			kind,
			preset.max_health,
			unclamped,
			ENEMY_SIZE_MAX,
		)
		size := enemy_body_size(preset.max_health)
		testing.expectf(
			t,
			size <= envelope,
			"%v's %.0fpx body overflows the %.0fpx corridor the shared flow field keeps clear of walls",
			kind,
			size,
			envelope,
		)
	}
}

// nothing on the roster can catch a player who keeps moving: pressure comes
// from ground and angles, not a footrace. The catalog's rule is a ceiling
// well under the player's speed, not merely below it - the margin is what
// makes kiting *work* rather than barely hold - so the ceiling is pinned
// against the player too. The Charger's dash is the named exception and
// its own test pins that half; its sustained approach is held here with
// everything else.
ENEMY_SUSTAINED_SPEED_CEILING :: f32(70)

@(test)
test_every_presets_sustained_speed_is_under_the_players :: proc(t: ^testing.T) {
	testing.expectf(
		t,
		ENEMY_SUSTAINED_SPEED_CEILING < PLAYER_BASE_MOVE_SPEED,
		"the roster's speed ceiling %v is not under the player's %v",
		ENEMY_SUSTAINED_SPEED_CEILING,
		PLAYER_BASE_MOVE_SPEED,
	)
	for kind in Enemy_Kind {
		speed := movement_sustained_speed(enemy_presets[kind].movement)
		testing.expectf(
			t,
			speed < ENEMY_SUSTAINED_SPEED_CEILING,
			"%v sustains %v against a ceiling of %v (the player runs at %v)",
			kind,
			speed,
			ENEMY_SUSTAINED_SPEED_CEILING,
			PLAYER_BASE_MOVE_SPEED,
		)
	}
}

// payout sits on ENEMY_GOLD_PER_MAX_HEALTH's anchor unless the Kind is
// named here, with the direction it deviates in - so a named Kind must
// actually deviate, and that way round, or the list rots into a blanket
// exemption
ENEMY_GOLD_ANCHOR_TOLERANCE :: 3 // Gold; room to round a payout to a readable number

Payout_Deviation :: enum {
	None,
	Below,
	Above,
}

@(test)
test_every_presets_payout_sits_on_the_anchor_or_is_a_named_deviation :: proc(t: ^testing.T) {
	named_deviation: [Enemy_Kind]Payout_Deviation
	named_deviation[.Sentry] = .Below // a body that never moves is the safest kill on the roster
	named_deviation[.Lancer] = .Above // the highest threat per body
	named_deviation[.Mite] = .Below // far below: Gold rolls per body, so at swarm density an anchored Mite out-earns the ladder

	for kind in Enemy_Kind {
		preset := enemy_presets[kind]
		anchor := int(math.round(preset.max_health * ENEMY_GOLD_PER_MAX_HEALTH))
		actual: Payout_Deviation = .None
		if preset.gold - anchor > ENEMY_GOLD_ANCHOR_TOLERANCE {
			actual = .Above
		} else if anchor - preset.gold > ENEMY_GOLD_ANCHOR_TOLERANCE {
			actual = .Below
		}
		testing.expectf(
			t,
			actual == named_deviation[kind],
			"%v pays %d against an anchor of %d (%v), but is authored as %v",
			kind,
			preset.gold,
			anchor,
			actual,
			named_deviation[kind],
		)
	}
}

// a Kind no authored composition places is content the player never meets;
// the check is over the baked table, so it holds for what ships rather than
// for what the editor could load
@(test)
test_every_enemy_kind_appears_in_an_authored_composition :: proc(t: ^testing.T) {
	seen: [Enemy_Kind]bool
	for name in Map_Name {
		for trigger in maps[name].spawn_triggers {
			for entry in trigger.composition {
				testing.expectf(t, entry.count > 0, "%v places %d %v, which spawns nothing", name, entry.count, entry.kind)
				seen[entry.kind] = true
			}
		}
	}
	for kind in Enemy_Kind {
		testing.expectf(t, seen[kind], "no authored Map places a %v", kind)
	}
}

// the same "at least one" clause the Tell_Area and Charger tests carry: the
// family that holds still is a player response of its own (you must cross to
// it), and it falls off the roster silently if no Kind is authored Inert
@(test)
test_an_inert_preset_holds_the_line :: proc(t: ^testing.T) {
	_, found := a_kind_moving_as(.Inert)
	testing.expect(t, found, "no Kind is Inert, so nothing on the roster makes the player cross open ground")
}
