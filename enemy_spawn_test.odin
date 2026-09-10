package shooter

import "core:testing"

// Off-screen spawn placement (enemy-spawn-revamp map, ticket 02) is pure
// geometry - no game global reliance - except tile_blocks_point/
// tilemap_world_bounds, which take a Tilemap directly rather than reading
// game.current_map, so tests build their own throwaway tilemaps instead of
// touching shared state (no ODIN_TEST_THREADS=1 concerns for this file).

@(test)
test_camera_visible_world_rect_is_half_extent_box_around_target :: proc(t: ^testing.T) {
	camera := Camera {
		target = {100, 50},
		zoom   = 2,
	}
	// get_screen_width/height read rl.GetScreenWindow*, which has no real
	// window in a test run - both return 0, so half_w/half_h are 0 and the
	// rect collapses to a point at target. That's still a valid check of the
	// centering math without needing a live raylib window.
	bounds := camera_visible_world_rect(camera)

	testing.expect(t, bounds.min_x == camera.target.x, "visible rect should be centered on camera.target")
	testing.expect(t, bounds.max_x == camera.target.x, "visible rect should be centered on camera.target")
	testing.expect(t, bounds.min_y == camera.target.y, "visible rect should be centered on camera.target")
	testing.expect(t, bounds.max_y == camera.target.y, "visible rect should be centered on camera.target")
}

@(test)
test_tilemap_world_bounds_spans_every_tile :: proc(t: ^testing.T) {
	tilemap := Tilemap {
		tile_size = {16, 16},
	}
	append(&tilemap.tiles, Tile{world_coords = {0, 0}})
	append(&tilemap.tiles, Tile{world_coords = {3, -2}})
	defer delete(tilemap.tiles)

	bounds := tilemap_world_bounds(&tilemap)

	testing.expectf(t, bounds.min_x == 0, "expected min_x 0, got %v", bounds.min_x)
	testing.expectf(t, bounds.max_x == 4 * 16, "expected max_x 64, got %v", bounds.max_x)
	testing.expectf(t, bounds.min_y == -2 * 16, "expected min_y -32, got %v", bounds.min_y)
	testing.expectf(t, bounds.max_y == 1 * 16, "expected max_y 16, got %v", bounds.max_y)
}

@(test)
test_tile_blocks_point_true_only_for_a_colliding_tile_under_the_point :: proc(t: ^testing.T) {
	tilemap := Tilemap {
		tile_size = {16, 16},
	}
	append(&tilemap.tiles, Tile{world_coords = {1, 1}, collides = true})
	append(&tilemap.tiles, Tile{world_coords = {2, 1}, collides = false})
	defer delete(tilemap.tiles)

	testing.expect(t, tile_blocks_point(&tilemap, {20, 20}), "a point inside a colliding tile should be blocked")
	testing.expect(t, !tile_blocks_point(&tilemap, {36, 20}), "a point inside a non-colliding tile should not be blocked")
	testing.expect(t, !tile_blocks_point(&tilemap, {200, 200}), "a point over no tile at all should not be blocked")
}

@(test)
test_pick_offscreen_spawn_point_never_lands_inside_the_visible_rect :: proc(t: ^testing.T) {
	tilemap := Tilemap {
		tile_size = {16, 16},
	}
	// a large, entirely non-colliding tilemap so clamping/blocking never
	// interferes with the invariant under test
	for x in i32(-50) ..< 50 {
		for y in i32(-50) ..< 50 {
			append(&tilemap.tiles, Tile{world_coords = {x, y}, collides = false})
		}
	}
	defer delete(tilemap.tiles)

	player_pos := Vec2{0, 0}
	visible_rect := World_Bounds{-100, 100, -80, 80} // centered on player_pos, matching the camera-caught-up case
	map_bounds := tilemap_world_bounds(&tilemap)

	for _ in 0 ..< 20 {
		point := pick_offscreen_spawn_point(player_pos, visible_rect, map_bounds, &tilemap, nil)
		testing.expectf(
			t,
			!point_in_world_bounds(point, visible_rect),
			"spawn point %v should never land inside the visible rect %v when camera.target == player_pos",
			point,
			visible_rect,
		)
	}
}

@(test)
test_pick_offscreen_spawn_point_clamps_into_map_bounds :: proc(t: ^testing.T) {
	tilemap := Tilemap {
		tile_size = {16, 16},
	}
	// a tiny map (one tile) near the origin - any angle-around-player pick
	// at the visible rect's half-diagonal+margin distance will land well
	// outside this map's tiny bounds, forcing the clamp to engage
	append(&tilemap.tiles, Tile{world_coords = {0, 0}, collides = false})
	defer delete(tilemap.tiles)

	player_pos := Vec2{8, 8} // inside the map's only tile
	visible_rect := World_Bounds{-200, 200, -200, 200}
	bounds := tilemap_world_bounds(&tilemap)

	for _ in 0 ..< 20 {
		point := pick_offscreen_spawn_point(player_pos, visible_rect, bounds, &tilemap, nil)
		testing.expectf(t, point_in_world_bounds(point, bounds), "spawn point %v should be clamped into map bounds %v", point, bounds)
	}
}

@(test)
test_tilemap_world_bounds_of_an_empty_tilemap_is_zero_valued_not_inverted :: proc(t: ^testing.T) {
	tilemap := Tilemap{tile_size = {16, 16}}
	bounds := tilemap_world_bounds(&tilemap)
	testing.expectf(
		t,
		bounds == World_Bounds{},
		"an empty tilemap's bounds should be the zero value, not an inverted min>max box that would poison clamp(), got %v",
		bounds,
	)
}

// -- spawn reachability (content-expansion-build ticket 07) ---------------
// The field never reads `game` either, so these stay in this file's
// throwaway-fixture idiom: a Tilemap and a Flow_Field built here, nothing
// shared. fixture_room comes from flow_field_test.odin.

// Every field here floods at FLOW_FIELD_INFLATION_RADIUS rather than 0. At
// radius 0 the filled set is simply the walkable set and the reachability test
// is trivial; at the radius the game actually runs, the flood refuses to enter
// the envelope around every wall, and a third of the standable cells carry no
// distance of their own - which is the configuration the test has to hold in.

// two open halves with one solid wall column between them, and no way round:
// every cell right of the wall is walkable but unreachable from a player
// standing on the left. That is the shape criterion 1 is about - a spawn
// candidate that no wall sits under, on ground the player can never get to.
@(private = "file")
split_room :: proc() -> Tilemap {
	return fixture_room(
		{
			"............#............",
			"............#............",
			"............#............",
			"............#............",
			"............#............",
		},
	)
}

@(private = "file")
SPLIT_ROOM_PLAYER := Vec2{40, 40} // cell {2,2}'s centre, in the left half
@(private = "file")
SPLIT_ROOM_FAR_SIDE := Vec2{300, 40} // inside cell {18,2}, walkable and sealed off

@(test)
test_flow_field_reaches_rejects_a_walkable_cell_the_flood_never_reached :: proc(t: ^testing.T) {
	tilemap := split_room()
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)
	flow_field_rebuild(&field, &tilemap, SPLIT_ROOM_PLAYER, i32(FLOW_FIELD_INFLATION_RADIUS))

	testing.expect(
		t,
		!tile_blocks_point(&tilemap, SPLIT_ROOM_FAR_SIDE),
		"the far side must be walkable, or this fixture is testing tile_blocks_point instead",
	)
	testing.expect(
		t,
		!flow_field_reaches(&field, SPLIT_ROOM_FAR_SIDE),
		"a walkable cell on the far side of a sealed wall should be rejected",
	)
	testing.expect(
		t,
		flow_field_reaches(&field, SPLIT_ROOM_PLAYER),
		"the player's own cell should be reachable",
	)
}

@(test)
test_flow_field_reaches_accepts_everything_without_a_field :: proc(t: ^testing.T) {
	// nil is the caller saying this body cannot be stranded - a Floater
	testing.expect(
		t,
		flow_field_reaches(nil, SPLIT_ROOM_FAR_SIDE),
		"a nil field asks no question, so nothing can fail it",
	)

	empty: Flow_Field
	defer flow_field_destroy(&empty)
	testing.expect(
		t,
		flow_field_reaches(&empty, SPLIT_ROOM_FAR_SIDE),
		"an unbuilt field must not veto every candidate on the map",
	)
}

@(test)
test_flow_field_reaches_accepts_everything_when_the_flood_filled_nothing :: proc(t: ^testing.T) {
	// the case ticket 04 left open: a player standing inside a wall floods
	// nothing, and a filter reading that as "nowhere is reachable" would
	// reject every candidate and leave placement worse than it found it
	tilemap := fixture_room({".....", ".###.", ".###.", ".###.", "....."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)
	flow_field_rebuild(&field, &tilemap, {40, 40}, i32(FLOW_FIELD_INFLATION_RADIUS)) // cell {2,2}, inside the block

	testing.expectf(t, field.filled_count == 0, "expected an empty flood, got %v cells", field.filled_count)
	testing.expect(
		t,
		flow_field_reaches(&field, {8, 8}),
		"a field with no answers must not veto a candidate",
	)
}

@(test)
test_flow_field_reaches_a_walkable_cell_inside_the_inflation_envelope :: proc(t: ^testing.T) {
	// The two halves of the same question, at the radius the game runs. A cell
	// beside a wall on the player's own side is unfilled - the flood only ever
	// leaves the envelope - but a body put there walks straight out, so
	// rejecting it would cost a third of the map's spawn candidates. A cell on
	// the far side of the wall is unfilled *and* has no filled neighbour, and
	// stays rejected.
	tilemap := split_room()
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)
	flow_field_rebuild(&field, &tilemap, SPLIT_ROOM_PLAYER, i32(FLOW_FIELD_INFLATION_RADIUS))

	beside_the_wall := cell_center_to_world({11, 2}, tilemap.tile_size) // the player's side, in the envelope
	testing.expectf(
		t,
		flow_field_distance(&field, {11, 2}) == FLOW_UNREACHED,
		"the fixture needs this cell unfilled, or it is not testing the envelope",
	)
	testing.expect(
		t,
		flow_field_reaches(&field, beside_the_wall),
		"a body beside a wall on the player's own side is not stranded - it steps out to a filled neighbour",
	)

	far_of_the_wall := cell_center_to_world({13, 2}, tilemap.tile_size) // the sealed side, also in the envelope
	testing.expect(
		t,
		!flow_field_reaches(&field, far_of_the_wall),
		"the envelope on the sealed side has no filled neighbour to step to, and stays rejected",
	)

}

@(test)
test_flow_field_reaches_never_accepts_a_wall_the_player_is_standing_against :: proc(t: ^testing.T) {
	// The player beside a wall is the case where a wall cell has filled
	// neighbours at all: the flood is seeded inside the envelope it stands in
	// and traverses the rest of that pocket, so the cells around the wall
	// carry distances. The wall itself must still be refused - "has somewhere
	// to step" is not the whole question, and a spawn inside a wall two tiles
	// from the player is the failure this catches.
	tilemap := fixture_room({".....", ".....", "..#..", ".....", "....."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)
	player := cell_center_to_world({1, 2}, tilemap.tile_size) // immediately west of the wall
	flow_field_rebuild(&field, &tilemap, player, i32(FLOW_FIELD_INFLATION_RADIUS))

	testing.expect(
		t,
		flow_field_distance(&field, {1, 1}) != FLOW_UNREACHED,
		"the fixture needs the envelope around the player filled, or the wall has no filled neighbour to be tempted by",
	)
	testing.expect(
		t,
		!flow_field_reaches(&field, cell_center_to_world({2, 2}, tilemap.tile_size)),
		"a wall's own cell is never somewhere a body can stand",
	)
}

@(test)
test_pick_offscreen_spawn_point_never_lands_on_a_cell_the_field_never_reached :: proc(t: ^testing.T) {
	tilemap := split_room()
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)
	flow_field_rebuild(&field, &tilemap, SPLIT_ROOM_PLAYER, i32(FLOW_FIELD_INFLATION_RADIUS))

	// a ring wide enough to reach across the wall: half-diagonal 170 + the
	// 30px margin puts candidates 200px out, and the far half starts 168px
	// from the player
	visible_rect := World_Bounds{-80, 160, -80, 160}
	map_bounds := tilemap_world_bounds(&tilemap)

	for _ in 0 ..< 200 {
		point := pick_offscreen_spawn_point(SPLIT_ROOM_PLAYER, visible_rect, map_bounds, &tilemap, &field)
		testing.expectf(
			t,
			flow_field_reaches(&field, point),
			"spawn point %v sits on a cell the flood never reached",
			point,
		)
	}
}

@(test)
test_pick_offscreen_spawn_point_falls_back_to_the_field_when_nothing_reachable_is_offered :: proc(t: ^testing.T) {
	// The player sealed into a 3x3 room at one end of a wide open map. Every
	// candidate on the ring lands out in the open, which is walkable, unwalled
	// and completely unreachable - so all six retries are refused and there is
	// no reachable candidate to fall back to either. The field's own filled
	// set is the only thing left that knows where a body may go.
	// The room is deliberately not square: a 3x3 one is symmetric under
	// transpose, so a field index read back with its x and y swapped would
	// still name a cell inside it and the assertion below would pass on a
	// wrong answer.
	tilemap := fixture_room(
		{
			"#########################",
			"#...#....................",
			"#####....................",
			"#........................",
			"#########################",
		},
	)
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)
	player := cell_center_to_world({2, 1}, tilemap.tile_size)
	flow_field_rebuild(&field, &tilemap, player, i32(FLOW_FIELD_INFLATION_RADIUS))
	testing.expectf(t, field.filled_count > 0, "the sealed room must flood, got %v cells", field.filled_count)

	visible_rect := World_Bounds{player.x - 120, player.x + 120, player.y - 120, player.y + 120}
	map_bounds := tilemap_world_bounds(&tilemap)

	for _ in 0 ..< 200 {
		point := pick_offscreen_spawn_point(player, visible_rect, map_bounds, &tilemap, &field)
		cell := world_to_cell_coord(point, tilemap.tile_size)
		testing.expectf(
			t,
			flow_field_reaches(&field, point),
			"an exhausted pick must still land somewhere the player can reach, got %v on cell %v",
			point,
			cell,
		)
		testing.expectf(
			t,
			cell.y == 1 && cell.x >= 1 && cell.x <= 3,
			"the only reachable ground is the sealed room, cells {1,1}..{3,1}; got cell %v",
			cell,
		)
	}
}

@(test)
test_pick_offscreen_spawn_point_takes_a_reachable_candidate_over_an_offscreen_one :: proc(t: ^testing.T) {
	// a visible rect covering the whole map, so no candidate can ever pass
	// the off-screen test and every pick exhausts its retries. Reachability
	// is the one failure that is permanent, so it is the one the fallback
	// must still honour.
	tilemap := split_room()
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)
	flow_field_rebuild(&field, &tilemap, SPLIT_ROOM_PLAYER, i32(FLOW_FIELD_INFLATION_RADIUS))

	visible_rect := World_Bounds{-1000, 1000, -1000, 1000}
	map_bounds := tilemap_world_bounds(&tilemap)

	for _ in 0 ..< 200 {
		point := pick_offscreen_spawn_point(SPLIT_ROOM_PLAYER, visible_rect, map_bounds, &tilemap, &field)
		testing.expectf(
			t,
			flow_field_reaches(&field, point),
			"an exhausted pick should still fall back to a reachable candidate, got %v",
			point,
		)
	}
}

@(test)
test_pick_offscreen_spawn_point_clamps_inside_the_last_authored_cell :: proc(t: ^testing.T) {
	// tilemap_world_bounds' max is the far *edge* of the last tile, which is
	// the near edge of the next cell along. A candidate clamped straight onto
	// it lands one cell outside the authored map, where the flood has nothing
	// and every enemy reverts to straight-line chasing. No field here on
	// purpose: with one, the reachability filter would reject that cell and
	// hide the clamp behind its own fallback.
	tilemap := fixture_room({"....", "....", "....", "...."})
	defer delete(tilemap.tiles)

	min_cell, max_cell, has_tiles := tilemap_cell_bounds(&tilemap)
	testing.expect(t, has_tiles, "the fixture should have tiles")

	// a rect far larger than the map, so every candidate is thrown well past
	// its edges and the clamp is what decides where it lands
	visible_rect := World_Bounds{-1000, 1000, -1000, 1000}
	map_bounds := tilemap_world_bounds(&tilemap)

	for _ in 0 ..< 100 {
		point := pick_offscreen_spawn_point({8, 8}, visible_rect, map_bounds, &tilemap, nil)
		cell := world_to_cell_coord(point, tilemap.tile_size)
		testing.expectf(
			t,
			cell.x >= min_cell.x && cell.x <= max_cell.x && cell.y >= min_cell.y && cell.y <= max_cell.y,
			"spawn point %v is on cell %v, outside the authored cells %v..%v",
			point,
			cell,
			min_cell,
			max_cell,
		)
	}
}
