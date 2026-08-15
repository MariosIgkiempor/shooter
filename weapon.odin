package shooter

Weapon_Kind :: enum {
	Pistol,
	SMG,
	Shotgun,
}

Fire_Mode :: enum {
	Semi_Automatic,
	Automatic,
}

Weapon :: struct {
	kind:             Weapon_Kind,
	fire_mode:        Fire_Mode,
	damage:           f32, // per bullet/pellet
	projectile_speed: f32,
	fire_rate:        f32, // shots/sec; cooldown between shots is 1/fire_rate
	cooldown_timer:   f32,
	clip_size:        int,
	ammo_in_clip:     int,
	reserve_ammo:     int, // ammo available to reload from; depletes and is not auto-refilled
	reload_time:      f32,
	reload_timer:     f32, // > 0 while reloading
	pellet_count:     int, // 1 for pistol/SMG, >1 for shotgun-style spread
	spread_angle:     f32, // degrees, total cone width across pellets
	bullet_lifetime:  f32,
}

weapon_presets: [Weapon_Kind]Weapon = {
	.Pistol = {
		kind = .Pistol,
		fire_mode = .Semi_Automatic,
		damage = 25,
		projectile_speed = 400,
		fire_rate = 3,
		clip_size = 12,
		reload_time = 1.2,
		pellet_count = 1,
		spread_angle = 0,
		bullet_lifetime = 1.5,
	},
	.SMG = {
		kind = .SMG,
		fire_mode = .Automatic,
		damage = 10,
		projectile_speed = 500,
		fire_rate = 12,
		clip_size = 30,
		reload_time = 1.8,
		pellet_count = 1,
		spread_angle = 4,
		bullet_lifetime = 1.2,
	},
	.Shotgun = {
		kind = .Shotgun,
		fire_mode = .Semi_Automatic,
		damage = 8,
		projectile_speed = 350,
		fire_rate = 1.1,
		clip_size = 6,
		reload_time = 2.2,
		pellet_count = 8,
		spread_angle = 28,
		bullet_lifetime = 0.6,
	},
}

WEAPON_STARTING_RESERVE_CLIPS :: 3 // clips worth of reserve ammo a fresh weapon starts with

weapon_create :: proc(kind: Weapon_Kind) -> Weapon {
	w := weapon_presets[kind]
	w.ammo_in_clip = w.clip_size
	w.reserve_ammo = w.clip_size * WEAPON_STARTING_RESERVE_CLIPS
	return w
}

update_weapon :: proc(weapon: ^Weapon, dt: f32) {
	if weapon.cooldown_timer > 0 {
		weapon.cooldown_timer -= dt
	}

	if weapon.reload_timer > 0 {
		weapon.reload_timer -= dt
		if weapon.reload_timer <= 0 {
			new_ammo := min(weapon.clip_size, weapon.ammo_in_clip + weapon.reserve_ammo)
			weapon.reserve_ammo -= new_ammo - weapon.ammo_in_clip
			weapon.ammo_in_clip = new_ammo
		}
	}
}

start_reload :: proc(weapon: ^Weapon) {
	if weapon.reload_timer > 0 || weapon.ammo_in_clip == weapon.clip_size || weapon.reserve_ammo <= 0 {
		return
	}

	weapon.reload_timer = weapon.reload_time
}

WEAPON_UPGRADE_DAMAGE_MULT :: 1.15 // +15% damage per pick
WEAPON_UPGRADE_FIRE_RATE_MULT :: 1.10 // +10% fire rate per pick
WEAPON_UPGRADE_CLIP_BONUS :: 1 // +1 clip capacity per pick

// boosts the current weapon's stats in place; stacks across multiple picks
// over a run (mutation persists via game.player.weapon)
upgrade_weapon :: proc(weapon: ^Weapon) {
	weapon.damage *= WEAPON_UPGRADE_DAMAGE_MULT
	weapon.fire_rate *= WEAPON_UPGRADE_FIRE_RATE_MULT
	weapon.clip_size += WEAPON_UPGRADE_CLIP_BONUS
	weapon.ammo_in_clip += WEAPON_UPGRADE_CLIP_BONUS
}

WEAPON_REFILL_RESERVE_CLIPS :: 2 // clips worth of reserve ammo granted per "Refill Ammo" pick

refill_weapon_reserve :: proc(weapon: ^Weapon) {
	weapon.reserve_ammo += weapon.clip_size * WEAPON_REFILL_RESERVE_CLIPS
}

try_fire_weapon :: proc(weapon: ^Weapon, origin, aim_dir: Vec2) {
	if weapon.reload_timer > 0 || weapon.cooldown_timer > 0 {
		return
	}

	if weapon.ammo_in_clip <= 0 {
		start_reload(weapon)
		return
	}

	weapon.ammo_in_clip -= 1
	weapon.cooldown_timer = 1.0 / weapon.fire_rate

	fire_pellets(weapon^, origin, aim_dir)

	if weapon.ammo_in_clip <= 0 {
		start_reload(weapon)
	}
}
