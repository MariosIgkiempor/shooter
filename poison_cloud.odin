package shooter

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

// ambient gas-puff particles, spawned continuously while the cloud lives -
// flat squares that shrink+fade (art-revamp ticket 06). Kept slow and
// short-lived so a puff never drifts past the cloud's own radius before it
// fades.
POISON_GAS_SPAWN_INTERVAL: f32 = 0.1
POISON_GAS_SPRITE_SIZE: f32 = 14.0
POISON_GAS_MIN_LIFETIME: f32 = 0.5
POISON_GAS_MAX_LIFETIME: f32 = 0.9
POISON_GAS_MAX_DRIFT_SPEED: f32 = 6.0
// keeps puff centers away from the very edge, since the sprite itself has
// radius (a puff spawned exactly on the boundary would draw half outside it)
POISON_GAS_SPAWN_RADIUS_FRACTION: f32 = 0.75

// alpha (0..255) of the flat disc drawn under the gas puffs to mark the
// cloud's actual damage radius
POISON_CLOUD_FILL_ALPHA: f32 = 90

Poison_Cloud :: struct {
	position:        Vec2,
	radius:          f32,
	damage:          f32, // damage applied per tick to each enemy currently overlapping
	tick_rate:       f32, // damage ticks/sec
	tick_timer:      f32, // counts down to 0, fires a tick, then resets to 1/tick_rate
	lifetime:        f32, // seconds remaining; despawns at <= 0
	gas_spawn_timer: f32, // counts down to 0, spawns a gas puff, then resets
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
			gas_spawn_timer = 0, // spawns its first puff immediately too
		},
	)
}

// spawns one ambient gas-puff particle at a random point within the cloud's
// radius, drifting slowly so it fades out before it could drift past the
// cloud's own edge
spawn_poison_gas_puff :: proc(cloud: Poison_Cloud) {
	angle := rand.float32_range(0, math.TAU)
	// sqrt of a uniform sample gives a uniform distribution over the disc's
	// area, not a bias toward the center
	r := cloud.radius * POISON_GAS_SPAWN_RADIUS_FRACTION * math.sqrt(rand.float32_range(0, 1))
	offset := Vec2{math.cos(angle), math.sin(angle)} * r

	drift_angle := rand.float32_range(0, math.TAU)
	drift_speed := rand.float32_range(0, POISON_GAS_MAX_DRIFT_SPEED)
	drift := Vec2{math.cos(drift_angle), math.sin(drift_angle)} * drift_speed

	spawn_particle_square(
		cloud.position + offset,
		drift,
		POISON_GAS_SQUARE_COLOR,
		POISON_GAS_SPRITE_SIZE,
		rand.float32_range(POISON_GAS_MIN_LIFETIME, POISON_GAS_MAX_LIFETIME),
	)
}

// Poison_Staff's Windup telegraph (ticket 06): gas puffs already filling the
// eventual cloud's footprint at the Trigger-locked target (ADR-0005) - reuses
// the same puff distribution/animation as a live cloud's own ambient puffs
// (spawn_poison_gas_puff), just growing toward full cloud_radius as Windup
// nears completion instead of a flat telegraph ring. Called once per frame
// throughout Windup (update_magic_cast_particles, weapon.odin).
spawn_poison_windup_puff :: proc(target: Vec2, cloud_radius, progress: f32) {
	radius := cloud_radius * progress
	angle := rand.float32_range(0, math.TAU)
	// sqrt of a uniform sample gives a uniform distribution over the disc's
	// area, not a bias toward the center
	r := radius * math.sqrt(rand.float32_range(0, 1))
	offset := Vec2{math.cos(angle), math.sin(angle)} * r

	drift_angle := rand.float32_range(0, math.TAU)
	drift_speed := rand.float32_range(0, POISON_GAS_MAX_DRIFT_SPEED)
	drift := Vec2{math.cos(drift_angle), math.sin(drift_angle)} * drift_speed

	spawn_particle_square(
		target + offset,
		drift,
		POISON_GAS_SQUARE_COLOR,
		POISON_GAS_SPRITE_SIZE,
		rand.float32_range(POISON_GAS_MIN_LIFETIME, POISON_GAS_MAX_LIFETIME),
	)
}

update_poison_clouds :: proc(dt: f32) {
	#reverse for &cloud, i in game.poison_clouds {
		cloud.lifetime -= dt
		if cloud.lifetime <= 0 {
			unordered_remove(&game.poison_clouds, i)
			continue
		}

		cloud.gas_spawn_timer -= dt
		if cloud.gas_spawn_timer <= 0 {
			cloud.gas_spawn_timer += POISON_GAS_SPAWN_INTERVAL
			spawn_poison_gas_puff(cloud)
		}

		cloud.tick_timer -= dt
		if cloud.tick_timer > 0 {
			continue
		}
		cloud.tick_timer += 1.0 / cloud.tick_rate

		// repeating tick to everyone currently inside, not a single hit on
		// entry - lingering in the cloud stacks up damage (ticket 11)
		#reverse for enemy, j in game.enemies {
			enemy_box := actor_collision_rect(enemy.rect)
			if !rl.CheckCollisionCircleRec(cloud.position, cloud.radius, enemy_box) {
				continue
			}
			apply_hit_to_enemy(j, cloud.damage, Vec2{enemy.x, enemy.y})
		}
	}
}

draw_poison_clouds :: proc(clouds: []Poison_Cloud) {
	for cloud in clouds {
		rl.DrawCircleV(cloud.position, cloud.radius, rl.Color{50, 180, 60, u8(POISON_CLOUD_FILL_ALPHA)})
	}
}
