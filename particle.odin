package shooter

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

PARTICLE_DRAG :: 6.0 // 1/s exponential-ish velocity decay

// hit-spark preset: fast, small, very short-lived - a crisp instant spark
HIT_SPARK_COUNT :: 6
HIT_SPARK_MIN_SPEED :: 60.0
HIT_SPARK_MAX_SPEED :: 160.0
HIT_SPARK_MIN_LIFETIME :: 0.1
HIT_SPARK_MAX_LIFETIME :: 0.2
HIT_SPARK_MIN_RADIUS :: 1.8
HIT_SPARK_MAX_RADIUS :: 3.5

// damage-burst preset: slower, bigger, longer-lived - a more noticeable "hurt" cue
DAMAGE_BURST_COUNT :: 10
DAMAGE_BURST_MIN_SPEED :: 30.0
DAMAGE_BURST_MAX_SPEED :: 90.0
DAMAGE_BURST_MIN_LIFETIME :: 0.25
DAMAGE_BURST_MAX_LIFETIME :: 0.45
DAMAGE_BURST_MIN_RADIUS :: 2.5
DAMAGE_BURST_MAX_RADIUS :: 5.0

Particle :: struct {
	position:     Vec2,
	velocity:     Vec2,
	color:        rl.Color,
	radius:       f32,
	lifetime:     f32, // seconds remaining; despawns at <= 0
	max_lifetime: f32, // starting lifetime, used to compute fade fraction
}

reset_particles :: proc() {
	clear(&game.particles)
}

// spawns `count` particles from `position`, fanned in random directions with
// speed/lifetime/radius drawn from the given ranges, all sharing `color`
spawn_particle_burst :: proc(
	position: Vec2,
	count: int,
	color: rl.Color,
	min_speed, max_speed: f32,
	min_lifetime, max_lifetime: f32,
	min_radius, max_radius: f32,
) {
	for _ in 0 ..< count {
		angle := rand.float32_range(0, math.TAU)
		speed := rand.float32_range(min_speed, max_speed)
		direction := Vec2{math.cos(angle), math.sin(angle)}
		lifetime := rand.float32_range(min_lifetime, max_lifetime)

		append(
			&game.particles,
			Particle {
				position     = position,
				velocity     = direction * speed,
				color        = color,
				radius       = rand.float32_range(min_radius, max_radius),
				lifetime     = lifetime,
				max_lifetime = lifetime,
			},
		)
	}
}

// preset burst for a bullet striking an enemy
spawn_hit_spark :: proc(position: Vec2) {
	spawn_particle_burst(
		position,
		HIT_SPARK_COUNT,
		rl.ORANGE,
		HIT_SPARK_MIN_SPEED,
		HIT_SPARK_MAX_SPEED,
		HIT_SPARK_MIN_LIFETIME,
		HIT_SPARK_MAX_LIFETIME,
		HIT_SPARK_MIN_RADIUS,
		HIT_SPARK_MAX_RADIUS,
	)
}

// preset burst for the player taking damage
spawn_damage_burst :: proc(position: Vec2) {
	spawn_particle_burst(
		position,
		DAMAGE_BURST_COUNT,
		rl.RED,
		DAMAGE_BURST_MIN_SPEED,
		DAMAGE_BURST_MAX_SPEED,
		DAMAGE_BURST_MIN_LIFETIME,
		DAMAGE_BURST_MAX_LIFETIME,
		DAMAGE_BURST_MIN_RADIUS,
		DAMAGE_BURST_MAX_RADIUS,
	)
}

update_particles :: proc(dt: f32) {
	#reverse for &particle, i in game.particles {
		particle.lifetime -= dt
		if particle.lifetime <= 0 {
			unordered_remove(&game.particles, i)
			continue
		}

		particle.velocity *= 1 - min(PARTICLE_DRAG * dt, 1)
		particle.position += particle.velocity * dt
	}
}

draw_particles :: proc(particles: []Particle) {
	for particle in particles {
		t := particle.lifetime / particle.max_lifetime // 1 -> 0 over life
		rl.DrawCircleV(particle.position, particle.radius * t, rl.Fade(particle.color, t))
	}
}
