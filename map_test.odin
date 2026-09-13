package shooter

import "core:fmt"
import "core:log"
import "core:math"
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
			composition = slice.clone([]Spawn_Composition_Entry{{kind = .Grunt, count = 1}}),
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
				[]Spawn_Composition_Entry{{kind = .Gazer, count = 2}, {kind = .Mite, count = 1}},
			),
		},
	)
	append(
		&template.spawn_triggers,
		Spawn_Trigger {
			condition = Time_Elapsed{seconds = 10},
			mode = One_Shot{},
			composition = slice.clone([]Spawn_Composition_Entry{{kind = .Grunt, count = 3}}),
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
		"Gazer",
		"Mite",
		"Grunt",
	}
	for name in expected_names {
		testing.expectf(t, strings.contains(text, name), "the saved map should name `{}`", name)
	}
	ordinal_prone_fields := []string{"kind", "kind_save"}
	for field in ordinal_prone_fields {
		testing.expectf(
			t,
			!strings.contains(text, fmt.tprintf(`"%s":0`, field)) &&
			!strings.contains(text, fmt.tprintf(`"%s": 0`, field)),
			"no `{}` should still be written as an ordinal",
			field,
		)
	}

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

	testing.expect_value(t, loaded.spawn_triggers[0].composition[0].kind, Enemy_Kind.Gazer)
	testing.expect_value(t, loaded.spawn_triggers[0].composition[0].count, 2)
	testing.expect_value(t, loaded.spawn_triggers[0].composition[1].kind, Enemy_Kind.Mite)

	_, time_ok := loaded.spawn_triggers[1].condition.(Time_Elapsed)
	testing.expect(t, time_ok, "trigger 1's condition should come back as Time_Elapsed")
	_, one_shot_ok := loaded.spawn_triggers[1].mode.(One_Shot)
	testing.expect(t, one_shot_ok, "trigger 1's mode should come back as One_Shot")
	testing.expect_value(t, loaded.spawn_triggers[1].composition[0].kind, Enemy_Kind.Grunt)
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

	testing.expect_value(t, loaded.spawn_triggers[0].composition[0].kind, Enemy_Kind.Grunt)
	testing.expect_value(t, loaded.spawn_triggers[0].composition[1].kind, Enemy_Kind.Spitter)
	testing.expect_value(t, loaded.spawn_triggers[1].composition[0].kind, Enemy_Kind.Wraith)
	testing.expect_value(t, loaded.spawn_triggers[2].composition[0].kind, Enemy_Kind.Mite)
}

// -- The Map's own look (ADR-0024) --------------------------------------
// A Map's ambient set is the fourth thing on it persisted by name rather
// than by ordinal (ADR-0028), and the one most exposed to reordering: the
// effects are a decorative roster that will grow and be re-sorted, where a
// silently-shifted ordinal would swap one effect for another with nothing
// to notice.

// its own path rather than ROUND_TRIP_MAP_PATH above: two tests writing one
// file race under the default (parallel) test runner
@(private = "file")
AMBIENT_MAP_PATH :: "data/map_ambient_round_trip_test.json"

@(test)
test_a_saved_maps_ambient_set_round_trips_by_name :: proc(t: ^testing.T) {
	template: Map
	template.name = "Ambient"
	template.ambient = {.Motes, .Light_Wash}
	append(&template.tilemap.tiles, Tile{world_coords = {0, 0}})
	defer delete_map(template)

	testing.expect(t, save_map(AMBIENT_MAP_PATH, template), "the template map should save")
	defer os.remove(AMBIENT_MAP_PATH)

	written, read_err := os.read_entire_file(AMBIENT_MAP_PATH, context.temp_allocator)
	testing.expect(t, read_err == nil, "the saved map should be readable")
	text := string(written)
	testing.expect(t, strings.contains(text, "Motes"), "the saved map should name `Motes`")
	testing.expect(t, strings.contains(text, "Light_Wash"), "the saved map should name `Light_Wash`")

	loaded, load_ok := load_map(AMBIENT_MAP_PATH)
	testing.expect(t, load_ok, "the saved map should load back")
	defer delete_map(loaded)
	defer delete(loaded.name)

	testing.expect(
		t,
		loaded.ambient == {.Motes, .Light_Wash},
		"the ambient set should come back as the two effects it was saved with",
	)
}

@(private = "file")
STALE_AMBIENT_MAP_PATH :: "data/map_stale_ambient_test.json"

@(test)
test_load_map_reports_an_ambient_name_this_build_does_not_know :: proc(t: ^testing.T) {
	STALE :: `{"name":"Stale","tilemap":{"tile_size":[16,16],"tiles":[]},"spawn_triggers":[],"ambient_save":["Motess"]}`
	write_err := os.write_entire_file(STALE_AMBIENT_MAP_PATH, transmute([]byte)string(STALE))
	testing.expect(t, write_err == nil, "the stale map should be writable")
	defer os.remove(STALE_AMBIENT_MAP_PATH)

	// as above: the reported error is the point, but core:testing fails any
	// test that emits an error-level log
	reporting := context.logger
	context.logger = log.nil_logger()
	defer context.logger = reporting

	_, ok := load_map(STALE_AMBIENT_MAP_PATH)
	testing.expect(t, !ok, "an ambient effect naming a case this build lacks should fail the load, not be dropped")
}

// Fourth checkbox of
// .scratch/content-expansion-build/issues/13-a-map-owns-its-look.md: the
// palette moved off the TILEMAP_* constants and onto the Map, so the one
// committed Map has to still render in the sand it renders in today. Reads
// the baked table rather than the file, since that is what Playing draws.
// The first assertion over `maps`; ticket 15 grows this into the full
// validity sweep.
@(test)
test_the_baked_desert_dungeon_keeps_todays_palette :: proc(t: ^testing.T) {
	desert := maps[.Desert_Dungeon]

	testing.expect_value(t, desert.floor_color, Color{56, 48, 40, 255})
	testing.expect_value(t, desert.wall_color, Color{124, 110, 90, 255})
	testing.expect_value(t, desert.rung, 1)

	// the swatch the Map Selection screen draws is the wall itself, so the
	// menu cannot advertise a colour the world does not have
	testing.expect_value(t, map_swatch_color(desert), desert.wall_color)

	// derived rather than authored, and within one 8-bit step of the
	// TILEMAP_WALL_BEVEL_COLOR it replaces ({74, 64, 52})
	testing.expect_value(t, map_bevel_color(desert), Color{74, 64, 53, 255})
}

// -- Map validity (ticket 15) ---------------------------------------------
// The seven checks spec.md's Testing Decisions name, one test each, over the
// baked `maps` table Playing draws from: a broken Map fails the build rather
// than the playtest. Every test here is read-only against `maps` - a
// `map_data := maps[name]` copy aliases the table's own tile and trigger
// arrays (map.odin's clone_map comment), so nothing below may append to,
// delete, or clone one - and builds any Flow_Field it needs on its own stack,
// so the file's no-thread-pinning discipline still holds.
//
// Order is deliberate: the start-on-floor check comes first because a start
// inside a wall floods nothing, and the connectivity check after it would
// then report every walkable cell as sealed off.

// "on a floor tile" is strictly stronger than "not inside a wall": an absent
// cell is walkable (ADR-0025) but is drawn as the clear colour rather than the
// Map's floor, and Desert Dungeon's start sat on one until this ticket.
@(test)
test_every_baked_maps_player_start_is_on_a_floor_tile :: proc(t: ^testing.T) {
	for name in Map_Name {
		map_data := maps[name]
		cell := world_to_cell_coord(map_data.player_start, map_data.tilemap.tile_size)

		found: Tile
		on_tile := false
		for tile in map_data.tilemap.tiles {
			if tile.world_coords == cell {
				found = tile
				on_tile = true
				break
			}
		}

		testing.expectf(t, on_tile, "%v: player_start %v is on cell %v, which has no tile at all", name, map_data.player_start, cell)
		testing.expectf(t, !on_tile || !found.collides, "%v: player_start %v is on cell %v, which is a wall", name, map_data.player_start, cell)
	}
}

// Flooded at radius 0 rather than the radius the game runs at, and that is
// the whole design of this test. At FLOW_FIELD_INFLATION_RADIUS the flood
// refuses to re-enter the envelope around a wall, so 741 of Desert Dungeon's
// 2239 standable cells and 388 of Cold Hall's 2108 carry no distance - and 47
// and 16 of those respectively have no filled neighbour either, so even
// flow_field_reaches rejects them. Both Maps are connected; it is the radius
// that is opinionated. At radius 0 `inflated` is stamped only on the wall
// cells themselves, so the filled set is exactly the source's walkable
// component and "every walkable cell in the extent is filled" is the
// connectivity question with nothing left over.
@(test)
test_every_baked_map_is_one_connected_walkable_region :: proc(t: ^testing.T) {
	for name in Map_Name {
		map_data := maps[name]

		field: Flow_Field
		defer flow_field_destroy(&field)
		flow_field_rebuild(&field, &map_data.tilemap, map_data.player_start, 0)

		// flow_field_reaches answers true for everything once nothing is
		// filled, and a start inside a wall floods nothing - so without this
		// guard the sweep passes silently on the worst Map there is
		testing.expectf(t, field.filled_count > 0, "%v: the flood from player_start filled nothing - the start is inside a wall or the Map has no tiles", name)
		if field.filled_count == 0 {
			continue
		}

		// one message per Map, not per cell: a split Map strands hundreds of
		// cells and every one of them names the same defect
		unreached := 0
		first: Vec2i
		for y in field.origin.y ..< field.origin.y + field.size.y {
			for x in field.origin.x ..< field.origin.x + field.size.x {
				cell, in_bounds := flow_field_cell(&field, {x, y})
				if !in_bounds || cell.collides || cell.distance != FLOW_UNREACHED {
					continue
				}
				if unreached == 0 {
					first = {x, y}
				}
				unreached += 1
			}
		}

		testing.expectf(
			t,
			unreached == 0,
			"%v: %v walkable cells are sealed off from player_start (first at cell %v; %v cells reached)",
			name,
			unreached,
			first,
			field.filled_count,
		)
	}
}

// the ring the game actually throws candidates onto: angle-around-player at
// the visible rect's half-diagonal plus OFFSCREEN_SPAWN_MARGIN, clamped into
// the Map the way pick_offscreen_spawn_point clamps. Sampled at fixed angles
// rather than through that proc, deliberately: it picks its angles with rand,
// and on exhausted retries falls back to flow_field_nearest_reachable, which
// always names a reachable cell - so asserting through it is close to a
// tautology and would pass on a Map where one angle in sixty-four works.
@(private = "file")
SPAWN_RING_ANGLES :: 64

// the shipped window (initialize_default_game_state). There is no real one in
// a test run, so camera_visible_world_rect would hand back a zero-sized rect
// and collapse the ring to bare OFFSCREEN_SPAWN_MARGIN.
@(private = "file")
SPAWN_RING_VIEW_SIZE :: Vec2{1920 / 2, 1080 / 2}

// This one floods at FLOW_FIELD_INFLATION_RADIUS, unlike the connectivity
// check above: these are the very points the live spawn filter tests, so the
// question is asked at the radius the game asks it at.
@(test)
test_every_baked_maps_spawn_ring_is_reachable :: proc(t: ^testing.T) {
	for name in Map_Name {
		map_data := maps[name]
		start := map_data.player_start

		field: Flow_Field
		defer flow_field_destroy(&field)
		flow_field_rebuild(&field, &map_data.tilemap, start, i32(FLOW_FIELD_INFLATION_RADIUS))
		testing.expectf(t, field.filled_count > 0, "%v: the flood from player_start filled nothing, and an empty field reaches everywhere", name)
		if field.filled_count == 0 {
			continue
		}

		half := SPAWN_RING_VIEW_SIZE / GAMEPLAY_ZOOM / 2
		ring := math.hypot(half.x, half.y) + OFFSCREEN_SPAWN_MARGIN

		// pick_offscreen_spawn_point's own clamp, half a tile in from the far
		// edge - the bounds' max is the near edge of the *next* cell
		map_bounds := tilemap_world_bounds(&map_data.tilemap)
		inset := map_data.tilemap.tile_size * 0.5
		max_x := max(map_bounds.min_x, map_bounds.max_x - inset.x)
		max_y := max(map_bounds.min_y, map_bounds.max_y - inset.y)

		stranded := 0
		first_stranded: Vec2i
		for i in 0 ..< SPAWN_RING_ANGLES {
			angle := math.TAU * f32(i) / SPAWN_RING_ANGLES
			point := start + Vec2{math.cos(angle), math.sin(angle)} * ring
			point.x = clamp(point.x, map_bounds.min_x, max_x)
			point.y = clamp(point.y, map_bounds.min_y, max_y)

			// a candidate under a wall is refused and retried, which is
			// ordinary. A candidate on open ground the player can never walk
			// to is the permanent failure: a body spawned there holds the
			// Map's Cleared condition open for the rest of the Run.
			if tile_blocks_point(&field, point) {
				continue
			}
			if !flow_field_reaches(&field, point) {
				if stranded == 0 {
					first_stranded = world_to_cell_coord(point, map_data.tilemap.tile_size)
				}
				stranded += 1
			}
		}

		testing.expectf(
			t,
			stranded == 0,
			"%v: %v of %v spawn-ring angles land on walkable ground the player can never reach (first on cell %v)",
			name,
			stranded,
			SPAWN_RING_ANGLES,
			first_stranded,
		)
	}
}

@(test)
test_every_baked_maps_extent_is_within_bound :: proc(t: ^testing.T) {
	for name in Map_Name {
		map_data := maps[name]
		min_cell, max_cell, ok := tilemap_cell_bounds(&map_data.tilemap)
		testing.expectf(t, ok, "%v: has no tiles at all", name)
		if !ok {
			continue
		}
		extent := max_cell - min_cell + {1, 1}
		testing.expectf(
			t,
			extent.x <= MAP_MAX_CELL_EXTENT.x && extent.y <= MAP_MAX_CELL_EXTENT.y,
			"%v: is %v cells, past the %v footprint the ladder holds flat - a harder Map is denser, not bigger",
			name,
			extent,
			MAP_MAX_CELL_EXTENT,
		)
	}
}

// 1..N with N the number of authored Maps, not a number written here: the
// ladder is however long it is, and ticket 17's four Maps make this "1
// through 5" the moment they land. Gaps and duplicates both break ticket 16's
// gating, which opens rung n+1 on clearing rung n.
@(test)
test_the_baked_maps_rungs_cover_the_ladder_once_each :: proc(t: ^testing.T) {
	ladder := len(Map_Name)
	holders: [len(Map_Name)]int // holders[r-1] = how many Maps claim rung r
	for name in Map_Name {
		rung := maps[name].rung
		testing.expectf(t, rung >= 1 && rung <= ladder, "%v: rung %v is off a ladder of %v", name, rung, ladder)
		if rung >= 1 && rung <= ladder {
			holders[rung - 1] += 1
		}
	}
	for count, index in holders {
		testing.expectf(t, count == 1, "rung %v is held by %v Maps, not one", index + 1, count)
	}
}

// a zero-valued Color is what a Map that never authored a theme carries, and
// it draws as nothing (ADR-0024). Beyond that the pair has to be a floor and a
// wall: map_bevel_color mixes toward the floor to keep a wall's inset darker
// than the wall, which only holds while the floor is the darker of the two -
// what MAP_BEVEL_MIX's comment promises this ticket checks.
@(test)
test_every_baked_map_authors_its_own_colours :: proc(t: ^testing.T) {
	for name in Map_Name {
		map_data := maps[name]
		testing.expectf(t, map_data.floor_color.a > 0, "%v: floor colour %v is not authored, so the floor draws as nothing", name, map_data.floor_color)
		testing.expectf(t, map_data.wall_color.a > 0, "%v: wall colour %v is not authored, so the walls draw as nothing", name, map_data.wall_color)
		testing.expectf(
			t,
			color_luma(map_data.floor_color) < color_luma(map_data.wall_color),
			"%v: floor %v is not darker than wall %v, so the wall bevel would inset lighter than the wall",
			name,
			map_data.floor_color,
			map_data.wall_color,
		)
	}
}

@(test)
test_every_baked_maps_time_limit_clears_its_own_timeline :: proc(t: ^testing.T) {
	for name in Map_Name {
		map_data := maps[name]
		end, bounded := map_timeline_earliest_end(map_data.spawn_triggers[:])

		testing.expectf(t, bounded, "%v: a Repeating trigger with duration <= 0 runs until the Run ends, so this Map can never be Cleared", name)

		// <= 0 is untimed, which stays a legal authoring choice - it only
		// means anything on a Map whose timeline is finite, which `bounded`
		// above is what checks
		testing.expectf(
			t,
			map_data.time_limit <= 0 || map_data.time_limit > end,
			"%v: time_limit %v does not clear the earliest its timeline can finish (%v s)",
			name,
			map_data.time_limit,
			end,
		)
	}
}

// -- map_timeline_earliest_end on its own ---------------------------------
// The two things it deliberately does not know, pinned so the honesty is
// checked rather than commented.

// a Kills_Reached trigger's activation is play-dependent, so it is folded in
// at zero: the answer is the earliest the timeline can finish, a floor the
// time limit must clear for certain, not a prediction of when it will
@(test)
test_timeline_earliest_end_folds_a_kills_trigger_in_at_zero :: proc(t: ^testing.T) {
	triggers := []Spawn_Trigger {
		{condition = Time_Elapsed{seconds = 30}, mode = Repeating{interval = 2, duration = 40}},
		{condition = Kills_Reached{count = 50}, mode = Repeating{interval = 2, duration = 100}},
		{condition = Time_Elapsed{seconds = 120}, mode = One_Shot{}},
	}
	end, bounded := map_timeline_earliest_end(triggers)
	testing.expect(t, bounded, "every trigger here has a finite span")
	// 120 from the one-shot, not 30+40=70, and not the kills trigger's 100
	// pushed out by any guess at when 50 kills happen
	testing.expect_value(t, end, f32(120))
}

@(test)
test_timeline_earliest_end_reports_an_unbounded_repeating_trigger :: proc(t: ^testing.T) {
	triggers := []Spawn_Trigger {
		{condition = Time_Elapsed{seconds = 0}, mode = Repeating{interval = 3, duration = 0}},
	}
	_, bounded := map_timeline_earliest_end(triggers)
	testing.expect(t, !bounded, "a Repeating trigger with duration <= 0 never finishes, so the timeline has no end")
}
