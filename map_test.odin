package shooter

import "core:log"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

// clone_map's composition needs its own nested clone pass - a bare
// slice.clone_to_dynamic on the outer spawn_triggers array only copies each
// Spawn_Trigger struct by value, which would leave every clone's
// composition field aliasing the same backing array as the template (map.odin
// map format migration ticket 05). This test constructs its own throwaway
// template Map rather than touching game.current_map/game.editing_map, so it
// needs no ODIN_TEST_THREADS=1 discipline.

@(test)
test_clone_map_composition_does_not_alias_the_template :: proc(t: ^testing.T) {
	template: Map
	append(&template.tilemap.tiles, Tile{world_coords = {0, 0}})
	append(
		&template.spawn_triggers,
		Spawn_Trigger {
			condition = Time_Elapsed{seconds = 0},
			mode = One_Shot{},
			composition = slice.clone([]Spawn_Composition_Entry{{movement_template = Grounded{speed = 40}, count = 1}}),
		},
	)
	defer delete_map(template)

	clone := clone_map(template)
	defer delete_map(clone)

	clone.spawn_triggers[0].composition[0].count = 99

	testing.expectf(
		t,
		template.spawn_triggers[0].composition[0].count == 1,
		"mutating a clone's composition entry should not affect the template's - got template count %v",
		template.spawn_triggers[0].composition[0].count,
	)
}

@(test)
test_clone_map_tilemap_and_spawn_triggers_do_not_alias_the_template :: proc(t: ^testing.T) {
	template: Map
	append(&template.tilemap.tiles, Tile{world_coords = {0, 0}})
	append(&template.spawn_triggers, Spawn_Trigger{condition = Time_Elapsed{seconds = 0}, mode = One_Shot{}})
	defer delete_map(template)

	clone := clone_map(template)
	defer delete_map(clone)

	append(&clone.tilemap.tiles, Tile{world_coords = {1, 1}})
	append(&clone.spawn_triggers, Spawn_Trigger{condition = Time_Elapsed{seconds = 5}, mode = One_Shot{}})

	testing.expectf(t, len(template.tilemap.tiles) == 1, "growing a clone's tiles should not affect the template's, got %v", len(template.tilemap.tiles))
	testing.expectf(t, len(template.spawn_triggers) == 1, "growing a clone's spawn_triggers should not affect the template's, got %v", len(template.spawn_triggers))
}

// -- Identity strings (ADR-0028) ----------------------------------------
// A Map's four discriminants are persisted as their enum case names, so
// reordering Spawn_Condition_Kind/Spawn_Mode_Kind/Movement_Style_Kind/
// Attack_Style_Kind can't silently repoint a saved map at a different
// variant. These tests write and read real files, but under their own
// throwaway path rather than data/maps/ - the map_builder globs that
// directory on every build and would bake a test artifact into maps.odin.

@(private = "file")
ROUND_TRIP_MAP_PATH :: "data/map_identity_round_trip_test.json"

@(test)
test_a_saved_map_names_every_discriminant_and_loads_back :: proc(t: ^testing.T) {
	template: Map
	append(&template.tilemap.tiles, Tile{world_coords = {0, 0}})
	append(
		&template.spawn_triggers,
		Spawn_Trigger {
			condition = Kills_Reached{count = 15},
			mode = Repeating{interval = 3, duration = 120},
			composition = slice.clone(
				[]Spawn_Composition_Entry {
					{movement_template = Floater{speed = 30}, attack_template = Ranged{max_range = 120}, count = 2},
					{movement_template = Swarmer{speed = 50}, attack_template = nil, count = 1},
				},
			),
		},
	)
	append(
		&template.spawn_triggers,
		Spawn_Trigger {
			condition = Time_Elapsed{seconds = 10},
			mode = One_Shot{},
			composition = slice.clone(
				[]Spawn_Composition_Entry{{movement_template = Grounded{speed = 40}, attack_template = Melee{attack_damage = 10}, count = 3}},
			),
		},
	)
	defer delete_map(template)

	testing.expect(t, save_map(ROUND_TRIP_MAP_PATH, template), "the template map should save")
	defer os.remove(ROUND_TRIP_MAP_PATH)

	written, read_err := os.read_entire_file(ROUND_TRIP_MAP_PATH, context.temp_allocator)
	testing.expect(t, read_err == nil, "the saved map should be readable")
	text := string(written)
	expected_names := []string {
		"Kills_Reached",
		"Repeating",
		"Time_Elapsed",
		"One_Shot",
		"Grounded",
		"Floater",
		"Swarmer",
		"Melee",
		"Ranged",
		"Inert",
	}
	for name in expected_names {
		testing.expectf(t, strings.contains(text, name), "the saved map should name `{}`", name)
	}
	testing.expect(
		t,
		!strings.contains(text, `"kind":0`) && !strings.contains(text, `"kind": 0`),
		"no discriminant should still be written as an ordinal",
	)

	loaded, load_ok := load_map(ROUND_TRIP_MAP_PATH)
	testing.expect(t, load_ok, "the saved map should load back")
	defer delete_map(loaded)
	defer delete(loaded.name)

	kills, kills_ok := loaded.spawn_triggers[0].condition.(Kills_Reached)
	testing.expect(t, kills_ok, "trigger 0's condition should come back as Kills_Reached")
	testing.expect_value(t, kills.count, 15)
	repeating, repeating_ok := loaded.spawn_triggers[0].mode.(Repeating)
	testing.expect(t, repeating_ok, "trigger 0's mode should come back as Repeating")
	testing.expect_value(t, repeating.interval, f32(3))

	floater, floater_ok := loaded.spawn_triggers[0].composition[0].movement_template.(Floater)
	testing.expect(t, floater_ok, "entry 0's movement should come back as Floater")
	testing.expect_value(t, floater.speed, f32(30))
	_, ranged_ok := loaded.spawn_triggers[0].composition[0].attack_template.(Ranged)
	testing.expect(t, ranged_ok, "entry 0's attack should come back as Ranged")
	_, swarmer_ok := loaded.spawn_triggers[0].composition[1].movement_template.(Swarmer)
	testing.expect(t, swarmer_ok, "entry 1's movement should come back as Swarmer")
	testing.expect(t, loaded.spawn_triggers[0].composition[1].attack_template == nil, "entry 1 should have no attack")

	_, time_ok := loaded.spawn_triggers[1].condition.(Time_Elapsed)
	testing.expect(t, time_ok, "trigger 1's condition should come back as Time_Elapsed")
	_, one_shot_ok := loaded.spawn_triggers[1].mode.(One_Shot)
	testing.expect(t, one_shot_ok, "trigger 1's mode should come back as One_Shot")
	_, grounded_ok := loaded.spawn_triggers[1].composition[0].movement_template.(Grounded)
	testing.expect(t, grounded_ok, "entry 0's movement should come back as Grounded")
}

// The central case of
// .scratch/content-expansion-build/issues/03-enums-persist-by-identity-string.md: a Spawn_Condition_Kind case renamed since the
// map was authored. Before identity strings this decoded to ordinal zero -
// Time_Elapsed{0}, a trigger that fires immediately - with no error at all.
@(test)
test_load_map_reports_a_kind_name_this_build_does_not_know :: proc(t: ^testing.T) {
	STALE :: `{"name":"Stale","tilemap":{"tile_size":[16,16],"tiles":[]},"spawn_triggers":[{"condition_save":{"kind":"Time_Elapsedd","time_elapsed":{"seconds":5}},"mode_save":{"kind":"One_Shot","one_shot":{}},"composition":[]}]}`
	write_err := os.write_entire_file(ROUND_TRIP_MAP_PATH, transmute([]byte)string(STALE))
	testing.expect(t, write_err == nil, "the stale map should be writable")
	defer os.remove(ROUND_TRIP_MAP_PATH)

	// the reported error is what this test is asserting on, but core:testing
	// fails any test that emits an error-level log, so silence it here
	reporting := context.logger
	context.logger = log.nil_logger()
	defer context.logger = reporting

	_, ok := load_map(ROUND_TRIP_MAP_PATH)
	testing.expect(t, !ok, "a condition naming a case this build lacks should fail the load, not resolve to ordinal zero")
}

// Fourth checkbox of
// .scratch/content-expansion-build/issues/03-enums-persist-by-identity-string.md:
// the one committed map fixture, migrated from ordinals to
// identity strings, still loads and still means what it meant.
@(test)
test_the_committed_desert_dungeon_map_still_loads :: proc(t: ^testing.T) {
	loaded, ok := load_map("data/maps/desert_dungeon.json")
	testing.expect(t, ok, "the committed map should load")
	if !ok {
		return
	}
	defer delete_map(loaded)
	defer delete(loaded.name)

	testing.expect_value(t, len(loaded.spawn_triggers), 3)

	_, first_time_ok := loaded.spawn_triggers[0].condition.(Time_Elapsed)
	testing.expect(t, first_time_ok, "trigger 0 should still be Time_Elapsed")
	kills, kills_ok := loaded.spawn_triggers[1].condition.(Kills_Reached)
	testing.expect(t, kills_ok, "trigger 1 should still be Kills_Reached")
	testing.expect_value(t, kills.count, 15)

	_, grounded_ok := loaded.spawn_triggers[0].composition[0].movement_template.(Grounded)
	testing.expect(t, grounded_ok, "trigger 0's first entry should still be Grounded")
	_, melee_ok := loaded.spawn_triggers[0].composition[0].attack_template.(Melee)
	testing.expect(t, melee_ok, "trigger 0's first entry should still be Melee")
	_, floater_ok := loaded.spawn_triggers[1].composition[0].movement_template.(Floater)
	testing.expect(t, floater_ok, "trigger 1's first entry should still be Floater")
	_, swarmer_ok := loaded.spawn_triggers[2].composition[0].movement_template.(Swarmer)
	testing.expect(t, swarmer_ok, "trigger 2's first entry should still be Swarmer")
	_, ranged_ok := loaded.spawn_triggers[1].composition[1].attack_template.(Ranged)
	testing.expect(t, ranged_ok, "trigger 1's second entry should still be Ranged")
}
