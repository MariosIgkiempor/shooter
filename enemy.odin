package shooter

import "core:container/queue"
import "core:math"
import "core:math/linalg"
import "core:slice"
import rl "vendor:raylib"

MAX_ENEMIES :: 24
ENEMY_SIZE: i32 = 12
DEFAULT_SPAWNER_INTERVAL :: 3

Enemy :: struct {
	using rect: Rect, // bottom-center "feet" anchor, same convention as Player
	animation:  Animation,
	flip_x:     bool,
	behaviour:  Enemy_Behaviour,
	path:       Path,
}

// the union variant is the enemy kind; nil means inert (stands still).
//
// Chaser must stay first: Spawner.template is this union and is now saved to
// disk, but core:encoding/json unmarshals a union by trying each variant in
// declaration order and keeping the first one that parses without error.
// Struct fields are optional on decode (missing ones are just left zeroed),
// so a lone `{"speed":40}` would happily "succeed" as any of these variants
// - putting Chaser first is what makes it decode back as a Chaser, which is
// the only variant the editor currently creates spawners for.
Enemy_Behaviour :: union {
	Chaser,
	Patrol,
	Sine_Flyer,
}

Patrol :: struct {
	// offsets from the spawner in a template, fixed up to world-space at spawn
	from, to:   Vec2,
	speed:      f32,
	heading_to: bool,
}

Chaser :: struct {
	speed: f32,
}

Sine_Flyer :: struct {
	origin:    Vec2,
	speed:     f32, // horizontal drift
	amplitude: f32,
	frequency: f32,
	phase:     f32,
}

Spawner :: struct {
	position:  Vec2,
	interval:  f32,
	timer:     f32,
	animation: Animation_Name,
	template:  Enemy_Behaviour, // copied by value into each spawned enemy
}

// enemies are transient (`json:"-"`), so they are empty after every load;
// this must run after load_game so they start clean under whatever spawners
// were loaded. Spawners themselves are level data and persist through
// save/load, so they're left untouched here.
reset_enemies :: proc() {
	clear(&game.enemies)
}

update_spawners :: proc(dt: f32) {
	for &spawner in game.spawners {
		spawner.timer -= dt
		if spawner.timer > 0 || len(game.enemies) >= MAX_ENEMIES {
			continue
		}

		spawner.timer = spawner.interval
		spawn_enemy(spawner)
	}
}

spawn_enemy :: proc(spawner: Spawner) {
	enemy := Enemy {
		rect      = {spawner.position.x, spawner.position.y, 0, 0},
		animation = animation_create(spawner.animation),
		behaviour = spawner.template,
	}

	// fix up template state that is relative to the spawner's position
	switch &b in enemy.behaviour {
	case Patrol:
		b.from += spawner.position
		b.to += spawner.position
	case Sine_Flyer:
		b.origin = spawner.position
	case Chaser:
	case:
	}

	append(&game.enemies, enemy)
}

update_enemies :: proc(dt: f32) {
	inflated_collision_map := build_inflated_collision_map(&game.tilemap, 1)
	for &enemy in game.enemies {
		delta: Vec2

		switch &b in enemy.behaviour {
		case Patrol:
			target := b.heading_to ? b.to : b.from
			to_target := target - Vec2{enemy.x, enemy.y}
			if linalg.length(to_target) < 1 {
				b.heading_to = !b.heading_to
			}
			delta = linalg.normalize0(to_target) * b.speed * dt
		case Chaser:
			enemy_cell := world_to_cell_coord(Vec2{enemy.x, enemy.y})

			enemy_path, ok := find_path(
				inflated_collision_map,
				enemy_cell,
				world_to_cell_coord(Vec2{game.player.x, game.player.y}),
			)
			if ok {
				delete(enemy.path)
				enemy.path = enemy_path
			} else {
				enemy.path = {}
			}

			path_index := 0
			ARRIVE_RADIUS: f32 = 4.0
			for path_index < len(enemy.path) &&
			    linalg.distance(
				    cell_center_to_world(enemy.path[path_index]),
				    Vec2{enemy.x, enemy.y},
			    ) <
				    ARRIVE_RADIUS {
				path_index += 1
			}

			target: Vec2
			if path_index < len(enemy.path) {
				target = cell_center_to_world(enemy.path[path_index])
			} else {
				target = Vec2{game.player.x, game.player.y}
			}

			to_target := target - Vec2{enemy.x, enemy.y}
			delta = linalg.normalize0(to_target) * b.speed * dt
		case Sine_Flyer:
			b.phase += b.frequency * dt
			b.origin.x += b.speed * dt
			target := b.origin + Vec2{0, math.sin(b.phase) * b.amplitude}
			delta = target - Vec2{enemy.x, enemy.y}
		case:
		// nil: inert
		}

		if delta.x != 0 || delta.y != 0 {
			animation_update(&enemy.animation, dt)
			enemy.flip_x = delta.x < 0
		}

		move_actor(&enemy.rect, enemy.animation, &game.tilemap, delta)
	}
}

world_to_cell_coord :: proc(world_pos: Vec2) -> Vec2i {
	return {
		i32(math.floor(world_pos.x / game.tilemap.tile_size.x)),
		i32(math.floor(world_pos.y / game.tilemap.tile_size.y)),
	}
}

cell_center_to_world :: proc(cell: Vec2i) -> Vec2 {
	return {
		(f32(cell.x) + 0.5) * game.tilemap.tile_size.x,
		(f32(cell.y) + 0.5) * game.tilemap.tile_size.y,
	}
}

Collision_Map :: map[Vec2i]bool

build_inflated_collision_map :: proc(tilemap: ^Tilemap, radius: i32) -> Collision_Map {
	result: Collision_Map
	for tile in tilemap.tiles {
		if !tile.collides do continue

		for dx in -radius ..= radius {
			for dy in -radius ..= radius {
				result[{tile.world_coords.x + dx, tile.world_coords.y + dy}] = true
			}
		}
	}
	return result
}

Path :: [dynamic]Vec2i
MAX_SEARCH_NODES :: 1024
find_path :: proc(collision_map: Collision_Map, start, goal: Vec2i) -> (path: Path, ok: bool) {
	frontier: queue.Queue(Vec2i)
	defer queue.destroy(&frontier)
	queue.init(&frontier)
	queue.push(&frontier, start)

	came_from := map[Vec2i]Vec2i{}
	defer delete(came_from)
	came_from[start] = start

	for queue.len(frontier) != 0 && len(came_from) < MAX_SEARCH_NODES {
		current := queue.pop_front(&frontier)
		if current == goal do break

		for neighbour in get_neighbours(current) {
			if neighbour in came_from do continue
			if does_cell_collide(collision_map, neighbour, start, goal) do continue

			came_from[neighbour] = current
			queue.push(&frontier, neighbour)
		}
	}

	if !(goal in came_from) do return {}, false

	node := goal
	for node != start {
		append(&path, node)
		node = came_from[node]
	}

	slice.reverse(path[:])
	return path, true

	get_neighbours :: proc(cell: Vec2i) -> [4]Vec2i {
		return {
			{cell.x - 1, cell.y},
			{cell.x + 1, cell.y},
			{cell.x, cell.y - 1},
			{cell.x, cell.y + 1},
		}
	}

	does_cell_collide :: proc(collision_map: Collision_Map, cell, start, goal: Vec2i) -> bool {
		if cell == start || cell == goal do return false // endpoints always allowed
		return collision_map[cell]
	}
}
