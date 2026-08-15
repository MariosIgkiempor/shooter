package shooter

import "core:math"
import rl "vendor:raylib"

BULLET_RADIUS :: 2.0

Bullet :: struct {
	position: Vec2,
	velocity: Vec2, // direction * speed, computed once at spawn
	damage:   f32,
	lifetime: f32, // seconds remaining; despawns at <= 0
}

reset_bullets :: proc() {
	clear(&game.bullets)
}

// spawns weapon.pellet_count bullets, fanned across weapon.spread_angle
// degrees around aim_dir (a single bullet straight down aim_dir when
// pellet_count is 1, e.g. pistol/SMG)
fire_pellets :: proc(weapon: Weapon, origin, aim_dir: Vec2) {
	pellets := max(weapon.pellet_count, 1)
	base_angle := math.atan2(aim_dir.y, aim_dir.x)

	for i in 0 ..< pellets {
		angle := base_angle

		if pellets > 1 {
			t := f32(i) / f32(pellets - 1) - 0.5 // -0.5 .. 0.5
			angle += math.to_radians(weapon.spread_angle) * t
		}

		direction := Vec2{math.cos(angle), math.sin(angle)}

		append(
			&game.bullets,
			Bullet {
				position = origin,
				velocity = direction * weapon.projectile_speed,
				damage = weapon.damage,
				lifetime = weapon.bullet_lifetime,
			},
		)
	}
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

		#reverse for &enemy, j in game.enemies {
			enemy_box := actor_collision_rect(enemy.rect, enemy.animation)
			if !rl.CheckCollisionCircleRec(bullet.position, BULLET_RADIUS, enemy_box) {
				continue
			}

			enemy.health -= bullet.damage
			if enemy.health <= 0 {
				delete(enemy.path)
				unordered_remove(&game.enemies, j)
			}

			hit = true
			break
		}

		if hit {
			unordered_remove(&game.bullets, i)
		}
	}
}
