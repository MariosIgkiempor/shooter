package shooter

import "core:math/linalg"
import "core:testing"

// Separation (content-expansion-build ticket 07) never reads `game` -
// build_separation_grid and compute_separation_direction both take the enemy
// slice explicitly - so this file stays on throwaway crowds and needs no
// ODIN_TEST_THREADS=1 pinning, like flow_field_test.odin and
// enemy_spawn_test.odin. Keep it that way.
//
// Every body here is Grounded, whose Separation radius (40) is the same as
// SEPARATION_GRID_CELL_SIZE, so a fixture placed inside one 40px cell is a
// fixture where the bucket sweep finds everything and the *budget* is the only
// thing bounding what gets read.

@(private = "file")
grounded_crowd :: proc(positions: []Vec2) -> [dynamic]Enemy {
	crowd: [dynamic]Enemy
	for position in positions {
		append(&crowd, Enemy{rect = {position.x, position.y, 0, 0}, movement = Grounded{speed = 60}})
	}
	return crowd
}

@(private = "file")
push_for :: proc(crowd: []Enemy, index: int) -> Vec2 {
	grid := build_separation_grid(crowd)
	return compute_separation_direction(crowd, index, grid)
}

@(test)
test_separation_points_away_from_a_close_neighbour :: proc(t: ^testing.T) {
	crowd := grounded_crowd({{20, 20}, {30, 20}})
	defer delete(crowd)

	push := push_for(crowd[:], 0)

	testing.expectf(t, push.x < -0.9, "expected a push west away from the neighbour, got %v", push)
	testing.expectf(t, abs(push.y) < 0.1, "expected no north/south component, got %v", push)
}

@(test)
test_separation_ignores_a_neighbour_beyond_the_radius :: proc(t: ^testing.T) {
	// 45px apart, past Grounded's radius of 40, but still inside the 3x3
	// bucket neighbourhood - so this is the radius test doing the work and
	// not the grid's
	crowd := grounded_crowd({{20, 20}, {65, 20}})
	defer delete(crowd)

	testing.expectf(t, push_for(crowd[:], 0) == Vec2{}, "a body past the radius should exert no push")
}

@(test)
test_separation_ignores_a_neighbour_of_another_movement_style :: proc(t: ^testing.T) {
	crowd := grounded_crowd({{20, 20}})
	defer delete(crowd)
	append(&crowd, Enemy{rect = {30, 20, 0, 0}, movement = Floater{speed = 60}})

	testing.expectf(
		t,
		push_for(crowd[:], 0) == Vec2{},
		"Separation only pushes against the same Movement Style",
	)
}

@(test)
test_separation_reads_no_more_than_its_neighbour_budget :: proc(t: ^testing.T) {
	// Eight near bodies east of the reader, then a hundred more to its west,
	// each individually weaker but overwhelming in bulk. A scan that reads the
	// whole bucket is pushed east by the hundred; one that stops at
	// SEPARATION_MAX_NEIGHBOURS never sees them and is pushed west by the
	// eight. The sign of the answer is the bound.
	positions: [dynamic]Vec2
	defer delete(positions)
	append(&positions, Vec2{20, 20}) // the reader, index 0
	for _ in 0 ..< SEPARATION_MAX_NEIGHBOURS {
		append(&positions, Vec2{25, 20}) // 5px east: weight (40-5)/40
	}
	for _ in 0 ..< 100 {
		append(&positions, Vec2{2, 20}) // 18px west: weight (40-18)/40, but a hundred of them
	}

	crowd := grounded_crowd(positions[:])
	defer delete(crowd)

	push := push_for(crowd[:], 0)

	testing.expectf(
		t,
		push.x < 0,
		"a bounded sample reads only the eight nearest-in-bucket bodies and is pushed west; got %v, which is the whole bucket summed",
		push,
	)
}

@(test)
test_separation_gives_two_bodies_in_one_place_different_neighbours :: proc(t: ^testing.T) {
	// Both readers stand at exactly the same point in a bucket far larger than
	// the budget. If every body started reading its bucket at the same place
	// they would be handed the same eight neighbours and shoved the same way,
	// which is the systematic sample the rotation exists to avoid - one clique
	// pushed against by the whole cell while the rest of the crowd is
	// invisible to it.
	positions: [dynamic]Vec2
	defer delete(positions)
	append(&positions, Vec2{20, 20}) // reader A, index 0
	for _ in 0 ..< 19 {
		append(&positions, Vec2{30, 20}) // indices 1..19, east
	}
	append(&positions, Vec2{20, 20}) // reader B, index 20, on top of A
	for _ in 0 ..< 19 {
		append(&positions, Vec2{10, 20}) // indices 21..39, west
	}

	crowd := grounded_crowd(positions[:])
	defer delete(crowd)

	a := push_for(crowd[:], 0)
	b := push_for(crowd[:], 20)

	testing.expectf(t, a.x < 0, "reader A reads the bodies after it - the east group - and is pushed west, got %v", a)
	testing.expectf(t, b.x > 0, "reader B reads the bodies after it - the west group - and is pushed east, got %v", b)
}

@(test)
test_separation_spends_its_budget_on_its_own_cell_first :: proc(t: ^testing.T) {
	// Eight bodies almost touching the reader in its own cell, and eight more
	// out at the far corner of the radius in the cell up and to the left. Both
	// groups are inside the sweep, and the budget only stretches to one of
	// them: which one it goes to is the sweep's order. Reading the ring before
	// the centre - which a plain dx/dy loop from -1 does - spends the whole
	// budget on the distant group and pushes the reader south-east, into the
	// bodies it is standing on top of.
	positions: [dynamic]Vec2
	defer delete(positions)
	append(&positions, Vec2{20, 20}) // the reader, index 0, cell {0,0}
	for _ in 0 ..< SEPARATION_MAX_NEIGHBOURS {
		append(&positions, Vec2{25, 20}) // 5px east, same cell
	}
	for _ in 0 ..< SEPARATION_MAX_NEIGHBOURS {
		append(&positions, Vec2{-5, -5}) // 35px north-west, cell {-1,-1}
	}

	crowd := grounded_crowd(positions[:])
	defer delete(crowd)

	push := push_for(crowd[:], 0)

	testing.expectf(
		t,
		push.x < 0,
		"the budget should go to the reader's own cell, pushing it west off the bodies 5px away; got %v",
		push,
	)
}

@(test)
test_separation_spreads_a_swarm_density_crowd :: proc(t: ^testing.T) {
	// Ticket 07's third criterion: the bound is only worth having if crowding
	// still works at the density it was introduced for. Three hundred bodies
	// in a 180px square is past anything the roster produces - ADR-0025 sizes
	// rung 4 at 150-250 concurrent - and puts every body's nearest neighbour
	// about 5px away, well inside Grounded's Separation radius of 40.
	COUNT :: 300
	BLOB :: f32(180) // px on a side

	// deterministic disorder rather than a lattice. A grid is the
	// spacing-maximising arrangement for its density, so *any* movement
	// lowers its mean nearest-neighbour distance and the measurement would
	// read a crowd merely being disordered as a crowd being crushed.
	seed: u32 = 0x9e3779b9
	next :: proc(seed: ^u32) -> f32 {
		seed^ = seed^ * 1664525 + 1013904223
		return f32(seed^ >> 8) / f32(1 << 24)
	}

	positions: [dynamic]Vec2
	defer delete(positions)
	for _ in 0 ..< COUNT {
		append(&positions, Vec2{next(&seed) * BLOB, next(&seed) * BLOB})
	}

	crowd := grounded_crowd(positions[:])
	defer delete(crowd)

	packing_before := mean_nearest_neighbour_distance(crowd[:])

	// a second of movement at 60fps, at the fixture's Grounded speed. Pushes
	// are computed for every body before any of them moves, so the answer does
	// not depend on the order the crowd is walked in.
	dt :: f32(1.0 / 60.0)
	for _ in 0 ..< 60 {
		grid := build_separation_grid(crowd[:])
		deltas: [COUNT]Vec2
		for i in 0 ..< COUNT {
			deltas[i] = compute_separation_direction(crowd[:], i, grid) * 60 * dt
		}
		for i in 0 ..< COUNT {
			crowd[i].x += deltas[i].x
			crowd[i].y += deltas[i].y
		}
	}

	packing_after := mean_nearest_neighbour_distance(crowd[:])

	// measured at 5.6px -> 8.1px with the shipped cap of eight, and 14.6px
	// with no cap at all. The threshold is the criterion - bodies visibly
	// further apart than they started - not the measurement.
	testing.expectf(
		t,
		packing_after > packing_before * 1.3,
		"a packed crowd should still be pushed apart at swarm density; mean nearest-neighbour distance went %v -> %v",
		packing_before,
		packing_after,
	)
}

@(private = "file")
mean_nearest_neighbour_distance :: proc(crowd: []Enemy) -> f32 {
	total: f32
	for enemy, i in crowd {
		nearest := max(f32)
		for other, j in crowd {
			if i == j {
				continue
			}
			nearest = min(nearest, linalg.distance(Vec2{enemy.x, enemy.y}, Vec2{other.x, other.y}))
		}
		total += nearest
	}
	return total / f32(len(crowd))
}
