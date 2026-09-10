package shooter

import "core:testing"

// Same conventions as weapon_test.odin: no game loop, no raylib window, drive
// update_bullets directly with controlled dt steps, and assert on observable
// side effects (a body's health dropped, a Bullet left game.bullets) rather
// than on how a bullet is drawn. These mutate game.bullets/game.enemies via
// the same globals every other hit source does, so run this suite with
// `odin test . -define:ODIN_TEST_THREADS=1`.

// how far a bullet moves per frame at the speeds the catalog authors: enough
// that a shot spends several frames inside a 24px body, which is the whole
// reason a pierce needs a memory rather than a refractory timer
TEST_BULLET_SPEED :: f32(400)
TEST_FRAME :: f32(1) / 60

// resets every global a bullet's hit path writes to. apply_hit_to_enemy
// sparks, spawns a damage number and may drop a pickup, so a test that kills
// something touches four arrays, not one.
test_reset_bullet_world :: proc() {
	clear(&game.bullets)
	clear(&game.enemies)
	clear(&game.particles)
	clear(&game.damage_numbers)
	clear(&game.pickups)
}

// a line of bodies along TEST_AIM, `spacing` apart - the arrangement a
// piercing shot exists for. Spacing stays above the 24px body so the boxes
// never overlap and "how many did it pass through" has one answer.
test_body_line :: proc(count: int, first_x, spacing, health: f32) {
	for i in 0 ..< count {
		append(&game.enemies, test_enemy_centered_at(Vec2{first_x + f32(i) * spacing, 0}, health))
	}
}

// a single shot from TEST_ORIGIN along TEST_AIM, through the same spawn path
// every weapon uses so it carries a real shot identity. Spawning a bare
// Bullet{} instead would leave id 0 - the "no shot has hit me" value every
// fresh body already carries - and the shot would pass through the world
// touching nothing.
test_fire_one_shot :: proc(pierces: int, damage: f32 = 25) {
	spawn_bullet(
		Bullet {
			position = TEST_ORIGIN,
			velocity = TEST_AIM * TEST_BULLET_SPEED,
			damage = damage,
			lifetime = 2,
			pierces_left = pierces,
		},
	)
}

test_advance_bullets :: proc(frames := 60) {
	for _ in 0 ..< frames {
		update_bullets(TEST_FRAME)
	}
}

@(test)
test_a_shot_with_no_pierce_still_stops_at_the_first_body :: proc(t: ^testing.T) {
	// today's behaviour, pinned before pierce exists so it stays true after:
	// pierce_count defaults to 0 and 0 means "stop where you land"
	test_reset_bullet_world()
	defer test_reset_bullet_world()

	test_body_line(2, 40, 40, 500)
	test_fire_one_shot(0)
	test_advance_bullets()

	testing.expect_value(t, game.enemies[0].health, 500 - 25)
	testing.expectf(
		t,
		game.enemies[1].health == 500,
		"a shot with no pierce should never reach the second body, but it took %v damage",
		500 - game.enemies[1].health,
	)
	testing.expect(t, len(game.bullets) == 0, "a shot that landed should be spent")
}

@(test)
test_a_piercing_shot_damages_a_body_at_most_once :: proc(t: ^testing.T) {
	// the reason a pierce needs a memory at all: at 400 speed a shot covers
	// ~6.7px a frame against a 24px body, so it overlaps for three or four
	// frames, and without an identity to check it would hit on every one
	test_reset_bullet_world()
	defer test_reset_bullet_world()

	test_body_line(1, 40, 40, 500)
	test_fire_one_shot(3)
	test_advance_bullets()

	testing.expectf(
		t,
		game.enemies[0].health == 500 - 25,
		"a piercing shot should damage a body once, not once per frame it overlaps it - took %v",
		500 - game.enemies[0].health,
	)
}

@(test)
test_a_piercing_shot_passes_through_as_many_bodies_as_it_is_authored_for :: proc(t: ^testing.T) {
	test_reset_bullet_world()
	defer test_reset_bullet_world()

	test_body_line(4, 40, 40, 500)
	test_fire_one_shot(3) // the first body plus three more
	test_advance_bullets()

	for enemy, i in game.enemies {
		testing.expectf(t, enemy.health == 500 - 25, "body %v should have been passed through, took %v", i, 500 - enemy.health)
	}
}

@(test)
test_a_piercing_shot_dies_on_the_body_past_its_last_pierce :: proc(t: ^testing.T) {
	test_reset_bullet_world()
	defer test_reset_bullet_world()

	test_body_line(5, 40, 40, 500)
	test_fire_one_shot(3)
	test_advance_bullets()

	for i in 0 ..< 4 {
		testing.expectf(t, game.enemies[i].health == 500 - 25, "body %v is within the shot's pierce budget", i)
	}
	testing.expectf(
		t,
		game.enemies[4].health == 500,
		"the fifth body is one past the budget and should be untouched, took %v",
		500 - game.enemies[4].health,
	)
	testing.expect(t, len(game.bullets) == 0, "a shot spent on its last body should be gone")
}

@(test)
test_a_body_swapped_into_a_dead_ones_slot_is_not_skipped_by_a_piercing_shot :: proc(t: ^testing.T) {
	// why a pierce remembers shot identity rather than enemy indices:
	// apply_hit_to_enemy removes with unordered_remove, so killing the front
	// body swaps the back body into the front body's slot. An index-keyed
	// memory would then read as "already hit" and the shot would fly through
	// the survivor. Certain at swarm density, invisible at one body.
	test_reset_bullet_world()
	defer test_reset_bullet_world()

	append(&game.enemies, test_enemy_centered_at(Vec2{40, 0}, 25)) // dies to one hit
	append(&game.enemies, test_enemy_centered_at(Vec2{120, 0}, 500))
	test_fire_one_shot(3)
	test_advance_bullets()

	testing.expect(t, len(game.enemies) == 1, "sanity check: the front body should have died and been removed")
	testing.expectf(
		t,
		game.enemies[0].health == 500 - 25,
		"the survivor swapped into the dead body's slot should still be hit, took %v",
		500 - game.enemies[0].health,
	)
}

@(test)
test_every_pellet_of_a_volley_carries_its_own_shot_identity :: proc(t: ^testing.T) {
	// each pellet is its own shot, so a future piercing shotgun works with no
	// further change - and one shared identity would mean the first pellet to
	// touch a body stamped it and the other seven skipped it
	test_reset_bullet_world()
	defer test_reset_bullet_world()

	weapon := weapon_create(.Shotgun)
	gun := weapon.variant.(Gun)
	fire_pellets(weapon, gun, TEST_ORIGIN, TEST_AIM)

	testing.expect(t, len(game.bullets) == gun.pellet_count, "sanity check: one Bullet per pellet")
	for pellet, i in game.bullets {
		testing.expectf(t, pellet.id != 0, "pellet %v carries no shot identity", i)
		for other, j in game.bullets {
			if i == j do continue
			testing.expectf(t, pellet.id != other.id, "pellets %v and %v share one shot identity", i, j)
		}
	}
}

@(test)
test_a_shot_identity_is_never_reused_across_two_shots :: proc(t: ^testing.T) {
	test_reset_bullet_world()
	defer test_reset_bullet_world()

	test_fire_one_shot(0)
	first := game.bullets[0].id
	test_fire_one_shot(0)

	testing.expect(t, game.bullets[1].id != first, "two shots should never share an identity - the counter is monotonic")
}

@(test)
test_a_fireball_claims_a_shot_identity_of_its_own :: proc(t: ^testing.T) {
	// a Fireball never pierces, but an unstamped id 0 matches every fresh
	// body's last_hit_bullet_id, so it would fly through the world without
	// ever finding something to explode on
	test_reset_bullet_world()
	defer test_reset_bullet_world()

	weapon := weapon_create(.Fire_Wand)
	magic := weapon.variant.(Magic)
	cast_fireball(magic, weapon.damage, TEST_ORIGIN, TEST_AIM)

	testing.expect(t, game.bullets[0].id != 0, "a Fireball needs a shot identity like any other shot")
}

@(test)
test_a_fireball_still_explodes_on_the_first_body_it_touches :: proc(t: ^testing.T) {
	// pierce and explode never combine: the AoE a Fireball becomes *is* its
	// effect, so it ends where it lands whatever is behind that
	test_reset_bullet_world()
	defer test_reset_bullet_world()

	append(&game.enemies, test_enemy_centered_at(Vec2{40, 0}, 500))
	append(&game.enemies, test_enemy_centered_at(Vec2{200, 0}, 500)) // far outside the blast
	spawn_bullet(
		Bullet {
			position = TEST_ORIGIN,
			velocity = TEST_AIM * TEST_BULLET_SPEED,
			damage = 35,
			lifetime = 2,
			explosion_radius = 24,
			pierces_left = 3, // even authored one, an explosion ends the shot
		},
	)
	test_advance_bullets()

	testing.expect(t, game.enemies[0].health == 500 - 35, "the body it landed on should take the blast")
	testing.expectf(
		t,
		game.enemies[1].health == 500,
		"a Fireball ends where it explodes and should never reach past it - took %v",
		500 - game.enemies[1].health,
	)
	testing.expect(t, len(game.bullets) == 0, "a Fireball that exploded should be spent")
}

@(test)
test_the_rifle_is_the_only_weapon_the_catalog_authors_a_pierce_for :: proc(t: ^testing.T) {
	// pierce_count defaults to 0, which is exactly the behaviour every gun had
	// before it existed - so this pins that adding the field changed nothing
	// for the seven weapons that are not Ranged's top tier
	for kind in Weapon_Kind {
		gun, is_gun := weapon_presets[kind].variant.(Gun)
		if !is_gun {
			continue
		}
		expected := kind == .Rifle
		testing.expectf(
			t,
			(gun.pierce_count > 0) == expected,
			"%v authors pierce_count %v - Ranged's crowd answer is the Rifle's line and nothing else's",
			kind,
			gun.pierce_count,
		)
	}
}

@(test)
test_the_rifle_passes_its_shot_through_a_line_of_bodies :: proc(t: ^testing.T) {
	// the whole reason the Rifle exists: every other Gun bullet stops on the
	// first body it touches, which left Ranged with no answer to a crowd
	test_reset_bullet_world()
	defer test_reset_bullet_world()

	weapon := weapon_create(.Rifle)
	gun := weapon.variant.(Gun)
	test_body_line(gun.pierce_count + 1, 40, 40, 500)
	fire_pellets(weapon, gun, TEST_ORIGIN, TEST_AIM)
	test_advance_bullets()

	for enemy, i in game.enemies {
		testing.expectf(t, enemy.health == 500 - weapon.damage, "body %v should be on the Rifle's line, took %v", i, 500 - enemy.health)
	}
}

// puts one collidable tile at `coords`, on a tilemap sized so the caller can
// place it in px. Restores nothing - callers clear game.current_map.tilemap.
test_wall_at :: proc(coords: Vec2i, tile_size: Vec2 = {32, 32}) {
	game.current_map.tilemap.tile_size = tile_size
	append(&game.current_map.tilemap.tiles, Tile{world_coords = coords, collides = true})
}

@(test)
test_a_bolt_is_stopped_by_a_wall_in_its_last_partial_step :: proc(t: ^testing.T) {
	// segment_first_wall_hit marches in fixed steps, and a segment is almost
	// never a whole number of them. The half-tile stride covers any wall the
	// line passes *through*, but not one it merely ends *inside*: here the last
	// sample lands 11px short of the tile's edge and the endpoint is 1px past
	// it, so without testing the far end separately the bolt draws into a wall.
	// A Range stack moves the bolt's length off every step multiple, so this is
	// reachable the moment a player buys one.
	test_reset_bullet_world()
	clear(&game.current_map.tilemap.tiles)
	defer {
		test_reset_bullet_world()
		clear(&game.current_map.tilemap.tiles)
	}

	// tile 3 spans x in [96, 128)
	test_wall_at({3, 0}, {32, 32})
	from := Vec2{5, 16} // offset so the 16px stride never lands on the tile edge
	to := Vec2{97, 16} // 92px of line: strides reach x=85, and 97 is inside the wall

	point, blocked := segment_first_wall_hit(from, to)

	testing.expect(t, blocked, "a segment ending inside a wall should be stopped by it")
	testing.expect_value(t, point, to)
}

@(test)
test_a_bolt_reports_no_wall_on_a_clear_line :: proc(t: ^testing.T) {
	test_reset_bullet_world()
	clear(&game.current_map.tilemap.tiles)
	defer {
		test_reset_bullet_world()
		clear(&game.current_map.tilemap.tiles)
	}

	test_wall_at({8, 0})
	to := Vec2{100, 16}
	point, blocked := segment_first_wall_hit(Vec2{0, 16}, to)

	testing.expect(t, !blocked, "a segment that reaches no wall should report none")
	testing.expect_value(t, point, to)
}
