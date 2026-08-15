package shooter

import "core:container/queue"
import "core:math"
import "core:math/linalg"
import "core:slice"
import rl "vendor:raylib"

MAX_ENEMIES :: 24
ENEMY_SIZE: i32 = 12
DEFAULT_SPAWNER_INTERVAL :: 3
ENEMY_MAX_HEALTH :: 50

Enemy :: struct {
	using rect: Rect, // bottom-center "feet" anchor, same convention as Player
	animation:  Animation,
	flip_x:     bool,
	behaviour:  Enemy_Behaviour,
	path:       Path,
	health:     f32,
}

// the union variant is the enemy kind; nil means inert (stands still).
//
// Melee must stay first: Spawner.template is this union and is now saved to
// disk, but core:encoding/json unmarshals a union by trying each variant in
// declaration order and keeping the first one that parses without error.
// Struct fields are optional on decode (missing ones are just left zeroed),
// so a lone `{"speed":40}` would happily "succeed" as either variant -
// putting Melee first is what makes it decode back as a Melee, which is the
// default the editor creates spawners with. A spawner explicitly switched to
// Ranged, saved, and reloaded may decode back as Melee for the same reason.
Enemy_Behaviour :: union {
	Melee,
	Ranged,
}

Melee :: struct {
	speed:           f32,
	attack_damage:   f32,
	attack_range:    f32, // contact distance to land a hit
	attack_cooldown: f32, // seconds between hits
	attack_timer:    f32, // runtime countdown, not editor-set
}

Ranged :: struct {
	speed:            f32,
	min_range:        f32, // retreats if the player is closer than this
	max_range:        f32, // advances if the player is farther than this
	attack_damage:    f32,
	projectile_speed: f32,
	fire_rate:        f32, // shots/sec while in the min..max band
	bullet_lifetime:  f32,
	fire_timer:       f32, // runtime countdown, not editor-set
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
		health    = ENEMY_MAX_HEALTH,
	}

	append(&game.enemies, enemy)
}

update_enemies :: proc(dt: f32) {
	inflated_collision_map := build_inflated_collision_map(&game.tilemap, 1)
	player_pos := Vec2{game.player.x, game.player.y}

	for &enemy in game.enemies {
		delta: Vec2

		switch &b in enemy.behaviour {
		case Melee:
			delta = chase_to(&enemy, inflated_collision_map, player_pos, b.speed, dt)

			dist_to_player := linalg.distance(Vec2{enemy.x, enemy.y}, player_pos)
			b.attack_timer -= dt

			if dist_to_player <= b.attack_range {
				delta = {}
				if b.attack_timer <= 0 {
					damage_player(b.attack_damage)
					b.attack_timer = b.attack_cooldown
				}
			}
		case Ranged:
			dist_to_player := linalg.distance(Vec2{enemy.x, enemy.y}, player_pos)
			b.fire_timer -= dt

			switch {
			case dist_to_player > b.max_range:
				delta = chase_to(&enemy, inflated_collision_map, player_pos, b.speed, dt)
			case dist_to_player < b.min_range:
				delta = linalg.normalize0(Vec2{enemy.x, enemy.y} - player_pos) * b.speed * dt
			case:
				if b.fire_timer <= 0 {
					direction := linalg.normalize0(player_pos - Vec2{enemy.x, enemy.y})
					fire_enemy_bullet(Vec2{enemy.x, enemy.y}, direction, b)
					b.fire_timer = 1.0 / b.fire_rate
				}
			}
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

// computes a fresh BFS path from enemy to goal_world, stores it on enemy.path
// (for the debug draw), and returns this frame's movement delta toward the
// next un-arrived waypoint
chase_to :: proc(enemy: ^Enemy, collision_map: Collision_Map, goal_world: Vec2, speed, dt: f32) -> Vec2 {
	enemy_cell := world_to_cell_coord(Vec2{enemy.x, enemy.y})

	enemy_path, ok := find_path(collision_map, enemy_cell, world_to_cell_coord(goal_world))
	if ok {
		delete(enemy.path)
		enemy.path = enemy_path
	} else {
		enemy.path = {}
	}

	path_index := 0
	ARRIVE_RADIUS: f32 = 4.0
	for path_index < len(enemy.path) &&
	    linalg.distance(cell_center_to_world(enemy.path[path_index]), Vec2{enemy.x, enemy.y}) <
		    ARRIVE_RADIUS {
		path_index += 1
	}

	target: Vec2
	if path_index < len(enemy.path) {
		target = cell_center_to_world(enemy.path[path_index])
	} else {
		target = goal_world
	}

	return linalg.normalize0(target - Vec2{enemy.x, enemy.y}) * speed * dt
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
