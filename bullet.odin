package shooter

import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

BULLET_RADIUS: f32 = 2.0
BULLET_TRAIL_COLOR :: rl.Color{255, 241, 150, 200} // gun pellets
FIREBALL_TRAIL_COLOR :: rl.Color{255, 140, 30, 220} // Fire_Wand's explosion_radius > 0 bullets

// bullet shape dimensions (art-revamp ticket 03): plain bullets are a thin
// streak, Fireball bullets get a thicker "comet" so "this one explodes" reads
// at a glance rather than only on close color inspection
BULLET_STREAK_LENGTH: f32 = 10.0
BULLET_STREAK_WIDTH: f32 = 4.0 // was BULLET_RADIUS * 2; independent now that radius is a Tunable
BULLET_COMET_LENGTH: f32 = 14.0
BULLET_COMET_WIDTH: f32 = 6.4 // was BULLET_RADIUS * 3.2; see BULLET_STREAK_WIDTH

Bullet :: struct {
	position:         Vec2,
	velocity:         Vec2, // direction * speed, computed once at spawn
	damage:           f32,
	lifetime:         f32, // seconds remaining; despawns at <= 0
	// 0 for a normal single-target bullet; >0 makes it explode into an AoE
	// on hit instead (fireball - ticket 11), via explode_bullet below
	explosion_radius: f32,
}

reset_bullets :: proc() {
	clear(&game.bullets)
}

// spawns gun.pellet_count bullets, fanned across gun.spread_angle degrees
// around aim_dir (a single bullet straight down aim_dir when pellet_count is
// 1, e.g. pistol/SMG). damage comes from the weapon header since it applies
// generically across all weapon types, not just Gun.
fire_pellets :: proc(weapon: Weapon, gun: Gun, muzzle, aim_dir: Vec2) {
	pellets := max(gun.pellet_count, 1)
	base_angle := math.atan2(aim_dir.y, aim_dir.x)

	for i in 0 ..< pellets {
		angle := base_angle

		if pellets > 1 {
			t := f32(i) / f32(pellets - 1) - 0.5 // -0.5 .. 0.5
			angle += math.to_radians(gun.spread_angle) * t
		}

		direction := Vec2{math.cos(angle), math.sin(angle)}

		append(
			&game.bullets,
			Bullet {
				position = muzzle,
				velocity = direction * gun.projectile_speed,
				damage = weapon.damage,
				lifetime = gun.bullet_lifetime,
			},
		)
	}
}

// spawns a single explosive Bullet along aim_dir - reuses the Bullet
// movement/collision/lifetime pipeline as-is (Gun already exercises this
// same shape); update_bullets branches on explosion_radius > 0 to do an AoE
// sweep instead of a single-target hit. Reaching max lifetime without a hit
// despawns it silently below, same as any other bullet - a miss fizzles
// with no explosion (ticket 11).
cast_fireball :: proc(magic: Magic, damage: f32, muzzle, aim_dir: Vec2) {
	append(
		&game.bullets,
		Bullet {
			position = muzzle,
			velocity = aim_dir * magic.projectile_speed,
			damage = damage,
			lifetime = magic.bullet_lifetime,
			explosion_radius = magic.explosion_radius,
		},
	)
}

// true if position (a bullet's center) overlaps any collidable tile -
// shared by player and enemy bullets to stop them at walls the same way
// move_actor stops the player/enemies
bullet_hits_wall :: proc(position: Vec2) -> bool {
	for tile in game.current_map.tilemap.tiles {
		if !tile.collides {
			continue
		}

		if rl.CheckCollisionCircleRec(position, BULLET_RADIUS, tile_world_rect(tile.world_coords, game.current_map.tilemap.tile_size)) {
			return true
		}
	}

	return false
}

update_bullets :: proc(dt: f32) {
	#reverse for &bullet, i in game.bullets {
		bullet.position += bullet.velocity * dt
		bullet.lifetime -= dt

		if bullet.lifetime <= 0 {
			unordered_remove(&game.bullets, i)
			continue
		}

		trail_color := bullet.explosion_radius > 0 ? FIREBALL_TRAIL_COLOR : BULLET_TRAIL_COLOR
		spawn_bullet_trail_particle(bullet.position, trail_color)

		hit := false

		#reverse for enemy, j in game.enemies {
			enemy_box := actor_collision_rect(enemy.rect)
			if !rl.CheckCollisionCircleRec(bullet.position, BULLET_RADIUS, enemy_box) {
				continue
			}

			if bullet.explosion_radius > 0 {
				explode_bullet(bullet)
			} else {
				apply_hit_to_enemy(j, bullet.damage, bullet.position)
			}

			hit = true
			break
		}

		// wall check comes after the enemy check above so a bullet touching
		// both a wall and a wall-adjacent enemy at once still registers the
		// hit (also lets bullets still reach a Floater that has drifted into
		// a wall, since Floater ignores tilemap collision - see enemy.odin)
		if !hit && bullet_hits_wall(bullet.position) {
			if bullet.explosion_radius > 0 {
				explode_bullet(bullet)
			}
			hit = true
		}

		if hit {
			unordered_remove(&game.bullets, i)
		}
	}
}

// damages every enemy within explosion_radius of the bullet's impact point,
// not just the one it directly collided with (fireball AoE - ticket 11)
explode_bullet :: proc(bullet: Bullet) {
	#reverse for enemy, i in game.enemies {
		if linalg.length(Vec2{enemy.x, enemy.y} - bullet.position) > bullet.explosion_radius {
			continue
		}
		apply_hit_to_enemy(i, bullet.damage, Vec2{enemy.x, enemy.y})
	}
}

// applies damage to game.enemies[index] at hit_position, spawning a hit
// spark and, on death, tallying the kill (the per-Enemy_Kind
// input, tallied at Run end - see account_progression.odin) + a pickup drop
// + removal - shared by bullet collision above and melee's arc/cone
// hit-check (weapon.odin's try_swing_melee), so death handling is never
// duplicated between weapon types. God Mode (debug.odin) 1-shot kills: the
// applied damage is bumped up to exactly the enemy's remaining health,
// regardless of the weapon's actual damage, so even a single Flamethrower
// tick or Pistol shot kills outright.
apply_hit_to_enemy :: proc(index: int, damage: f32, hit_position: Vec2) {
	enemy := &game.enemies[index]

	enemy.health -= game.debug.god_mode ? enemy.health : damage
	spawn_hit_spark(hit_position)
	spawn_damage_number(hit_position, damage, rl.WHITE)

	if enemy.health <= 0 {
		game.player.kills[enemy.kind] += 1
		maybe_spawn_pickup(Vec2{enemy.x, enemy.y}, enemy.kind)
		delete(enemy.path)
		unordered_remove(&game.enemies, index)
	}
}

Enemy_Bullet :: struct {
	position: Vec2,
	velocity: Vec2,
	damage:   f32,
	lifetime: f32, // seconds remaining; despawns at <= 0
}

reset_enemy_bullets :: proc() {
	clear(&game.enemy_bullets)
}

fire_enemy_bullet :: proc(origin, direction: Vec2, ranged: Ranged) {
	append(
		&game.enemy_bullets,
		Enemy_Bullet {
			position = origin,
			velocity = direction * ranged.projectile_speed,
			damage = ranged.attack_damage,
			lifetime = ranged.bullet_lifetime,
		},
	)
}

update_enemy_bullets :: proc(dt: f32) {
	#reverse for &bullet, i in game.enemy_bullets {
		bullet.position += bullet.velocity * dt
		bullet.lifetime -= dt

		if bullet.lifetime <= 0 {
			unordered_remove(&game.enemy_bullets, i)
			continue
		}

		player_box := actor_collision_rect(game.player.rect)
		if rl.CheckCollisionCircleRec(bullet.position, BULLET_RADIUS, player_box) {
			damage_player(bullet.damage)
			unordered_remove(&game.enemy_bullets, i)
			continue
		}

		if bullet_hits_wall(bullet.position) {
			unordered_remove(&game.enemy_bullets, i)
		}
	}
}
