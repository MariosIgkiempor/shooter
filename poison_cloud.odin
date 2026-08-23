package shooter

import rl "vendor:raylib"

Poison_Cloud :: struct {
	position:   Vec2,
	radius:     f32,
	damage:     f32, // damage applied per tick to each enemy currently overlapping
	tick_rate:  f32, // damage ticks/sec
	tick_timer: f32, // counts down to 0, fires a tick, then resets to 1/tick_rate
	lifetime:   f32, // seconds remaining; despawns at <= 0
}

reset_poison_clouds :: proc() {
	clear(&game.poison_clouds)
}

// spawns a lingering DoT zone at `position` - its own tracked entity per
// ticket 04/11's lock that a persisting spell effect lives off Weapon/Magic,
// the same way fire_pellets spawns Bullets
cast_poison_cloud :: proc(magic: Magic, damage: f32, position: Vec2) {
	append(
		&game.poison_clouds,
		Poison_Cloud {
			position = position,
			radius = magic.cloud_radius,
			damage = damage,
			tick_rate = magic.cloud_tick_rate,
			tick_timer = 0, // ticks immediately on its first update
			lifetime = magic.cloud_duration,
		},
	)
}

update_poison_clouds :: proc(dt: f32) {
	#reverse for &cloud, i in game.poison_clouds {
		cloud.lifetime -= dt
		if cloud.lifetime <= 0 {
			unordered_remove(&game.poison_clouds, i)
			continue
		}

		cloud.tick_timer -= dt
		if cloud.tick_timer > 0 {
			continue
		}
		cloud.tick_timer += 1.0 / cloud.tick_rate

		// repeating tick to everyone currently inside, not a single hit on
		// entry - lingering in the cloud stacks up damage (ticket 11)
		#reverse for enemy, j in game.enemies {
			enemy_box := actor_collision_rect(enemy.rect, enemy.animation)
			if !rl.CheckCollisionCircleRec(cloud.position, cloud.radius, enemy_box) {
				continue
			}
			apply_hit_to_enemy(j, cloud.damage, Vec2{enemy.x, enemy.y})
		}
	}
}

draw_poison_clouds :: proc(clouds: []Poison_Cloud) {
	for cloud in clouds {
		rl.DrawCircleV(cloud.position, cloud.radius, rl.Color{50, 180, 60, 90})
	}
}
