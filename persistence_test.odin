package shooter

import "base:intrinsics"
import "core:log"
import "core:testing"

// Pure conversions over static type info - no `game` global, no files - so
// unlike weapon_test.odin/tuning_test.odin these need no
// -define:ODIN_TEST_THREADS=1 discipline.

@(private = "file")
expect_round_trip :: proc(t: ^testing.T, $E: typeid) where intrinsics.type_is_enum(E) {
	for value in E {
		name := enum_identity_string(value)
		testing.expectf(t, name != "", "{} should have a non-empty identity string", value)

		back, ok := enum_from_identity_string(E, name)
		testing.expectf(t, ok, "identity `{}` should resolve back to a {}", name, typeid_of(E))
		testing.expectf(t, back == value, "{} should round-trip through `{}`, got {}", value, name, back)
	}
}

// Third checkbox of
// .scratch/content-expansion-build/issues/03-enums-persist-by-identity-string.md,
// mechanically: every enum this game persists survives a
// trip through its identity string. Driven off the enum type itself rather
// than a hand-written case list, so a case added later is covered for free.
@(test)
test_every_persisted_enum_round_trips_through_its_identity_string :: proc(t: ^testing.T) {
	expect_round_trip(t, Weapon_Kind)
	expect_round_trip(t, Fire_Mode)
	expect_round_trip(t, Spell_Kind)
	expect_round_trip(t, Weapon_Variant_Kind)
	expect_round_trip(t, Spawn_Condition_Kind)
	expect_round_trip(t, Spawn_Mode_Kind)
	expect_round_trip(t, Movement_Style_Kind)
	expect_round_trip(t, Attack_Style_Kind)
	expect_round_trip(t, Map_Name)
}

// Round-trip alone would pass under any self-consistent encoding. This pins
// it to Odin's own declared case names, which is what makes the on-disk form
// readable and the map_builder's duplicated string literals correct.
@(test)
test_an_identity_string_is_the_declared_case_name :: proc(t: ^testing.T) {
	testing.expect_value(t, enum_identity_string(Weapon_Kind.Poison_Staff), "Poison_Staff")
	testing.expect_value(t, enum_identity_string(Fire_Mode.Semi_Automatic), "Semi_Automatic")
	testing.expect_value(t, enum_identity_string(Movement_Style_Kind.Inert), "Inert")
}

// Second checkbox of that same ticket, at the unit level. The point isn't which value comes
// back - it's that ok is false, so no caller can mistake a renamed case for
// whatever now sits at ordinal zero.
@(test)
test_an_unrecognised_identity_string_is_rejected :: proc(t: ^testing.T) {
	// the reported error is what this test asserts on, and core:testing
	// fails any test that emits an error-level log
	reporting := context.logger
	context.logger = log.nil_logger()
	defer context.logger = reporting

	_, misspelled_ok := enum_from_identity_string(Spawn_Condition_Kind, "Time_Elapsedd")
	testing.expect(t, !misspelled_ok, "a misspelled case name should not resolve")

	_, empty_ok := enum_from_identity_string(Spawn_Condition_Kind, "")
	testing.expect(t, !empty_ok, "an absent identity should not resolve")

	// the ordinal encoding this replaces, offered as a name
	_, ordinal_ok := enum_from_identity_string(Movement_Style_Kind, "0")
	testing.expect(t, !ordinal_ok, "an ordinal should not resolve as an identity")
}
