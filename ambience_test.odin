package shooter

// Ambience (ambience.odin): the seams take slices, a Tilemap and a bounds
// explicitly and never read `game`, so everything here drives throwaway
// values. Rendering (the three draw_ambient_* procs) is deliberately
// untested, per the content-expansion spec - the guarantee that an empty
// ambient set draws nothing is by construction, every draw call gated on the
// Map's set.

import "core:testing"
import rl "vendor:raylib"

@(test)
test_the_accent_is_the_wall_pushed_toward_white :: proc(t: ^testing.T) {
	desert := Map{floor_color = {56, 48, 40, 255}, wall_color = {124, 110, 90, 255}}
	accent := map_accent_color(desert)
	testing.expect_value(t, accent.a, u8(255))
	testing.expect(t, color_luma(accent) > color_luma(desert.wall_color), "the accent tints motes and light over the wall, so it has to be lighter than it")
	testing.expect(t, accent.r > accent.b, "pushing toward white keeps the wall's own hue, so a warm wall gives a warm accent")
}

@(private = "file")
BOUNDS :: World_Bounds{min_x = 0, max_x = 320, min_y = 0, max_y = 180}

@(test)
test_a_mote_that_drifts_out_of_view_is_reseeded_inside_it :: proc(t: ^testing.T) {
	motes: [4]Mote
	for &m in motes {
		seed_mote(&m, BOUNDS)
		testing.expect(t, point_in_world_bounds(m.position, BOUNDS), "a seeded mote starts inside the view")
		testing.expect(t, m.radius > 0, "a seeded mote has a body to draw")
	}

	// far enough for any drift to carry every mote well past the edge
	update_motes(motes[:], BOUNDS, 10_000)
	for m in motes {
		testing.expect(t, point_in_world_bounds(m.position, BOUNDS), "a mote that leaves the view comes back inside it, never accumulating off-screen")
	}
}

@(test)
test_motes_drift_with_time_and_hold_still_without_it :: proc(t: ^testing.T) {
	motes: [1]Mote
	seed_mote(&motes[0], BOUNDS)
	motes[0].position = {160, 90}
	motes[0].drift = {10, 0}

	update_motes(motes[:], BOUNDS, 0)
	testing.expect_value(t, motes[0].position, Vec2{160, 90})

	update_motes(motes[:], BOUNDS, 0.5)
	testing.expect_value(t, motes[0].position, Vec2{165, 90})
}

// -- floor patches -----------------------------------------------------------

// a walled room with a floor pocket in the middle and an untiled gap on the
// right: a patch belongs on '.' and nowhere else
@(private = "file")
patch_room :: proc() -> Tilemap {
	return fixture_room(
		{
			"########",
			"#......#",
			"#......#",
			"#......#",
			"#......#",
			"########",
			"        ",
		},
	)
}

@(test)
test_floor_patches_land_on_floor_tiles_only :: proc(t: ^testing.T) {
	tilemap := patch_room()
	defer delete(tilemap.tiles)

	patches: [AMBIENT_PATCH_MAX]Floor_Patch
	count := seed_floor_patches(patches[:], &tilemap)
	testing.expect(t, count > 0, "a room with floor gets patches")
	testing.expect(t, count <= AMBIENT_PATCH_MAX, "never more than the budget")
	for p in patches[:count] {
		testing.expect(t, p.radius > 0, "a patch has a body to draw")
		on_floor := false
		for tile in tilemap.tiles {
			if !tile.collides &&
			   rl.CheckCollisionPointRec(p.position, tile_world_rect(tile.world_coords, tilemap.tile_size)) {
				on_floor = true
			}
		}
		testing.expectf(t, on_floor, "patch at %v is not centred on a floor tile - a blotch on a wall or in the void is a wrong read of the place", p.position)
	}
}

@(test)
test_floor_patches_are_the_same_every_time_a_map_is_entered :: proc(t: ^testing.T) {
	tilemap := patch_room()
	defer delete(tilemap.tiles)

	first, second: [AMBIENT_PATCH_MAX]Floor_Patch
	first_count := seed_floor_patches(first[:], &tilemap)
	second_count := seed_floor_patches(second[:], &tilemap)
	testing.expect_value(t, second_count, first_count)
	for i in 0 ..< first_count {
		testing.expect_value(t, second[i], first[i])
	}
}

@(test)
test_an_empty_tilemap_seeds_no_patches :: proc(t: ^testing.T) {
	tilemap := Tilemap{tile_size = {16, 16}}
	patches: [AMBIENT_PATCH_MAX]Floor_Patch
	testing.expect_value(t, seed_floor_patches(patches[:], &tilemap), 0)
}

// -- ambience_ensure ---------------------------------------------------------

@(test)
test_patches_are_placed_once_per_map_and_replaced_when_the_tiles_change :: proc(t: ^testing.T) {
	map_data := Map{tilemap = patch_room(), ambient = {.Floor_Patches}}
	defer delete(map_data.tilemap.tiles)

	ambience: Ambience
	testing.expect(t, ambience_ensure(&ambience, &map_data), "the first frame on a Map places its patches")
	testing.expect(t, ambience.patch_count > 0, "and there are some")
	testing.expect(t, !ambience_ensure(&ambience, &map_data), "the next frame on the same tiles leaves them where they are")

	// a wall blocked out in the editor is a different place to decorate
	tilemap_place_tile(&map_data.tilemap, {3, 8})
	testing.expect(t, ambience_ensure(&ambience, &map_data), "a tile painted underneath re-places them")
}

@(test)
test_a_map_without_floor_patches_places_none :: proc(t: ^testing.T) {
	map_data := Map{tilemap = patch_room(), ambient = {.Motes, .Light_Wash}}
	defer delete(map_data.tilemap.tiles)

	ambience: Ambience
	ambience_ensure(&ambience, &map_data)
	testing.expect_value(t, ambience.patch_count, 0)
}
