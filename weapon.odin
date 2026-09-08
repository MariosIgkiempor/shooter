package shooter

import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

Weapon_Kind :: enum {
	Pistol,
	SMG,
	Shotgun,
	// placeholder melee content so try_swing_melee (ticket 03) and the
	// weapon-family cycle below are actually usable for testing - real tier-ladder
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
	kind:        Weapon_Kind,
	fire_mode:   Fire_Mode,
	damage:      f32, // per bullet/pellet/swing/cast
	action_rate: f32, // actions/sec; cooldown between actions is 1/action_rate
	// runtime countdown, not persisted (json:"-") - unlike windup_timer below,
	// cooldown_timer crossing zero has no side effect of its own, but it's
	// excluded for the same reason: it's transient/frame-driven state, not
	// saved content
	cooldown_timer: f32 `json:"-"`,

	// Windup/Follow-through (see CONTEXT.md, ADR-0003/0004): exactly one of
	// these two pairs is ever nonzero for a given Weapon_Kind, decided
	// entirely by fire_mode. windup_fraction is a proportion of the cycle,
	// not a fixed duration, so it stays nested inside 1/action_rate no
	// matter how much action_rate has grown from upgrades (ADR-0004) -
	// windup_timer's actual seconds are derived fresh at Trigger as
	// windup_fraction/action_rate. follow_through_time has no equivalent
	// invariant to protect (purely cosmetic), so it stays a fixed duration -
	// the generalized, Weapon-level successor to Melee_Weapon's old
	// swing_time/swing_timer. windup_timer/follow_through_timer are tagged
	// json:"-": unlike cooldown_timer, windup_timer crossing zero now has a
	// real side effect (resolve_weapon_action) - restoring a positive
	// windup_timer from a save would fire that weapon on its own on the
	// first post-load frame, with no Trigger from the player.
	windup_fraction:      f32, // 0..1, Semi_Automatic only
	windup_timer:         f32 `json:"-"`,
	follow_through_time:  f32, // seconds, Automatic only
	follow_through_timer: f32 `json:"-"`,

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
	reload_time:      f32,
	reload_timer:     f32, // > 0 while reloading
	pellet_count:     int, // 1 for pistol/SMG, >1 for shotgun-style spread
	spread_angle:     f32, // degrees, total cone width across pellets
	bullet_lifetime:  f32,
}

Melee_Weapon :: struct {
	range:       f32, // max distance from origin a swing's arc reaches
	arc_degrees: f32, // total cone width, centered on aim_dir
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
	// captured from mouse_world at Trigger, not Resolve (ADR-0005): unlike
	// aim_dir-based casts, a ground-targeted cast locks in the instant the
	// player commits rather than tracking the mouse live through Windup.
	// Stays on Magic rather than the common Weapon struct - this is specific
	// to Poison_Cloud's targeting model, not a cross-variant Fire_Mode
	// concern like windup_fraction/follow_through_time. Tagged json:"-" even
	// though Magic is embedded directly in Weapon_Variant_Save (unlike the
	// live variant): it's transient/frame-driven runtime state, not saved
	// content, same as windup_timer.
	locked_target: Vec2 `json:"-"`,
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
		windup_fraction = 0.24,
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
		follow_through_time = 0.045,
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
		// reads heavier than Pistol purely because its cycle is ~2.7x longer
		// at a similar fraction - no separate escalation mechanism needed
		windup_fraction = 0.26,
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
		follow_through_time = 0.15, // carried over unchanged from the old swing_time
		variant = Melee_Weapon{range = 40, arc_degrees = 70},
	},
	.Sword = {
		kind = .Sword,
		fire_mode = .Semi_Automatic,
		damage = 30,
		action_rate = 1.8,
		windup_fraction = 0.37,
		variant = Melee_Weapon{range = 60, arc_degrees = 110},
	},
	.Fire_Wand = {
		kind = .Fire_Wand,
		fire_mode = .Semi_Automatic,
		damage = 35, // direct hit + explosion both use this
		action_rate = 1.2,
		windup_fraction = 0.21,
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
		// discrete per-tick pulse, not a continuous stream - a continuous
		// stream was prototyped and read worse at this tick rate
		follow_through_time = 0.08,
		variant = Magic{spell_kind = .Flamethrower, range = 50, arc_degrees = 50},
	},
	.Poison_Staff = {
		kind = .Poison_Staff,
		fire_mode = .Semi_Automatic, // one click, one cloud - not holdable
		damage = 4, // per tick
		action_rate = 0.5, // 2s between casts
		windup_fraction = 0.18,
		variant = Magic {
			spell_kind = .Poison_Cloud,
			cast_range = 90,
			cloud_radius = 28,
			cloud_duration = 5,
			cloud_tick_rate = 2,
		},
	},
}

// weapon shape dimensions/colors by family (art-revamp ticket 02): distinct
// silhouette per family, not per-kind - Gun = thin rod, Melee = wedge/blade,
// Magic = rod with a circular orb tip. Colors lean metal-toned for the
// physical weapons (a tone the Ammo indicator's glyph still echoes) and
// warm/glowy for Magic's orb.
WEAPON_GUN_COLOR :: rl.Color{180, 180, 190, 255}
WEAPON_MELEE_COLOR :: rl.Color{210, 210, 220, 255}
WEAPON_MAGIC_ROD_COLOR :: rl.Color{110, 80, 150, 255}
WEAPON_MAGIC_ORB_COLOR :: rl.Color{255, 205, 90, 255}

// -- per-kind visual identity (ADR-0018) ------------------------------------
//
// The eight weapons are eight distinct silhouettes, in the world as well as
// in the UI, and their effects share the family's *shapes* while varying in
// *magnitude* per kind - a Pistol's muzzle flash is smaller than a
// Shotgun's. The geometry itself lives in icon.odin (weapon_icons); this
// table is only how big each one draws and how hard each one hits the
// screen.
//
// Deliberately NOT stored on Weapon. Weapon is serialized into
// data/game_save.json, so a stored copy would bake art into save data: a
// player who saved before a retune would keep the old silhouette, and a
// save predating the fields would decode them as zero - an invisible weapon,
// silently, with no error. Derived from `kind` at draw time instead, the
// same way draw_weapon already reads the live upgrade-scaled
// Melee_Weapon.range rather than a stored copy. See ADR-0018 and ADR-0007.
Weapon_Visual :: struct {
	// world side of the glyph's unit square, in px, for Gun and Magic.
	// Melee ignores it: its size comes from Melee_Weapon.range, because a
	// blade's drawn length is *reporting* its actual reach, not decorating
	// it - see weapon_world_frame_size.
	length:                f32,
	muzzle_streak_count:   int,
	muzzle_spread_degrees: f32,
	muzzle_flash_radius:   f32,
	// motion-trail echoes behind a melee swing: several fading copies of the
	// same blade sampled earlier on the swing curve. Zero for a weapon that
	// shouldn't leave one, which is how Dagger stays a quick jab while Sword
	// reads as a heavy sweep - previously a hardcoded `kind == .Sword` check
	// in draw_weapon.
	swing_echo_count:      int,
}

weapon_visuals: [Weapon_Kind]Weapon_Visual = {
	// Ranged: the ladder reads as it climbs - a compact sidearm, a longer
	// SMG, then the Shotgun's broad twin-barrel with the biggest report
	.Pistol       = {length = 30, muzzle_streak_count = 3, muzzle_spread_degrees = 16, muzzle_flash_radius = 10},
	.SMG          = {length = 34, muzzle_streak_count = 4, muzzle_spread_degrees = 22, muzzle_flash_radius = 12},
	.Shotgun      = {length = 38, muzzle_streak_count = 7, muzzle_spread_degrees = 34, muzzle_flash_radius = 18},

	// Melee: `length` unused (range supplies it). Only Sword trails echoes.
	.Dagger       = {swing_echo_count = 0},
	.Sword        = {swing_echo_count = 3},

	// Magic: the flash is a cast effect rather than a muzzle report, so the
	// streak burst stays at zero for all three - their family vocabulary is
	// the flash and the tick burst, not streaks
	.Fire_Wand    = {length = 30, muzzle_flash_radius = 13},
	.Flame_Staff  = {length = 34, muzzle_flash_radius = 9},
	.Poison_Staff = {length = 32, muzzle_flash_radius = 15},
}

// global multiplier on every weapon's drawn size, driven live by the F8
// debug panel's slider so silhouettes can be judged in motion at gameplay
// zoom rather than argued about statically (ADR-0018). Applies to Gun and
// Magic only: scaling a melee blade would decouple its drawn length from
// the reach it is reporting, making the silhouette lie about its hit arc.
weapon_visual_scale: f32 = 1
// alpha of the one-shot muzzle flash disc, 0..1
MUZZLE_FLASH_ALPHA: f32 = 0.8

WEAPON_VISUAL_SCALE_MIN :: 0.4
WEAPON_VISUAL_SCALE_MAX :: 2.5

// the side, in px, of the unit square draw_weapon maps a weapon's glyph
// onto. For Melee this is derived from the live `range` so the blade's tip
// lands exactly at the weapon's actual reach - weapon_icon_reach says where
// along the glyph that kind's business end sits, so a Dagger (tip at 0.80)
// and a Sword (0.92) both point at their real range rather than short of it.
weapon_world_frame_size :: proc(weapon: Weapon) -> f32 {
	if melee, is_melee := weapon.variant.(Melee_Weapon); is_melee {
		reach := weapon_icon_reach[weapon.kind]
		if reach <= 0 {
			return melee.range
		}
		return melee.range / reach
	}
	return weapon_visuals[weapon.kind].length * weapon_visual_scale
}

// hud.odin's Shop panel weapon-tier-ladder button labels
weapon_display_name: [Weapon_Kind]string = {
	.Pistol       = "Pistol",
	.SMG          = "SMG",
	.Shotgun      = "Shotgun",
	.Dagger       = "Dagger",
	.Sword        = "Sword",
	.Fire_Wand    = "Fire Wand",
	.Flame_Staff  = "Flame Staff",
	.Poison_Staff = "Poison Staff",
}

weapon_create :: proc(kind: Weapon_Kind) -> Weapon {
	w := weapon_presets[kind]
	// reapplies owned Account_Stat allocations and Upgrade stacks onto the
	// fresh preset baseline (ADR-0007) - a no-op for whichever is empty.
	// Every caller is responsible for game.player.upgrade_stacks already
	// holding the right value before calling this (initialize_default_game_state
	// explicitly zeroes it first, start_new_run likewise, and the Shop/load
	// paths only ever call this after upgrade_stacks is already correct) -
	// weapon_create itself has no Player to read a "should be zero here"
	// invariant from.
	apply_upgrades(&w, game.player.upgrade_stacks, game.player.account_stat_stacks)
	switch &v in w.variant {
	case Gun:
		v.ammo_in_clip = v.clip_size
	case Melee_Weapon, Magic: // no runtime init yet - tickets 03/04
	}
	return w
}

// runs every frame regardless of Trigger: ticks cooldown_timer down as
// before, ticks windup_timer down and calls resolve_weapon_action the
// instant it crosses to <=0 (exactly once - the `> 0` guard only lets a
// weapon in Winding Up reach the inner check at all), and ticks
// follow_through_timer down with no side effect (purely cosmetic). Callers
// must pass this frame's freshly-computed origin/aim_dir/mouse_world so a
// Resolve on Windup completion always fires against current-frame aim state,
// not whatever was live at Trigger.
update_weapon :: proc(weapon: ^Weapon, dt: f32, origin, aim_dir, mouse_world: Vec2, enemies: []Enemy) {
	if weapon.cooldown_timer > 0 {
		weapon.cooldown_timer -= dt
	}

	if weapon.windup_timer > 0 {
		weapon.windup_timer -= dt
		if weapon.windup_timer <= 0 {
			resolve_weapon_action(weapon, origin, aim_dir, mouse_world, enemies)
		}
	}

	if weapon.follow_through_timer > 0 {
		weapon.follow_through_timer -= dt
	}

	switch &v in weapon.variant {
	case Gun:
		if v.reload_timer > 0 {
			v.reload_timer -= dt
			if v.reload_timer <= 0 {
				// a reload refills the clip outright - there is no reserve to
				// draw from, so reload_time is the whole of what a reload
				// costs (CONTEXT.md's Weapon variants entry)
				v.ammo_in_clip = v.clip_size
			}
		}
	case Melee_Weapon, Magic:
	}
}

start_reload :: proc(weapon: ^Weapon) {
	switch &v in weapon.variant {
	case Gun:
		if v.reload_timer > 0 || v.ammo_in_clip == v.clip_size {
			return
		}
		v.reload_timer = v.reload_time
	case Melee_Weapon, Magic: // no reload concept
	}
}

// 0 the instant a weapon fires, ramping back to 1 as cooldown_timer counts
// down to Ready (see CONTEXT.md's Weapon readiness entry) - drives the
// player's Cooldown indicator (Melee_Weapon/Magic secondary Resource
// indicator, resource_indicator.odin, ADR-0011). Recomputes cooldown_duration
// from the *current* action_rate every frame, same tradeoff as
// weapon_windup_progress above: an action_rate upgrade picked up mid-cooldown
// would skew this frame's fraction against the untouched cooldown_timer it
// started from; purely a cosmetic wobble on a display-only value, not a
// Resolve-correctness issue, since cooldown_timer itself never depends on
// this.
weapon_ready_fraction :: proc(weapon: Weapon) -> f32 {
	if weapon.action_rate <= 0 {
		return 1
	}
	cooldown_duration := 1.0 / weapon.action_rate
	return clamp(1 - weapon.cooldown_timer / cooldown_duration, 0, 1)
}

// Trigger-time entry point (a press for Semi_Automatic, each re-fire tick
// while held for Automatic - see CONTEXT.md's Trigger entry). Gates on the
// shared cooldown. Semi_Automatic weapons only start the cycle here
// (cooldown_timer/windup_timer, both from the same instant - "nested inside
// cooldown" requires they start together, not staggered) and return without
// resolving; Automatic weapons resolve immediately via resolve_weapon_action,
// unchanged from pre-Windup behavior, and start Follow-through if the action
// succeeded. Once a Windup starts it always completes into Resolve - there is
// no cancel-by-releasing-early path (see CONTEXT.md's Windup entry).
try_use_weapon :: proc(weapon: ^Weapon, origin, aim_dir, mouse_world: Vec2, enemies: []Enemy) {
	if weapon.cooldown_timer > 0 {
		return
	}

	if weapon.fire_mode == .Semi_Automatic {
		// Gun-specific: an empty clip gates Windup starting at all (mirrors
		// try_fire_gun's own gate below, via the shared gun_can_fire helper)
		// - neither timer starts, start_reload runs exactly as it does
		// today, nothing plays. Melee_Weapon/Magic have no equivalent
		// resource gate and always start Windup unconditionally.
		switch &v in weapon.variant {
		case Gun:
			if !gun_can_fire(v) {
				start_reload(weapon)
				return
			}
		case Melee_Weapon, Magic:
		}

		lock_poison_cloud_target(weapon, origin, mouse_world)

		weapon.cooldown_timer = 1.0 / weapon.action_rate
		weapon.windup_timer = weapon.windup_fraction / weapon.action_rate

		// a zero-length Windup (windup_fraction == 0) has already "completed"
		// the instant it starts - update_weapon's `windup_timer > 0` guard
		// only fires on the > 0 -> <= 0 transition, so it would otherwise
		// never see this Windup and never resolve it at all
		if weapon.windup_timer <= 0 {
			resolve_weapon_action(weapon, origin, aim_dir, mouse_world, enemies)
		}
		return
	}

	if resolve_weapon_action(weapon, origin, aim_dir, mouse_world, enemies) {
		weapon.cooldown_timer = 1.0 / weapon.action_rate
		weapon.follow_through_timer = weapon.follow_through_time
	}
}

// extracted from try_use_weapon's old inline variant-dispatch switch so it's
// callable from two sites: try_use_weapon directly (Automatic weapons resolve
// on Trigger) and update_weapon (Semi_Automatic weapons resolve on Windup
// completion). Magic's Poison_Cloud reads its Trigger-locked target instead
// of live mouse_world (ADR-0005); everything else aiming along aim_dir (Gun,
// Melee_Weapon, Fireball, Flamethrower) keeps tracking live, so a Resolve may
// whiff if the target moved or died since Trigger.
resolve_weapon_action :: proc(weapon: ^Weapon, origin, aim_dir, mouse_world: Vec2, enemies: []Enemy) -> bool {
	// projectiles and muzzle effects come out of the weapon's far end, not
	// the player's feet anchor - see weapon_muzzle_position. Hit-checks below
	// (melee arc, flamethrower cone, Poison_Cloud range) keep using `origin`,
	// so reach is unchanged.
	muzzle := weapon_muzzle_position(weapon^, origin, aim_dir)

	switch &v in weapon.variant {
	case Gun:
		return try_fire_gun(weapon, &v, muzzle, aim_dir)
	case Melee_Weapon:
		return try_swing_melee(&v, weapon.damage, origin, aim_dir, enemies)
	case Magic:
		target := mouse_world
		if v.spell_kind == .Poison_Cloud {
			target = v.locked_target
		}
		return try_cast_magic(&v, weapon_visuals[weapon.kind], weapon.damage, origin, aim_dir, muzzle, target, enemies)
	}
	return false
}

// captures mouse_world into Magic's locked_target the instant Windup starts,
// for Poison_Cloud specifically - a no-op for every other weapon/spell.
// Ground-targeted casts commit their target at Trigger rather than tracking
// the mouse live through Windup like everything aim_dir-based does (see
// ADR-0005): the natural mental model for a discrete point pick is that the
// choice is locked in once made.
lock_poison_cloud_target :: proc(weapon: ^Weapon, origin, mouse_world: Vec2) {
	switch &v in weapon.variant {
	case Magic:
		if v.spell_kind == .Poison_Cloud {
			v.locked_target = clamp_point_to_range(origin, mouse_world, v.cast_range)
		}
	case Gun, Melee_Weapon:
	}
}

// 0 at Trigger -> 1 the instant Windup completes (and clamped to 1 whenever
// there's no Windup in flight), shared by draw_weapon's pullback (main.odin)
// and update_magic_cast_particles below so the windup_fraction/action_rate
// derivation (ADR-0004) is expressed once. Recomputes windup_duration from
// the *current* action_rate every frame, same as windup_timer's own
// derivation at Trigger - stable across a Windup for every reachable path
// today, but an action_rate upgrade picked up mid-Windup (e.g. via the
// level-up modal) would skew this frame's progress against the untouched
// windup_timer it started from; purely a cosmetic wobble, not a
// Resolve-correctness issue, since windup_timer itself never depends on this.
weapon_windup_progress :: proc(weapon: Weapon) -> f32 {
	if weapon.windup_timer <= 0 {
		return 1
	}
	windup_duration := weapon.windup_fraction / weapon.action_rate
	if windup_duration <= 0 {
		return 1
	}
	return clamp(1 - weapon.windup_timer / windup_duration, 0, 1)
}

// -- muzzle geometry -------------------------------------------------------
//
// The `origin` threaded through try_use_weapon/update_weapon is the player's
// bottom-center anchor - where they *stand* (see actor_collision_rect's note,
// main.odin), not where the weapon *points from*. Anything that visually comes
// out of the weapon (bullets, fireballs, muzzle flash/streaks, cast particles)
// must spawn at the far end of the drawn shape instead, or it reads as firing
// out of the player's feet. Gameplay hit-checks (melee/flamethrower arcs,
// Poison_Cloud range clamping) deliberately keep using `origin`, so moving the
// visuals never quietly changes reach.
//
// Deliberately animation-free: draw_weapon's Windup pullback and
// Follow-through recoil displace the drawn pivot on top of this, but both are
// zero at the instant a weapon Resolves, and the recoil that starts right
// after reads correctly as the gun kicking back away from where the shot left.

WEAPON_PIVOT_HEIGHT: f32 = 12 // px above the player's feet anchor (main.odin) - roughly chest height

// the weapon's grip point: chest height on the player's feet anchor. Shared
// with draw_weapon (main.odin) so the shape the player sees and the point its
// effects spawn from can never drift apart.
weapon_pivot_position :: proc(origin: Vec2) -> Vec2 {
	return origin + Vec2{0, -WEAPON_PIVOT_HEIGHT}
}

// the far end of the weapon along aim_dir: a Gun's barrel tip, a Magic rod's
// orb, a Melee blade's tip. Reuses the pair that already answers this for
// drawing - weapon_world_frame_size for how big the glyph is in the world,
// weapon_icon_reach for how far along it that kind's business end sits - so a
// per-kind silhouette retune (ADR-0018) moves the effects with the shape
// automatically, including through the F8 weapon_visual_scale slider.
weapon_muzzle_position :: proc(weapon: Weapon, origin, aim_dir: Vec2) -> Vec2 {
	reach := weapon_world_frame_size(weapon) * weapon_icon_reach[weapon.kind]
	return weapon_pivot_position(origin) + aim_dir * reach
}

// spawns this frame's Magic windup/cast particles (ticket 06's confirmed
// "all three need real new art" finding) - called once per frame from
// update_game (main.odin), after update_weapon, so windup_timer/locked_target
// reflect this frame's state. A no-op for anything that isn't Magic, or for
// a spell_kind with nothing active this frame (no Windup in flight, cone not
// held). One particle per call is intentional: called every frame, so a
// ~150-200ms Windup naturally accumulates a handful of embers/puffs without
// needing a separate spawn-interval timer field.
update_magic_cast_particles :: proc(weapon: Weapon, origin, aim_dir: Vec2, mouse_held: bool) {
	magic, is_magic := weapon.variant.(Magic)
	if !is_magic {
		return
	}

	switch magic.spell_kind {
	case .Fireball:
		if weapon.windup_timer <= 0 {
			return
		}
		progress := weapon_windup_progress(weapon)
		spawn_fire_wand_charge_particle(weapon_muzzle_position(weapon, origin, aim_dir), progress)
	case .Poison_Cloud:
		if weapon.windup_timer <= 0 {
			return
		}
		progress := weapon_windup_progress(weapon)
		spawn_poison_windup_puff(magic.locked_target, magic.cloud_radius, progress)
	case .Flamethrower:
		if !mouse_held {
			return
		}
		spawn_flame_cone_particle(origin, aim_dir, magic.range, magic.arc_degrees)
	}
}

// shared by try_use_weapon's Semi_Automatic Windup-gate and try_fire_gun's
// own Resolve-time check (ticket 02), so the empty-clip/reloading condition
// that decides whether a Gun can act at all is expressed exactly once
gun_can_fire :: proc(gun: Gun) -> bool {
	return gun.reload_timer <= 0 && gun.ammo_in_clip > 0
}

try_fire_gun :: proc(weapon: ^Weapon, gun: ^Gun, muzzle, aim_dir: Vec2) -> bool {
	if !gun_can_fire(gun^) {
		start_reload(weapon)
		return false
	}

	gun.ammo_in_clip -= 1

	fire_pellets(weapon^, gun^, muzzle, aim_dir)
	// muzzle effect (art-revamp ticket 02) - the enhanced particle layer
	// (streak burst + flash) confirmed to supply the "punch" plain
	// icon-transform lacked
	visual := weapon_visuals[weapon.kind]
	spawn_streak_burst(muzzle, aim_dir, visual.muzzle_streak_count, visual.muzzle_spread_degrees, WEAPON_GUN_COLOR)
	spawn_muzzle_flash(muzzle, rl.Fade(rl.WHITE, MUZZLE_FLASH_ALPHA), visual.muzzle_flash_radius)

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
	enemy_box := actor_collision_rect(enemy.rect)
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
// ammo-style failure case like Gun's empty-clip. `enemies` is threaded in
// explicitly rather than read from game.enemies, for consistency with
// origin/aim_dir already being explicit params (ticket 01).
try_swing_melee :: proc(melee: ^Melee_Weapon, damage: f32, origin, aim_dir: Vec2, enemies: []Enemy) -> bool {
	#reverse for enemy, i in enemies {
		if !enemy_in_melee_arc(melee^, origin, aim_dir, enemy) do continue
		apply_hit_to_enemy(i, damage, Vec2{enemy.x, enemy.y})
	}

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
// cooldown_timer gate in try_use_weapon. `target` is live mouse_world for
// aim_dir-based spells, or Poison_Cloud's Trigger-locked point (already
// clamped by lock_poison_cloud_target) - resolve_weapon_action decides which.
// `visual` carries the casting weapon's per-kind effect magnitudes
// (ADR-0018) - Magic has no `kind` of its own, and deriving one back from
// spell_kind would be a second, silently-drifting source of truth.
try_cast_magic :: proc(
	magic: ^Magic,
	visual: Weapon_Visual,
	damage: f32,
	origin, aim_dir, muzzle, target: Vec2,
	enemies: []Enemy,
) -> bool {
	switch magic.spell_kind {
	case .Fireball:
		cast_fireball(magic^, damage, muzzle, aim_dir)
		spawn_muzzle_flash(muzzle, WEAPON_MAGIC_ORB_COLOR, visual.muzzle_flash_radius) // art-revamp ticket 02
	case .Flamethrower:
		cast_flamethrower_tick(magic^, damage, origin, aim_dir, muzzle, enemies)
	case .Poison_Cloud:
		cast_poison_cloud(magic^, damage, target)
		// the flash is the Magic family's own cast primitive, and
		// Poison_Cloud was the one spell with no cast feedback at all -
		// its ground-targeted placement reads as nothing happening
		// otherwise. Same shape as its two siblings, its own magnitude.
		spawn_muzzle_flash(target, ICON_POISON_COLOR, visual.muzzle_flash_radius)
	}
	return true
}

// re-run every Automatic-mode trigger while the mouse is held (try_use_weapon's
// existing cooldown/action_rate gate controls tick rate) - reuses the same
// arc/cone hit-check as melee (ticket 03), just against Magic's own
// range/arc_degrees, hitting every enemy in the cone each tick (cleave, no
// single-target cap). Also fires a cosmetic per-tick particle burst (ticket
// 06's confirmed finding - see spawn_flame_tick_burst) whether or not it hit
// anything, same as the always-on flamethrower cone draw.
cast_flamethrower_tick :: proc(magic: Magic, damage: f32, origin, aim_dir, muzzle: Vec2, enemies: []Enemy) {
	cone := Melee_Weapon{range = magic.range, arc_degrees = magic.arc_degrees}

	#reverse for enemy, i in enemies {
		if !enemy_in_melee_arc(cone, origin, aim_dir, enemy) do continue
		apply_hit_to_enemy(i, damage, Vec2{enemy.x, enemy.y})
	}

	spawn_flame_tick_burst(muzzle)
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

// -- Weapon_Family (see CONTEXT.md's Weapon family entry and ADR-0008) -----
//
// Purely descriptive of whichever Weapon is currently equipped - the player
// picks any weapon fresh at the start of every Run (main.odin's Run_Start
// screen, hud.odin's draw_run_start_ui), so nothing on Player stores a
// family directly; it's always derived via weapon_kind_family from
// game.player.weapon.kind. weapon_family_kinds[family][0] becomes a fresh
// Run's starting weapon when that family is picked; weapon_kind_family is
// also the reverse lookup dev/debug weapon switching (arrow keys, main.odin)
// uses to stay within the equipped weapon's family while cycling
// Weapon_Kinds for testing - weapon_family_kinds is only a cycle order for
// that debug tool, not the Shop's priced tier ladder (shop.odin).

Weapon_Family :: enum {
	Ranged,
	Melee,
	Magic,
}

// hud.odin's draw_run_start_ui button labels
weapon_family_display_name: [Weapon_Family]string = {
	.Ranged = "Ranged",
	.Melee  = "Melee",
	.Magic  = "Magic",
}

weapon_kind_family: [Weapon_Kind]Weapon_Family = {
	.Pistol  = .Ranged,
	.SMG     = .Ranged,
	.Shotgun = .Ranged,
	.Dagger  = .Melee,
	.Sword   = .Melee,
	.Fire_Wand    = .Magic,
	.Flame_Staff  = .Magic,
	.Poison_Staff = .Magic,
}

weapon_family_kinds: [Weapon_Family][]Weapon_Kind = {
	.Ranged = {.Pistol, .SMG, .Shotgun},
	.Melee  = {.Dagger, .Sword},
	.Magic  = {.Fire_Wand, .Flame_Staff, .Poison_Staff},
}

// steps to the next/previous Weapon_Kind within current's family (wrapping) -
// never crosses into another family
cycle_weapon_kind :: proc(current: Weapon_Kind, delta: int) -> Weapon_Kind {
	kinds := weapon_family_kinds[weapon_kind_family[current]]

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
