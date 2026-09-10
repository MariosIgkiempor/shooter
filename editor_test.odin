package shooter

import "core:os"
import "core:strings"
import "core:testing"

// -- Map-level authoring (content-expansion-build ticket 14) ---------------
//
// The editor's Map mode is immediate-mode ui and can't be driven from a test,
// so the pieces it stands on are factored out as plain procs and tested here:
// the name buffer typing edits, the name -> file slug the Save button derives,
// the stub a New Map starts from, and the cell -> player_start snap. The one
// end-to-end assertion goes through save_map/load_map, which is the seam
// between "the editor authored it" and "the bake can read it".

// -- the name field's buffer ----------------------------------------------

@(test)
test_typing_into_a_text_buffer_appends_and_backspace_removes :: proc(t: ^testing.T) {
	buf: Text_Buffer

	text_buffer_set(&buf, "Hall")
	testing.expect_value(t, text_buffer_string(&buf), "Hall")

	testing.expect(t, text_buffer_insert(&buf, 's'), "an insert with room left should take")
	testing.expect_value(t, text_buffer_string(&buf), "Halls")

	testing.expect(t, text_buffer_backspace(&buf), "a backspace with characters left should take")
	testing.expect_value(t, text_buffer_string(&buf), "Hall")
}

@(test)
test_a_text_buffer_refuses_to_overflow_and_refuses_to_underflow :: proc(t: ^testing.T) {
	buf: Text_Buffer

	for _ in 0 ..< TEXT_BUFFER_CAPACITY {
		testing.expect(t, text_buffer_insert(&buf, 'x'), "every insert up to capacity should take")
	}
	testing.expect(t, !text_buffer_insert(&buf, 'x'), "an insert past capacity should be refused")
	testing.expect_value(t, len(text_buffer_string(&buf)), TEXT_BUFFER_CAPACITY)

	empty: Text_Buffer
	testing.expect(t, !text_buffer_backspace(&empty), "a backspace on an empty buffer should be refused")
}

// only printable ASCII reaches a Map name: the slug it becomes is a filename,
// and a control character in one is a file nobody can name back
@(test)
test_a_text_buffer_ignores_characters_that_cannot_ride_in_a_name :: proc(t: ^testing.T) {
	buf: Text_Buffer

	testing.expect(t, !text_buffer_insert(&buf, '\n'), "a newline should be refused")
	testing.expect(t, !text_buffer_insert(&buf, '\t'), "a tab should be refused")
	testing.expect(t, !text_buffer_insert(&buf, 'é'), "a non-ASCII rune should be refused")
	testing.expect_value(t, text_buffer_string(&buf), "")
}

// -- the name -> file slug ------------------------------------------------

// the slug is what map_builder turns back into a Map_Name case, so the
// round trip through strings.to_ada_case is the property that matters
@(test)
test_a_map_name_becomes_a_slug_the_bake_turns_back_into_its_case_name :: proc(t: ^testing.T) {
	cases := []struct {
		name: string,
		slug: string,
		case_name: string,
	} {
		{"Cold Hall", "cold_hall", "Cold_Hall"},
		{"Desert Dungeon", "desert_dungeon", "Desert_Dungeon"},
		{"The Warren", "the_warren", "The_Warren"},
	}

	for c in cases {
		slug := map_file_slug(c.name)
		testing.expectf(t, slug == c.slug, "`{}` should slug to `{}`, got `{}`", c.name, c.slug, slug)

		baked := strings.to_ada_case(slug, context.temp_allocator)
		testing.expectf(t, baked == c.case_name, "`{}` should bake to `{}`, got `{}`", slug, c.case_name, baked)
	}
}

@(test)
test_a_map_name_slug_collapses_punctuation_and_never_comes_back_empty :: proc(t: ^testing.T) {
	testing.expect_value(t, map_file_slug("Boss  Keep!!"), "boss_keep")
	testing.expect_value(t, map_file_slug("  spaced  out  "), "spaced_out")
	testing.expect_value(t, map_file_slug("Rung 2"), "rung_2")
	testing.expect_value(t, map_file_slug(""), UNTITLED_MAP_SLUG)
	testing.expect_value(t, map_file_slug("!!!"), UNTITLED_MAP_SLUG)
}

@(test)
test_a_slug_becomes_a_path_under_the_directory_the_bake_globs :: proc(t: ^testing.T) {
	testing.expect_value(t, map_file_path_for_slug("cold_hall"), "data/maps/cold_hall.json")
}

// -- the New Map stub ------------------------------------------------------

// a stub carries every property an author would otherwise have to remember to
// set before drawing: opaque colours (ADR-0024 calls a zero-valued colour
// invalid), a rung on the ladder (ADR-0022 starts at 1), and an objective a
// Run can be timed out against (ADR-0017). What it does *not* carry is
// covered by the test below.
@(test)
test_a_new_map_stub_carries_a_theme_a_rung_and_an_objective :: proc(t: ^testing.T) {
	stub := new_map_stub("New Map", {16, 16})
	defer delete_map(stub)

	testing.expect_value(t, stub.name, "New Map")
	testing.expect_value(t, stub.tilemap.tile_size, Vec2{16, 16})
	testing.expect_value(t, stub.rung, 1)
	testing.expect(t, stub.time_limit > 0, "a stub should carry a time limit a Run can be timed out against")
	testing.expect(t, stub.victory_multiplier >= 1, "a stub should never pay a cleared Run less than its net take")
	testing.expect_value(t, stub.floor_color.a, 255)
	testing.expect_value(t, stub.wall_color.a, 255)

	// the bevel mixes toward the floor, so a floor lighter than its wall
	// would invert the inset (map.odin's MAP_BEVEL_MIX note)
	floor_sum := int(stub.floor_color.r) + int(stub.floor_color.g) + int(stub.floor_color.b)
	wall_sum := int(stub.wall_color.r) + int(stub.wall_color.g) + int(stub.wall_color.b)
	testing.expect(t, floor_sum < wall_sum, "a stub's floor should be darker than its wall")
}

// a stub is emptiness with a palette, not a Map: CONTEXT.md's validity is one
// connected walkable region, a player start on floor and a reachable
// off-screen spawn ring, and a Map with no tiles has none of the three.
// Asserted rather than assumed, because the stub's colours and objective make
// it look finished and the Save button next to it does not care - ticket 15's
// sweep over the baked table is what catches one that reached a build.
@(test)
test_a_new_map_stub_has_no_floor_until_one_is_drawn_on_it :: proc(t: ^testing.T) {
	stub := new_map_stub("New Map", {16, 16})
	defer delete_map(stub)

	testing.expect_value(t, len(stub.tilemap.tiles), 0)
}

// -- placing the player start ---------------------------------------------

// player_start is the player rect's feet anchor in world units, and a click
// lands anywhere inside a cell - so it snaps to that cell's centre rather
// than to wherever in the cell the pointer happened to be
@(test)
test_placing_the_player_start_snaps_to_the_centre_of_the_clicked_cell :: proc(t: ^testing.T) {
	testing.expect_value(t, editor_start_position_for_cell({0, 0}, {16, 16}), Vec2{8, 8})
	testing.expect_value(t, editor_start_position_for_cell({3, 5}, {16, 16}), Vec2{56, 88})
}

// -- the authoring round trip ---------------------------------------------

@(private = "file")
AUTHORED_MAP_PATH :: "data/map_authoring_round_trip_test.json"

// every field ticket 14 makes authorable, written by the same save_map the
// editor's Save button calls and read back by the same load_map its switcher
// calls. Under a throwaway path rather than data/maps/, which map_builder
// globs on every build.
@(test)
test_a_map_authored_from_a_stub_saves_and_loads_back_whole :: proc(t: ^testing.T) {
	authored := new_map_stub("Boss Keep", {16, 16})
	defer delete_map(authored)

	tilemap_place_tile(&authored.tilemap, {4, 4})
	authored.player_start = editor_start_position_for_cell({4, 4}, authored.tilemap.tile_size)
	authored.time_limit = 240
	authored.victory_multiplier = 2.25
	authored.rung = 5
	authored.floor_color = {30, 22, 34, 255}
	authored.wall_color = {110, 84, 120, 255}

	testing.expect(t, save_map(AUTHORED_MAP_PATH, authored), "an authored map should save")
	defer os.remove(AUTHORED_MAP_PATH)

	loaded, ok := load_map(AUTHORED_MAP_PATH)
	testing.expect(t, ok, "an authored map should load back")
	defer delete_map(loaded)

	testing.expect_value(t, loaded.name, "Boss Keep")
	testing.expect_value(t, loaded.player_start, Vec2{72, 72})
	testing.expect_value(t, loaded.time_limit, f32(240))
	testing.expect_value(t, loaded.victory_multiplier, f32(2.25))
	testing.expect_value(t, loaded.rung, 5)
	testing.expect_value(t, loaded.floor_color, Color{30, 22, 34, 255})
	testing.expect_value(t, loaded.wall_color, Color{110, 84, 120, 255})
	testing.expect_value(t, len(loaded.tilemap.tiles), 1)
}
