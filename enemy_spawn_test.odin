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
		point := pick_offscreen_spawn_point(player_pos, visible_rect, map_bounds, &tilemap)
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
		point := pick_offscreen_spawn_point(player_pos, visible_rect, bounds, &tilemap)
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
