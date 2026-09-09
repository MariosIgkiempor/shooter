package shooter

import "core:log"
import "core:os"
import "core:strings"
import "core:testing"

// These drive save_game/load_game, which read and write a real file at
// SAVE_GAME_PATH and operate on the package-level `game` global - so every
// test here snapshots and restores both, the same discipline
// tuning_test.odin applies to TUNING_PATH and the Tunable registry. Run with
// `odin test . -define:ODIN_TEST_THREADS=1`.
//
// Weapon.kind and Weapon.fire_mode are only exercised end-to-end here: they
// live on the live Weapon struct and convert to their identity strings at
// the save_game/load_game boundary (see persistence.odin and ADR-0028),
// which no pure converter test reaches.

@(private = "file")
snapshot_save_file :: proc() -> (contents: []byte, existed: bool) {
	data, err := os.read_entire_file(SAVE_GAME_PATH, context.allocator)
	return data, err == nil
}

@(private = "file")
restore_save_file :: proc(contents: []byte, existed: bool) {
	if existed {
		_ = os.write_entire_file(SAVE_GAME_PATH, contents)
		delete(contents)
	} else {
		os.remove(SAVE_GAME_PATH)
	}
}

@(private = "file")
write_save_file :: proc(t: ^testing.T, contents: string) {
	err := os.write_entire_file(SAVE_GAME_PATH, transmute([]byte)contents)
	testing.expect(t, err == nil, "the test save file should be writable")
}

// Flame_Staff is the most demanding subject on the roster: Weapon_Kind
// ordinal 6, Fire_Mode.Automatic ordinal 1, Spell_Kind.Flamethrower ordinal
// 1 - all three nonzero, so a silent collapse to ordinal zero is visible.
@(test)
test_save_game_round_trips_the_weapon_by_name :: proc(t: ^testing.T) {
	snapshot, existed := snapshot_save_file()
	defer restore_save_file(snapshot, existed)
	saved_game := game
	defer game = saved_game

	game.player.weapon = weapon_presets[.Flame_Staff]
	save_game()

	written, read_err := os.read_entire_file(SAVE_GAME_PATH, context.temp_allocator)
	testing.expect(t, read_err == nil, "the save file should be readable")
	text := string(written)
	testing.expect(t, strings.contains(text, "Flame_Staff"), "the weapon kind should be written by name")
	testing.expect(t, strings.contains(text, "Automatic"), "the fire mode should be written by name")
	testing.expect(t, strings.contains(text, "Flamethrower"), "the spell kind should be written by name")

	game.player.weapon = {}
	load_game()

	testing.expect_value(t, game.player.weapon.kind, Weapon_Kind.Flame_Staff)
	testing.expect_value(t, game.player.weapon.fire_mode, Fire_Mode.Automatic)
	magic, is_magic := game.player.weapon.variant.(Magic)
	testing.expect(t, is_magic, "the loaded weapon should still be a Magic")
	testing.expect_value(t, magic.spell_kind, Spell_Kind.Flamethrower)
}

// The whole point of the ticket, at the outermost seam. Asserting only that
// the weapon didn't come back as Flame_Staff would pass under the old
// ordinal behaviour too - what distinguishes them is that the *fallback ran*,
// so the level and gold in the file are gone rather than paired with a
// Pistol conjured out of ordinal zero.
@(test)
test_load_game_falls_back_when_the_save_names_a_weapon_this_build_lacks :: proc(t: ^testing.T) {
	snapshot, existed := snapshot_save_file()
	defer restore_save_file(snapshot, existed)
	saved_game := game
	defer game = saved_game

	write_save_file(
		t,
		`{"player":{"weapon":{"kind_save":"Blunderbuss","fire_mode_save":"Automatic"},"weapon_variant_save":{"kind":"Gun","gun":{"clip_size":12}},"level":9,"gold":500}}`,
	)

	// the reported error is what this test asserts on, and core:testing
	// fails any test that emits an error-level log
	reporting := context.logger
	context.logger = log.nil_logger()
	defer context.logger = reporting
	load_game()

	testing.expect_value(t, game.player.level, 1)
	testing.expect_value(t, game.player.gold, 0)
}
