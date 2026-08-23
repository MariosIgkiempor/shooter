package shooter

import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

BULLET_RADIUS :: 2.0

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
fire_pellets :: proc(weapon: Weapon, gun: Gun, origin, aim_dir: Vec2) {
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
				position = origin,
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
cast_fireball :: proc(magic: Magic, damage: f32, origin, aim_dir: Vec2) {
	append(
		&game.bullets,
		Bullet {
			position = origin,
			velocity = aim_dir * magic.projectile_speed,
			damage = damage,
			lifetime = magic.bullet_lifetime,
			explosion_radius = magic.explosion_radius,
		},
	)
}

update_bullets :: proc(dt: f32) {
	#reverse for &bullet, i in game.bullets {
		bullet.position += bullet.velocity * dt
		bullet.lifetime -= dt

		if bullet.lifetime <= 0 {
			unordered_remove(&game.bullets, i)
			continue
		}

		hit := false

		#reverse for enemy, j in game.enemies {
			enemy_box := actor_collision_rect(enemy.rect, enemy.animation)
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
// spark and, on death, an xp orb + pickup drop + removal - shared by bullet
// collision above and melee's arc/cone hit-check (weapon.odin's
// try_swing_melee), so death handling is never duplicated between weapon
// types
apply_hit_to_enemy :: proc(index: int, damage: f32, hit_position: Vec2) {
	enemy := &game.enemies[index]

	enemy.health -= damage
	spawn_hit_spark(hit_position)

	if enemy.health <= 0 {
		spawn_xp_orb(Vec2{enemy.x, enemy.y})
		maybe_spawn_pickup(Vec2{enemy.x, enemy.y})
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

		player_box := actor_collision_rect(game.player.rect, game.player.animation)
		if rl.CheckCollisionCircleRec(bullet.position, BULLET_RADIUS, player_box) {
			damage_player(bullet.damage)
			unordered_remove(&game.enemy_bullets, i)
		}
	}
}
