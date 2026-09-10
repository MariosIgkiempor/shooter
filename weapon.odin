package shooter

import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

Weapon_Kind :: enum {
	Pistol,
	SMG,
	Shotgun,
	Rifle,
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
	Lightning_Staff,
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
	Lightning_Bolt,
}

// Weapon is a wrapper struct, not a bare union like Enemy's Movement_Style/
// Attack_Style: common state (kind/fire_mode/damage/action_rate/
// cooldown_timer) is read directly at existing call sites with no switch
// (main.odin's fire_mode/kind reads), and Odin unions require a
// switch/type-assertion to read any field at all. Type-specific state lives
// behind `variant`. See ADR-0001.
Weapon :: struct {
	// kind/fire_mode keep their enum types - they're read directly all over
	// (apply_upgrades, weapon_family_for_kind, the renderer) - but are
	// tagged json:"-" and mirrored by the identity strings beside them. An
	// enum written as a bare ordinal is silently rewritten by any reorder of
	// its cases and read back as whatever then sits at ordinal zero;
	// save_game/load_game convert at the boundary instead. See
	// persistence.odin and ADR-0028.
	kind:           Weapon_Kind `json:"-"`,
	kind_save:      string,
	fire_mode:      Fire_Mode `json:"-"`,
	fire_mode_save: string,
	damage:         f32, // per bullet/pellet/swing/cast
	action_rate:    f32, // actions/sec; cooldown between actions is 1/action_rate
	// runtime countdown, not persisted (json:"-") - unlike windup_timer below,
	// cooldown_timer crossing zero has no side effect of its own, but it's
	// excluded for the same reason: it's transient/frame-driven state, not
	// saved content
	cooldown_timer: f32 `json:"-"`,

	// Windup/Follow-through (see CONTEXT.md, ADR-0003/0004/0026).
	// windup_fraction is a proportion of the cycle, not a fixed duration, so
	// it stays nested inside 1/action_rate no matter how much action_rate has
	// grown from upgrades (ADR-0004) - windup_timer's actual seconds are
	// derived fresh at Trigger as windup_fraction/action_rate. Fire mode still
	// decides whether a weapon Windups (Semi_Automatic only), but it no longer
	// decides Follow-through: **both** fire modes carry one, because for
	// anything that swings, Follow-through *is* the window its Hit volume is
	// live for (hit_volume.odin, ADR-0026). A Sword Windups and then swings.
	// follow_through_time has no proportionality invariant to protect the way
	// windup_fraction does, so it stays a fixed duration - the generalized,
	// Weapon-level successor to Melee_Weapon's old swing_time/swing_timer.
	// windup_timer/follow_through_timer are tagged json:"-": unlike
	// cooldown_timer, windup_timer crossing zero has a real side effect
	// (resolve_weapon_action) - restoring a positive windup_timer from a save
	// would fire that weapon on its own on the first post-load frame, with no
	// Trigger from the player. follow_through_timer is now load-bearing for the
	// same reason and excluded for the same reason.
	windup_fraction:      f32, // 0..1, Semi_Automatic only
	windup_timer:         f32 `json:"-"`,
	follow_through_time:  f32, // seconds; both fire modes
	follow_through_timer: f32 `json:"-"`,

	// identity of the swing currently in flight, matched against
	// Enemy.last_hit_swing_id so one swing damages a given body at most once
	// however long its Hit volume overlaps (hit_volume.odin). Transient
	// runtime state, never saved - a restored id would dedupe against bodies
	// from a previous session.
	swing_id: u32 `json:"-"`,

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
	// bodies past the first a shot passes through; 0 for every gun but the
	// Rifle. Sits here beside pellet_count/spread_angle - fields only one
	// weapon uses - rather than on Weapon, because Ranged is the only family
	// this is a question for: Magic's Fireball ends where it explodes and a
	// swing already hits everything its Hit volume touches, with no cap.
	pierce_count:     int,
}

// One field, deliberately: a swing's shape is its Hit volume (hit_volume.odin),
// authored per kind alongside its glyph, and the arc that volume sweeps through
// is per-kind too (Weapon_Visual.swing_arc_degrees). `range` is the only thing
// left that an Upgrade can scale, and scaling it scales the drawn blade and its
// volume together - see weapon_world_frame_size. The retired `arc_degrees` was
// the width of a cone measured from the player's feet; there is no cone here
// any more (ADR-0026).
Melee_Weapon :: struct {
	range: f32, // how far from the grip the weapon's tip reaches
}

// fields cover all three Spell_Kinds; each weapon_presets entry only sets
// the fields its spell_kind actually uses (mirrors Gun's pellet_count/
// spread_angle being pistol/SMG-irrelevant but shotgun-relevant)
Magic :: struct {
	// json:"-" + an identity string beside it, same reason as Weapon.kind -
	// except this pair converts inside weapon_variant_to_save/_from_save
	// rather than at the save_game/load_game boundary, because Magic is only
	// ever persisted through Weapon_Variant_Save.
	spell_kind:      Spell_Kind `json:"-"`,
	spell_kind_save: string,

	// Fireball: travels like a Bullet (bullet.odin's cast_fireball), explodes
	// into an AoE on impact instead of a single-target hit
	projectile_speed: f32,
	bullet_lifetime:  f32,
	explosion_radius: f32,

	// Flamethrower: instant cone hit-check re-run every Automatic-mode tick
	// while held (cast_flamethrower_tick below), reusing melee's arc-check.
	// `range` is shared with Lightning_Bolt, whose reach is a line rather than
	// a cone but is the same quantity - px from the caster - which is what
	// lets apply_magic_range_upgrade treat the two identically. arc_degrees
	// stays the Flamethrower's alone.
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
	// no weapon equipped yet - what initialize_default_game_state leaves
	// behind, and what quitting from the Main Menu on a fresh install saves.
	// weapon_variant_to_save used to hit unreachable() on that path; the
	// four other *_to_save procs all name their nil case (Inert), and now
	// this one does too. Declaring it first is free precisely because
	// nothing is keyed by ordinal any more.
	None,
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
	// identity string, not ordinal - see persistence.odin and ADR-0028
	kind:  string,
	gun:   Maybe(Gun) `json:"gun,omitempty"`,
	melee: Maybe(Melee_Weapon) `json:"melee,omitempty"`,
	magic: Maybe(Magic) `json:"magic,omitempty"`,
}

weapon_variant_to_save :: proc(variant: Weapon_Variant) -> Weapon_Variant_Save {
	switch v in variant {
	case Gun:
		return {kind = enum_identity_string(Weapon_Variant_Kind.Gun), gun = v}
	case Melee_Weapon:
		return {kind = enum_identity_string(Weapon_Variant_Kind.Melee), melee = v}
	case Magic:
		magic := v
		magic.spell_kind_save = enum_identity_string(v.spell_kind)
		return {kind = enum_identity_string(Weapon_Variant_Kind.Magic), magic = magic}
	}
	return {kind = enum_identity_string(Weapon_Variant_Kind.None)}
}

// explicit switch on the decoded `kind` - never lets json.unmarshal's
// union-variant-guessing loop run, since a Weapon_Variant is never the
// direct target of json.unmarshal; only Weapon_Variant_Save is.
weapon_variant_from_save :: proc(s: Weapon_Variant_Save) -> (variant: Weapon_Variant, ok: bool) {
	kind := enum_from_identity_string(Weapon_Variant_Kind, s.kind) or_return
	switch kind {
	case .None:
		return nil, true
	case .Gun:
		return s.gun.? or_else Gun{}, true
	case .Melee:
		return s.melee.? or_else Melee_Weapon{}, true
	case .Magic:
		magic := s.magic.? or_else Magic{}
		magic.spell_kind = enum_from_identity_string(Spell_Kind, magic.spell_kind_save) or_return
		return magic, true
	}
	return nil, false // unreachable: kind is always one of the above
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
	.Rifle = {
		kind = .Rifle,
		fire_mode = .Semi_Automatic,
		// 64 DPS against a single body - *below* the Pistol's 75 and half the
		// SMG's 120. Against a line of four it is 256, which nothing else in
		// Ranged can approach. Climbing to it buys a different question, not a
		// bigger number.
		damage = 40,
		action_rate = 1.6,
		// the heaviest commitment in the catalog, ahead of the Shotgun's 0.26:
		// a shot you line a crowd up for is a shot you should have to plan
		windup_fraction = 0.30,
		// a Gun's Follow-through is draw_weapon's recoil kick and nothing
		// else, and this is the one gun that should visibly buck
		follow_through_time = 0.10,
		variant = Gun {
			projectile_speed = 700, // fastest on the roster - a line that reads as instant without being one
			// the floor test_every_clip_size_stack_grows_every_gun_s_clip
			// allows: at 4, the second Clip_Size stack rounds back to 5 and
			// buys the player nothing they just paid for
			clip_size = 5,
			reload_time = 2.0,
			pellet_count = 1,
			spread_angle = 0,
			bullet_lifetime = 1.2, // 840px of travel
			// the first and only authored pierce: the first body plus three
			// more. Ranged was the family structurally locked out of a crowd
			// (bullet.odin), and this is what unlocks it.
			pierce_count = 3,
		},
	},
	.Dagger = {
		kind = .Dagger,
		fire_mode = .Automatic, // hold to spam quick swings
		damage = 15,
		action_rate = 4,
		// the window its blade is live for, not just a flourish after the fact
		follow_through_time = 0.15,
		variant = Melee_Weapon{range = 40},
	},
	.Sword = {
		kind = .Sword,
		fire_mode = .Semi_Automatic,
		damage = 30,
		action_rate = 1.8,
		windup_fraction = 0.37,
		// Semi_Automatic weapons never carried a Follow-through before
		// ADR-0026; the Sword's swing was reconstructed inside draw_weapon
		// from cooldown arithmetic and lasted exactly this long. Now it is
		// the swing, and the window its blade damages through.
		follow_through_time = 0.18,
		variant = Melee_Weapon{range = 60},
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
	.Lightning_Staff = {
		kind = .Lightning_Staff,
		fire_mode = .Semi_Automatic, // one commit per bolt; there is nothing to hold
		// the largest number any single action in the catalog puts out, which
		// is what makes a bolt read as an event rather than a stream. 78 DPS
		// against a single body - top of the roster's 40-120 band without
		// exceeding the SMG - which is ~4.2 casts and ~2.9s of *perfect*
		// uptime against a 220-health boss. Recorded here for the Warden
		// ticket, which authors its health and phase thresholds against the
		// whole roster rather than against this one weapon.
		damage = 52,
		action_rate = 1.5,
		// you cannot mis-lead a hitscan target, only mis-commit through its
		// Windup - so the whole of this weapon's risk lives in this number
		windup_fraction = 0.36,
		follow_through_time = 0.06,
		variant = Magic{spell_kind = .Lightning_Bolt, range = 240},
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
	// total sweep a swing travels, centered on aim_dir - drawn back to
	// -arc/2 at Resolve and out to +arc/2 (melee_swing_angle_offset,
	// hit_volume.odin). Moved here from the deleted Melee_Weapon.arc_degrees,
	// which is what makes Weapon_Visual no longer cosmetic-only: it now drives
	// where the Hit volume goes, not just what the swing looks like. That is
	// the honest price of the volume *being* the silhouette, and it buys a
	// real thing - an arc near zero is a thrust rather than a broken sweep, so
	// a thrusting weapon needs no machinery of its own (ADR-0026).
	swing_arc_degrees:     f32,
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
	// the longest gun and the tightest fan in the catalog (8 degrees against
	// the Pistol's 16 and the Shotgun's 34), so its muzzle effect reads as a
	// lance rather than a spray - the family's own shape at its own magnitude
	.Rifle        = {length = 42, muzzle_streak_count = 5, muzzle_spread_degrees = 8, muzzle_flash_radius = 16},

	// Melee: `length` unused (range supplies it). Only Sword trails echoes.
	.Dagger       = {swing_arc_degrees = 70, swing_echo_count = 0},
	.Sword        = {swing_arc_degrees = 110, swing_echo_count = 3},

	// Magic: the flash is a cast effect rather than a muzzle report, so the
	// streak burst stays at zero for all three - their family vocabulary is
	// the flash and the tick burst, not streaks
	.Fire_Wand    = {length = 30, muzzle_flash_radius = 13},
	.Flame_Staff  = {length = 34, muzzle_flash_radius = 9},
	.Poison_Staff = {length = 32, muzzle_flash_radius = 15},
	// muzzle_streak_count stays 0 with its siblings: that field is the muzzle
	// *fan*, and a bolt is a line drawn along its whole segment instead
	// (spawn_lightning_bolt)
	.Lightning_Staff = {length = 34, muzzle_flash_radius = 11},
}

// global multiplier on every weapon's drawn size, driven live by the F8
// debug panel's slider so silhouettes can be judged in motion at gameplay
// zoom rather than argued about statically (ADR-0018). Applies to Gun and
// Magic only, and melee's exclusion now has the opposite reason to the one it
// was written with: a blade's drawn length and its reach used to be two
// quantities the slider could decouple, and since ADR-0026 they are one - the
// blade *is* the Hit volume. Scaling it here would be a live reach cheat, not
// a silhouette tool.
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
	.Rifle        = "Rifle",
	.Dagger       = "Dagger",
	.Sword        = "Sword",
	.Fire_Wand    = "Fire Wand",
	.Flame_Staff  = "Flame Staff",
	.Poison_Staff = "Poison Staff",
	.Lightning_Staff = "Lightning Staff",
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
// follow_through_timer down. That last one is no longer side-effect-free: for
// anything that swings it is the swing's active window, so every frame of it
// re-tests the weapon's Hit volume against the world (ADR-0026). Callers must
// pass this frame's freshly-computed origin/aim_dir/mouse_world so both a
// Resolve on Windup completion and each frame of a swing act against
// current-frame aim state, not whatever was live at Trigger.
update_weapon :: proc(weapon: ^Weapon, dt: f32, origin, aim_dir, mouse_world: Vec2, enemies: []Enemy) {
	if weapon.cooldown_timer > 0 {
		weapon.cooldown_timer -= dt
	}

	// Ahead of the Windup block below, so a swing always gets its whole window.
	// A Semi_Automatic weapon Resolves from inside that block, and ticking a
	// freshly-set follow_through_timer down by the same frame's dt would eat
	// the front of the swing it just started - the more so the longer the
	// frame. This ordering makes both fire modes agree: the timer is set at
	// the end of a frame and the next frame is the swing's first, exactly as
	// an Automatic weapon already behaved by resolving from try_use_weapon
	// after update_weapon had run.
	//
	// `was_swinging` is captured before the tick so the swing's last frame -
	// the one taking the timer to <= 0 - is still tested rather than dropped.
	was_swinging := weapon.follow_through_timer > 0
	if weapon.follow_through_timer > 0 {
		weapon.follow_through_timer -= dt
	}

	if was_swinging {
		// the previous pose is recomputed from the timer rather than stored
		// (ADR-0007): the swing's angle is a pure function of how far into the
		// window it is, so there is nothing to keep in sync
		elapsed_now := weapon.follow_through_time - max(weapon.follow_through_timer, 0)
		swing_hit_check(weapon, origin, aim_dir, elapsed_now - dt, elapsed_now, enemies)
	}

	if weapon.windup_timer > 0 {
		weapon.windup_timer -= dt
		if weapon.windup_timer <= 0 {
			resolve_weapon_action(weapon, origin, aim_dir, mouse_world, enemies)
		}
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
// unchanged from pre-Windup behavior. Follow-through is started by
// resolve_weapon_action itself now, for both fire modes. Once a Windup starts it always completes into Resolve - there is
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
	// the player's feet anchor - see weapon_muzzle_position. The flamethrower
	// cone and Poison_Cloud's range clamp still measure from `origin`; melee
	// no longer measures anything from it at all, since its Hit volume hangs
	// off the pivot with the blade (hit_volume.odin).
	muzzle := weapon_muzzle_position(weapon^, origin, aim_dir)

	acted := false
	switch &v in weapon.variant {
	case Gun:
		acted = try_fire_gun(weapon, &v, muzzle, aim_dir)
	case Melee_Weapon:
		acted = start_melee_swing(weapon)
	case Magic:
		target := mouse_world
		if v.spell_kind == .Poison_Cloud {
			target = v.locked_target
		}
		acted = try_cast_magic(
			&v,
			weapon_visuals[weapon.kind],
			weapon.damage,
			origin,
			aim_dir,
			muzzle,
			target,
			enemies,
		)
	}

	// Follow-through starts here rather than in try_use_weapon's Automatic
	// branch, because this is the one point both fire modes pass through and
	// both now carry one (ADR-0026). Gated on the action having succeeded, so
	// a Gun that found an empty clip still plays nothing.
	if acted {
		weapon.follow_through_timer = weapon.follow_through_time
	}
	return acted
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

// 0 at Resolve -> 1 when the Follow-through ends, and `active` false whenever
// there is no Follow-through in flight. Sibling of weapon_windup_progress
// above, and the single reader of the swing's active window: for anything that
// swings this is not a cosmetic curve but the window its Hit volume is live
// for (hit_volume.odin), which is why draw_weapon and swing_hit_check both
// read it rather than each deriving one. draw_weapon used to reconstruct this
// from (cycle - windup_duration) - cooldown_timer, which is exactly how the
// swing the player watched and the swing that damaged drifted apart.
weapon_follow_through_progress :: proc(weapon: Weapon) -> (progress: f32, active: bool) {
	if weapon.follow_through_timer <= 0 || weapon.follow_through_time <= 0 {
		return 0, false
	}
	return clamp(1 - weapon.follow_through_timer / weapon.follow_through_time, 0, 1), true
}

// -- muzzle geometry -------------------------------------------------------
//
// The `origin` threaded through try_use_weapon/update_weapon is the player's
// bottom-center anchor - where they *stand* (see actor_collision_rect's note,
// main.odin), not where the weapon *points from*. Anything that visually comes
// out of the weapon (bullets, fireballs, muzzle flash/streaks, cast particles)
// must spawn at the far end of the drawn shape instead, or it reads as firing
// out of the player's feet. The flamethrower's cone and Poison_Cloud's range
// clamp still measure from `origin` - an emitted effect starts at the caster,
// and neither is a drawn shape whose position could disagree with its reach.
//
// Melee used to be on that list, on the reasoning that keeping hit-checks at
// the feet meant "moving the visuals never quietly changes reach". That
// reasoning inverted the moment a blade's Hit volume became the blade itself
// (ADR-0026): its volume hangs off the pivot with the silhouette, and being
// unable to move one without the other is now the safety property rather than
// the hazard.
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
	case .Lightning_Bolt:
		// the Windup is where this weapon's whole risk lives - a hitscan bolt
		// cannot be mis-led, only mis-committed - so it is the one thing that
		// has to be visible before Resolve
		if weapon.windup_timer <= 0 {
			return
		}
		spawn_lightning_charge_particle(weapon_muzzle_position(weapon, origin, aim_dir), weapon_windup_progress(weapon))
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

// true if enemy is within a cone: inside range (plus a fudge for the enemy's
// own collision size, derived from its existing collision rect - Enemy has no
// dedicated radius field) and within arc_degrees/2 of aim_dir. Mirrors
// Gun.spread_angle's cone-around-aim_dir idea, reused for hit detection
// instead of pellet fan-out.
//
// This is Magic's own test now. It used to be melee's, borrowed by the
// flamethrower via a fabricated Melee_Weapon; the borrowing ended with the
// field it borrowed. The cone was never wrong in general - it was wrong for
// *blades*, which are thin things pretending to be wedges, and which now hit
// with their own shape (hit_volume.odin, ADR-0026). An emitted flame really is
// a spreading wedge, so it keeps the shape it always had.
enemy_in_magic_cone :: proc(range, arc_degrees: f32, origin, aim_dir: Vec2, enemy: Enemy) -> bool {
	enemy_box := actor_collision_rect(enemy.rect)
	enemy_radius := max(enemy_box.width, enemy_box.height) / 2

	to_enemy := Vec2{enemy.x, enemy.y} - origin
	dist := linalg.length(to_enemy)
	if dist > range + enemy_radius {
		return false
	}

	direction_to_enemy := linalg.normalize0(to_enemy)
	angle_to_enemy := math.to_degrees(math.acos(clamp(linalg.dot(aim_dir, direction_to_enemy), -1, 1)))

	return angle_to_enemy <= arc_degrees / 2
}

// A swing damages nothing here. Resolve is where a swing's Hit volume goes
// *live*, not where its hit-check finishes: the blade is then tested every
// frame until the Follow-through ends (swing_hit_check, driven from
// update_weapon), so a body entering the arc after Resolve is still hit and a
// body leaving before the blade arrives is not.
//
// That is the whole point. The predecessor resolved instantly and cleaved
// everything inside a cone measured from the player's feet - on the exact
// frame a Sword's blade is drawn back at -arc/2, pointing away from most of
// what it had just killed.
//
// All this does is claim a fresh swing identity, which is what stops the
// frames that follow damaging the same body over and over. Always "acts" once
// triggered - no ammo-style failure case like Gun's empty-clip.
start_melee_swing :: proc(weapon: ^Weapon) -> bool {
	weapon.swing_id = next_swing_identity()
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
	case .Lightning_Bolt:
		// no spawn_muzzle_flash here, unlike its two siblings: the flash and
		// the bolt have to share one endpoint, so the cast owns both
		cast_lightning_bolt(magic^, damage, muzzle, aim_dir, enemies)
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
// existing cooldown/action_rate gate controls tick rate) - tests Magic's own
// cone (enemy_in_magic_cone) against its own range/arc_degrees, hitting every
// enemy in it each tick (cleave, no
// single-target cap). Also fires a cosmetic per-tick particle burst (ticket
// 06's confirmed finding - see spawn_flame_tick_burst) whether or not it hit
// anything, same as the always-on flamethrower cone draw.
cast_flamethrower_tick :: proc(magic: Magic, damage: f32, origin, aim_dir, muzzle: Vec2, enemies: []Enemy) {
	#reverse for enemy, i in enemies {
		if !enemy_in_magic_cone(magic.range, magic.arc_degrees, origin, aim_dir, enemy) do continue
		apply_hit_to_enemy(i, damage, Vec2{enemy.x, enemy.y})
	}

	spawn_flame_tick_burst(muzzle)
}

// Resolves along its line in the instant it is cast - the one thing on the
// roster that does not send something travelling, which is exactly what stops
// it being a Pistol. A single-target arealess magic projectile *is* a gun shot:
// a Bullet with explosion_radius 0 is literally what fire_pellets spawns. What
// a bolt has that no Bullet does is that you cannot mis-lead it, only
// mis-commit through its Windup - the right property for the weapon that
// exists to threaten a boss.
//
// Nothing persists past this call. The whole visual is a handful of ~0.07s
// particles, so "instant" costs no entity, no update path and no draw path,
// where cast_fireball spawns a Bullet the pipeline then has to carry.
cast_lightning_bolt :: proc(magic: Magic, damage: f32, muzzle, aim_dir: Vec2, enemies: []Enemy) {
	end := muzzle + aim_dir * magic.range

	// walls clip the line *before* bodies are ranked. Ranking first and
	// wall-checking after would let a bolt pick a target through terrain and
	// then merely draw itself short of it.
	if wall, blocked := segment_first_wall_hit(muzzle, end); blocked {
		end = wall
	}

	// Find first, damage second. Every other hit source walks #reverse to
	// survive apply_hit_to_enemy's unordered_remove mid-walk; here nothing is
	// removed during the walk at all, which is why this one reads forward.
	//
	// Ranked by distance from the muzzle to a body's centre rather than by
	// where the segment enters it: actor_collision_rect is the same size for
	// every Enemy whatever it draws at, so the two orderings are identical and
	// this needs no geometry the codebase does not already have.
	nearest := -1
	nearest_distance_sq := max(f32)
	for enemy, i in enemies {
		center, radius := enemy_body_circle(enemy)
		if !segment_circle_overlap(muzzle, end, center, radius) {
			continue
		}
		distance_sq := linalg.length2(center - muzzle)
		if distance_sq >= nearest_distance_sq {
			continue
		}
		nearest_distance_sq = distance_sq
		nearest = i
	}

	// the bolt stops where it connects, so the line the player sees is the
	// line that damaged - the same promise a Hit volume makes for a swing
	if nearest >= 0 {
		center, _ := enemy_body_circle(enemies[nearest])
		end = center
	}

	spawn_lightning_bolt(muzzle, end)

	if nearest >= 0 {
		apply_hit_to_enemy(nearest, damage, end)
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

// -- Weapon_Family (see CONTEXT.md's Weapon family entry and ADR-0008) -----
//
// Purely descriptive of whichever Weapon is currently equipped: the player
// picks a family fresh at the start of every Run by picking its tier-0 weapon
// (main.odin's Run_Start screen, hud.odin's draw_run_start_ui), so nothing on
// Player stores a family directly - it is always derived via
// weapon_kind_family from game.player.weapon.kind.

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
	.Rifle   = .Ranged,
	.Dagger  = .Melee,
	.Sword   = .Melee,
	.Fire_Wand    = .Magic,
	.Flame_Staff  = .Magic,
	.Poison_Staff = .Magic,
	.Lightning_Staff = .Magic,
}

// -- the weapon tier ladder ------------------------------------------------
//
// One list, and its order *is* the tier ladder (CONTEXT.md's Weapon tier
// ladder entry): index 0 is the family's free starting weapon, everything
// above it is a Shop purchase. Every reader below goes through a name rather
// than indexing the slice, because reading it two ways at once is exactly what
// let Shotgun be picked free at Ranged tier 2 with weapon_next_tier returning
// nil - the Shop's weapon slot dead for the rest of the Run - while Pistol
// cost 390 Gold to reach the same place (ADR-0008's amendment).
//
// What the ladder *is* lives here; what it *costs* lives in shop.odin.
//
// Note this is the one per-kind table Odin will not catch you leaving
// incomplete: it is indexed by Weapon_Family, not Weapon_Kind, so a new kind
// missing from it compiles clean, is simply unreachable, and quietly falls
// back to tier 0 in weapon_tier_index. That is what
// test_every_weapon_kind_sits_on_exactly_one_family_ladder is for.
weapon_family_kinds: [Weapon_Family][]Weapon_Kind = {
	.Ranged = {.Pistol, .SMG, .Shotgun, .Rifle},
	.Melee  = {.Dagger, .Sword},
	.Magic  = {.Fire_Wand, .Flame_Staff, .Poison_Staff, .Lightning_Staff},
}

// the one weapon a family gives away: the bottom of its ladder, and the only
// button that family gets on the Run Start screen. Named rather than spelled
// `weapon_family_kinds[family][0]` at the call site, because that expression
// appearing anywhere is the ladder being read as a menu.
weapon_family_starter :: proc(family: Weapon_Family) -> Weapon_Kind {
	return weapon_family_kinds[family][0]
}

// 0-based position of `kind` within its Weapon_Family's tier ladder - tier 0
// is always the family's starting weapon, equipped for free when picked on the
// Run_Start screen, never purchased
weapon_tier_index :: proc(kind: Weapon_Kind) -> int {
	kinds := weapon_family_kinds[weapon_kind_family[kind]]
	for k, i in kinds {
		if k == kind {
			return i
		}
	}
	return 0
}

// the next Weapon_Kind up from `kind` in its Weapon_Family's tier ladder, or
// nil if `kind` is already the ladder's top tier
weapon_next_tier :: proc(kind: Weapon_Kind) -> Maybe(Weapon_Kind) {
	kinds := weapon_family_kinds[weapon_kind_family[kind]]
	index := weapon_tier_index(kind)
	if index + 1 >= len(kinds) {
		return nil
	}
	return kinds[index + 1]
}
