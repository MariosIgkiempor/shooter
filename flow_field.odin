package shooter

import "core:math"
import "core:math/linalg"

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
	inflated: bool,      // inside some wall's (2r+1)^2 envelope at `radius`, or inside an obstacle's grown disc
	obstacle: bool,      // inside a Flow_Obstacle's disc this build; always also `inflated`, so flow_can_enter needs no rule of its own
}

// a body the flood routes around rather than through - the Boss's bulk
// (ticket 21). Its centre and its own half-extent in px; the field grows
// the disc by its own inflation radius, exactly as it grows a wall's
// envelope, so the caller need not know what radius the field was built at.
// Stamped as `inflated` rather than `collides`: the cells are not walls
// (move_actor must not stop the Boss on its own body, nor the player), they
// are ground the flood will not step onto from open ground. A body standing
// inside the stamp - the Boss itself, an add it walked over - reads an
// unfilled cell and takes flow_field_step_target's neighbour fallback out.
Flow_Obstacle :: struct {
	centre: Vec2,
	radius: f32,
}

// what a rebuild stamped, remembered so flow_field_ensure can tell whether
// an obstacle has crossed a cell. Stamped about the obstacle's *cell
// centre*, so the cell set is a pure function of (cell, radius) and "moved
// within a cell" is exactly "nothing changed" - the same cell-granular
// rebuild rule the source already has.
Flow_Obstacle_Stamp :: struct {
	cell:   Vec2i,
	radius: f32,
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
	// the obstacles the last rebuild stamped, in the order they were given
	obstacles:     [dynamic]Flow_Obstacle_Stamp,
}

// how far a wall's influence is stamped outward, in cells, so a body with
// width does not have its route threaded through a gap it cannot fit. A
// Tunable, and stored on the field, so dragging it re-floods on the next
// frame against the debug overlay.
FLOW_FIELD_INFLATION_RADIUS: int = 1

// the radius a body of `body_size` px needs so its route is never threaded
// through a gap it cannot fit: the inverse of the envelope the preset test
// holds the roster inside (2 * (r * tile + tile / 2)). The roster's <= 48px
// bodies come out at the shipped FLOW_FIELD_INFLATION_RADIUS; the Boss's
// 72px asks for one more, and gets a field of its own at it (ADR-0025:
// "built lazily for the radii in use"). A degenerate tile size falls back to
// the shipped radius rather than dividing by zero.
flow_field_radius_for_body :: proc(body_size, tile: f32) -> i32 {
	if tile <= 0 {
		return i32(FLOW_FIELD_INFLATION_RADIUS)
	}
	return i32(max(0, math.ceil((body_size / 2 - tile / 2) / tile)))
}

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

// flow_field_index's inverse, for the one direction that has to walk `cells`
// rather than ask about a cell it already has: which coord row-major slot
// `index` holds.
@(private = "file")
flow_field_coord :: proc(field: ^Flow_Field, index: int) -> Vec2i {
	width := int(field.size.x)
	return field.origin + {i32(index % width), i32(index / width)}
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

// the cell-indexed solid set ADR-0025 promised move_actor: whether an
// authored colliding Tile sits on `cell`. Off the extent answers false, and
// that is correct rather than a guess - the extent contains every authored
// tile, so a cell outside it is untiled ground. An unusable field (no tiles,
// or a zero tile_size) has no solid cells either, which is what a scan of an
// empty tile list found.
//
// This reads whatever was last built and does not consult `built`: an
// invalidated field keeps its cells, so answering "not solid" while unbuilt
// would drop every wall for a frame, and answering from the stale cells is
// the previous Map's walls. Neither is fixable here. Keeping the field fresh
// is the caller's job - the frame loop runs flow_field_ensure before anything
// moves (see update_game_state), and a test drives the field it built itself.
flow_field_is_solid :: proc(field: ^Flow_Field, cell: Vec2i) -> bool {
	if !flow_field_is_usable(field) {
		return false
	}
	index, ok := flow_field_index(field, cell)
	return ok && field.cells[index].collides
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
	obstacles: []Flow_Obstacle = {},
) -> (
	rebuilt: bool,
) {
	if !field.built ||
	   field.radius != radius ||
	   field.tile_size != tilemap.tile_size ||
	   field.tile_count != len(tilemap.tiles) {
		flow_field_rebuild(field, tilemap, source_world, radius, obstacles)
		return true
	}

	// a degenerate field has no cells to flood into and no valid tile_size to
	// convert a world position with; it is already built and stays empty
	if tilemap.tile_size.x <= 0 || tilemap.tile_size.y <= 0 {
		return false
	}

	if world_to_cell_coord(source_world, tilemap.tile_size) != field.source ||
	   !flow_obstacles_match(field, obstacles) {
		flow_field_rebuild(field, tilemap, source_world, radius, obstacles)
		return true
	}
	return false
}

// whether `obstacles` would stamp the same cells the last rebuild did: the
// same bodies, each in the same cell at the same radius
@(private = "file")
flow_obstacles_match :: proc(field: ^Flow_Field, obstacles: []Flow_Obstacle) -> bool {
	if len(obstacles) != len(field.obstacles) {
		return false
	}
	for obstacle, i in obstacles {
		stamp := field.obstacles[i]
		if stamp.radius != obstacle.radius || world_to_cell_coord(obstacle.centre, field.tile_size) != stamp.cell {
			return false
		}
	}
	return true
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
	delete(field.obstacles)
	field^ = {}
}

// re-floods unconditionally. Reuses `cells` when the extent's size is
// unchanged, but always clears every cell: skipping the clear leaves the
// previous map's walls and distances behind, which is silent and shows up only
// as enemies refusing to enter a room.
flow_field_rebuild :: proc(field: ^Flow_Field, tilemap: ^Tilemap, source_world: Vec2, radius: i32, obstacles: []Flow_Obstacle = {}) {
	field.tile_size = tilemap.tile_size
	field.radius = radius
	field.tile_count = len(tilemap.tiles)
	field.built = true
	field.max_distance = 0
	field.filled_count = 0
	clear(&field.obstacles)

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

	// an obstacle is a disc about its cell's centre, grown by the field's
	// radius the way a wall's envelope is, so a body steered by this field
	// is kept its own half-width off the obstacle's edge
	for obstacle in obstacles {
		cell := world_to_cell_coord(obstacle.centre, tilemap.tile_size)
		append(&field.obstacles, Flow_Obstacle_Stamp{cell = cell, radius = obstacle.radius})
		centre := cell_center_to_world(cell, tilemap.tile_size)
		reach := obstacle.radius + f32(radius) * tilemap.tile_size.x
		span := i32(math.ceil(reach / tilemap.tile_size.x))
		for dx in -span ..= span {
			for dy in -span ..= span {
				coord := cell + {dx, dy}
				if linalg.distance(cell_center_to_world(coord, tilemap.tile_size), centre) > reach {
					continue
				}
				if index, ok := flow_field_index(field, coord); ok {
					field.cells[index].inflated = true
					field.cells[index].obstacle = true
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

// the field's own units for a world-space distance, so a Swarmer's surround
// radius - authored in pixels, on its Attack Style - can be compared against a
// path distance. One cell of travel costs FLOW_COST_ORTHOGONAL, so a radius of
// two tiles is 20. Only the x tile size is read: a non-square tile would make
// "distance" direction-dependent and the flood's two edge weights meaningless,
// which is a deeper problem than this conversion.
flow_field_cost_for_world_distance :: proc(field: ^Flow_Field, world_distance: f32) -> u32 {
	if !flow_field_is_usable(field) || world_distance <= 0 {
		return 0
	}
	return u32((world_distance / field.tile_size.x) * FLOW_COST_ORTHOGONAL)
}

// how far a distance sits from the contour, in cost units, without underflowing
// u32 - both arguments are unsigned and either may be the larger
@(private = "file")
flow_cost_gap :: proc(a, b: u32) -> u32 {
	return a > b ? a - b : b - a
}

// how wide the contour is: one diagonal step, the largest single move the flood
// makes. Narrower and a body standing between two cells would find no
// neighbour on the ring at all; wider and the "ring" is a band thick enough for
// two Swarmers to orbit inside each other.
FLOW_CONTOUR_BAND :: u32(FLOW_COST_DIAGONAL)

// the world point a body drifting along a fixed path-distance contour should
// head for: the neighbouring cell that both sits on the contour and lies
// furthest around it in the direction `drift_sign` turns.
//
// The tangent is the cell's own inward gradient turned ninety degrees, so the
// drift follows whatever shape the flood made - which is what makes the ring
// wrap geometry instead of cutting through it. Only *filled* neighbours are
// candidates, and a filled cell is walkable by construction, so a wall across
// the contour is simply not among the options: the drift slides along it rather
// than into it.
//
// ok=false where there is nowhere to drift - the source cell (no gradient), an
// unfilled cell, or an arc that dead-ends against geometry in this direction.
// The caller then holds its ground rather than pressing inward.
flow_field_contour_target :: proc(
	field: ^Flow_Field,
	world_pos: Vec2,
	target_cost: u32,
	drift_sign: f32,
) -> (
	target: Vec2,
	ok: bool,
) {
	if !flow_field_is_usable(field) {
		return {}, false
	}

	cell_coord := world_to_cell_coord(world_pos, field.tile_size)
	here, in_bounds := flow_field_cell(field, cell_coord)
	if !in_bounds || here.distance == FLOW_UNREACHED || here.step == .None {
		return {}, false
	}

	offset := FLOW_STEP_OFFSET[here.step]
	inward := linalg.normalize0(Vec2{f32(offset.x), f32(offset.y)})
	turn: f32 = drift_sign < 0 ? -1 : 1
	tangent := Vec2{-inward.y, inward.x} * turn

	best_cell: Vec2i
	best_gap: u32
	best_align: f32
	for dy in i32(-1) ..= 1 {
		for dx in i32(-1) ..= 1 {
			if dx == 0 && dy == 0 {
				continue
			}

			neighbour := cell_coord + {dx, dy}
			found, neighbour_in_bounds := flow_field_cell(field, neighbour)
			if !neighbour_in_bounds || found.distance == FLOW_UNREACHED {
				continue
			}

			gap := flow_cost_gap(found.distance, target_cost)
			if gap > FLOW_CONTOUR_BAND {
				continue
			}

			// the flood's own corner rule: a diagonal whose two flanking cells
			// are not both enterable is a route drawn through the gap where two
			// walls touch. The drift may not take a step the flood itself
			// refuses, or it would squeeze past a corner the field routed
			// around.
			if dx != 0 && dy != 0 {
				if !flow_can_enter(field, cell_coord + {dx, 0}, here) ||
				   !flow_can_enter(field, cell_coord + {0, dy}, here) {
					continue
				}
			}

			// strictly forward around the contour: a step with no tangential
			// component at all is the one the body just came from, and a
			// backward one would reverse the drift every frame it spent
			// against a wall
			align := linalg.dot(linalg.normalize0(Vec2{f32(dx), f32(dy)}), tangent)
			if align <= 0 {
				continue
			}

			// the ring first, the turn second. Alignment alone would take a
			// perfectly tangential neighbour a whole diagonal inside the
			// contour over a slightly angled one sitting on it, and near
			// geometry that walks a Swarmer inward a step at a time until it is
			// a band's width closer than it was asked to stand.
			better := gap < best_gap || (gap == best_gap && align > best_align)
			if !ok || better {
				best_gap = gap
				best_align = align
				best_cell = neighbour
				ok = true
			}
		}
	}

	if !ok {
		return {}, false
	}
	return cell_center_to_world(best_cell, field.tile_size), true
}

// whether the field has any answers to give. nil is accepted because the spawn
// path asks these questions of a body it may have no field for at all - a
// Floater, which flies over the geometry that would strand anything else. An
// unusable field (degenerate Map, or none built yet) and a flood that filled
// nothing (the player is standing inside a wall - see ticket 04) are the other
// two ways to have no opinion, and all three must read as "no opinion" rather
// than "nothing is reachable": a filter that vetoes every cell on the map
// leaves its caller worse off than no filter at all.
@(private = "file")
flow_field_has_answers :: proc(field: ^Flow_Field) -> bool {
	return field != nil && flow_field_is_usable(field) && field.filled_count > 0
}

// whether a body standing at `world_pos` can get to the player. Because the
// flood runs outward from the player, that is the same question as "can the
// player get to it" - which is what ticket 07 tests a spawn candidate against.
// A field with no answers reaches everywhere; see flow_field_has_answers.
//
// Not simply "is this cell filled". The flood only ever *leaves* the inflation
// envelope, so at the shipped radius of 1 a cell merely adjacent to a wall
// carries no distance - 741 of Desert Dungeon's 2239 standable cells, measured
// by ticket 04 - while standing in open ground a body walks out of without
// noticing. Reading those as unreachable would reject a third of the map for
// the very styles this test exists to protect.
//
// So the question asked is the one steering asks: flow_field_step_target walks
// a body on an unfilled cell out by the best-valued of its eight neighbours,
// and a cell with such a neighbour is a cell with somewhere to go. A sealed
// pocket has none - its neighbours are its own cells and the walls around
// them - so criterion 1 is unaffected.
flow_field_reaches :: proc(field: ^Flow_Field, world_pos: Vec2) -> bool {
	if !flow_field_has_answers(field) {
		return true
	}

	cell_coord := world_to_cell_coord(world_pos, field.tile_size)
	here, in_bounds := flow_field_cell(field, cell_coord)
	if !in_bounds || here.collides {
		return false
	}
	if here.distance != FLOW_UNREACHED {
		return true
	}

	_, has_filled_neighbour := flow_field_extreme_neighbour(field, cell_coord, .Nearest)
	return has_filled_neighbour
}

// the filled cell whose centre lies nearest `world_pos` - the answer to "I
// must put a body somewhere the player can actually reach, and I have run out
// of candidates of my own". Linear in the field's cells, which is why it is a
// last resort for a caller whose own retries all failed rather than a
// placement strategy in its own right.
//
// ok=false where the field has no answers - there is genuinely no reachable
// cell to name then, and the caller must fall back to whatever it did before
// the field existed.
flow_field_nearest_reachable :: proc(field: ^Flow_Field, world_pos: Vec2) -> (target: Vec2, ok: bool) {
	if !flow_field_has_answers(field) {
		return {}, false
	}

	best_distance := max(f32)
	for cell, index in field.cells {
		if cell.distance == FLOW_UNREACHED {
			continue
		}

		center := cell_center_to_world(flow_field_coord(field, index), field.tile_size)
		// squared, since only the ordering is used
		offset := center - world_pos
		distance := offset.x * offset.x + offset.y * offset.y
		if distance < best_distance {
			best_distance = distance
			target = center
			ok = true
		}
	}
	return target, ok
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
