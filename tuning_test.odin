package shooter

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

// The Tunable registry is a package-level global that register_tunables
// appends to, and save_tuning/load_tuning read and write a real file at
// TUNING_PATH. Every test here therefore snapshots and restores both, the
// same discipline relic_test.odin and upgrade_test.odin apply to game.player -
// this suite races the same way if run in parallel, hence
// `odin test . -define:ODIN_TEST_THREADS=1`.
//
// Registration also writes through the registered pointers on reset/load, so
// tests that mutate a Tunable restore its Default before finishing rather than
// leaving a globals table skewed for whatever runs next.

// stands the real registry up in isolation and tears it back down. Uses the
// production register_tunables so the tests cover the actual table, not a
// fixture that can drift from it.
@(private = "file")
with_registry :: proc() {
	deinit_tunables()
	register_tunables()
}

@(private = "file")
restore_defaults :: proc() {
	for t in tunables {
		tunable_reset(t)
	}
}

// paired with with_registry, and always deferred. Every slug/label the registry
// clones must be freed inside the same test that allocated it: odin test gives
// each test its own tracking allocator, so a registry built in one test and
// torn down in the next reads as a leak *and* a bad free. Same class of
// test-allocator quirk array_capacity.odin documents.
@(private = "file")
teardown_registry :: proc() {
	restore_defaults()
	deinit_tunables()
}

@(test)
test_every_tunable_slug_is_unique_and_non_empty :: proc(t: ^testing.T) {
	with_registry()
	defer teardown_registry()

	// load-bearing rather than cosmetic: slugs are deliberately decoupled from
	// the Odin identifiers (see Tunable.slug), so nothing structural stops two
	// entries claiming the same key. A collision would silently make one
	// Tunable's Override overwrite the other's on load, and would also hand
	// ui.slider a duplicate node key.
	seen := make(map[string]bool, len(tunables), context.temp_allocator)

	for tunable in tunables {
		testing.expect(t, tunable.slug != "", "every Tunable needs a non-empty slug")
		testing.expectf(t, !seen[tunable.slug], "duplicate Tunable slug %q", tunable.slug)
		seen[tunable.slug] = true
	}

	testing.expect(t, len(tunables) > 0, "register_tunables should register something")
}

@(test)
test_every_label_uses_only_glyphs_the_font_has :: proc(t: ^testing.T) {
	with_registry()
	defer teardown_registry()

	// data/font.ttf bakes a deliberately small glyph set (see atlas_glyphs).
	// A character outside it doesn't fail loudly - it draws as `?`, which is
	// how "Size / Max Health" and "Player (1)" shipped looking like
	// "Size ? Max Health" and "Player ?1?". Checked against the real atlas so
	// it stays honest if the font's coverage ever changes.
	has_glyph :: proc(r: rune) -> bool {
		if r == ' ' {
			return true // no baked glyph; raylib advances past it
		}
		for glyph in atlas_glyphs {
			if glyph.value == r {
				return true
			}
		}
		return false
	}

	for tunable in tunables {
		for r in tunable.label {
			testing.expectf(
				t,
				has_glyph(r),
				"Tunable %q\'s label %q contains %q, which has no glyph in the font and will draw as `?`",
				tunable.slug,
				tunable.label,
				r,
			)
		}
	}

	for group in Tuning_Group {
		for r in tuning_group_display_name[group] {
			testing.expectf(
				t,
				has_glyph(r),
				"Tuning Group %v\'s name %q contains %q, which has no glyph in the font",
				group,
				tuning_group_display_name[group],
				r,
			)
		}
	}
}

@(test)
test_every_tunable_default_lies_within_its_range :: proc(t: ^testing.T) {
	with_registry()
	defer teardown_registry()

	// a Default outside its own slider range is unreachable: the first drag
	// would snap the value somewhere else and there'd be no way back to the
	// authored number short of Reset
	for tunable in tunables {
		testing.expectf(
			t,
			tunable.min <= tunable.max,
			"%q has an inverted range %v..%v",
			tunable.slug,
			tunable.min,
			tunable.max,
		)
		testing.expectf(
			t,
			tunable.default >= tunable.min && tunable.default <= tunable.max,
			"%q's Default %v is outside its range %v..%v",
			tunable.slug,
			tunable.default,
			tunable.min,
			tunable.max,
		)
	}
}

@(test)
test_reset_restores_the_default_for_every_value_kind :: proc(t: ^testing.T) {
	with_registry()
	defer teardown_registry()

	// one of each Tunable_Value variant, so a kind whose get/set round-trip is
	// wrong (int truncating instead of rounding, say) can't hide behind the f32
	// case that dominates the registry
	kinds_seen := 0
	for tunable in tunables {
		moved: f32
		switch value in tunable.value {
		case ^f32:
			moved = tunable.default + 1
		case ^int:
			moved = tunable.default + 1
		case ^bool:
			moved = tunable.default == 0 ? 1 : 0
		}

		tunable_set(tunable, moved)
		testing.expectf(t, tunable_overridden(tunable), "%q should read as Overridden after a change", tunable.slug)

		tunable_reset(tunable)
		testing.expectf(
			t,
			!tunable_overridden(tunable),
			"%q should be back at its Default %v after Reset, got %v",
			tunable.slug,
			tunable.default,
			tunable_get(tunable),
		)
		kinds_seen += 1
	}

	testing.expect(t, kinds_seen == len(tunables), "every registered Tunable should round-trip through Reset")
}

@(test)
test_a_tunable_into_a_union_variant_writes_through_to_the_preset :: proc(t: ^testing.T) {
	with_registry()
	defer teardown_registry()

	// Weapon.variant and Upgrade_Preset.effect are both unions, and their
	// fields are registered from inside a `switch &v in ...`. If that yielded a
	// copy rather than a pointer into the table, every Gun/Melee/Magic and
	// every Upgrade effect slider would silently edit nothing - so assert
	// against the preset table itself, not through the Tunable that wrote it.
	shotgun := find_tunable("weapon.shotgun.pellet_count")
	testing.expect(t, shotgun != nil, "weapon.shotgun.pellet_count should be registered")
	if shotgun != nil {
		tunable_set(shotgun^, 3)
		gun, is_gun := weapon_presets[.Shotgun].variant.(Gun)
		testing.expect(t, is_gun, "Shotgun's variant should be a Gun")
		testing.expectf(t, gun.pellet_count == 3, "expected the write to reach weapon_presets, got %v", gun.pellet_count)
	}

	damage := find_tunable("upgrade.damage.effect")
	testing.expect(t, damage != nil, "upgrade.damage.effect should be registered")
	if damage != nil {
		tunable_set(damage^, 1.5)
		effect, is_multiplicative := upgrade_presets[.Damage].effect.(Multiplicative)
		testing.expect(t, is_multiplicative, "Damage's effect should be Multiplicative")
		testing.expectf(t, f32(effect) == 1.5, "expected the write to reach upgrade_presets, got %v", f32(effect))
	}
}

@(test)
test_value_text_renders_each_kind_without_format_errors :: proc(t: ^testing.T) {
	// the direct regression for `{:.*f}`: Odin's fmt has no runtime-precision
	// verb, and rather than failing it writes its own error text
	// ("%!f(int=1)%!(EXTRA 222.9)") straight into the label - which is what
	// the panel actually displayed.
	value: f32 = 222.919992
	coarse := Tunable {
		slug  = "test.coarse",
		value = &value,
		min   = 0,
		max   = 400,
	}
	testing.expectf(t, tunable_value_text(coarse) == "222.9", "expected \"222.9\", got %q", tunable_value_text(coarse))

	ratio_value: f32 = 0.35
	ratio := Tunable {
		slug  = "test.ratio",
		value = &ratio_value,
		min   = 0,
		max   = 1,
	}
	testing.expectf(t, tunable_value_text(ratio) == "0.350", "expected \"0.350\", got %q", tunable_value_text(ratio))

	count := 7
	int_tunable := Tunable {
		slug  = "test.count",
		value = &count,
		min   = 0,
		max   = 20,
	}
	testing.expectf(t, tunable_value_text(int_tunable) == "7", "expected \"7\", got %q", tunable_value_text(int_tunable))

	flag := true
	bool_tunable := Tunable {
		slug  = "test.flag",
		value = &flag,
	}
	testing.expectf(t, tunable_value_text(bool_tunable) == "ON", "expected \"ON\", got %q", tunable_value_text(bool_tunable))
}

@(test)
test_int_tunable_rounds_rather_than_truncating :: proc(t: ^testing.T) {
	value := 0
	tunable := Tunable {
		slug  = "test.int",
		value = &value,
		min   = 0,
		max   = 10,
	}

	// a slider hands back a continuous f32; truncating would make the top of
	// the range unreachable, since dragging to the far right lands a hair under
	// the maximum
	tunable_set(tunable, 9.999)
	testing.expectf(t, value == 10, "expected 9.999 to round to 10, got %v", value)

	tunable_set(tunable, 3.4)
	testing.expectf(t, value == 3, "expected 3.4 to round to 3, got %v", value)
}

@(test)
test_save_writes_only_overrides_and_load_restores_them :: proc(t: ^testing.T) {
	with_registry()
	defer teardown_registry()

	saved_path_contents, had_existing := snapshot_tuning_file()
	defer restore_tuning_file(saved_path_contents, had_existing)

	first := &tunables[0]
	second := &tunables[len(tunables) / 2]
	first_value := first.default + 1
	second_value := second.default + 1
	tunable_set(first^, first_value)
	tunable_set(second^, second_value)

	testing.expect(t, save_tuning(), "save_tuning should succeed")

	// the file is sparse by design: everything still at its Default is absent,
	// so a later change to a Default shows through instead of being masked
	written, read_error := os.read_entire_file(TUNING_PATH, context.temp_allocator)
	testing.expect(t, read_error == nil, "the saved tuning file should be readable")
	testing.expectf(
		t,
		strings.contains(string(written), first.slug),
		"an Overridden Tunable %q should appear in the file",
		first.slug,
	)

	untouched := tunables[1]
	if untouched.slug != second.slug {
		testing.expectf(
			t,
			!strings.contains(string(written), untouched.slug),
			"a Tunable still at its Default (%q) should not be written",
			untouched.slug,
		)
	}

	// wipe every value, then load: exactly the two Overrides should come back
	restore_defaults()
	load_tuning()

	testing.expectf(t, tunable_get(first^) == first_value, "%q should reload its Override", first.slug)
	testing.expectf(t, tunable_get(second^) == second_value, "%q should reload its Override", second.slug)
	testing.expect(t, !tunable_overridden(tunables[1]) || tunables[1].slug == second.slug, "an unwritten Tunable should stay at its Default")
}

@(test)
test_load_drops_an_unknown_key_without_failing :: proc(t: ^testing.T) {
	with_registry()
	defer teardown_registry()

	saved_path_contents, had_existing := snapshot_tuning_file()
	defer restore_tuning_file(saved_path_contents, had_existing)

	known := &tunables[0]
	known_value := known.default + 1

	// a renamed or deleted global orphans its slug. That must not take the rest
	// of the file down with it - the same self-healing posture load_game takes
	// toward a stale save.
	contents := strings.concatenate(
		{"{\n  \"tuning.slug.that.does.not.exist\": 123,\n  \"", known.slug, "\": "},
		context.temp_allocator,
	)
	contents = strings.concatenate({contents, tunable_value_json(known_value), "\n}\n"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(TUNING_PATH, transmute([]byte)contents) == nil, "test fixture should write")

	restore_defaults()
	load_tuning()

	testing.expectf(
		t,
		tunable_get(known^) == known_value,
		"the known key should still apply alongside an unknown one, got %v",
		tunable_get(known^),
	)
}

// -- fixtures ----------------------------------------------------------------

@(private = "file")
find_tunable :: proc(slug: string) -> ^Tunable {
	for &t in tunables {
		if t.slug == slug {
			return &t
		}
	}
	return nil
}

@(private = "file")
snapshot_tuning_file :: proc() -> (contents: []byte, existed: bool) {
	data, read_error := os.read_entire_file(TUNING_PATH, context.allocator)
	if read_error != nil {
		return nil, false
	}
	return data, true
}

@(private = "file")
restore_tuning_file :: proc(contents: []byte, existed: bool) {
	if existed {
		_ = os.write_entire_file(TUNING_PATH, contents)
		delete(contents)
	} else {
		os.remove(TUNING_PATH)
	}
}

@(private = "file")
tunable_value_json :: proc(value: f32) -> string {
	return fmt.tprintf("{}", value)
}
