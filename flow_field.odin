package shooter



// The shared flow field: one flood outward from the player's cell that every
// terrain-colliding enemy reads, replacing the per-enemy BFS every Grounded
// enemy used to run every frame. See CONTEXT.md's Flow field entry and
// ADR-0025.
//
// The decisive property is the direction of the search. Flooding from the
// player rather than from each enemy means a crowd of hundreds costs what one
// enemy costs, there is no node budget to truncate a long route, and a cell the
// flood never reaches is *unreachable from the player*, full stop - a more
// useful answer than a failed path, and what tickets 05 and 07 both build on.
//
// Nothing in this file reads `game`: every proc takes the Tilemap and a world
// position explicitly. That is what keeps flow_field_test.odin on throwaway
// fixtures with no ODIN_TEST_THREADS=1 pinning - keep it that way.

// which neighbour a cell's flood parent is - the direction to step to get
// closer to the source. Eight-neighbour: the four-neighbour flood the deleted
// find_path used walked bodies in L-shapes through open ground, and its routes
// came out 11% longer than the true shortest path at the median on Desert
// Dungeon (43% at worst, and longer than optimal on 81% of its cells).
// `.None` covers both "the source itself" and "never filled": neither has
// anywhere to step.
Flow_Step :: enum u8 {
	None,
	Left,
	Right,
	Up,
	Down,
	Up_Left,
	Up_Right,
	Down_Left,
	Down_Right,
}

FLOW_STEP_OFFSET := [Flow_Step]Vec2i {
	.None       = {0, 0},
	.Left       = {-1, 0},
	.Right      = {1, 0},
	.Up         = {0, -1},
	.Down       = {0, 1},
	.Up_Left    = {-1, -1},
	.Up_Right   = {1, -1},
	.Down_Left  = {-1, 1},
	.Down_Right = {1, 1},
}

FLOW_STEP_OPPOSITE := [Flow_Step]Flow_Step {
	.None       = .None,
	.Left       = .Right,
	.Right      = .Left,
	.Up         = .Down,
	.Down       = .Up,
	.Up_Left    = .Down_Right,
	.Up_Right   = .Down_Left,
	.Down_Left  = .Up_Right,
	.Down_Right = .Up_Left,
}

// A diagonal costs what a diagonal is worth. 14/10 approximates sqrt(2) to
// within 1%, in integers, which is the whole reason distance is counted in
// these units rather than in cells: a uniform-cost eight-neighbour flood would
// make a diagonal free, and `distance` would stop being a distance - a ring at
// a fixed path-distance would come out square, which is exactly what ticket
// 05's Swarmer contour cannot use. Divide by FLOW_COST_ORTHOGONAL for a
// human-readable cell count.
FLOW_COST_ORTHOGONAL :: 10
FLOW_COST_DIAGONAL :: 14

// Dial's bucket queue needs one bucket per distinct distance in flight, and
// with a largest edge of FLOW_COST_DIAGONAL nothing queued is ever more than
// that far ahead of the distance being swept. Two edge weights is what makes
// this worth it over a binary heap: the heap was ~1.1ms of a 1.2ms rebuild on
// Desert Dungeon, almost all of it indirect calls through its comparison and
// swap procs.
FLOW_BUCKET_COUNT :: FLOW_COST_DIAGONAL + 1

FLOW_STEP_COST := [Flow_Step]u32 {
	.None       = 0,
	.Left       = FLOW_COST_ORTHOGONAL,
	.Right      = FLOW_COST_ORTHOGONAL,
	.Up         = FLOW_COST_ORTHOGONAL,
	.Down       = FLOW_COST_ORTHOGONAL,
	.Up_Left    = FLOW_COST_DIAGONAL,
	.Up_Right   = FLOW_COST_DIAGONAL,
	.Down_Left  = FLOW_COST_DIAGONAL,
	.Down_Right = FLOW_COST_DIAGONAL,
}

// every direction the flood expands in, `.None` excluded
FLOW_NEIGHBOUR_STEPS := [8]Flow_Step {
	.Left,
	.Right,
	.Up,
	.Down,
	.Up_Left,
	.Up_Right,
	.Down_Left,
	.Down_Right,
}

// a cell the flood never reached. A sentinel distance rather than a separate
// `filled` bool so the fallback's "best-valued neighbour" scan is a plain
// min() with no special case, and so ticket 07's reachability test is one
// comparison.
FLOW_UNREACHED :: max(u32)

Flow_Cell :: struct {
	distance: u32,       // path cost from the source cell in FLOW_COST_* units; FLOW_UNREACHED if never filled
	step:     Flow_Step, // toward distance-1; .None at the source and in unfilled cells
	collides: bool,      // an authored colliding Tile sits here
	inflated: bool,      // inside some wall's (2r+1)^2 envelope at `radius`
}

Flow_Field :: struct {
	// the cell extent: the authored tile box grown to contain the source
	// cell (see flow_field_rebuild). origin may be negative - the editor
	// places tiles at negative coords, and a player standing off the top of
	// the map pulls the box up past zero - so nothing may assume {0,0}; a
	// zero `size` means there is no field at all and every lookup answers
	// "unreached".
	origin:        Vec2i,
	size:          Vec2i,
	tile_size:     Vec2,
	radius:        i32, // inflation radius baked into `inflated`; a change forces a rebuild
	source:        Vec2i, // the cell flooded from - what "the player changed cell" compares against
	built:         bool, // false = unbuilt or invalidated; explicit, so a map switch rebuilds
	// cheap staleness guard against a tilemap swapped under the field. The
	// editor only ever mutates game.editing_map, so the live tilemap is never
	// edited beneath us - this is belt-and-braces, not a supported
	// edit-while-playing path.
	tile_count:    int,
	max_distance:  u32, // largest filled distance, in cost units - the debug shading ramp, and ticket 05's contour math
	filled_count:  int, // cells the flood reached
	cells:         [dynamic]Flow_Cell, // row-major: (cell.y-origin.y)*size.x + (cell.x-origin.x)
	// the flood's frontier, bucketed by distance (see FLOW_BUCKET_COUNT).
	// Owned by the field rather than made per rebuild so the backing arrays
	// are allocated once and reused for the life of the map.
	buckets:       [FLOW_BUCKET_COUNT][dynamic]Vec2i,
}

// how far a wall's influence is stamped outward, in cells, so a body with
// width does not have its route threaded through a gap it cannot fit. A
// Tunable, and stored on the field, so dragging it re-floods on the next
// frame against the debug overlay.
FLOW_FIELD_INFLATION_RADIUS: int = 1

// the tilemap's authored extent in cell coords - the integer sibling of
// tilemap_world_bounds, which the field needs because it must *enumerate*
// cells rather than merely clamp a point into them
tilemap_cell_bounds :: proc(tilemap: ^Tilemap) -> (min_cell, max_cell: Vec2i, ok: bool) {
	if len(tilemap.tiles) == 0 {
		return {}, {}, false
	}

	min_cell = tilemap.tiles[0].world_coords
	max_cell = min_cell
	for tile in tilemap.tiles[1:] {
		min_cell.x = min(min_cell.x, tile.world_coords.x)
		min_cell.y = min(min_cell.y, tile.world_coords.y)
		max_cell.x = max(max_cell.x, tile.world_coords.x)
		max_cell.y = max(max_cell.y, tile.world_coords.y)
	}
	return min_cell, max_cell, true
}

// whether the field has cells to look anything up in. A degenerate map is a
// real state - game.current_map = Map{} has no tiles and a zero tile_size -
// and every lookup must answer "nothing" rather than divide a world position
// by a zero tile size.
flow_field_is_usable :: proc(field: ^Flow_Field) -> bool {
	return field.size.x > 0 && field.size.y > 0 && field.tile_size.x > 0 && field.tile_size.y > 0
}

@(private = "file")
flow_field_index :: proc(field: ^Flow_Field, cell: Vec2i) -> (index: int, ok: bool) {
	local := cell - field.origin
	if local.x < 0 || local.y < 0 || local.x >= field.size.x || local.y >= field.size.y {
		return 0, false
	}
	return int(local.y) * int(field.size.x) + int(local.x), true
}

flow_field_cell :: proc(field: ^Flow_Field, cell: Vec2i) -> (Flow_Cell, bool) {
	index, ok := flow_field_index(field, cell)
	if !ok {
		return {}, false
	}
	return field.cells[index], true
}

flow_field_distance :: proc(field: ^Flow_Field, cell: Vec2i) -> u32 {
	found, ok := flow_field_cell(field, cell)
	if !ok {
		return FLOW_UNREACHED
	}
	return found.distance
}

// the per-frame entry point. Rebuilds only when the answer would actually
// differ: the player crossed into a new cell, the field is unbuilt or was
// invalidated, the inflation radius changed, or the tilemap underneath is not
// the one the field was built from. Returns whether it rebuilt - which is what
// makes "rebuilt only when the player changes cell" assertable without
// counters or timing.
flow_field_ensure :: proc(
	field: ^Flow_Field,
	tilemap: ^Tilemap,
	source_world: Vec2,
	radius: i32,
) -> (
	rebuilt: bool,
) {
	if !field.built ||
	   field.radius != radius ||
	   field.tile_size != tilemap.tile_size ||
	   field.tile_count != len(tilemap.tiles) {
		flow_field_rebuild(field, tilemap, source_world, radius)
		return true
	}

	// a degenerate field has no cells to flood into and no valid tile_size to
	// convert a world position with; it is already built and stays empty
	if tilemap.tile_size.x <= 0 || tilemap.tile_size.y <= 0 {
		return false
	}

	if world_to_cell_coord(source_world, tilemap.tile_size) != field.source {
		flow_field_rebuild(field, tilemap, source_world, radius)
		return true
	}
	return false
}

// drops the field's answers while keeping its allocation, so the next
// flow_field_ensure re-floods. Called where the live map is replaced.
flow_field_invalidate :: proc(field: ^Flow_Field) {
	field.built = false
}

flow_field_destroy :: proc(field: ^Flow_Field) {
	delete(field.cells)
	for &bucket in field.buckets {
		delete(bucket)
	}
	field^ = {}
}

// re-floods unconditionally. Reuses `cells` when the extent's size is
// unchanged, but always clears every cell: skipping the clear leaves the
// previous map's walls and distances behind, which is silent and shows up only
// as enemies refusing to enter a room.
flow_field_rebuild :: proc(field: ^Flow_Field, tilemap: ^Tilemap, source_world: Vec2, radius: i32) {
	field.tile_size = tilemap.tile_size
	field.radius = radius
	field.tile_count = len(tilemap.tiles)
	field.built = true
	field.max_distance = 0
	field.filled_count = 0

	min_cell, max_cell, has_tiles := tilemap_cell_bounds(tilemap)
	has_size := tilemap.tile_size.x > 0 && tilemap.tile_size.y > 0
	field.source = has_size ? world_to_cell_coord(source_world, tilemap.tile_size) : Vec2i{}

	if !has_tiles || !has_size {
		field.origin = {}
		field.size = {}
		clear(&field.cells)
		return
	}

	// the authored tile box, grown to contain the player's own cell. Bounding
	// to the tiles alone gives the field an off switch: Desert Dungeon's
	// bounding box has 48 walkable cells on its border and 648 cells reachable
	// from player_start lie outside it, so one walk off the top edge left the
	// source out of bounds, filled nothing, and reverted every enemy to
	// straight-line chasing. Growing by the source keeps the flood bounded -
	// the box only ever reaches as far as the player has actually strayed -
	// while letting the flood start under the player and walk back into the
	// map across the untiled ground around it.
	extent_min := Vec2i{min(min_cell.x, field.source.x), min(min_cell.y, field.source.y)}
	extent_max := Vec2i{max(max_cell.x, field.source.x), max(max_cell.y, field.source.y)}
	field.origin = extent_min
	field.size = extent_max - extent_min + {1, 1}

	count := int(field.size.x) * int(field.size.y)
	if len(field.cells) != count {
		resize(&field.cells, count)
	}
	for &cell in field.cells {
		cell = Flow_Cell {
			distance = FLOW_UNREACHED,
			step     = .None,
		}
	}

	for tile in tilemap.tiles {
		if !tile.collides {
			continue
		}

		if index, ok := flow_field_index(field, tile.world_coords); ok {
			field.cells[index].collides = true
		}
		for dx in -radius ..= radius {
			for dy in -radius ..= radius {
				if index, ok := flow_field_index(field, tile.world_coords + {dx, dy}); ok {
					field.cells[index].inflated = true
				}
			}
		}
	}

	source_index, source_in_bounds := flow_field_index(field, field.source)
	// the extent is grown to contain the source, so out-of-bounds here means
	// only that there were no tiles to grow from. A source standing inside a
	// wall is the case that survives, and it fills nothing rather than being
	// nudged out: nudging would flood from a cell the player is not in, where
	// filling nothing simply falls every enemy back to the straight-line
	// chase it had before the field existed.
	if !source_in_bounds || field.cells[source_index].collides {
		return
	}

	for &bucket in field.buckets {
		clear(&bucket)
	}
	field.cells[source_index].distance = 0
	append(&field.buckets[0], field.source)

	// Dial's algorithm: a bucket queue rather than the plain FIFO a
	// uniform-cost flood allowed, because a diagonal costs more than an
	// orthogonal step and cells must still come out in increasing distance
	// order. `sweep` only ever moves forward, so a cell whose distance was
	// improved after being queued is recognised by its stored distance no
	// longer matching the bucket it was found in, and dropped.
	pending := 1
	sweep := u32(0)
	for pending > 0 {
		bucket := &field.buckets[sweep % FLOW_BUCKET_COUNT]
		if len(bucket) == 0 {
			sweep += 1
			continue
		}

		cell_coord := pop(bucket)
		pending -= 1
		current_index, _ := flow_field_index(field, cell_coord)
		current_cell := field.cells[current_index]
		if current_cell.distance != sweep {
			continue
		}

		for step in FLOW_NEIGHBOUR_STEPS {
			offset := FLOW_STEP_OFFSET[step]
			neighbour := cell_coord + offset
			if !flow_can_enter(field, neighbour, current_cell) {
				continue
			}
			// a diagonal squeezes between two cells, and a body with width
			// cannot pass a corner those two block. Requiring both flanks
			// keeps the field honest about what an actor can walk, and is
			// what stops a route being drawn through the gap where two walls
			// touch corner to corner.
			if offset.x != 0 && offset.y != 0 {
				if !flow_can_enter(field, cell_coord + {offset.x, 0}, current_cell) ||
				   !flow_can_enter(field, cell_coord + {0, offset.y}, current_cell) {
					continue
				}
			}

			index, _ := flow_field_index(field, neighbour)
			next := current_cell.distance + FLOW_STEP_COST[step]
			if next >= field.cells[index].distance {
				continue
			}

			field.cells[index].distance = next
			field.cells[index].step = FLOW_STEP_OPPOSITE[step]
			append(&field.buckets[next % FLOW_BUCKET_COUNT], neighbour)
			pending += 1
		}
	}

	// counted after the flood rather than during it: a cell's distance can be
	// improved after it is first reached, so a running maximum could be left
	// holding a value no cell ends up carrying
	for cell in field.cells {
		if cell.distance == FLOW_UNREACHED {
			continue
		}
		field.filled_count += 1
		field.max_distance = max(field.max_distance, cell.distance)
	}
}

// whether the flood may step into `cell` from a cell whose record is `from`.
// An inflated cell is enterable only *from* an inflated cell, and the source
// is the only inflated cell ever seeded - so the flood walks out of whatever
// envelope pocket the player is standing in, and can never step back into the
// envelope once it reaches open ground. This generalises the deleted
// find_path's "endpoints always allowed" exemption, and it is load-bearing
// rather than defensive. Measured on Desert Dungeon at radius 1: 741 of its
// 2239 standable cells are inside the envelope, and 101 have no free
// orthogonal neighbour at all - so a flood that refused to leave the envelope
// would collapse to a single cell whenever the player stood on one of those
// 101.
@(private = "file")
flow_can_enter :: proc(field: ^Flow_Field, cell: Vec2i, from: Flow_Cell) -> bool {
	target, in_bounds := flow_field_cell(field, cell)
	if !in_bounds || target.collides {
		return false
	}
	return !target.inflated || from.inflated
}

// the world point a field-steered enemy at world_pos should head for: the
// centre of the next cell along the flood, so the target is constant while the
// enemy occupies one cell and changes exactly once, when it enters the next.
// That is why there is no arrive radius any more - the cell transition *is*
// the arrival test.
//
// From an unfilled cell (Separation can push a body into the inflation
// envelope) it falls back to the best-valued of the eight neighbours. ok=false
// on the player's own cell, and wherever nothing has a value at all: the
// caller then steers straight at its goal, exactly as an empty path made it do
// before.
flow_field_step_target :: proc(field: ^Flow_Field, world_pos: Vec2) -> (target: Vec2, ok: bool) {
	if !flow_field_is_usable(field) {
		return {}, false
	}

	cell_coord := world_to_cell_coord(world_pos, field.tile_size)
	if cell, in_bounds := flow_field_cell(field, cell_coord); in_bounds && cell.distance != FLOW_UNREACHED {
		if cell.step == .None {
			return {}, false // the source cell: steering straight at the player is more precise
		}
		return cell_center_to_world(cell_coord + FLOW_STEP_OFFSET[cell.step], field.tile_size), true
	}

	best, found := flow_field_extreme_neighbour(field, cell_coord, .Nearest)
	if !found {
		return {}, false
	}
	return cell_center_to_world(best, field.tile_size), true
}

// a Ranged enemy backing out of its minimum range steps to the highest
// path-distance neighbour, which is walkable by construction (only a filled
// cell has a distance). It has one cell of lookahead, so it can still reverse
// into a dead end - accepted by ADR-0025.
//
// The step must strictly *increase* the distance to the player, which is not
// automatic: at a local maximum of the field - the back of a dead end, a
// pocket behind a pillar, some 3% of the cells a flood from Desert Dungeon's
// player_start fills - every neighbour is closer than the cell the enemy is
// standing in, and taking the least-close of them would walk the enemy toward
// the player and then back out next frame, oscillating on the spot. There is
// nowhere better to stand, so this answers "nothing" and lets the caller keep
// its euclidean back-away, which at least holds a stable direction.
flow_field_retreat_target :: proc(field: ^Flow_Field, world_pos: Vec2) -> (target: Vec2, ok: bool) {
	if !flow_field_is_usable(field) {
		return {}, false
	}

	cell_coord := world_to_cell_coord(world_pos, field.tile_size)
	best, found := flow_field_extreme_neighbour(field, cell_coord, .Farthest)
	if !found {
		return {}, false
	}

	// an enemy standing on an unfilled cell has no distance of its own to
	// improve on, so any valued neighbour is progress
	if here, in_bounds := flow_field_cell(field, cell_coord); in_bounds && here.distance != FLOW_UNREACHED {
		if flow_field_distance(field, best) <= here.distance {
			return {}, false
		}
	}
	return cell_center_to_world(best, field.tile_size), true
}

// which end of the distance ramp a neighbour scan wants: closing on the
// player, or backing away from them
@(private = "file")
Neighbour_Preference :: enum {
	Nearest,
	Farthest,
}

// the lowest- or highest-distance filled cell of the eight around `cell`.
// Eight rather than four in both directions: a filled cell is walkable
// whichever way it lies, and the diagonals are what let a body pushed into the
// envelope find its way back out.
@(private = "file")
flow_field_extreme_neighbour :: proc(
	field: ^Flow_Field,
	cell: Vec2i,
	prefer: Neighbour_Preference,
) -> (
	best_cell: Vec2i,
	ok: bool,
) {
	best: u32
	for dy in i32(-1) ..= 1 {
		for dx in i32(-1) ..= 1 {
			if dx == 0 && dy == 0 {
				continue
			}

			neighbour := cell + {dx, dy}
			found, in_bounds := flow_field_cell(field, neighbour)
			if !in_bounds || found.distance == FLOW_UNREACHED {
				continue
			}

			better := prefer == .Nearest ? found.distance < best : found.distance > best
			if !ok || better {
				best = found.distance
				best_cell = neighbour
				ok = true
			}
		}
	}
	return best_cell, ok
}
