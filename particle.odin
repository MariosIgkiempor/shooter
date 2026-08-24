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

// what a Particle looks like - a plain filled circle, or an animated atlas
// sprite. Orthogonal to the rest of Particle's fields (position/velocity/
// lifetime), same bare-union-on-the-struct-field idiom as Enemy's
// Movement_Style/Attack_Style. See CONTEXT.md's Movement Style entry.
Particle_Visual :: union {
	Particle_Circle,
	Particle_Sprite,
}

Particle_Circle :: struct {
	color:  rl.Color,
	radius: f32,
}

Particle_Sprite :: struct {
	animation: Animation,
	size:      Vec2, // drawn world-space size, centered on position
}

Particle :: struct {
	position:     Vec2,
	velocity:     Vec2,
	visual:       Particle_Visual,
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
				position = position,
				velocity = direction * speed,
				visual = Particle_Circle {
					color = color,
					radius = rand.float32_range(min_radius, max_radius),
				},
				lifetime = lifetime,
				max_lifetime = lifetime,
			},
		)
	}
}

// spawns a single animated-sprite particle - used for effects that need more
// than a flat-colored circle, e.g. the poison cloud's gas puffs
spawn_particle_sprite :: proc(
	position, velocity: Vec2,
	anim: Animation_Name,
	size: Vec2,
	lifetime: f32,
) {
	append(
		&game.particles,
		Particle {
			position = position,
			velocity = velocity,
			visual = Particle_Sprite{animation = animation_create(anim), size = size},
			lifetime = lifetime,
			max_lifetime = lifetime,
		},
	)
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

		switch &v in particle.visual {
		case Particle_Circle:
		case Particle_Sprite:
			animation_update(&v.animation, dt)
		}
	}
}

draw_particles :: proc(particles: []Particle) {
	for particle in particles {
		t := particle.lifetime / particle.max_lifetime // 1 -> 0 over life

		switch v in particle.visual {
		case Particle_Circle:
			rl.DrawCircleV(particle.position, v.radius * t, rl.Fade(v.color, t))
		case Particle_Sprite:
			tex := animation_atlas_texture(v.animation)
			dest := Rect{particle.position.x, particle.position.y, v.size.x, v.size.y}
			draw_atlas_tile(tex.rect, dest, v.size / 2, 0, rl.Fade(rl.WHITE, t))
		}
	}
}
