package shooter

import "core:math"
import "core:math/linalg"

Weapon_Kind :: enum {
	Pistol,
	SMG,
	Shotgun,
	// placeholder melee content so try_swing_melee (ticket 03) and the Class
	// cycle below are actually usable for testing - real tier-ladder
	// naming/stats for Melee are still content-authoring for a later ticket
	// (map's "Not yet specified")
	Dagger,
	Sword,
	// Magic tier ladder (ticket 11): each tier is a distinct spell, mirroring
	// Ranged's Pistol/SMG/Shotgun being three distinct weapons rather than
	// numeric upgrades of one
	Fire_Wand,
	Flame_Staff,
	Poison_Staff,
}

Fire_Mode :: enum {
	Semi_Automatic,
	Automatic,
}

// which spell a Magic weapon casts - ticket 11 fulfilling the Spell_Kind
// enum ticket 04 anticipated
Spell_Kind :: enum {
	Fireball,
	Flamethrower,
	Poison_Cloud,
}

// Weapon is a wrapper struct, not a bare union like Enemy's Movement_Style/
// Attack_Style: common state (kind/fire_mode/damage/action_rate/
// cooldown_timer) is read directly at existing call sites with no switch
// (main.odin's fire_mode/kind reads), and Odin unions require a
// switch/type-assertion to read any field at all. Type-specific state lives
// behind `variant`. See ADR-0001.
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

Melee_Weapon :: struct {
	range:       f32, // max distance from origin a swing's arc reaches
	arc_degrees: f32, // total cone width, centered on aim_dir
	swing_time:  f32, // cosmetic-only animation duration
	// counts down from swing_time to 0 while the cosmetic swing-sweep
	// animation plays (main.odin's draw_weapon); never gates the hit-check -
	// ticket 03's hit already resolved instantly before this starts (ticket
	// 07's animation requirement)
	swing_timer: f32,
}

// fields cover all three Spell_Kinds; each weapon_presets entry only sets
// the fields its spell_kind actually uses (mirrors Gun's pellet_count/
// spread_angle being pistol/SMG-irrelevant but shotgun-relevant)
Magic :: struct {
	spell_kind: Spell_Kind,

	// Fireball: travels like a Bullet (bullet.odin's cast_fireball), explodes
	// into an AoE on impact instead of a single-target hit
	projectile_speed: f32,
	bullet_lifetime:  f32,
	explosion_radius: f32,

	// Flamethrower: instant cone hit-check re-run every Automatic-mode tick
	// while held (cast_flamethrower_tick below), reusing melee's arc-check
	range:       f32,
	arc_degrees: f32,

	// Poison Cloud: ground-targeted lingering DoT zone (poison_cloud.odin)
	cast_range:      f32, // max distance from the player it can be placed
	cloud_radius:    f32,
	cloud_duration:  f32,
	cloud_tick_rate: f32, // damage ticks/sec for enemies standing inside
}

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
	.Dagger = {
		kind = .Dagger,
		fire_mode = .Automatic, // hold to spam quick swings
		damage = 15,
		action_rate = 4,
		variant = Melee_Weapon{range = 40, arc_degrees = 70, swing_time = 0.15},
	},
	.Sword = {
		kind = .Sword,
		fire_mode = .Semi_Automatic,
		damage = 30,
		action_rate = 1.8,
		variant = Melee_Weapon{range = 60, arc_degrees = 110, swing_time = 0.35},
	},
	.Fire_Wand = {
		kind = .Fire_Wand,
		fire_mode = .Semi_Automatic,
		damage = 35, // direct hit + explosion both use this
		action_rate = 1.2,
		variant = Magic {
			spell_kind = .Fireball,
			projectile_speed = 300,
			bullet_lifetime = 1.2,
			explosion_radius = 24,
		},
	},
	.Flame_Staff = {
		kind = .Flame_Staff,
		fire_mode = .Automatic, // hold to channel
		damage = 6, // per tick
		action_rate = 10, // ticks/sec while held
		variant = Magic{spell_kind = .Flamethrower, range = 50, arc_degrees = 50},
	},
	.Poison_Staff = {
		kind = .Poison_Staff,
		fire_mode = .Semi_Automatic, // one click, one cloud - not holdable
		damage = 4, // per tick
		action_rate = 0.5, // 2s between casts
		variant = Magic {
			spell_kind = .Poison_Cloud,
			cast_range = 90,
			cloud_radius = 28,
			cloud_duration = 5,
			cloud_tick_rate = 2,
		},
	},
}

weapon_texture_names: [Weapon_Kind]Texture_Name = {
	.Pistol  = .Weapon_Pistol,
	.SMG     = .Weapon_Smg,
	.Shotgun = .Weapon_Shotgun,
	.Dagger  = .Weapon_Dagger,
	.Sword   = .Weapon_Sword,
	// no magic art yet - reusing the pistol icon as a placeholder for all
	// three, same as the old single Wand did
	.Fire_Wand    = .Weapon_Pistol,
	.Flame_Staff  = .Weapon_Pistol,
	.Poison_Staff = .Weapon_Pistol,
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
	case Melee_Weapon:
		if v.swing_timer > 0 {
			v.swing_timer -= dt
		}
	case Magic: // nothing yet - ticket 04
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
try_use_weapon :: proc(weapon: ^Weapon, origin, aim_dir, mouse_world: Vec2) {
	if weapon.cooldown_timer > 0 {
		return
	}

	acted: bool
	switch &v in weapon.variant {
	case Gun:
		acted = try_fire_gun(weapon, &v, origin, aim_dir)
	case Melee_Weapon:
		acted = try_swing_melee(&v, weapon.damage, origin, aim_dir)
	case Magic:
		acted = try_cast_magic(&v, weapon.damage, origin, aim_dir, mouse_world)
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

// true if enemy is within melee's arc/cone: inside range (plus a fudge for
// the enemy's own collision size, derived from its existing collision rect -
// Enemy has no dedicated radius field) and within arc_degrees/2 of aim_dir.
// Mirrors Gun.spread_angle's cone-around-aim_dir idea, reused for hit
// detection instead of pellet fan-out.
enemy_in_melee_arc :: proc(melee: Melee_Weapon, origin, aim_dir: Vec2, enemy: Enemy) -> bool {
	enemy_box := actor_collision_rect(enemy.rect, enemy.animation)
	enemy_radius := max(enemy_box.width, enemy_box.height) / 2

	to_enemy := Vec2{enemy.x, enemy.y} - origin
	dist := linalg.length(to_enemy)
	if dist > melee.range + enemy_radius {
		return false
	}

	direction_to_enemy := linalg.normalize0(to_enemy)
	angle_to_enemy := math.to_degrees(math.acos(clamp(linalg.dot(aim_dir, direction_to_enemy), -1, 1)))

	return angle_to_enemy <= melee.arc_degrees / 2
}

// resolves the swing instantly and synchronously - no active-frame window to
// guard, so there's no per-swing "already hit" flag to manage. A single pass
// gathers every enemy in the arc (cleave), applying the hit to each via the
// same apply_hit_to_enemy pipeline bullets use, so death handling is never
// duplicated between weapon types. Always "acts" once triggered - no
// ammo-style failure case like Gun's empty-clip.
try_swing_melee :: proc(melee: ^Melee_Weapon, damage: f32, origin, aim_dir: Vec2) -> bool {
	#reverse for enemy, i in game.enemies {
		if !enemy_in_melee_arc(melee^, origin, aim_dir, enemy) do continue
		apply_hit_to_enemy(i, damage, Vec2{enemy.x, enemy.y})
	}

	melee.swing_timer = melee.swing_time

	return true
}

// resolves the cast instantly and synchronously, exactly like try_swing_melee/
// try_fire_gun - no active-cast/channel window, no state on Magic beyond its
// fixed preset fields. Dispatches on spell_kind (ticket 11, fulfilling
// ticket 04's anticipated interface); any effect that needs to persist
// beyond this frame spawns its own tracked entity the way fire_pellets
// spawns Bullets (fireball reuses Bullet directly; poison cloud gets its own
// Poison_Cloud array), rather than being represented here. Always "acts"
// once triggered - no ammo/cooldown-style failure case beyond the shared
// cooldown_timer gate in try_use_weapon.
try_cast_magic :: proc(magic: ^Magic, damage: f32, origin, aim_dir, mouse_world: Vec2) -> bool {
	switch magic.spell_kind {
	case .Fireball:
		cast_fireball(magic^, damage, origin, aim_dir)
	case .Flamethrower:
		cast_flamethrower_tick(magic^, damage, origin, aim_dir)
	case .Poison_Cloud:
		// ground-targeted at the mouse rather than a fixed point along
		// aim_dir (ticket 11) - the one spell that breaks from the
		// aim_dir-targeting model the others share - clamped so it can't be
		// dropped anywhere on screen regardless of player position
		target := clamp_point_to_range(origin, mouse_world, magic.cast_range)
		cast_poison_cloud(magic^, damage, target)
	}
	return true
}

// re-run every Automatic-mode trigger while the mouse is held (try_use_weapon's
// existing cooldown/action_rate gate controls tick rate) - reuses the same
// arc/cone hit-check as melee (ticket 03), just against Magic's own
// range/arc_degrees, hitting every enemy in the cone each tick (cleave, no
// single-target cap)
cast_flamethrower_tick :: proc(magic: Magic, damage: f32, origin, aim_dir: Vec2) {
	cone := Melee_Weapon{range = magic.range, arc_degrees = magic.arc_degrees}

	#reverse for enemy, i in game.enemies {
		if !enemy_in_melee_arc(cone, origin, aim_dir, enemy) do continue
		apply_hit_to_enemy(i, damage, Vec2{enemy.x, enemy.y})
	}
}

// clamps `target` to at most `max_range` from `origin`, preserving direction -
// caps Poison Cloud placement so it can't be dropped anywhere on screen
// regardless of player position (ticket 11)
clamp_point_to_range :: proc(origin, target: Vec2, max_range: f32) -> Vec2 {
	offset := target - origin
	dist := linalg.length(offset)
	if dist <= max_range || dist == 0 {
		return target
	}
	return origin + offset * (max_range / dist)
}

// -- dev/debug weapon switching (arrow keys, main.odin) -------------------
//
// A quick way to reach every Weapon_Kind for testing, ahead of the real
// Class-locked Shop/tier-ladder progression (tickets 08/10). `Class` and
// weapon_kind_class are the same lookup table those tickets already
// anticipated needing (see CONTEXT.md's Class entry and ADR-0002); this is
// just an early, informal user of it. class_weapon_kinds is only a cycle
// order for this debug tool, not ticket 10's priced tier ladder.

Class :: enum {
	Ranged,
	Melee,
	Magic,
}

weapon_kind_class: [Weapon_Kind]Class = {
	.Pistol  = .Ranged,
	.SMG     = .Ranged,
	.Shotgun = .Ranged,
	.Dagger  = .Melee,
	.Sword   = .Melee,
	.Fire_Wand    = .Magic,
	.Flame_Staff  = .Magic,
	.Poison_Staff = .Magic,
}

class_weapon_kinds: [Class][]Weapon_Kind = {
	.Ranged = {.Pistol, .SMG, .Shotgun},
	.Melee  = {.Dagger, .Sword},
	.Magic  = {.Fire_Wand, .Flame_Staff, .Poison_Staff},
}

// steps to the next/previous Weapon_Kind within current's class (wrapping)
cycle_weapon_kind :: proc(current: Weapon_Kind, delta: int) -> Weapon_Kind {
	kinds := class_weapon_kinds[weapon_kind_class[current]]

	index := 0
	for k, i in kinds {
		if k == current {
			index = i
			break
		}
	}

	n := len(kinds)
	return kinds[((index + delta) % n + n) % n]
}

// steps to the next/previous Class (wrapping), equipping that class's first
// Weapon_Kind
cycle_class :: proc(current: Weapon_Kind, delta: int) -> Weapon_Kind {
	n := len(class_weapon_kinds)
	current_class := int(weapon_kind_class[current])
	next_class := Class(((current_class + delta) % n + n) % n)
	return class_weapon_kinds[next_class][0]
}
