package shooter

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

PARTICLE_DRAG: f32 = 6.0 // 1/s exponential-ish velocity decay

// hit-spark preset: fast, small, very short-lived - a crisp instant spark
HIT_SPARK_COUNT: int = 6
HIT_SPARK_MIN_SPEED: f32 = 60.0
HIT_SPARK_MAX_SPEED: f32 = 160.0
HIT_SPARK_MIN_LIFETIME: f32 = 0.1
HIT_SPARK_MAX_LIFETIME: f32 = 0.2
HIT_SPARK_MIN_RADIUS: f32 = 1.8
HIT_SPARK_MAX_RADIUS: f32 = 3.5

// damage-burst preset: slower, bigger, longer-lived - a more noticeable "hurt" cue
DAMAGE_BURST_COUNT: int = 10
DAMAGE_BURST_MIN_SPEED: f32 = 30.0
DAMAGE_BURST_MAX_SPEED: f32 = 90.0
DAMAGE_BURST_MIN_LIFETIME: f32 = 0.25
DAMAGE_BURST_MAX_LIFETIME: f32 = 0.45
DAMAGE_BURST_MIN_RADIUS: f32 = 2.5
DAMAGE_BURST_MAX_RADIUS: f32 = 5.0

// flame-tick-burst preset: small and short-lived, fired once per
// Flame_Staff Automatic tick (ticket 06's confirmed finding - a discrete
// per-tick pulse read better than a continuous stream at its 100ms tick
// rate) - reuses the same flat-circle burst as hit_spark/damage_burst, just
// warm-colored
FLAME_TICK_BURST_COUNT: int = 5
FLAME_TICK_BURST_MIN_SPEED: f32 = 40.0
FLAME_TICK_BURST_MAX_SPEED: f32 = 90.0
FLAME_TICK_BURST_MIN_LIFETIME: f32 = 0.08
FLAME_TICK_BURST_MAX_LIFETIME: f32 = 0.15
FLAME_TICK_BURST_MIN_RADIUS: f32 = 2.0
FLAME_TICK_BURST_MAX_RADIUS: f32 = 4.0

// Fire_Wand charge-particle preset: tiny embers drifting inward toward the
// muzzle, spawned one-per-frame throughout Windup (update_magic_cast_particles,
// weapon.odin) - replaces a single flat growing circle with particles that
// read as energy gathering into a point
FIRE_WAND_CHARGE_MIN_LIFETIME: f32 = 0.12
FIRE_WAND_CHARGE_MAX_LIFETIME: f32 = 0.22
FIRE_WAND_CHARGE_MIN_RADIUS: f32 = 1.0
FIRE_WAND_CHARGE_MAX_RADIUS: f32 = 2.2
FIRE_WAND_CHARGE_SPREAD: f32 = 7.0 // px, shrinks toward the muzzle as Windup progress -> 1
FIRE_WAND_CHARGE_INWARD_PULL: f32 = 5.0 // 1/s, how fast a charge ember drifts toward the muzzle

// muzzle-effect presets (art-revamp ticket 02): a fanned streak burst plus a
// one-shot flash, fired once at Resolve - the enhanced particle layer
// confirmed to supply the "punch" plain icon-transform lacked
MUZZLE_STREAK_MIN_SPEED: f32 = 250.0
MUZZLE_STREAK_MAX_SPEED: f32 = 400.0
MUZZLE_STREAK_MIN_LIFETIME: f32 = 0.06
MUZZLE_STREAK_MAX_LIFETIME: f32 = 0.12
MUZZLE_STREAK_LENGTH: f32 = 8.0
MUZZLE_STREAK_WIDTH: f32 = 2.0
MUZZLE_FLASH_MAX_RADIUS: f32 = 14.0
MUZZLE_FLASH_LIFETIME: f32 = 0.1

// poison-gas puff preset (art-revamp ticket 06): a flat square that
// shrinks+fades, replacing the old animated-sprite puff
POISON_GAS_SQUARE_COLOR :: rl.Color{90, 200, 90, 200}

// bullet-trail preset: tiny, stationary (no velocity of its own - just fades
// in place via PARTICLE_DRAG-less lifetime decay), spawned once per bullet
// per frame so gun pellets and Fireball read as leaving a trail rather than
// a bare dot in flight
BULLET_TRAIL_MIN_LIFETIME: f32 = 0.08
BULLET_TRAIL_MAX_LIFETIME: f32 = 0.16
BULLET_TRAIL_MIN_RADIUS: f32 = 0.8
BULLET_TRAIL_MAX_RADIUS: f32 = 1.6

// Flame_Staff cone-fill preset: small embers scattered across the
// Flamethrower's live cone each frame it's held, replacing a flat translucent
// sector - distinct from spawn_flame_tick_burst's discrete per-tick pulse at
// the muzzle, this is the continuous "reach" fill
FLAME_CONE_MIN_LIFETIME: f32 = 0.1
FLAME_CONE_MAX_LIFETIME: f32 = 0.2
FLAME_CONE_MIN_RADIUS: f32 = 1.5
FLAME_CONE_MAX_RADIUS: f32 = 3.5
FLAME_CONE_MIN_DRIFT_SPEED: f32 = 10.0
FLAME_CONE_MAX_DRIFT_SPEED: f32 = 30.0

// Lightning-bolt preset: a chain of stationary streaks laid along the whole
// line in one call, with the joints jittered off-axis so it forks rather than
// reading as a ruler. Very short-lived on purpose - the bolt is gone in about
// four frames, which is what "instant" looks like beside a Fireball the player
// can watch travel.
LIGHTNING_BOLT_LIFETIME: f32 = 0.07
LIGHTNING_BOLT_SEGMENT_LENGTH: f32 = 14.0
LIGHTNING_BOLT_JITTER: f32 = 4.0 // px, perpendicular offset per joint
LIGHTNING_BOLT_WIDTH: f32 = 2.5
// A Particle_Streak takes its orientation from its own velocity (draw_streak,
// renderer.odin), so a bolt segment cannot be perfectly stationary or it would
// draw horizontal whatever direction the shot went. This is the smallest speed
// that buys the orientation: over a segment's whole ~0.07s life it drifts less
// than a pixel, so the bolt still hangs in place and vanishes rather than
// flying anywhere.
LIGHTNING_BOLT_DRIFT_SPEED: f32 = 8.0
// backs the fixed-size joint buffer below, so it cannot itself be a Tunable
LIGHTNING_BOLT_MAX_SEGMENTS :: 32

// Lightning charge preset: the gathering crackle through Windup, spawned
// one-per-frame from update_magic_cast_particles like Fire_Wand's embers.
// Tiny outward flicks rather than an inward drift - what gathers here is a
// charge on the tip, not fuel being drawn in.
LIGHTNING_CHARGE_MIN_LIFETIME: f32 = 0.05
LIGHTNING_CHARGE_MAX_LIFETIME: f32 = 0.11
LIGHTNING_CHARGE_SPREAD: f32 = 9.0 // px, shrinks toward the tip as Windup progress -> 1
LIGHTNING_CHARGE_SPEED: f32 = 40.0
LIGHTNING_CHARGE_LENGTH: f32 = 5.0
LIGHTNING_CHARGE_WIDTH: f32 = 1.6

// what a Particle looks like - a plain filled circle, an oriented streak
// (art-revamp ticket 02), a one-shot radial-gradient flash (ticket 02), or a
// flat square (ticket 06's poison-gas puffs). Orthogonal to the rest of
// Particle's fields (position/velocity/lifetime), same bare-union-on-the-
// struct-field idiom as Enemy's Movement_Style/Attack_Style. See CONTEXT.md's
// Movement Style entry.
Particle_Visual :: union {
	Particle_Circle,
	Particle_Streak,
	Particle_Flash,
	Particle_Square,
}

Particle_Circle :: struct {
	color:  rl.Color,
	radius: f32,
}

// oriented to the particle's own velocity each frame, so it always reads as
// "moving this way" even as drag slows/curves it
Particle_Streak :: struct {
	color:  rl.Color,
	length: f32,
	width:  f32,
}

// one-shot bright glow, fast non-linear decay (radius grows while alpha
// fades, both eased) - a new primitive today's particle system didn't have
Particle_Flash :: struct {
	color:      rl.Color,
	max_radius: f32,
}

// flat square that shrinks+fades over time, same convention as
// Particle_Circle - replaces the old animated-sprite poison-gas puff (ticket
// 06)
Particle_Square :: struct {
	color: rl.Color,
	size:  f32,
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

// spawns a single square particle - used for the poison cloud's gas puffs
// (ticket 06)
spawn_particle_square :: proc(position, velocity: Vec2, color: rl.Color, size, lifetime: f32) {
	append(
		&game.particles,
		Particle {
			position = position,
			velocity = velocity,
			visual = Particle_Square{color = color, size = size},
			lifetime = lifetime,
			max_lifetime = lifetime,
		},
	)
}

// spawns a single oriented streak particle traveling in `direction` at
// `speed` (art-revamp ticket 02) - used for weapon muzzle effects
spawn_particle_streak :: proc(
	position, direction: Vec2,
	speed: f32,
	color: rl.Color,
	length, width: f32,
	lifetime: f32,
) {
	append(
		&game.particles,
		Particle {
			position = position,
			velocity = linalg.normalize0(direction) * speed,
			visual = Particle_Streak{color = color, length = length, width = width},
			lifetime = lifetime,
			max_lifetime = lifetime,
		},
	)
}

// fans `count` streak particles from `position` across `spread_degrees`
// around `direction` - a weapon's muzzle effect (art-revamp ticket 02),
// giving visual continuity with the streak-shaped bullet it launches
spawn_streak_burst :: proc(
	position, direction: Vec2,
	count: int,
	spread_degrees: f32,
	color: rl.Color,
) {
	base_angle := math.atan2(direction.y, direction.x)

	for i in 0 ..< count {
		t := count > 1 ? f32(i) / f32(count - 1) - 0.5 : 0 // -0.5 .. 0.5
		angle := base_angle + math.to_radians(spread_degrees) * t
		dir := Vec2{math.cos(angle), math.sin(angle)}
		speed := rand.float32_range(MUZZLE_STREAK_MIN_SPEED, MUZZLE_STREAK_MAX_SPEED)
		lifetime := rand.float32_range(MUZZLE_STREAK_MIN_LIFETIME, MUZZLE_STREAK_MAX_LIFETIME)
		spawn_particle_streak(position, dir, speed, color, MUZZLE_STREAK_LENGTH, MUZZLE_STREAK_WIDTH, lifetime)
	}
}

// a one-shot bright flash at `position` - a weapon's muzzle/cast effect
// (art-revamp ticket 02). `radius` comes from the firing weapon's
// Weapon_Visual so magnitude varies per Weapon_Kind while the flash's shape
// stays a family-level primitive (ADR-0018); it falls back to the shared
// default for any caller with no weapon behind it.
spawn_muzzle_flash :: proc(position: Vec2, color: rl.Color, radius: f32 = MUZZLE_FLASH_MAX_RADIUS) {
	append(
		&game.particles,
		Particle {
			position = position,
			visual = Particle_Flash{color = color, max_radius = radius},
			lifetime = MUZZLE_FLASH_LIFETIME,
			max_lifetime = MUZZLE_FLASH_LIFETIME,
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
	}
}

draw_particles :: proc(particles: []Particle) {
	for particle in particles {
		t := particle.lifetime / particle.max_lifetime // 1 -> 0 over life
		// non-linear (ease-out) fade throughout (art-revamp ticket 02),
		// replacing the old linear t - drops off faster near the end instead
		// of a flat linear ramp
		fade := ease_out_cubic(t)

		switch v in particle.visual {
		case Particle_Circle:
			rl.DrawCircleV(particle.position, v.radius * t, rl.Fade(v.color, fade))
		case Particle_Streak:
			draw_streak(particle.position, particle.velocity, v.length, v.width, rl.Fade(v.color, fade))
		case Particle_Flash:
			// grows while it fades - fast non-linear decay
			radius := v.max_radius * (1 - t * t)
			draw_flash(particle.position, radius, rl.Fade(v.color, fade))
		case Particle_Square:
			size := v.size * t
			rl.DrawRectangleV(particle.position - Vec2{size, size} / 2, Vec2{size, size}, rl.Fade(v.color, fade))
		}
	}
}

// lays the whole bolt down in one call: a chain of streaks from `from` to
// `to`, each joint pushed off the line so the result forks. The segments hang
// where they are laid and fade - a bolt does not travel, it is simply there
// and then gone, and anything that visibly moved would make an instant cast
// look like a slow one (see LIGHTNING_BOLT_DRIFT_SPEED for the sub-pixel
// exception the renderer forces).
spawn_lightning_bolt :: proc(from, to: Vec2) {
	offset := to - from
	length := linalg.length(offset)
	if length <= 0 {
		return
	}

	direction := offset / length
	perpendicular := Vec2{-direction.y, direction.x}

	segments := clamp(int(length / max(LIGHTNING_BOLT_SEGMENT_LENGTH, 1)), 2, LIGHTNING_BOLT_MAX_SEGMENTS)

	joints: [LIGHTNING_BOLT_MAX_SEGMENTS + 1]Vec2
	for i in 0 ..= segments {
		t := f32(i) / f32(segments)
		joints[i] = from + offset * t
		// the ends stay pinned: one is the muzzle and the other is what the
		// bolt actually hit, and a jittered end would draw a line to somewhere
		// nothing was damaged
		if i > 0 && i < segments {
			joints[i] += perpendicular * rand.float32_range(-LIGHTNING_BOLT_JITTER, LIGHTNING_BOLT_JITTER)
		}
	}

	for i in 0 ..< segments {
		span := joints[i + 1] - joints[i]
		spawn_particle_streak(
			joints[i] + span / 2,
			span,
			LIGHTNING_BOLT_DRIFT_SPEED,
			ICON_LIGHTNING_COLOR,
			linalg.length(span),
			LIGHTNING_BOLT_WIDTH,
			LIGHTNING_BOLT_LIFETIME,
		)
	}
}

// one Windup crackle at a random point within LIGHTNING_CHARGE_SPREAD*(1 -
// progress) of the staff's tip, flicking outward - called once per frame
// through Windup so the gathering tightens as Resolve approaches, the same
// shape as Fire_Wand's charge embers with the drift reversed
spawn_lightning_charge_particle :: proc(tip: Vec2, progress: f32) {
	spread := LIGHTNING_CHARGE_SPREAD * (1 - progress)
	angle := rand.float32_range(0, math.TAU)
	r := spread * math.sqrt(rand.float32_range(0, 1))
	direction := Vec2{math.cos(angle), math.sin(angle)}
	lifetime := rand.float32_range(LIGHTNING_CHARGE_MIN_LIFETIME, LIGHTNING_CHARGE_MAX_LIFETIME)

	spawn_particle_streak(
		tip + direction * r,
		direction,
		LIGHTNING_CHARGE_SPEED,
		ICON_LIGHTNING_COLOR,
		LIGHTNING_CHARGE_LENGTH,
		LIGHTNING_CHARGE_WIDTH,
		lifetime,
	)
}
