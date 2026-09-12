package shooter

import "core:testing"
import rl "vendor:raylib"

// move_actor takes its Flow_Field explicitly, so these drive a throwaway room
// (flow_field_test.odin's fixture_room) flooded into a local field and need
// no ODIN_TEST_THREADS=1 pinning. Pinned here: the one thing a caller can
// read back from a move besides the resolved position - whether a wall
// stopped it, the signal a Charger's dash ends on (charger_end_dash) - and
// that reading the field's solid set instead of scanning every tile changed
// nothing about where a body ends up.

@(test)
test_move_actor_reports_a_move_a_wall_resolved :: proc(t: ^testing.T) {
	// a floor cell with a wall immediately to its right
	tilemap := fixture_room({"..#"})
	defer delete(tilemap.tiles)
	field := fixture_field(&tilemap, {8, 8})
	defer flow_field_destroy(&field)

	// feet in the middle of the first floor cell; the collision box is
	// ACTOR_SIZE wide so a 16px step right lands it inside the wall
	actor := Rect{8, 16, 0, 0}
	blocked := move_actor(&actor, &field, {16, 0})

	testing.expect(t, blocked, "a step that a wall resolved should report blocked")
	testing.expectf(t, actor.x < 24, "the wall should have stopped the body short of it, got x = %v", actor.x)
}

@(test)
test_move_actor_reports_open_ground_as_unblocked :: proc(t: ^testing.T) {
	tilemap := fixture_room({"....."})
	defer delete(tilemap.tiles)
	field := fixture_field(&tilemap, {8, 8})
	defer flow_field_destroy(&field)

	actor := Rect{16, 16, 0, 0}
	blocked := move_actor(&actor, &field, {16, 0})

	testing.expect(t, !blocked, "a step across floor should not report blocked")
	testing.expect_value(t, actor.x, f32(32))
}

// a body resolved flush against a wall sits exactly on the wall column's
// boundary, so that column is among the cells its box is read against on
// the next move. Touching is not overlapping: moving along the wall must
// neither snap the body nor report it blocked.
@(test)
test_move_actor_slides_along_a_wall_without_snapping_the_other_axis :: proc(t: ^testing.T) {
	tilemap := fixture_room({"...#", "...#", "...#"})
	defer delete(tilemap.tiles)
	field := fixture_field(&tilemap, {8, 8})
	defer flow_field_destroy(&field)

	// box spans x 24..48, its right edge on the wall column at x = 48
	actor := Rect{36, 16, 0, 0}
	blocked := move_actor(&actor, &field, {0, 4})

	testing.expect(t, !blocked, "moving along a wall the body already touches is not a wall resolving the move")
	testing.expect_value(t, actor.x, f32(36))
	testing.expect_value(t, actor.y, f32(20))
}

@(test)
test_move_actor_stops_at_an_inside_corner_on_diagonal_input :: proc(t: ^testing.T) {
	tilemap := fixture_room({"....", "...#", "####"})
	defer delete(tilemap.tiles)
	field := fixture_field(&tilemap, {8, 8})
	defer flow_field_destroy(&field)

	// tucked into the corner: box right edge on x = 48, bottom on y = 32
	actor := Rect{36, 32, 0, 0}
	blocked := move_actor(&actor, &field, {3, 3})

	testing.expect(t, blocked, "a diagonal push into a corner is resolved on both axes")
	testing.expect_value(t, actor.x, f32(36))
	testing.expect_value(t, actor.y, f32(32))
}

@(test)
test_move_actor_ignores_a_gap_too_narrow_for_the_body :: proc(t: ^testing.T) {
	tilemap := fixture_room({"...", "#.#"})
	defer delete(tilemap.tiles)
	field := fixture_field(&tilemap, {24, 8})
	defer flow_field_destroy(&field)

	// centred over the one-cell gap; the 24px box overhangs both walls
	actor := Rect{24, 16, 0, 0}
	blocked := move_actor(&actor, &field, {0, 4})

	testing.expect(t, blocked, "a 24px body cannot enter a 16px gap")
	testing.expect_value(t, actor.y, f32(16))
}

// the editor places tiles at negative coords and the field's origin follows
// them; the cell range a box spans must floor, not truncate toward zero
@(test)
test_move_actor_resolves_against_a_wall_at_negative_cells :: proc(t: ^testing.T) {
	tilemap := Tilemap {
		tile_size = {16, 16},
	}
	append(&tilemap.tiles, Tile{world_coords = {-1, 0}, collides = true})
	append(&tilemap.tiles, Tile{world_coords = {0, 0}, collides = false})
	defer delete(tilemap.tiles)
	field := fixture_field(&tilemap, {8, 8})
	defer flow_field_destroy(&field)

	// box spans x 4..28; the wall is x -16..0
	actor := Rect{16, 16, 0, 0}
	blocked := move_actor(&actor, &field, {-8, 0})

	testing.expect(t, blocked, "the wall at x < 0 should resolve the move")
	testing.expect_value(t, actor.x, f32(12))
}

@(test)
test_move_actor_off_the_map_applies_its_delta :: proc(t: ^testing.T) {
	tilemap := fixture_room({"#"})
	defer delete(tilemap.tiles)
	field := fixture_field(&tilemap, {8, 8})
	defer flow_field_destroy(&field)

	actor := Rect{200, 200, 0, 0}
	blocked := move_actor(&actor, &field, {5, -5})

	testing.expect(t, !blocked, "untiled ground off the field's extent has no walls")
	testing.expect_value(t, actor.x, f32(205))
	testing.expect_value(t, actor.y, f32(195))
}

// game.current_map = Map{} is a real state (no tiles, zero tile_size) and so
// is a field never built at all: both are a Map with no walls, not a crash
@(test)
test_move_actor_with_an_unusable_field_applies_its_delta :: proc(t: ^testing.T) {
	tilemap := Tilemap{}
	field := fixture_field(&tilemap, {8, 8})
	defer flow_field_destroy(&field)

	actor := Rect{16, 16, 0, 0}
	blocked := move_actor(&actor, &field, {3, 3})
	testing.expect(t, !blocked, "a field with no cells has no walls")
	testing.expect_value(t, actor.x, f32(19))
	testing.expect_value(t, actor.y, f32(19))

	never_built: Flow_Field
	actor = Rect{16, 16, 0, 0}
	blocked = move_actor(&actor, &never_built, {3, 3})
	testing.expect(t, !blocked, "a field never built has no walls")
	testing.expect_value(t, actor.x, f32(19))
}

// the resolver move_actor replaced, kept verbatim as the reference: every
// colliding tile tested per axis. Reading only the cells the box sweeps is
// exactly equivalent for a body that is not already inside a wall (the box is
// only ever pushed back toward where it started, so every tile it can meet is
// in the sweep), which is the contract the sweep below exercises - it skips
// embedded starts, and it steps further than a tile so the old resolver's
// chain of ejections through a thick wall is among what must match.
@(private = "file")
move_actor_by_scan :: proc(rect: ^Rect, tilemap: ^Tilemap, delta: Vec2) -> (blocked: bool) {
	box := actor_collision_rect(rect^)

	box.x += delta.x
	for tile in tilemap.tiles {
		if !tile.collides {
			continue
		}
		tile_rect := tile_world_rect(tile.world_coords, tilemap.tile_size)
		if !rl.CheckCollisionRecs(box, tile_rect) {
			continue
		}
		if delta.x > 0 {
			box.x = tile_rect.x - box.width
			blocked = true
		} else if delta.x < 0 {
			box.x = tile_rect.x + tile_rect.width
			blocked = true
		}
	}

	box.y += delta.y
	for tile in tilemap.tiles {
		if !tile.collides {
			continue
		}
		tile_rect := tile_world_rect(tile.world_coords, tilemap.tile_size)
		if !rl.CheckCollisionRecs(box, tile_rect) {
			continue
		}
		if delta.y > 0 {
			box.y = tile_rect.y - box.height
			blocked = true
		} else if delta.y < 0 {
			box.y = tile_rect.y + tile_rect.height
			blocked = true
		}
	}

	rect.x = box.x + box.width / 2
	rect.y = box.y + box.height
	return
}

@(private = "file")
box_overlaps_a_wall :: proc(tilemap: ^Tilemap, box: Rect) -> bool {
	for tile in tilemap.tiles {
		if tile.collides && rl.CheckCollisionRecs(box, tile_world_rect(tile.world_coords, tilemap.tile_size)) {
			return true
		}
	}
	return false
}

@(test)
test_move_actor_matches_a_scan_of_every_tile :: proc(t: ^testing.T) {
	// outer walls, an interior pillar, a one-cell gap, an untiled doorway,
	// and a three-deep wall along the bottom for the long steps to land in
	tilemap := fixture_room({
		"########",
		"#......#",
		"#..#...#",
		"#..#  .#",
		"##.#####",
		"#......#",
		"#......#",
		"########",
		"########",
		"########",
	})
	defer delete(tilemap.tiles)
	field := fixture_field(&tilemap, {24, 24})
	defer flow_field_destroy(&field)

	deltas := [?]Vec2 {
		{0, 0},
		{3, 0}, {-3, 0}, {0, 3}, {0, -3},
		{3, 3}, {-3, 3}, {3, -3}, {-3, -3},
		{10, 7}, {-10, 7}, {10, -7}, {-10, -7},
		{17, 5}, {-17, 5}, {17, -5}, {-17, -5},
		{23, 23}, {-23, 23}, {23, -23}, {-23, -23},
		{0, 50}, {50, 0}, {-50, 0}, {0, -50}, {40, 45}, {-40, 45},
	}

	compared, mismatches := 0, 0
	for y := f32(-8.5); y <= 176; y += 4 {
		for x := f32(-8.5); x <= 136; x += 4 {
			start := Rect{x, y, 0, 0}
			if box_overlaps_a_wall(&tilemap, actor_collision_rect(start)) {
				continue
			}
			for delta in deltas {
				by_field, by_scan := start, start
				blocked_by_field := move_actor(&by_field, &field, delta)
				blocked_by_scan := move_actor_by_scan(&by_scan, &tilemap, delta)
				compared += 1
				if by_field != by_scan || blocked_by_field != blocked_by_scan {
					mismatches += 1
					if mismatches <= 5 {
						testing.expectf(
							t,
							false,
							"from %v by %v: field gave %v (blocked %v), scan gave %v (blocked %v)",
							Vec2{x, y}, delta,
							Vec2{by_field.x, by_field.y}, blocked_by_field,
							Vec2{by_scan.x, by_scan.y}, blocked_by_scan,
						)
					}
				}
			}
		}
	}

	testing.expectf(t, compared > 1000, "the sweep should cover the room, compared only %v moves", compared)
	testing.expect_value(t, mismatches, 0)
}
