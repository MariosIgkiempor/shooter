package shooter

import "core:testing"

// move_actor takes its Tilemap explicitly, so these drive a throwaway room
// (flow_field_test.odin's fixture_room) and need no ODIN_TEST_THREADS=1
// pinning. What is pinned here is the one thing a caller can read back from
// a move besides the resolved position: whether a wall stopped it - the
// signal a Charger's dash ends on (charger_end_dash).

@(test)
test_move_actor_reports_a_move_a_wall_resolved :: proc(t: ^testing.T) {
	// a floor cell with a wall immediately to its right
	tilemap := fixture_room({"..#"})
	defer delete(tilemap.tiles)

	// feet in the middle of the first floor cell; the collision box is
	// ACTOR_SIZE wide so a 16px step right lands it inside the wall
	actor := Rect{8, 16, 0, 0}
	blocked := move_actor(&actor, &tilemap, {16, 0})

	testing.expect(t, blocked, "a step that a wall resolved should report blocked")
	testing.expectf(t, actor.x < 24, "the wall should have stopped the body short of it, got x = %v", actor.x)
}

@(test)
test_move_actor_reports_open_ground_as_unblocked :: proc(t: ^testing.T) {
	tilemap := fixture_room({"....."})
	defer delete(tilemap.tiles)

	actor := Rect{16, 16, 0, 0}
	blocked := move_actor(&actor, &tilemap, {16, 0})

	testing.expect(t, !blocked, "a step across floor should not report blocked")
	testing.expect_value(t, actor.x, f32(32))
}
