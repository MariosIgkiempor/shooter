package shooter

import "core:testing"

// The flow field (ADR-0025) never reads `game` - every proc takes the Tilemap
// and a world position explicitly, exactly so this file can build throwaway
// tilemaps and needs no ODIN_TEST_THREADS=1 pinning. That's a constraint on
// flow_field.odin's signatures, not a happy accident; keep it if you add to
// either file.
//
// Deliberately not covered here: update_enemies' steering dispatch. Exercising
// it needs game.enemies/current_map/player and would drag this file into the
// snapshot/restore + thread-pinning idiom (see spawn_trigger_test.odin) for
// coverage the seam procs - movement_intent, movement_goal_point,
// field_chase_direction - already give directly.

// builds a Tilemap from an ASCII picture, one row per string, so the pocket
// and corridor cases below read as the shapes they are: '#' a colliding tile,
// '.' a floor tile, ' ' no tile at all (an untiled gap - walkable, and
// load-bearing on the shipped map, whose doorways are exactly this)
fixture_room :: proc(rows: []string) -> Tilemap {
	tilemap := Tilemap {
		tile_size = {16, 16},
	}
	for row, y in rows {
		for char, x in row {
			switch char {
			case '#':
				append(&tilemap.tiles, Tile{world_coords = {i32(x), i32(y)}, collides = true})
			case '.':
				append(&tilemap.tiles, Tile{world_coords = {i32(x), i32(y)}, collides = false})
			}
		}
	}
	return tilemap
}

// a field flooded from `source` at the radius the game runs at, for the
// tests whose subject is what reads the field rather than the flood itself
fixture_field :: proc(tilemap: ^Tilemap, source: Vec2) -> Flow_Field {
	field: Flow_Field
	flow_field_rebuild(&field, tilemap, source, i32(FLOW_FIELD_INFLATION_RADIUS))
	return field
}

@(private = "file")
cell_world_center :: proc(cell: Vec2i) -> Vec2 {
	return cell_center_to_world(cell, {16, 16})
}

// -- extent and degenerate tilemaps ----------------------------------------

@(test)
test_flow_field_is_empty_for_a_tilemap_with_no_tiles :: proc(t: ^testing.T) {
	tilemap := Tilemap {
		tile_size = {16, 16},
	}
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, {0, 0}, 1)

	testing.expectf(t, field.size == Vec2i{0, 0}, "expected an empty extent, got %v", field.size)
	testing.expect(t, len(field.cells) == 0, "an empty tilemap should allocate no cells")
	testing.expect(t, field.filled_count == 0, "nothing can be flooded with no tiles")
	testing.expect(
		t,
		flow_field_distance(&field, {0, 0}) == FLOW_UNREACHED,
		"every cell of an empty field is unreached",
	)
}

@(test)
test_flow_field_is_empty_for_a_zero_tile_size :: proc(t: ^testing.T) {
	// game.current_map = Map{} is a real state (spawn_trigger_test.odin), and
	// dividing a world position by a zero tile_size would poison every cell
	// coordinate before it ever reached an index
	tilemap: Tilemap
	append(&tilemap.tiles, Tile{world_coords = {0, 0}})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, {0, 0}, 1)

	testing.expectf(t, field.size == Vec2i{0, 0}, "expected an empty extent, got %v", field.size)
	testing.expect(t, field.built, "a degenerate rebuild still counts as built, so it isn't retried every frame")

	_, ok := flow_field_step_target(&field, {0, 0})
	testing.expect(t, !ok, "a zero-size field can offer no step target")
}

@(test)
test_flow_field_spans_the_authored_cell_extent_including_negative_coords :: proc(t: ^testing.T) {
	tilemap := Tilemap {
		tile_size = {16, 16},
	}
	append(&tilemap.tiles, Tile{world_coords = {-2, -1}})
	append(&tilemap.tiles, Tile{world_coords = {1, 3}})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({-2, -1}), 0)

	testing.expectf(t, field.origin == Vec2i{-2, -1}, "expected origin {-2,-1}, got %v", field.origin)
	testing.expectf(t, field.size == Vec2i{4, 5}, "expected a 4x5 extent, got %v", field.size)
}

// -- the flood -------------------------------------------------------------

@(test)
test_flow_field_source_cell_has_distance_zero_and_no_step :: proc(t: ^testing.T) {
	tilemap := fixture_room({"....."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({2, 0}), 0)

	cell, ok := flow_field_cell(&field, {2, 0})
	testing.expect(t, ok, "the source cell should be inside the extent")
	testing.expectf(t, cell.distance == 0, "expected distance 0 at the source, got %v", cell.distance)
	testing.expect(t, cell.step == .None, "the source has nowhere to step")
	testing.expect(t, field.filled_count > 0, "the source cell was flooded")
}

@(test)
test_flow_field_distance_increases_by_one_step_cost_per_cell_along_a_corridor :: proc(t: ^testing.T) {
	tilemap := fixture_room({"....."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({0, 0}), 0)

	for x in i32(0) ..< 5 {
		expected := u32(x) * FLOW_COST_ORTHOGONAL
		testing.expectf(
			t,
			flow_field_distance(&field, {x, 0}) == expected,
			"expected distance %v at cell %v, got %v",
			expected,
			x,
			flow_field_distance(&field, {x, 0}),
		)
	}
	testing.expectf(
		t,
		field.max_distance == 4 * FLOW_COST_ORTHOGONAL,
		"expected max_distance %v, got %v",
		4 * FLOW_COST_ORTHOGONAL,
		field.max_distance,
	)
	testing.expectf(t, field.filled_count == 5, "expected 5 filled cells, got %v", field.filled_count)
}

@(test)
test_flow_field_every_step_descends_toward_the_player :: proc(t: ^testing.T) {
	// the ticket's central claim: from any filled cell, following `step`
	// strictly decreases the distance, so every enemy is walking downhill
	tilemap := fixture_room({"........", ".##..##.", "........", ".##..##.", "........"})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({7, 4}), 0)

	for y in i32(0) ..< 5 {
		for x in i32(0) ..< 8 {
			cell, _ := flow_field_cell(&field, {x, y})
			if cell.distance == FLOW_UNREACHED || cell.step == .None {
				continue
			}

			next := Vec2i{x, y} + FLOW_STEP_OFFSET[cell.step]
			next_cell, in_bounds := flow_field_cell(&field, next)
			testing.expectf(t, in_bounds, "cell %v steps out of the extent to %v", Vec2i{x, y}, next)
			testing.expectf(
				t,
				next_cell.distance == cell.distance - FLOW_STEP_COST[cell.step],
				"cell %v at distance %v steps %v to %v at distance %v; expected %v",
				Vec2i{x, y},
				cell.distance,
				cell.step,
				next,
				next_cell.distance,
				cell.distance - FLOW_STEP_COST[cell.step],
			)
		}
	}
}

@(test)
test_flow_field_distance_wraps_around_a_wall :: proc(t: ^testing.T) {
	// the player sits behind a U of wall; the cell directly "above" it is 2
	// cells away in a straight line but must walk the long way round
	tilemap := fixture_room({".....", ".###.", ".#@#.", ".#.#.", "....."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	source := Vec2i{2, 2}
	flow_field_rebuild(&field, &tilemap, cell_world_center(source), 0)

	far := Vec2i{2, 0}
	distance := flow_field_distance(&field, far)
	testing.expect(t, distance != FLOW_UNREACHED, "the cell above the pocket is reachable the long way round")
	testing.expectf(
		t,
		distance > 2 * FLOW_COST_ORTHOGONAL,
		"expected a path distance beyond the straight-line two cells, got %v",
		distance,
	)

	// walking the steps must spend exactly `distance` arriving at the source,
	// which also proves the field is acyclic
	cursor := far
	spent := u32(0)
	for cursor != source && spent <= distance {
		cell, _ := flow_field_cell(&field, cursor)
		spent += FLOW_STEP_COST[cell.step]
		cursor += FLOW_STEP_OFFSET[cell.step]
	}
	testing.expectf(t, cursor == source, "expected the steps to arrive at %v, got %v", source, cursor)
	testing.expectf(t, spent == distance, "expected the walk to cost %v, got %v", distance, spent)
}

@(test)
test_flow_field_never_fills_an_enclosed_pocket :: proc(t: ^testing.T) {
	// a sealed 1x1 room inside an open one. The ticket's last criterion, and
	// what ticket 07 leans on to reject an unreachable spawn.
	tilemap := fixture_room({".....", ".###.", ".#.#.", ".###.", "....."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({0, 0}), 0)

	testing.expectf(
		t,
		flow_field_distance(&field, {2, 2}) == FLOW_UNREACHED,
		"the sealed cell must never be filled, got distance %v",
		flow_field_distance(&field, {2, 2}),
	)
	testing.expect(t, flow_field_distance(&field, {1, 1}) == FLOW_UNREACHED, "wall cells are never filled")
	// the 16 cells of the outer ring, and nothing else
	testing.expectf(t, field.filled_count == 16, "expected 16 filled cells, got %v", field.filled_count)
}

@(test)
test_flow_field_treats_a_cell_outside_the_extent_as_unreached :: proc(t: ^testing.T) {
	tilemap := fixture_room({"..", ".."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({0, 0}), 0)

	_, ok := flow_field_cell(&field, {2, 0})
	testing.expect(t, !ok, "a cell one past the extent is out of bounds, not a crash")
	testing.expect(t, flow_field_distance(&field, {2, 0}) == FLOW_UNREACHED, "out of bounds reads as unreached")
	testing.expect(t, flow_field_distance(&field, {-1, -1}) == FLOW_UNREACHED, "so does a cell before the origin")
}

@(test)
test_flow_field_grows_its_extent_to_contain_a_player_off_the_tiles :: proc(t: ^testing.T) {
	// a map's border is not necessarily sealed - Desert Dungeon's bounding box
	// has 48 walkable cells on it - so the player really can stand off the
	// authored tiles. Bounding the field to the tiles alone gave it an off
	// switch there: nothing flooded, and every enemy fell back to
	// straight-line chasing. The box grows to reach the player instead.
	tilemap := fixture_room({"..", ".."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	source := Vec2i{1, -2}
	flow_field_rebuild(&field, &tilemap, cell_world_center(source), 0)

	testing.expectf(t, field.origin == Vec2i{0, -2}, "expected the box to reach up to the player, got %v", field.origin)
	testing.expectf(t, field.size == Vec2i{2, 4}, "expected a 2x4 extent, got %v", field.size)
	testing.expectf(
		t,
		flow_field_distance(&field, source) == 0,
		"the player's own cell is the source, got distance %v",
		flow_field_distance(&field, source),
	)
	testing.expectf(
		t,
		flow_field_distance(&field, {1, 1}) == 3 * FLOW_COST_ORTHOGONAL,
		"the flood must walk back onto the tiles, got distance %v",
		flow_field_distance(&field, {1, 1}),
	)
}

@(test)
test_flow_field_fills_nothing_when_the_player_stands_inside_a_wall :: proc(t: ^testing.T) {
	// the case the grown extent cannot answer. Nudging the source to a
	// walkable cell would flood from somewhere the player is not; filling
	// nothing falls every enemy back to the straight-line chase, which is
	// what they did before the field.
	tilemap := fixture_room({"###", "###"})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({1, 0}), 0)

	testing.expectf(t, field.filled_count == 0, "expected 0 filled cells, got %v", field.filled_count)
	testing.expectf(t, field.max_distance == 0, "max_distance must reset, got %v", field.max_distance)
}

// -- inflation -------------------------------------------------------------

@(test)
test_flow_field_inflation_marks_the_ring_around_a_wall :: proc(t: ^testing.T) {
	tilemap := fixture_room({"...", ".#.", "..."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({0, 0}), 1)

	wall, _ := flow_field_cell(&field, {1, 1})
	testing.expect(t, wall.collides, "the authored tile is solid")

	for y in i32(0) ..< 3 {
		for x in i32(0) ..< 3 {
			cell, _ := flow_field_cell(&field, {x, y})
			testing.expectf(t, cell.inflated, "cell %v is inside the wall's radius-1 envelope", Vec2i{x, y})
			if x == 1 && y == 1 {
				continue
			}
			testing.expectf(t, !cell.collides, "cell %v carries no authored tile collision", Vec2i{x, y})
		}
	}
}

@(test)
test_flow_field_floods_out_of_a_source_inside_the_inflation_envelope :: proc(t: ^testing.T) {
	// a third of the shipped map's floor is inflation-solid at radius 1, so a
	// player standing next to a wall is the common case, not an edge one: a
	// flood that refused to leave its own cell would strand every enemy
	tilemap := fixture_room({"#....", "....."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	source := Vec2i{1, 0} // adjacent to the wall, so inflated at radius 1
	flow_field_rebuild(&field, &tilemap, cell_world_center(source), 1)

	source_cell, _ := flow_field_cell(&field, source)
	testing.expect(t, source_cell.inflated, "the source really is inside the envelope")
	testing.expect(t, field.filled_count > 1, "the source is flooded regardless, and does not stop there")
	testing.expect(
		t,
		flow_field_distance(&field, {4, 1}) != FLOW_UNREACHED,
		"open ground beyond the envelope must still fill",
	)
}

@(test)
test_flow_field_floods_out_of_a_fully_inflated_corridor :: proc(t: ^testing.T) {
	// the harder half of the same rule: every cell of the corridor is
	// inflated, so exempting only the source cell would still strand the
	// flood one cell in
	tilemap := fixture_room({"#####", ".....", "#.###", "..#..", "....."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	source := Vec2i{0, 1}
	flow_field_rebuild(&field, &tilemap, cell_world_center(source), 1)

	for x in i32(0) ..< 5 {
		cell, _ := flow_field_cell(&field, {x, 1})
		testing.expectf(t, cell.inflated, "corridor cell %v should be inflated", Vec2i{x, 1})
	}
	testing.expect(
		t,
		flow_field_distance(&field, {4, 1}) != FLOW_UNREACHED,
		"the far end of a wholly inflated corridor must fill",
	)
	testing.expect(
		t,
		flow_field_distance(&field, {4, 4}) != FLOW_UNREACHED,
		"and so must the room the corridor opens onto",
	)
}

@(test)
test_flow_field_does_not_re_enter_the_envelope_from_open_ground :: proc(t: ^testing.T) {
	// the other half of the may-enter rule: once the flood reaches free
	// ground it must stop hugging walls, or inflation buys nothing
	tilemap := fixture_room({".....", ".....", "..#..", ".....", "....."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({0, 0}), 1)

	// {2,1} is inside the wall's envelope and is only reachable through free
	// ground, never from another envelope cell connected to the source
	testing.expectf(
		t,
		flow_field_distance(&field, {2, 1}) == FLOW_UNREACHED,
		"an envelope cell reached only from open ground stays unfilled, got %v",
		flow_field_distance(&field, {2, 1}),
	)
	testing.expect(
		t,
		flow_field_distance(&field, {4, 4}) != FLOW_UNREACHED,
		"open ground on the far side of the pillar still fills",
	)
}

@(test)
test_flow_field_prefers_a_diagonal_across_open_ground :: proc(t: ^testing.T) {
	// the reason for weighting the steps rather than counting them: a
	// uniform-cost eight-neighbour flood would price this at one step and
	// make a diagonal free, and `distance` would stop being a distance
	tilemap := fixture_room({"...", "...", "..."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({0, 0}), 0)

	testing.expectf(
		t,
		flow_field_distance(&field, {2, 2}) == 2 * FLOW_COST_DIAGONAL,
		"expected two diagonals (%v), got %v",
		2 * FLOW_COST_DIAGONAL,
		flow_field_distance(&field, {2, 2}),
	)
	testing.expectf(
		t,
		flow_field_distance(&field, {2, 0}) == 2 * FLOW_COST_ORTHOGONAL,
		"a straight run along a row stays orthogonal, got %v",
		flow_field_distance(&field, {2, 0}),
	)

	cell, _ := flow_field_cell(&field, {2, 2})
	testing.expectf(t, cell.step == .Up_Left, "expected a diagonal step home, got %v", cell.step)
}

@(test)
test_flow_field_never_cuts_a_corner_between_two_walls :: proc(t: ^testing.T) {
	// two walls touching corner to corner leave a diagonal gap that a body
	// with width cannot pass. Allowing the diagonal would draw a route
	// through it and walk every enemy into the corner.
	tilemap := fixture_room({".#.", "#..", "..."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({0, 0}), 0)

	testing.expectf(
		t,
		flow_field_distance(&field, {1, 1}) == FLOW_UNREACHED,
		"the diagonal between two walls is not a route, got distance %v",
		flow_field_distance(&field, {1, 1}),
	)
	testing.expectf(t, field.filled_count == 1, "the source is walled in, so nothing else fills; got %v", field.filled_count)
}

// -- steering lookups ------------------------------------------------------

@(test)
test_flow_field_step_target_is_the_next_cell_centre :: proc(t: ^testing.T) {
	tilemap := fixture_room({"....."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({0, 0}), 0)

	target, ok := flow_field_step_target(&field, cell_world_center({3, 0}))
	testing.expect(t, ok, "a filled cell has a step target")
	testing.expectf(
		t,
		target == cell_world_center({2, 0}),
		"expected the centre of {2,0} (%v), got %v",
		cell_world_center({2, 0}),
		target,
	)
}

@(test)
test_flow_field_step_target_is_absent_at_the_source :: proc(t: ^testing.T) {
	tilemap := fixture_room({"....."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({2, 0}), 0)

	_, ok := flow_field_step_target(&field, cell_world_center({2, 0}))
	testing.expect(t, !ok, "standing on the player's own cell, steer straight at them instead")
}

@(test)
test_flow_field_step_target_falls_back_to_the_best_of_eight_neighbours :: proc(t: ^testing.T) {
	// Separation can push an enemy into an unfilled envelope cell. The
	// fallback reproduces find_path's "endpoints always allowed" exemption -
	// and must consider diagonals, and pick the lowest distance rather than
	// the first hit.
	tilemap := fixture_room({".....", ".....", "..#..", ".....", "....."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({0, 4}), 1)

	stranded := Vec2i{2, 1}
	testing.expect(t, flow_field_distance(&field, stranded) == FLOW_UNREACHED, "fixture assumption: {2,1} is unfilled")

	target, ok := flow_field_step_target(&field, cell_world_center(stranded))
	testing.expect(t, ok, "an unfilled cell still steers by its neighbours")

	// whichever neighbour it picked must be the lowest-distance one available
	best := FLOW_UNREACHED
	for dy in i32(-1) ..= 1 {
		for dx in i32(-1) ..= 1 {
			if dx == 0 && dy == 0 {
				continue
			}
			best = min(best, flow_field_distance(&field, stranded + {dx, dy}))
		}
	}
	chosen := world_to_cell_coord(target, {16, 16})
	testing.expectf(
		t,
		flow_field_distance(&field, chosen) == best,
		"expected the best-valued neighbour (distance %v), got %v at distance %v",
		best,
		chosen,
		flow_field_distance(&field, chosen),
	)
	testing.expectf(
		t,
		abs(chosen.x - stranded.x) <= 1 && abs(chosen.y - stranded.y) <= 1,
		"the fallback must pick a neighbour of %v, got %v",
		stranded,
		chosen,
	)
}

@(test)
test_flow_field_step_target_is_absent_with_no_valued_neighbour :: proc(t: ^testing.T) {
	tilemap := fixture_room({".....", ".###.", ".#.#.", ".###.", "....."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({0, 0}), 0)

	_, ok := flow_field_step_target(&field, cell_world_center({2, 2}))
	testing.expect(t, !ok, "sealed in a pocket, an enemy keeps the straight-line chase it had before the field")
}

@(test)
test_flow_field_retreat_target_is_the_farthest_neighbour :: proc(t: ^testing.T) {
	tilemap := fixture_room({"....."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({0, 0}), 0)

	target, ok := flow_field_retreat_target(&field, cell_world_center({2, 0}))
	testing.expect(t, ok, "a filled cell with filled neighbours can retreat")
	testing.expectf(
		t,
		target == cell_world_center({3, 0}),
		"expected the higher-distance neighbour {3,0} (%v), got %v",
		cell_world_center({3, 0}),
		target,
	)
}

@(test)
test_flow_field_retreat_target_is_absent_at_a_local_maximum :: proc(t: ^testing.T) {
	// the back of a dead end: every neighbour is *closer* to the player, so
	// the farthest of them is still a step inward. Taking it would walk the
	// enemy toward the player and straight back out next frame.
	tilemap := fixture_room({"....."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({0, 0}), 0)

	_, ok := flow_field_retreat_target(&field, cell_world_center({4, 0}))
	testing.expect(t, !ok, "with nowhere farther to stand, a Withdraw must not step back toward the player")
}

// -- rebuild policy --------------------------------------------------------

@(test)
test_flow_field_ensure_rebuilds_only_when_the_source_cell_changes :: proc(t: ^testing.T) {
	tilemap := fixture_room({".....", ".....", "....."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	testing.expect(t, flow_field_ensure(&field, &tilemap, {8, 8}, 1), "the first ensure builds the field")
	testing.expect(
		t,
		!flow_field_ensure(&field, &tilemap, {15, 15}, 1),
		"a move within the same cell must not rebuild - this is what makes the field affordable",
	)
	testing.expect(t, flow_field_ensure(&field, &tilemap, {24, 8}, 1), "crossing into the next cell rebuilds")
	testing.expectf(t, field.source == Vec2i{1, 0}, "expected the source to follow the player, got %v", field.source)
}

@(test)
test_flow_field_ensure_rebuilds_on_a_radius_change_and_after_invalidation :: proc(t: ^testing.T) {
	tilemap := fixture_room({".....", ".....", "....."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_ensure(&field, &tilemap, {8, 8}, 1)
	testing.expect(t, flow_field_ensure(&field, &tilemap, {8, 8}, 2), "a radius change rebuilds")
	testing.expect(t, !flow_field_ensure(&field, &tilemap, {8, 8}, 2), "and then settles again")

	flow_field_invalidate(&field)
	testing.expect(t, flow_field_ensure(&field, &tilemap, {8, 8}, 2), "an invalidated field rebuilds")
}

@(test)
test_flow_field_ensure_reuses_its_allocation_across_a_same_size_rebuild :: proc(t: ^testing.T) {
	tilemap := fixture_room({".....", ".....", "....."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_ensure(&field, &tilemap, {8, 8}, 1)
	before := raw_data(field.cells)
	before_cap := cap(field.cells)

	flow_field_ensure(&field, &tilemap, {24, 8}, 1)

	testing.expect(t, raw_data(field.cells) == before, "a same-size rebuild must not reallocate")
	testing.expectf(t, cap(field.cells) == before_cap, "expected capacity %v, got %v", before_cap, cap(field.cells))
}

@(test)
test_flow_field_rebuild_clears_the_previous_map_out_of_its_cells :: proc(t: ^testing.T) {
	// reusing the allocation without clearing every cell leaves ghost walls
	// and stale distances behind - silent, and visible only as enemies
	// refusing to enter a room
	walled := fixture_room({"...", ".#.", "..."})
	defer delete(walled.tiles)
	open := fixture_room({"...", "...", "..."})
	defer delete(open.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &walled, cell_world_center({0, 0}), 0)
	testing.expect(t, flow_field_distance(&field, {1, 1}) == FLOW_UNREACHED, "fixture assumption: the wall blocks")

	flow_field_rebuild(&field, &open, cell_world_center({0, 0}), 0)

	cell, _ := flow_field_cell(&field, {1, 1})
	testing.expect(t, !cell.collides, "the previous map's wall must not survive the rebuild")
	testing.expectf(
		t,
		cell.distance == FLOW_COST_DIAGONAL,
		"the cell the wall occupied is now ordinary floor, one diagonal from the source; got %v",
		cell.distance,
	)
}

@(test)
test_flow_field_destroy_zeroes_the_field_and_is_safe_twice :: proc(t: ^testing.T) {
	tilemap := fixture_room({"..", ".."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	flow_field_rebuild(&field, &tilemap, {0, 0}, 1)

	flow_field_destroy(&field)
	testing.expect(t, len(field.cells) == 0, "destroy frees the cells")
	testing.expect(t, !field.built, "destroy leaves an unbuilt field")

	flow_field_destroy(&field)
}

// -- the Attack Style seam -------------------------------------------------

@(test)
test_movement_intent_bands_a_ranged_enemy_against_its_firing_range :: proc(t: ^testing.T) {
	ranged := Ranged {
		min_range = 100,
		max_range = 200,
	}

	testing.expect(
		t,
		movement_intent({0, 0}, {300, 0}, ranged) == .Approach,
		"beyond max_range, a Ranged enemy closes",
	)
	testing.expect(t, movement_intent({0, 0}, {150, 0}, ranged) == .Hold, "inside the band, it holds")
	testing.expect(t, movement_intent({0, 0}, {50, 0}, ranged) == .Withdraw, "inside min_range, it backs off")
	testing.expect(t, movement_intent({0, 0}, {50, 0}, Melee{}) == .Approach, "a Melee enemy always closes")
	testing.expect(t, movement_intent({0, 0}, {50, 0}, nil) == .Approach, "and so does one with no attack")
}

@(test)
test_movement_goal_point_keeps_todays_euclidean_realisation :: proc(t: ^testing.T) {
	// Floater never reads the field, so its goal arithmetic must be exactly
	// what it was before the field existed
	enemy_pos := Vec2{100, 0}
	player_pos := Vec2{0, 0}

	testing.expect(t, movement_goal_point(enemy_pos, player_pos, .Approach) == player_pos, "Approach aims at the player")
	testing.expect(t, movement_goal_point(enemy_pos, player_pos, .Hold) == enemy_pos, "Hold aims at itself")
	testing.expectf(
		t,
		movement_goal_point(enemy_pos, player_pos, .Withdraw) == Vec2{100 + RANGED_RETREAT_LOOKAHEAD, 0},
		"Withdraw aims RANGED_RETREAT_LOOKAHEAD directly away from the player, got %v",
		movement_goal_point(enemy_pos, player_pos, .Withdraw),
	)
}

@(test)
test_field_chase_direction_follows_the_field_and_falls_back_to_the_goal :: proc(t: ^testing.T) {
	tilemap := fixture_room({"....."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({0, 0}), 0)

	pos := cell_world_center({3, 0})
	dir := field_chase_direction(&field, pos, .Approach, cell_world_center({0, 0}))
	testing.expectf(t, dir == Vec2{-1, 0}, "expected the field's leftward step, got %v", dir)

	testing.expect(t, field_chase_direction(&field, pos, .Hold, pos) == Vec2{}, "Hold steers nowhere")

	away := field_chase_direction(&field, pos, .Withdraw, pos + {100, 0})
	testing.expectf(t, away == Vec2{1, 0}, "expected a step to the farther cell, got %v", away)

	// an empty field is exactly the case an empty path used to cover
	empty: Flow_Field
	defer flow_field_destroy(&empty)
	fallback := field_chase_direction(&empty, {0, 0}, .Approach, {0, 100})
	testing.expectf(t, fallback == Vec2{0, 1}, "with no field, steer straight at the goal, got %v", fallback)
}

// -- the Swarmer contour ----------------------------------------------------
// A Swarmer follows the field inward to its surround distance and then drifts
// along that path-distance contour (CONTEXT.md's Swarmer entry, ADR-0025).
// Everything below goes through the same seam procs update_enemies calls, so
// the steering dispatch itself stays out of this file - see the note at the
// top.

@(test)
test_the_surround_radius_converts_to_the_fields_cost_units :: proc(t: ^testing.T) {
	tilemap := fixture_room({"...", "...", "..."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({0, 0}), 0)

	// 16px tiles: two tiles of travel is two orthogonal steps
	testing.expectf(
		t,
		flow_field_cost_for_world_distance(&field, 32) == 2 * FLOW_COST_ORTHOGONAL,
		"expected 32px to be two orthogonal steps, got %v",
		flow_field_cost_for_world_distance(&field, 32),
	)

	empty: Flow_Field
	defer flow_field_destroy(&empty)
	testing.expect(t, flow_field_cost_for_world_distance(&empty, 32) == 0, "no field, no cost")
	testing.expect(t, flow_field_cost_for_world_distance(&field, -5) == 0, "a negative radius is not a distance")
}

@(test)
test_a_swarmer_outside_its_surround_distance_closes_on_the_player :: proc(t: ^testing.T) {
	tilemap := fixture_room({"......."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({0, 0}), 0)

	pos := cell_world_center({5, 0})
	player := cell_world_center({0, 0})

	testing.expect(t, swarmer_intent(&field, pos, 32) == .Approach, "five cells out, one tile of radius: close")

	dir, drifting := swarmer_direction(&field, pos, player, 32, 1)
	testing.expectf(t, dir == Vec2{-1, 0}, "expected the field's leftward step, got %v", dir)
	testing.expect(t, !drifting, "closing is not drifting, so it moves at full speed")
}

@(test)
test_a_swarmer_on_its_contour_drifts_tangentially :: proc(t: ^testing.T) {
	tilemap := fixture_room({".......", ".......", ".......", ".......", ".......", ".......", "......."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({3, 3}), 0)

	// two orthogonal steps out, and a 32px surround radius is exactly that far
	pos := cell_world_center({5, 3})
	player := cell_world_center({3, 3})
	testing.expect(t, swarmer_intent(&field, pos, 32) == .Hold, "on the contour, it holds its distance")

	dir, drifting := swarmer_direction(&field, pos, player, 32, 1)
	testing.expect(t, drifting, "holding the contour is drifting")
	testing.expectf(t, dir == Vec2{0, -1}, "expected a step across the field's gradient, got %v", dir)

	// the step it took is still on the contour rather than one closer in
	stepped := flow_field_distance(&field, {5, 2})
	target := flow_field_cost_for_world_distance(&field, 32)
	testing.expectf(
		t,
		stepped >= target,
		"drifting must not press inward: %v against a contour at %v",
		stepped,
		target,
	)
}

@(test)
test_the_two_drift_signs_go_opposite_ways_round_the_contour :: proc(t: ^testing.T) {
	tilemap := fixture_room({".......", ".......", ".......", ".......", ".......", ".......", "......."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({3, 3}), 0)

	pos := cell_world_center({5, 3})
	player := cell_world_center({3, 3})

	clockwise, _ := swarmer_direction(&field, pos, player, 32, 1)
	widdershins, _ := swarmer_direction(&field, pos, player, 32, -1)

	testing.expectf(
		t,
		clockwise == -widdershins,
		"the two signs must mirror each other: %v against %v",
		clockwise,
		widdershins,
	)

	// an unset sign is a real state - an old save, or a template authored
	// before the field existed - and must still pick a side
	unset, _ := swarmer_direction(&field, pos, player, 32, 0)
	testing.expectf(t, unset == clockwise, "a zero sign reads as +1, got %v", unset)
}

@(test)
test_a_swarmer_inside_its_surround_distance_backs_out :: proc(t: ^testing.T) {
	tilemap := fixture_room({".......", ".......", ".......", ".......", ".......", ".......", "......."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({3, 3}), 0)

	// one cell out, but asked to surround at six
	pos := cell_world_center({4, 3})
	player := cell_world_center({3, 3})
	testing.expect(t, swarmer_intent(&field, pos, 96) == .Withdraw, "well inside the ring, it backs off")

	dir, drifting := swarmer_direction(&field, pos, player, 96, 1)
	testing.expect(t, !drifting, "backing out is not drifting")
	// only the x component is the assertion: several neighbours share the
	// farthest distance and scan order picks between them, so pinning y would
	// pin a tie-break rather than "away"
	testing.expectf(t, dir.x > 0, "expected a step away from the player, got %v", dir)

	// and the step it takes is genuinely farther out than where it stands
	stepped := pos + dir * 16
	testing.expectf(
		t,
		flow_field_distance(&field, world_to_cell_coord(stepped, {16, 16})) > flow_field_distance(&field, {4, 3}),
		"a withdrawal must strictly increase the path distance, got cell %v",
		world_to_cell_coord(stepped, {16, 16}),
	)
}

@(test)
test_a_swarmer_never_drifts_into_a_wall :: proc(t: ^testing.T) {
	// the same room, with a wall standing exactly where the open-ground drift
	// stepped in test_a_swarmer_on_its_contour_drifts_tangentially
	tilemap := fixture_room({".......", ".......", ".....#.", ".......", ".......", ".......", "......."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({3, 3}), 0)

	pos := cell_world_center({5, 3})
	player := cell_world_center({3, 3})

	// a colliding cell is never filled, so {5,2} is not a candidate; and {4,2},
	// the diagonal that would slip past the wall's corner, is refused by the
	// same flanking rule the flood uses. This arc dead-ends, so the Swarmer
	// holds its ground rather than pressing inward - Separation still spreads
	// the pack along it
	dir, drifting := swarmer_direction(&field, pos, player, 32, 1)
	testing.expect(t, drifting, "the wall blocks a step, not the drift itself")
	testing.expectf(t, dir == Vec2{}, "expected it to hold rather than push into the wall, got %v", dir)
}

@(test)
test_a_drift_slides_along_a_wall_it_runs_beside :: proc(t: ^testing.T) {
	// a wall down the right-hand side, parallel to the drift rather than
	// across it: the contour continues, so the Swarmer keeps moving
	tilemap := fixture_room({"......#", "......#", "......#", "......#", "......#", "......#", "......#"})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({3, 3}), 0)

	pos := cell_world_center({5, 3})
	player := cell_world_center({3, 3})

	dir, drifting := swarmer_direction(&field, pos, player, 32, 1)
	testing.expect(t, drifting, "it is on its contour")
	testing.expectf(t, dir == Vec2{0, -1}, "expected it to run alongside the wall, got %v", dir)
}

@(test)
test_a_swarmer_behind_a_wall_routes_around_it :: proc(t: ^testing.T) {
	// a wall down the middle, open only along the bottom row
	tilemap := fixture_room(
		{"...#...", "...#...", "...#...", "...#...", "...#...", "...#...", "......."},
	)
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({1, 0}), 0)

	pos := cell_world_center({5, 0})
	player := cell_world_center({1, 0})

	dir, _ := swarmer_direction(&field, pos, player, 16, 1)

	// straight at the player is straight into the wall; the field's route runs
	// down to the gap at the bottom first
	testing.expectf(t, dir != Vec2{-1, 0}, "a Swarmer must not walk into the wall, got %v", dir)
	testing.expectf(t, dir.y > 0, "expected it to head down toward the way round, got %v", dir)
}

@(test)
test_a_drift_step_never_leaves_the_contours_band :: proc(t: ^testing.T) {
	// the primitive directly, at costs swarmer_intent would never hand it -
	// what is being pinned is that the band is a filter and not merely a
	// tie-break, so a body has nowhere to drift rather than somewhere wrong.
	tilemap := fixture_room({".......", ".......", ".......", ".......", ".......", ".......", "......."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({3, 3}), 0)

	// {5,3} sits 20 out; its neighbours run 14 to 34, so a contour at 100 has
	// no cell here at all and the drift must decline rather than take the
	// best-aligned neighbour going
	_, ok := flow_field_contour_target(&field, cell_world_center({5, 3}), 100, 1)
	testing.expect(t, !ok, "no cell here is on the ring, so there is no step to take")

	// and where the ring does pass, the step lands on it rather than on
	// whichever neighbour points most squarely round the turn. At a contour of
	// 14 the diagonal {4,2} sits exactly on it while the perfectly tangential
	// {5,2}, at 24, is ten out - so the ring has to win, or a Swarmer walks
	// inward a step at a time until it stands a whole band closer than asked.
	target, on_ring := flow_field_contour_target(&field, cell_world_center({5, 3}), 14, 1)
	testing.expect(t, on_ring, "the ring passes through this cell's neighbours")
	testing.expectf(
		t,
		world_to_cell_coord(target, {16, 16}) == Vec2i{4, 2},
		"the ring beats the turn: expected the neighbour nearest the contour, got cell %v",
		world_to_cell_coord(target, {16, 16}),
	)
}

@(test)
test_a_swarmer_inside_the_inflation_envelope_closes_on_the_player :: proc(t: ^testing.T) {
	// the shipped field inflates walls by one cell (main.odin), and the flood
	// only ever leaves that envelope - so a Swarmer standing beside a wall has
	// no path distance of its own and cannot read a contour off one. It takes
	// the same fallback every other field consumer takes: walk back toward what
	// the field does know. Behaviour to watch, not a decision this ticket made.
	tilemap := fixture_room({".......", ".......", ".......", ".......", ".......", ".......", "######."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)

	flow_field_rebuild(&field, &tilemap, cell_world_center({3, 3}), 1)

	beside_the_wall := cell_world_center({2, 5})
	testing.expect(
		t,
		flow_field_distance(&field, {2, 5}) == FLOW_UNREACHED,
		"the fixture must actually put this cell in the envelope",
	)
	testing.expect(t, swarmer_intent(&field, beside_the_wall, 32) == .Approach, "no distance to hold, so it closes")
}

// the solid set as move_actor and tile_blocks_point read it: only an authored
// colliding tile answers true. An untiled gap inside the extent, a cell off
// the extent (which holds every authored tile, so off it is untiled ground),
// and a field with nothing in it all answer false, which is what a scan of the
// tiles would have found.
@(test)
test_flow_field_is_solid_answers_only_for_a_colliding_cell :: proc(t: ^testing.T) {
	tilemap := fixture_room({"#. ."})
	defer delete(tilemap.tiles)

	field: Flow_Field
	defer flow_field_destroy(&field)
	flow_field_rebuild(&field, &tilemap, cell_world_center({1, 0}), 1)

	testing.expect(t, flow_field_is_solid(&field, {0, 0}), "a colliding tile's cell is solid")
	testing.expect(t, !flow_field_is_solid(&field, {1, 0}), "a floor tile's cell is not solid")
	testing.expect(t, !flow_field_is_solid(&field, {2, 0}), "an untiled gap inside the extent is not solid")
	testing.expect(t, !flow_field_is_solid(&field, {0, 5}), "a cell off the extent is not solid")
	testing.expect(t, !flow_field_is_solid(&field, {-1, 0}), "a cell before the origin is not solid")

	empty: Flow_Field
	testing.expect(t, !flow_field_is_solid(&empty, {0, 0}), "a field that was never built has no solid cells")
}
