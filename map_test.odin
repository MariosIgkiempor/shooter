package shooter

import "core:slice"
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
