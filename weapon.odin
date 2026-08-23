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

// Weapon is a wrapper struct, not a bare union like Enemy_Behaviour: common
// state (kind/fire_mode/damage/action_rate/cooldown_timer) is read directly
// at existing call sites with no switch (main.odin's fire_mode/kind reads),
// and Odin unions require a switch/type-assertion to read any field at all.
// Type-specific state lives behind `variant`. See ADR-0001.
Weapon :: struct {
	kind:           Weapon_Kind,
	fire_mode:      Fire_Mode,
	damage:         f32, // per bullet/pellet/swing/cast
	action_rate:    f32, // actions/sec; cooldown between actions is 1/action_rate
	cooldown_timer: f32,

	// tagged json:"-": core:encoding/json decodes a union by trying each
	// variant in declaration order and keeping the first one that parses
	// without error, and every struct field is optional on decode - so a
	// lone `{}` would "succeed" as any variant (same hazard documented at
	// enemy.odin:23-32). `variant` is never passed to json.marshal/
	// json.unmarshal directly; persistence goes through the plain
	// Weapon_Variant_Save DTO instead (see weapon_variant_to_save/
	// weapon_variant_from_save below and Player.weapon_variant_save in
	// main.odin).
	variant: Weapon_Variant `json:"-"`,
}

Weapon_Variant :: union {
	Gun,
	Melee_Weapon,
	Magic,
}

Gun :: struct {
	projectile_speed: f32,
	clip_size:        int,
	ammo_in_clip:     int,
	reserve_ammo:     int, // ammo available to reload from; depletes and is not auto-refilled
	reload_time:      f32,
	reload_timer:     f32, // > 0 while reloading
	pellet_count:     int, // 1 for pistol/SMG, >1 for shotgun-style spread
	spread_angle:     f32, // degrees, total cone width across pellets
	bullet_lifetime:  f32,
}

// no runtime state yet - swing/cast mechanics land in tickets 03/04
Melee_Weapon :: struct {}
Magic :: struct {}

// discriminant for Weapon_Variant_Save; internal to persistence, unrelated
// to the gameplay Weapon_Kind enum (Pistol/SMG/Shotgun/...)
Weapon_Variant_Kind :: enum {
	Gun,
	Melee,
	Magic,
}

// plain (non-union) persisted shape of Weapon.variant. Being a struct, not a
// union, json.unmarshal never runs its variant-guessing loop on it at all -
// converting to/from the real Weapon_Variant union happens explicitly via
// weapon_variant_to_save/weapon_variant_from_save, switching on the decoded
// `kind` field.
Weapon_Variant_Save :: struct {
	kind:  Weapon_Variant_Kind,
	gun:   Maybe(Gun) `json:"gun,omitempty"`,
	melee: Maybe(Melee_Weapon) `json:"melee,omitempty"`,
	magic: Maybe(Magic) `json:"magic,omitempty"`,
}

weapon_variant_to_save :: proc(variant: Weapon_Variant) -> Weapon_Variant_Save {
	switch v in variant {
	case Gun:
		return {kind = .Gun, gun = v}
	case Melee_Weapon:
		return {kind = .Melee, melee = v}
	case Magic:
		return {kind = .Magic, magic = v}
	}
	unreachable()
}

// explicit switch on the decoded `kind` - never lets json.unmarshal's
// union-variant-guessing loop run, since a Weapon_Variant is never the
// direct target of json.unmarshal; only Weapon_Variant_Save is.
weapon_variant_from_save :: proc(s: Weapon_Variant_Save) -> Weapon_Variant {
	switch s.kind {
	case .Gun:
		return s.gun.? or_else Gun{}
	case .Melee:
		return s.melee.? or_else Melee_Weapon{}
	case .Magic:
		return s.magic.? or_else Magic{}
	}
	return Gun{} // unreachable: s.kind is always one of the above
}

weapon_presets: [Weapon_Kind]Weapon = {
	.Pistol = {
		kind = .Pistol,
		fire_mode = .Semi_Automatic,
		damage = 25,
		action_rate = 3,
		variant = Gun {
			projectile_speed = 400,
			clip_size = 12,
			reload_time = 1.2,
			pellet_count = 1,
			spread_angle = 0,
			bullet_lifetime = 1.5,
		},
	},
	.SMG = {
		kind = .SMG,
		fire_mode = .Automatic,
		damage = 10,
		action_rate = 12,
		variant = Gun {
			projectile_speed = 500,
			clip_size = 30,
			reload_time = 1.8,
			pellet_count = 1,
			spread_angle = 4,
			bullet_lifetime = 1.2,
		},
	},
	.Shotgun = {
		kind = .Shotgun,
		fire_mode = .Semi_Automatic,
		damage = 8,
		action_rate = 1.1,
		variant = Gun {
			projectile_speed = 350,
			clip_size = 6,
			reload_time = 2.2,
			pellet_count = 8,
			spread_angle = 28,
			bullet_lifetime = 0.6,
		},
	},
}

weapon_texture_names: [Weapon_Kind]Texture_Name = {
	.Pistol  = .Weapon_Pistol,
	.SMG     = .Weapon_Smg,
	.Shotgun = .Weapon_Shotgun,
}

WEAPON_STARTING_RESERVE_CLIPS :: 69420 // clips worth of reserve ammo a fresh weapon starts with

weapon_create :: proc(kind: Weapon_Kind) -> Weapon {
	w := weapon_presets[kind]
	switch &v in w.variant {
	case Gun:
		v.ammo_in_clip = v.clip_size
		v.reserve_ammo = v.clip_size * WEAPON_STARTING_RESERVE_CLIPS
	case Melee_Weapon, Magic: // no runtime init yet - tickets 03/04
	}
	return w
}

update_weapon :: proc(weapon: ^Weapon, dt: f32) {
	if weapon.cooldown_timer > 0 {
		weapon.cooldown_timer -= dt
	}

	switch &v in weapon.variant {
	case Gun:
		if v.reload_timer > 0 {
			v.reload_timer -= dt
			if v.reload_timer <= 0 {
				new_ammo := min(v.clip_size, v.ammo_in_clip + v.reserve_ammo)
				v.reserve_ammo -= new_ammo - v.ammo_in_clip
				v.ammo_in_clip = new_ammo
			}
		}
	case Melee_Weapon, Magic: // nothing yet - tickets 03/04
	}
}

start_reload :: proc(weapon: ^Weapon) {
	switch &v in weapon.variant {
	case Gun:
		if v.reload_timer > 0 || v.ammo_in_clip == v.clip_size || v.reserve_ammo <= 0 {
			return
		}
		v.reload_timer = v.reload_time
	case Melee_Weapon, Magic: // no reload concept
	}
}

WEAPON_UPGRADE_DAMAGE_MULT :: 1.15 // +15% damage per pick
WEAPON_UPGRADE_ACTION_RATE_MULT :: 1.10 // +10% action rate per pick
WEAPON_UPGRADE_CLIP_BONUS :: 1 // +1 clip capacity per pick

// boosts the current weapon's stats in place; stacks across multiple picks
// over a run (mutation persists via game.player.weapon)
upgrade_weapon :: proc(weapon: ^Weapon) {
	weapon.damage *= WEAPON_UPGRADE_DAMAGE_MULT
	weapon.action_rate *= WEAPON_UPGRADE_ACTION_RATE_MULT

	switch &v in weapon.variant {
	case Gun:
		v.clip_size += WEAPON_UPGRADE_CLIP_BONUS
		v.ammo_in_clip += WEAPON_UPGRADE_CLIP_BONUS
	case Melee_Weapon, Magic: // no clip-equivalent upgrade yet - ticket 06
	}
}

WEAPON_REFILL_RESERVE_CLIPS :: 2 // clips worth of reserve ammo granted per "Refill Ammo" pick

refill_weapon_reserve :: proc(weapon: ^Weapon) {
	switch &v in weapon.variant {
	case Gun:
		v.reserve_ammo += v.clip_size * WEAPON_REFILL_RESERVE_CLIPS
	case Melee_Weapon, Magic: // no reserve-ammo concept
	}
}

// dispatches the weapon's action (fire/swing/cast) by variant, gating on the
// shared cooldown and setting it from action_rate only if something actually
// happened - renamed from try_fire_weapon now that Gun is one of three cases
try_use_weapon :: proc(weapon: ^Weapon, origin, aim_dir: Vec2) {
	if weapon.cooldown_timer > 0 {
		return
	}

	acted: bool
	switch &v in weapon.variant {
	case Gun:
		acted = try_fire_gun(weapon, &v, origin, aim_dir)
	case Melee_Weapon: // ticket 03
	case Magic: // ticket 04
	}

	if acted {
		weapon.cooldown_timer = 1.0 / weapon.action_rate
	}
}

try_fire_gun :: proc(weapon: ^Weapon, gun: ^Gun, origin, aim_dir: Vec2) -> bool {
	if gun.reload_timer > 0 {
		return false
	}

	if gun.ammo_in_clip <= 0 {
		start_reload(weapon)
		return false
	}

	gun.ammo_in_clip -= 1

	fire_pellets(weapon^, gun^, origin, aim_dir)

	if gun.ammo_in_clip <= 0 {
		start_reload(weapon)
	}

	return true
}
