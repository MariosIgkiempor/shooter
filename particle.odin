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

// flame-tick-burst preset: small and short-lived, fired once per
// Flame_Staff Automatic tick (ticket 06's confirmed finding - a discrete
// per-tick pulse read better than a continuous stream at its 100ms tick
// rate) - reuses the same flat-circle burst as hit_spark/damage_burst, just
// warm-colored
FLAME_TICK_BURST_COUNT :: 5
FLAME_TICK_BURST_MIN_SPEED :: 40.0
FLAME_TICK_BURST_MAX_SPEED :: 90.0
FLAME_TICK_BURST_MIN_LIFETIME :: 0.08
FLAME_TICK_BURST_MAX_LIFETIME :: 0.15
FLAME_TICK_BURST_MIN_RADIUS :: 2.0
FLAME_TICK_BURST_MAX_RADIUS :: 4.0

// Fire_Wand charge-particle preset: tiny embers drifting inward toward the
// muzzle, spawned one-per-frame throughout Windup (update_magic_cast_particles,
// weapon.odin) - replaces a single flat growing circle with particles that
// read as energy gathering into a point
FIRE_WAND_CHARGE_MIN_LIFETIME :: 0.12
FIRE_WAND_CHARGE_MAX_LIFETIME :: 0.22
FIRE_WAND_CHARGE_MIN_RADIUS :: 1.0
FIRE_WAND_CHARGE_MAX_RADIUS :: 2.2
FIRE_WAND_CHARGE_SPREAD :: 7.0 // px, shrinks toward the muzzle as Windup progress -> 1
FIRE_WAND_CHARGE_INWARD_PULL :: 5.0 // 1/s, how fast a charge ember drifts toward the muzzle

// bullet-trail preset: tiny, stationary (no velocity of its own - just fades
// in place via PARTICLE_DRAG-less lifetime decay), spawned once per bullet
// per frame so gun pellets and Fireball read as leaving a trail rather than
// a bare dot in flight
BULLET_TRAIL_MIN_LIFETIME :: 0.08
BULLET_TRAIL_MAX_LIFETIME :: 0.16
BULLET_TRAIL_MIN_RADIUS :: 0.8
BULLET_TRAIL_MAX_RADIUS :: 1.6

// Flame_Staff cone-fill preset: small embers scattered across the
// Flamethrower's live cone each frame it's held, replacing a flat translucent
// sector - distinct from spawn_flame_tick_burst's discrete per-tick pulse at
// the muzzle, this is the continuous "reach" fill
FLAME_CONE_MIN_LIFETIME :: 0.1
FLAME_CONE_MAX_LIFETIME :: 0.2
FLAME_CONE_MIN_RADIUS :: 1.5
FLAME_CONE_MAX_RADIUS :: 3.5
FLAME_CONE_MIN_DRIFT_SPEED :: 10.0
FLAME_CONE_MAX_DRIFT_SPEED :: 30.0

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

// preset burst for Flame_Staff's per-tick pulse, called once per
// cast_flamethrower_tick regardless of whether it hit anything - reads as
// channeling even when whiffing, same as the continuous cone-fill particles
spawn_flame_tick_burst :: proc(position: Vec2) {
	spawn_particle_burst(
		position,
		FLAME_TICK_BURST_COUNT,
		rl.ORANGE,
		FLAME_TICK_BURST_MIN_SPEED,
		FLAME_TICK_BURST_MAX_SPEED,
		FLAME_TICK_BURST_MIN_LIFETIME,
		FLAME_TICK_BURST_MAX_LIFETIME,
		FLAME_TICK_BURST_MIN_RADIUS,
		FLAME_TICK_BURST_MAX_RADIUS,
	)
}

// spawns one Fire_Wand charge ember at a random point within
// FIRE_WAND_CHARGE_SPREAD*(1-progress) of `muzzle`, drifting inward toward
// it - called once per frame throughout Windup so embers accumulate and
// tighten as progress approaches 1 (Resolve)
spawn_fire_wand_charge_particle :: proc(muzzle: Vec2, progress: f32) {
	spread := FIRE_WAND_CHARGE_SPREAD * (1 - progress)
	angle := rand.float32_range(0, math.TAU)
	r := spread * math.sqrt(rand.float32_range(0, 1))
	position := muzzle + Vec2{math.cos(angle), math.sin(angle)} * r
	lifetime := rand.float32_range(FIRE_WAND_CHARGE_MIN_LIFETIME, FIRE_WAND_CHARGE_MAX_LIFETIME)

	append(
		&game.particles,
		Particle {
			position = position,
			velocity = (muzzle - position) * FIRE_WAND_CHARGE_INWARD_PULL,
			visual = Particle_Circle {
				color = rl.Color{255, 140, 30, 255},
				radius = rand.float32_range(FIRE_WAND_CHARGE_MIN_RADIUS, FIRE_WAND_CHARGE_MAX_RADIUS),
			},
			lifetime = lifetime,
			max_lifetime = lifetime,
		},
	)
}

// spawns one Flame_Staff cone-fill ember at a random point within the live
// Flamethrower cone (uniform over the sector's area), drifting outward along
// its own angle like embers pushed by the stream - called once per frame
// while held so the cone reads as filled rather than a flat translucent shape
spawn_flame_cone_particle :: proc(origin, aim_dir: Vec2, range, arc_degrees: f32) {
	base_angle := math.atan2(aim_dir.y, aim_dir.x)
	angle := base_angle + math.to_radians(rand.float32_range(-arc_degrees / 2, arc_degrees / 2))
	dist := range * math.sqrt(rand.float32_range(0, 1))
	direction := Vec2{math.cos(angle), math.sin(angle)}
	lifetime := rand.float32_range(FLAME_CONE_MIN_LIFETIME, FLAME_CONE_MAX_LIFETIME)

	append(
		&game.particles,
		Particle {
			position = origin + direction * dist,
			velocity = direction * rand.float32_range(FLAME_CONE_MIN_DRIFT_SPEED, FLAME_CONE_MAX_DRIFT_SPEED),
			visual = Particle_Circle {
				color = rl.Color{230, 100, 30, 220},
				radius = rand.float32_range(FLAME_CONE_MIN_RADIUS, FLAME_CONE_MAX_RADIUS),
			},
			lifetime = lifetime,
			max_lifetime = lifetime,
		},
	)
}

// spawns one trail particle at `position` - called once per bullet per frame
// (update_bullets, bullet.odin) so the trail traces the bullet's actual path
// rather than a fixed-interval approximation of it
spawn_bullet_trail_particle :: proc(position: Vec2, color: rl.Color) {
	lifetime := rand.float32_range(BULLET_TRAIL_MIN_LIFETIME, BULLET_TRAIL_MAX_LIFETIME)

	append(
		&game.particles,
		Particle {
			position = position,
			visual = Particle_Circle {
				color = color,
				radius = rand.float32_range(BULLET_TRAIL_MIN_RADIUS, BULLET_TRAIL_MAX_RADIUS),
			},
			lifetime = lifetime,
			max_lifetime = lifetime,
		},
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
