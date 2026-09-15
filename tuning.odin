package shooter

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import "core:strings"

// -- Tunables ----------------------------------------------------------------
// See CONTEXT.md's Tunable / Default / Override / Tuning Group entries, and
// ADR-0020 for why this is a hand-registered table over mutable globals rather
// than reflection over the Preset structs.
//
// A Tunable is the *editing handle* on one live variable - it is not itself
// game data. Most point into a Preset table (weapon_presets[.Shotgun].damage);
// the rest point at the loose feel constants that used to be `::` and are now
// `:=` precisely so a Tunable can hold their address.

TUNING_PATH :: "data/tuning.json"

// pointer to the live variable a Tunable edits. A bare union, but unlike every
// other union in this codebase it is never a json.unmarshal target - only a
// map[string]f32 of slug -> value is serialized (see save_tuning), so the
// variant-guessing hazard documented in weapon.odin's Weapon_Variant_Save
// doesn't apply here.
Tunable_Value :: union {
	^f32,
	^int,
	^bool,
}

Tunable :: struct {
	// stable key in data/tuning.json, deliberately decoupled from the Odin
	// identifier ("weapon.shotgun.damage", not "weapon_presets.Shotgun.damage")
	// so renaming a global doesn't orphan its Override. Nothing structural
	// enforces uniqueness as a result - tuning_test.odin's uniqueness test is
	// what does, and it is load-bearing rather than cosmetic.
	slug:    string,
	group:   Tuning_Group,
	// shown in the editor. Every Font bakes only LETTERS_IN_FONT (atlas.odin)
	// - anything else, notably * and #, draws as `?`. tuning_test.odin asserts
	// every label and group name stays inside that set.
	label:   string,
	value:   Tunable_Value,
	// hand-authored, per *field* rather than per field-per-kind: every weapon's
	// damage shares one range. A range only has to be wide enough to be useful,
	// and per-kind ranges silently go wrong the moment a rebalance pushes a
	// value past its own ceiling. Unused for bool.
	min:     f32,
	max:     f32,
	// the authored in-code value, captured at registration before load_tuning
	// applies any Override. int is widened, bool is 0/1.
	default: f32,
}

tunables: [dynamic]Tunable

// -- reading / writing a Tunable ---------------------------------------------
// everything goes through f32 so Override comparison, JSON, and the slider all
// see one shape. int rounds rather than truncating, or a slider dragged to its
// maximum could never actually reach it.

tunable_get :: proc(t: Tunable) -> f32 {
	switch v in t.value {
	case ^f32:
		return v^
	case ^int:
		return f32(v^)
	case ^bool:
		return v^ ? 1 : 0
	}
	return 0
}

tunable_set :: proc(t: Tunable, value: f32) {
	switch v in t.value {
	case ^f32:
		v^ = value
	case ^int:
		v^ = int(math.round(value))
	case ^bool:
		v^ = value != 0
	}
}

// true when this Tunable currently differs from its Default - what decides
// whether it is written to data/tuning.json, and whether its row offers Reset
tunable_overridden :: proc(t: Tunable) -> bool {
	return tunable_get(t) != t.default
}

tunable_reset :: proc(t: Tunable) {
	tunable_set(t, t.default)
}

// -- registration ------------------------------------------------------------

// Both `slug` and `label` are cloned, so callers may pass temp-allocated
// fmt.tprintf results - which the loop-registered per-kind entries do for both.
// Freed by deinit_tunables.
register_tunable :: proc(
	group: Tuning_Group,
	slug: string,
	label: string,
	value: Tunable_Value,
	min: f32 = 0,
	max: f32 = 1,
) {
	t := Tunable {
		slug  = strings.clone(slug),
		group = group,
		label = strings.clone(label),
		value = value,
		min   = min,
		max   = max,
	}
	t.default = tunable_get(t)
	append(&tunables, t)
}

// bools have no range; the row draws an ON/OFF button instead of a slider
register_tunable_bool :: proc(group: Tuning_Group, slug, label: string, value: ^bool) {
	register_tunable(group, slug, label, value, 0, 1)
}

deinit_tunables :: proc() {
	for t in tunables {
		delete(t.slug)
		delete(t.label)
	}
	delete(tunables)
	tunables = nil
}

// -- persistence -------------------------------------------------------------
// Sparse: only Overrides are written, so a later change to a Default still
// shows through on every Tunable you haven't deliberately moved. Mirrors
// map.odin's save_map/load_map shape (core:encoding/json + os read/write).

save_tuning :: proc() -> bool {
	log_info("Saving tuning to `{}`", TUNING_PATH)

	overrides := make(map[string]f32, 0, context.temp_allocator)
	for t in tunables {
		if tunable_overridden(t) {
			overrides[t.slug] = tunable_get(t)
		}
	}

	// sorted + pretty so the file is a readable git diff rather than one long
	// line in map iteration order - this file is tracked, unlike game_save.json
	json_data, json_error := json.marshal(
		overrides,
		{pretty = true, use_spaces = true, spaces = 2, sort_maps_by_key = true},
		context.temp_allocator,
	)
	if json_error != nil {
		log_error("Couldn't marshal tuning: {}", json_error)
		return false
	}

	file_error := os.write_entire_file(TUNING_PATH, json_data)
	if file_error != nil {
		log_error("Couldn't write tuning to `{}`: {}", TUNING_PATH, file_error)
		return false
	}

	log_info("Saved {} override(s) to `{}`", len(overrides), TUNING_PATH)
	return true
}

// a missing file is not an error - it just means every Tunable is at its
// Default, which is exactly the state a fresh clone should start in.
load_tuning :: proc() {
	file_contents, file_error := os.read_entire_file(TUNING_PATH, context.temp_allocator)
	if file_error != nil {
		log_info("No tuning file at `{}`; every Tunable stays at its Default.", TUNING_PATH)
		return
	}

	overrides: map[string]f32
	defer delete(overrides)

	json_error := json.unmarshal(file_contents, &overrides, allocator = context.allocator)
	if json_error != nil {
		log_error("Couldn't unmarshal tuning at `{}`: {}", TUNING_PATH, json_error)
		return
	}

	applied := 0
	for t in tunables {
		if value, found := overrides[t.slug]; found {
			tunable_set(t, value)
			applied += 1
		}
	}

	// an Override whose slug no longer exists is dropped, not fatal - the same
	// self-healing posture load_game takes toward a stale save. Logged by name
	// so a typo'd or renamed slug is findable rather than silently ignored.
	if applied < len(overrides) {
		for slug in overrides {
			if !tuning_slug_registered(slug) {
				log_warning("Dropping unknown tuning key `{}` from `{}`", slug, TUNING_PATH)
			}
		}
	}

	log_info("Applied {} tuning override(s) from `{}`", applied, TUNING_PATH)
}

tuning_slug_registered :: proc(slug: string) -> bool {
	for t in tunables {
		if t.slug == slug {
			return true
		}
	}
	return false
}

// -- live application --------------------------------------------------------

// re-derives everything downstream of a Preset edit. Both procs are idempotent
// and are already re-run by load_game to self-heal a hand-edited save
// (main.odin), so calling them on every slider tick is safe and cheap.
//
// This reaches the *player* only. A value copied into an entity when it spawned
// - an Enemy's health from its Kind's preset, a Bullet's speed from its weapon -
// keeps the number it was born with; only newly-spawned entities pick the
// change up. See ADR-0020.
apply_tuning_change :: proc() {
	apply_upgrades(&game.player.weapon, game.player.upgrade_stacks, game.player.account_stat_stacks)
	recompute_player_stats()
}

// -- helpers for the registry ------------------------------------------------

// lowercases an enum case name for use in a slug: .Fire_Wand -> "fire_wand".
// Temp-allocated; register_tunable clones what it keeps.
tuning_slug_part :: proc(name: string) -> string {
	return strings.to_lower(name, context.temp_allocator)
}

// Tunables in one Tuning Group, in registration order. Temp-allocated, rebuilt
// per frame by the editor's Tuning mode - the registry is small and only one
// group is ever expanded, so this never needs an index.
tunables_in_group :: proc(group: Tuning_Group) -> []^Tunable {
	result := make([dynamic]^Tunable, 0, 16, context.temp_allocator)
	for &t in tunables {
		if t.group == group {
			append(&result, &t)
		}
	}
	return result[:]
}

tuning_group_override_count :: proc(group: Tuning_Group) -> int {
	count := 0
	for t in tunables {
		if t.group == group && tunable_overridden(t) {
			count += 1
		}
	}
	return count
}

tuning_reset_group :: proc(group: Tuning_Group) {
	for t in tunables {
		if t.group == group {
			tunable_reset(t)
		}
	}
}

// keeps `slice` imported for the sorted-key helper below and mirrors
// map.odin's use of core:slice
tuning_sorted_slugs :: proc(allocator := context.temp_allocator) -> []string {
	result := make([dynamic]string, 0, len(tunables), allocator)
	for t in tunables {
		append(&result, t.slug)
	}
	slice.sort(result[:])
	return result[:]
}


// -- Tuning Groups -----------------------------------------------------------
// One collapsible category in the editor's Tuning mode, exactly one expanded at
// a time. Deliberately fine-grained rather than a handful of broad domains:
// each group maps to one natural preset table or file section and stays around
// a dozen rows, which keeps every frame's node count small (vendor/ui asserts a
// per-container child cap) and makes the list itself the navigation.
Tuning_Group :: enum {
	// one per Weapon_Kind - common fields, the kind's variant fields, and its
	// Weapon_Visual all sit together, since judging a weapon means judging all
	// three at once
	Weapon_Pistol,
	Weapon_SMG,
	Weapon_Shotgun,
	Weapon_Rifle,
	Weapon_Dagger,
	Weapon_Sword,
	Weapon_Spear,
	Weapon_Greatsword,
	Weapon_Fire_Wand,
	Weapon_Flame_Staff,
	Weapon_Poison_Staff,
	Weapon_Lightning_Staff,
	Weapon_Common,
	Bullets,
	Player,
	Pickups,
	Enemies,
	Enemy_Steering,
	Enemy_AI,
	Relics,
	Upgrades_Price,
	Upgrades_Effect,
	Account_Stats_Price,
	Account_Stats_Effect,
	Progression,
	Camera,
	Screen_Shake,
	Weapon_Animation,
	Particles_Common,
	Particles_Hit_Spark,
	Particles_Damage_Burst,
	Particles_Flame_Tick,
	Particles_Fire_Wand_Charge,
	Particles_Muzzle,
	Particles_Bullet_Trail,
	Particles_Flame_Cone,
	Particles_Lightning,
	Poison_Gas,
	Damage_Numbers,
	World_Render,
	Ambience,
}

tuning_group_display_name := [Tuning_Group]string {
	.Weapon_Pistol              = "Weapon: Pistol",
	.Weapon_SMG                 = "Weapon: SMG",
	.Weapon_Shotgun             = "Weapon: Shotgun",
	.Weapon_Rifle               = "Weapon: Rifle",
	.Weapon_Dagger              = "Weapon: Dagger",
	.Weapon_Sword               = "Weapon: Sword",
	.Weapon_Spear               = "Weapon: Spear",
	.Weapon_Greatsword          = "Weapon: Greatsword",
	.Weapon_Fire_Wand           = "Weapon: Fire Wand",
	.Weapon_Flame_Staff         = "Weapon: Flame Staff",
	.Weapon_Poison_Staff        = "Weapon: Poison Staff",
	.Weapon_Lightning_Staff     = "Weapon: Lightning Staff",
	.Weapon_Common              = "Weapons: Common",
	.Bullets                    = "Bullets",
	.Player                     = "Player",
	.Pickups                    = "Pickups",
	.Enemies                    = "Enemies",
	.Enemy_Steering             = "Enemies: Steering",
	.Enemy_AI                   = "Enemies: AI",
	.Relics                     = "Relics",
	.Upgrades_Price             = "Upgrades: Price",
	.Upgrades_Effect            = "Upgrades: Effect",
	.Account_Stats_Price        = "Account Stats: Price",
	.Account_Stats_Effect       = "Account Stats: Effect",
	.Progression                = "Progression",
	.Camera                     = "Camera",
	.Screen_Shake               = "Screen Shake",
	.Weapon_Animation           = "Weapon Animation",
	.Particles_Common           = "Particles: Common",
	.Particles_Hit_Spark        = "Particles: Hit Spark",
	.Particles_Damage_Burst     = "Particles: Damage Burst",
	.Particles_Flame_Tick       = "Particles: Flame Tick",
	.Particles_Fire_Wand_Charge = "Particles: Charge",
	.Particles_Muzzle           = "Particles: Muzzle",
	.Particles_Bullet_Trail     = "Particles: Bullet Trail",
	.Particles_Flame_Cone       = "Particles: Flame Cone",
	.Particles_Lightning        = "Particles: Lightning",
	.Poison_Gas                 = "Poison Gas",
	.Damage_Numbers             = "Damage Numbers",
	.World_Render               = "World Render",
	.Ambience                   = "Ambience",
}

weapon_tuning_group := [Weapon_Kind]Tuning_Group {
	.Pistol       = .Weapon_Pistol,
	.SMG          = .Weapon_SMG,
	.Shotgun      = .Weapon_Shotgun,
	.Rifle        = .Weapon_Rifle,
	.Dagger       = .Weapon_Dagger,
	.Sword        = .Weapon_Sword,
	.Spear        = .Weapon_Spear,
	.Greatsword   = .Weapon_Greatsword,
	.Fire_Wand    = .Weapon_Fire_Wand,
	.Flame_Staff  = .Weapon_Flame_Staff,
	.Poison_Staff = .Weapon_Poison_Staff,
	.Lightning_Staff = .Weapon_Lightning_Staff,
}

// -- registry ----------------------------------------------------------------
// Called once from initialize_program, before load_tuning and load_game (both
// of those read values a Tunable may have Overridden). Every entry's range is
// hand-authored; editor.odin's spawn-trigger sliders are the house precedent
// for what a useful range looks like.

register_tunables :: proc() {
	register_weapon_tunables()
	register_player_tunables()
	register_enemy_tunables()
	register_economy_tunables()
	register_feel_tunables()

	log_info("Registered {} Tunable(s) across {} Tuning Group(s)", len(tunables), len(Tuning_Group))
}

// Registered by looping Weapon_Kind rather than written out per kind: ranges
// are per *field*, so every weapon's damage shares one, and a new Weapon_Kind
// picks up the whole row set for free. Slugs are generated from the enum case
// ("weapon.shotgun.damage") - register_tunable clones them, so tprintf's temp
// allocation is fine here.
@(private = "file")
register_weapon_tunables :: proc() {
	// Magic's two ranged spells share one bound rather than two literals that
	// can drift apart, per this registry's rule that a range is authored per
	// *field* rather than per field-per-kind - a Flamethrower's cone and a
	// Lightning Bolt's line are the same quantity, px from the caster.
	MAGIC_RANGE_MAX :: f32(300)

	for kind in Weapon_Kind {
		group := weapon_tuning_group[kind]
		name := tuning_slug_part(fmt.tprintf("{}", kind))
		preset := &weapon_presets[kind]

		slug :: proc(name, field: string) -> string {
			return fmt.tprintf("weapon.{}.{}", name, field)
		}

		register_tunable(group, slug(name, "damage"), "Damage", &preset.damage, 0, 100)
		register_tunable(group, slug(name, "action_rate"), "Action Rate", &preset.action_rate, 0.1, 15)

		// Fire mode still gates Windup - Semi_Automatic only - so that row is
		// registered per fire mode. Follow-through is no longer the other half
		// of that either/or: both fire modes carry one, because for anything
		// that swings it is the window its Hit volume is live for (ADR-0026),
		// and a weapon really can have both rows now.
		if preset.fire_mode == .Semi_Automatic {
			register_tunable(
				group,
				slug(name, "windup_fraction"),
				"Windup Fraction",
				&preset.windup_fraction,
				0,
				1, // a fraction of the cycle by definition (ADR-0004) - never above 1
			)
		}
		register_tunable(group, slug(name, "follow_through_time"), "Follow-through", &preset.follow_through_time, 0, 0.5)

		switch &v in preset.variant {
		case Gun:
			register_tunable(group, slug(name, "projectile_speed"), "Projectile Speed", &v.projectile_speed, 0, 800)
			register_tunable(group, slug(name, "clip_size"), "Clip Size", &v.clip_size, 1, 60)
			register_tunable(group, slug(name, "reload_time"), "Reload Time", &v.reload_time, 0.1, 5)
			register_tunable(group, slug(name, "pellet_count"), "Pellet Count", &v.pellet_count, 1, 20)
			register_tunable(group, slug(name, "spread_angle"), "Spread Angle", &v.spread_angle, 0, 90)
			register_tunable(group, slug(name, "pierce_count"), "Pierce Count", &v.pierce_count, 0, 10)
			register_tunable(group, slug(name, "bullet_lifetime"), "Bullet Lifetime", &v.bullet_lifetime, 0.1, 5)
		case Melee_Weapon:
			// `range` is melee's only stat now - the swing's arc moved to the
			// kind's Weapon_Visual (registered below), since it drives where
			// the Hit volume travels rather than how wide a cone is
			register_tunable(group, slug(name, "range"), "Range", &v.range, 0, 150)
		case Magic:
			// Magic's fields cover all three Spell_Kinds but each preset only
			// sets the ones its spell uses (weapon.odin) - registering by
			// spell_kind keeps the dead fields off the panel
			switch v.spell_kind {
			case .Fireball:
				register_tunable(group, slug(name, "projectile_speed"), "Projectile Speed", &v.projectile_speed, 0, 800)
				register_tunable(group, slug(name, "bullet_lifetime"), "Bullet Lifetime", &v.bullet_lifetime, 0.1, 5)
				register_tunable(group, slug(name, "explosion_radius"), "Explosion Radius", &v.explosion_radius, 0, 120)
			case .Flamethrower:
				register_tunable(group, slug(name, "range"), "Range", &v.range, 0, MAGIC_RANGE_MAX)
				register_tunable(group, slug(name, "arc_degrees"), "Arc Degrees", &v.arc_degrees, 0, 360)
			case .Lightning_Bolt:
				register_tunable(group, slug(name, "range"), "Range", &v.range, 0, MAGIC_RANGE_MAX)
			case .Poison_Cloud:
				register_tunable(group, slug(name, "cast_range"), "Cast Range", &v.cast_range, 0, 250)
				register_tunable(group, slug(name, "cloud_radius"), "Cloud Radius", &v.cloud_radius, 0, 120)
				register_tunable(group, slug(name, "cloud_duration"), "Cloud Duration", &v.cloud_duration, 0.5, 20)
				register_tunable(group, slug(name, "cloud_tick_rate"), "Cloud Tick Rate", &v.cloud_tick_rate, 0.1, 10)
			}
		}

		// the kind's Weapon_Visual and icon reach sit in the same group: judging
		// a weapon means judging its numbers and its silhouette together
		visual := &weapon_visuals[kind]
		register_tunable(group, slug(name, "visual_length"), "Visual Length", &visual.length, 0, 80)
		register_tunable(group, slug(name, "muzzle_streak_count"), "Muzzle Streaks", &visual.muzzle_streak_count, 0, 20)
		register_tunable(
			group,
			slug(name, "muzzle_spread_degrees"),
			"Muzzle Spread",
			&visual.muzzle_spread_degrees,
			0,
			90,
		)
		register_tunable(group, slug(name, "muzzle_flash_radius"), "Muzzle Flash Radius", &visual.muzzle_flash_radius, 0, 40)
		// not a cosmetic row: this is the arc a swing's Hit volume travels
		// through, as well as the one it's drawn travelling through (ADR-0026)
		register_tunable(group, slug(name, "swing_arc_degrees"), "Swing Arc", &visual.swing_arc_degrees, 0, 360)
		// capped by SWORD_ECHO_COUNT, which backs a fixed-size array and so
		// cannot itself be a Tunable - draw_game already clamps with min()
		register_tunable(group, slug(name, "swing_echo_count"), "Swing Echoes", &visual.swing_echo_count, 0, 3)
		register_tunable(group, slug(name, "icon_reach"), "Icon Reach", &weapon_icon_reach[kind], 0, 1)
	}

	register_tunable(.Weapon_Common, "weapon.common.visual_scale", "Visual Scale", &weapon_visual_scale, WEAPON_VISUAL_SCALE_MIN, WEAPON_VISUAL_SCALE_MAX)
	register_tunable(.Weapon_Common, "weapon.common.pivot_height", "Pivot Height", &WEAPON_PIVOT_HEIGHT, 0, 32)

	register_tunable(.Bullets, "bullet.radius", "Radius", &BULLET_RADIUS, 0.5, 10)
	register_tunable(.Bullets, "bullet.streak_length", "Streak Length", &BULLET_STREAK_LENGTH, 0, 40)
	register_tunable(.Bullets, "bullet.streak_width", "Streak Width", &BULLET_STREAK_WIDTH, 0, 20)
	register_tunable(.Bullets, "bullet.comet_length", "Comet Length", &BULLET_COMET_LENGTH, 0, 40)
	register_tunable(.Bullets, "bullet.comet_width", "Comet Width", &BULLET_COMET_WIDTH, 0, 20)
}

@(private = "file")
register_player_tunables :: proc() {
	register_tunable(.Player, "player.move_speed", "Move Speed", &PLAYER_BASE_MOVE_SPEED, 0, 400)
	register_tunable(.Player, "player.max_health", "Max Health", &PLAYER_BASE_MAX_HEALTH, 1, 500)
	// ACTOR_SIZE is the hitbox for the player *and* every enemy - enemies draw
	// at enemy_body_size() but still collide at this
	register_tunable(.Player, "player.actor_size_x", "Actor Width", &ACTOR_SIZE.x, 4, 64)
	register_tunable(.Player, "player.actor_size_y", "Actor Height", &ACTOR_SIZE.y, 4, 64)
	register_tunable(.Player, "player.squash_rate", "Squash Rate", &ACTOR_SQUASH_RATE, 1, 40)
	register_tunable(.Player, "player.moving_scale_x", "Moving Scale X", &ACTOR_MOVING_SCALE.x, 0.5, 2)
	register_tunable(.Player, "player.moving_scale_y", "Moving Scale Y", &ACTOR_MOVING_SCALE.y, 0.5, 2)

	register_tunable(.Pickups, "pickup.drop_chance", "Drop Chance", &PICKUP_DROP_CHANCE, 0, 1)
	register_tunable(.Pickups, "pickup.magnet_radius", "Magnet Radius", &PICKUP_MAGNET_RADIUS, 0, 200)
	register_tunable(.Pickups, "pickup.pickup_radius", "Pickup Radius", &PICKUP_PICKUP_RADIUS, 1, 40)
	register_tunable(.Pickups, "pickup.homing_accel", "Homing Accel", &PICKUP_HOMING_ACCEL, 0, 3000)
	register_tunable(.Pickups, "pickup.max_speed", "Max Speed", &PICKUP_MAX_SPEED, 0, 1000)
	register_tunable(.Pickups, "pickup.heal_amount", "Heal Amount", &PICKUP_HEAL_AMOUNT, 0, 200)
	register_tunable(.Pickups, "pickup.gold_radius", "Gold Draw Radius", &PICKUP_GOLD_RADIUS, 1, 20)
}

@(private = "file")
register_enemy_tunables :: proc() {
	register_tunable(.Enemies, "enemy.max_alive", "Max Alive", &MAX_ENEMIES, 1, 4096)
	register_tunable(.Enemies, "enemy.size_min", "Size Min", &ENEMY_SIZE_MIN, 2, 64)
	register_tunable(.Enemies, "enemy.size_max", "Size Max", &ENEMY_SIZE_MAX, 2, 128)
	register_tunable(.Enemies, "enemy.size_per_max_health", "Size per Max Health", &ENEMY_SIZE_PER_MAX_HEALTH, 0, 2)
	register_tunable(.Enemies, "enemy.min_opacity", "Min Opacity", &ENEMY_MIN_OPACITY, 0, 1)
	register_tunable(.Enemies, "enemy.spawn_margin", "Off-screen Spawn Margin", &OFFSCREEN_SPAWN_MARGIN, 0, 300)
	register_tunable(.Enemies, "enemy.spawn_max_retries", "Spawn Retries", &OFFSCREEN_SPAWN_MAX_RETRIES, 1, 30)

	// deliberately nothing from enemy_presets: a Kind's numbers, max health
	// and Gold included, are the editor's Presets mode's, which persists them
	// only by writing the table back out as source (ADR-0027). A Tunable over
	// one would let Save Tuning persist a preset as data in tuning.json, a
	// second authority the roster is not allowed to have.

	// per-Movement Style, the same loop-by-enum shape the weapon registry uses
	for style in Movement_Style_Kind {
		name := tuning_slug_part(fmt.tprintf("{}", style))
		register_tunable(
			.Enemy_Steering,
			fmt.tprintf("enemy.separation.{}.radius", name),
			fmt.tprintf("{} Radius", style),
			&SEPARATION_RADIUS[style],
			0,
			120,
		)
		register_tunable(
			.Enemy_Steering,
			fmt.tprintf("enemy.separation.{}.strength", name),
			fmt.tprintf("{} Strength", style),
			&SEPARATION_STRENGTH[style],
			0,
			10,
		)
	}
	register_tunable(.Enemy_Steering, "enemy.separation.grid_cell_size", "Grid Cell Size", &SEPARATION_GRID_CELL_SIZE, 4, 200)
	register_tunable(.Enemy_Steering, "enemy.separation.max_neighbours", "Max Neighbours", &SEPARATION_MAX_NEIGHBOURS, 1, 32)

	register_tunable(.Enemy_AI, "enemy.swarmer.fallback_surround_radius", "Swarmer Fallback Radius", &SWARMER_FALLBACK_SURROUND_RADIUS, 0, 300)
	register_tunable(.Enemy_AI, "enemy.swarmer.drift_speed_scale", "Swarmer Drift Speed", &SWARMER_DRIFT_SPEED_SCALE, 0, 1)
	register_tunable(.Enemy_AI, "enemy.floater.wobble_side_damping", "Floater Side Damping", &FLOATER_WOBBLE_SIDE_DAMPING, 0, 2)
	register_tunable(.Enemy_AI, "enemy.floater.wobble_boost_scale", "Floater Wobble Boost", &FLOATER_WOBBLE_BOOST_SCALE, 0, 3)
	register_tunable(.Enemy_AI, "enemy.floater.wobble_amplitude_ceiling", "Floater Amplitude Ceiling", &FLOATER_WOBBLE_AMPLITUDE_CEILING, 0, 200)
	register_tunable(.Enemy_AI, "enemy.floater.wobble_primary_weight", "Wobble Primary Weight", &FLOATER_WOBBLE_PRIMARY_WEIGHT, 0, 2)
	register_tunable(.Enemy_AI, "enemy.floater.wobble_harmonic_weight", "Wobble Harmonic Weight", &FLOATER_WOBBLE_HARMONIC_WEIGHT, 0, 2)
	register_tunable(.Enemy_AI, "enemy.floater.wobble_harmonic_freq", "Wobble Harmonic Freq", &FLOATER_WOBBLE_HARMONIC_FREQ, 0, 8)
	register_tunable(.Enemy_AI, "enemy.floater.wobble_harmonic_phase", "Wobble Harmonic Phase", &FLOATER_WOBBLE_HARMONIC_PHASE, 0, 8)
	register_tunable(.Enemy_AI, "enemy.ranged.retreat_lookahead", "Ranged Retreat Lookahead", &RANGED_RETREAT_LOOKAHEAD, 0, 500)
	register_tunable(.Enemies, "enemy.tell.flash_base_mix", "Tell Flash Base Mix", &TELL_FLASH_BASE_MIX, 0, 1)
	register_tunable(.Enemies, "enemy.tell.flash_pulse_mix", "Tell Flash Pulse Mix", &TELL_FLASH_PULSE_MIX, 0, 1)
	register_tunable(.Enemies, "enemy.tell.flash_pulse_hz", "Tell Flash Pulses", &TELL_FLASH_PULSE_HZ, 0, 12)
	register_tunable(.Enemies, "enemy.tell.flash_pulse_hz_gain", "Tell Flash Pulse Gain", &TELL_FLASH_PULSE_HZ_GAIN, 0, 24)
	register_tunable(
		.Enemy_AI,
		"enemy.flow_field.inflation_radius",
		"Flow Field Inflation",
		&FLOW_FIELD_INFLATION_RADIUS,
		0,
		3,
	)
}

@(private = "file")
register_economy_tunables :: proc() {
	relic := &relic_presets[.Orbiting_Orb]
	register_tunable(.Relics, "relic.orb.orbit_radius", "Orbit Radius", &RELIC_ORB_ORBIT_RADIUS, 0, 200)
	register_tunable(.Relics, "relic.orb.size", "Orb Size", &RELIC_ORB_SIZE, 1, 40)
	register_tunable(.Relics, "relic.orb.angular_speed", "Angular Speed", &RELIC_ORB_ANGULAR_SPEED, 0, 12)
	register_tunable(.Relics, "relic.orb.base_damage", "Base Damage", &RELIC_ORB_BASE_DAMAGE, 0, 100)
	register_tunable(.Relics, "relic.orb.tick_rate", "Tick Rate", &RELIC_ORB_TICK_RATE, 0.1, 20)
	register_tunable(.Relics, "relic.orb.core_fraction", "Core Fraction", &RELIC_ORB_CORE_FRACTION, 0, 1)
	register_tunable(.Relics, "relic.orb.base_price", "Base Price", &relic.base_price, 0, 5000)
	register_tunable(.Relics, "relic.orb.price_growth", "Price Growth", &relic.price_growth, 1, 3)
	register_tunable(.Relics, "relic.orb.max_stack", "Max Stack", &relic.max_stack, 1, 20)
	register_tunable(.Relics, "relic.orb.unlock_level", "Unlock Level", &relic.unlock_level, 1, 50)

	for kind in Upgrade_Kind {
		name := tuning_slug_part(fmt.tprintf("{}", kind))
		preset := &upgrade_presets[kind]
		register_tunable(.Upgrades_Price, fmt.tprintf("upgrade.{}.base_price", name), preset.display_name, &preset.base_price, 0, 2000)
		register_tunable(.Upgrades_Price, fmt.tprintf("upgrade.{}.price_growth", name), fmt.tprintf("{} Growth", preset.display_name), &preset.price_growth, 1, 3)
		register_tunable(.Upgrades_Effect, fmt.tprintf("upgrade.{}.max_stack", name), fmt.tprintf("{} Cap", preset.display_name), &preset.max_stack, 1, 50)
		// Multiplicative and Additive are both `distinct f32` (ADR-0007), so a
		// Tunable can point straight at either variant's payload - the union
		// tag is the *shape* of the effect and stays a design decision, only
		// its magnitude is tunable.
		//
		// The shape is part of the slug because the two read the same number
		// incompatibly: an Override of 2 is "+2 per stack" under Additive and
		// "x2 per stack" under Multiplicative, and both sit inside the other's
		// slider range. Sharing one slug would let a stale Override survive an
		// effect-shape change and be applied with the wrong meaning, silently.
		// Spelling the shape into the slug retires it instead, which
		// load_tuning already handles by dropping it with a warning.
		switch &effect in preset.effect {
		case Multiplicative:
			register_tunable(.Upgrades_Effect, fmt.tprintf("upgrade.{}.effect_mult", name), preset.display_name, cast(^f32)&effect, 1, 3)
		case Additive:
			register_tunable(.Upgrades_Effect, fmt.tprintf("upgrade.{}.effect_add", name), preset.display_name, cast(^f32)&effect, 0, 100)
		}
	}

	for stat in Account_Stat {
		name := tuning_slug_part(fmt.tprintf("{}", stat))
		preset := &account_stat_presets[stat]
		register_tunable(.Account_Stats_Price, fmt.tprintf("account_stat.{}.base_price", name), preset.display_name, &preset.base_price, 0, 5000)
		register_tunable(.Account_Stats_Price, fmt.tprintf("account_stat.{}.price_growth", name), fmt.tprintf("{} Growth", preset.display_name), &preset.price_growth, 1, 3)
		register_tunable(.Account_Stats_Price, fmt.tprintf("account_stat.{}.max_stack", name), fmt.tprintf("{} Cap", preset.display_name), &preset.max_stack, 1, 50)
		register_tunable(.Account_Stats_Effect, fmt.tprintf("account_stat.{}.effect", name), preset.display_name, cast(^f32)&preset.effect, 1, 3)
		register_tunable(.Account_Stats_Effect, fmt.tprintf("account_stat.{}.unlock_level", name), fmt.tprintf("{} Unlock", preset.display_name), &preset.unlock_level, 1, 50)
	}

	register_tunable(.Progression, "progression.weapon_tier_base_price", "Weapon Tier Base Price", &WEAPON_TIER_BASE_PRICE, 0, 2000)
	register_tunable(.Progression, "progression.weapon_tier_price_growth", "Weapon Tier Growth", &WEAPON_TIER_PRICE_GROWTH, 1, 4)
	register_tunable(.Progression, "progression.level_base", "Level Base", &LEVEL_BASE, 1, 5000)
	register_tunable(.Progression, "progression.level_growth", "Level Growth", &LEVEL_GROWTH, 1, 3)
	register_tunable(.Progression, "progression.debug_gold_grant", "Debug Gold Grant", &DEBUG_GOLD_GRANT, 0, 10000)
}

@(private = "file")
register_feel_tunables :: proc() {
	register_tunable(.Camera, "camera.min_speed", "Min Speed", &CAMERA_MIN_SPEED, 0, 300)
	register_tunable(.Camera, "camera.min_effect_length", "Deadzone", &CAMERA_MIN_EFFECT_LENGTH, 0, 100)
	register_tunable(.Camera, "camera.fraction_speed", "Fraction Speed", &CAMERA_FRACTION_SPEED, 0, 4)
	register_tunable(.Camera, "camera.speed_curve", "Speed Curve", &CAMERA_SPEED_CURVE, 0, 1)
	register_tunable(.Camera, "camera.zoom_ease_rate", "Zoom Ease Rate", &CAMERA_ZOOM_EASE_RATE, 0.5, 30)
	register_tunable(.Camera, "camera.gameplay_zoom", "Gameplay Zoom", &GAMEPLAY_ZOOM, 0.5, 4)

	register_tunable(.Screen_Shake, "shake.decay", "Decay", &SCREEN_SHAKE_DECAY, 0.1, 20)
	register_tunable(.Screen_Shake, "shake.max_offset", "Max Offset", &SCREEN_SHAKE_MAX_OFFSET, 0, 400)
	register_tunable(.Screen_Shake, "shake.tell_resolve", "Tell Resolve", &TELL_AREA_RESOLVE_SHAKE, 0, 1)

	register_tunable(.Weapon_Animation, "weapon_anim.windup_pullback", "Windup Pullback", &WEAPON_WINDUP_PULLBACK, 0, 40)
	register_tunable(.Weapon_Animation, "weapon_anim.recoil_kick", "Recoil Kick", &WEAPON_RECOIL_KICK, 0, 40)
	register_tunable(.Weapon_Animation, "weapon_anim.flame_staff_pulse_scale", "Flame Staff Pulse", &FLAME_STAFF_PULSE_SCALE, 0, 2)
	// where the swing reaches its extreme, as a fraction of the window rather
	// than the absolute out/return seconds this used to be a pair of - the
	// swing's shape is expressed relative to its own follow_through_time now,
	// which is what keeps the animation and the Hit volume's active window the
	// same length by construction (ADR-0026). Not a purely cosmetic row for
	// the same reason: this is where the blade is when it damages.
	register_tunable(.Weapon_Animation, "weapon_anim.swing_out_fraction", "Swing Out Fraction", &SWING_OUT_FRACTION, 0.05, 0.95)
	register_tunable(.Weapon_Animation, "weapon_anim.sword_echo_step", "Sword Echo Step", &SWORD_ECHO_STEP, 0.02, 0.5)
	register_tunable(.Weapon_Animation, "weapon_anim.sword_echo_fade", "Sword Echo Fade", &SWORD_ECHO_FADE, 0, 1)

	register_tunable(.Particles_Common, "particle.drag", "Drag", &PARTICLE_DRAG, 0, 30)

	register_tunable(.Particles_Hit_Spark, "particle.hit_spark.count", "Count", &HIT_SPARK_COUNT, 0, 40)
	register_tunable(.Particles_Hit_Spark, "particle.hit_spark.min_speed", "Min Speed", &HIT_SPARK_MIN_SPEED, 0, 600)
	register_tunable(.Particles_Hit_Spark, "particle.hit_spark.max_speed", "Max Speed", &HIT_SPARK_MAX_SPEED, 0, 600)
	register_tunable(.Particles_Hit_Spark, "particle.hit_spark.min_lifetime", "Min Lifetime", &HIT_SPARK_MIN_LIFETIME, 0.01, 2)
	register_tunable(.Particles_Hit_Spark, "particle.hit_spark.max_lifetime", "Max Lifetime", &HIT_SPARK_MAX_LIFETIME, 0.01, 2)
	register_tunable(.Particles_Hit_Spark, "particle.hit_spark.min_radius", "Min Radius", &HIT_SPARK_MIN_RADIUS, 0.1, 20)
	register_tunable(.Particles_Hit_Spark, "particle.hit_spark.max_radius", "Max Radius", &HIT_SPARK_MAX_RADIUS, 0.1, 20)

	register_tunable(.Particles_Damage_Burst, "particle.damage_burst.count", "Count", &DAMAGE_BURST_COUNT, 0, 40)
	register_tunable(.Particles_Damage_Burst, "particle.damage_burst.min_speed", "Min Speed", &DAMAGE_BURST_MIN_SPEED, 0, 600)
	register_tunable(.Particles_Damage_Burst, "particle.damage_burst.max_speed", "Max Speed", &DAMAGE_BURST_MAX_SPEED, 0, 600)
	register_tunable(.Particles_Damage_Burst, "particle.damage_burst.min_lifetime", "Min Lifetime", &DAMAGE_BURST_MIN_LIFETIME, 0.01, 2)
	register_tunable(.Particles_Damage_Burst, "particle.damage_burst.max_lifetime", "Max Lifetime", &DAMAGE_BURST_MAX_LIFETIME, 0.01, 2)
	register_tunable(.Particles_Damage_Burst, "particle.damage_burst.min_radius", "Min Radius", &DAMAGE_BURST_MIN_RADIUS, 0.1, 20)
	register_tunable(.Particles_Damage_Burst, "particle.damage_burst.max_radius", "Max Radius", &DAMAGE_BURST_MAX_RADIUS, 0.1, 20)

	register_tunable(.Particles_Flame_Tick, "particle.flame_tick.count", "Count", &FLAME_TICK_BURST_COUNT, 0, 40)
	register_tunable(.Particles_Flame_Tick, "particle.flame_tick.min_speed", "Min Speed", &FLAME_TICK_BURST_MIN_SPEED, 0, 600)
	register_tunable(.Particles_Flame_Tick, "particle.flame_tick.max_speed", "Max Speed", &FLAME_TICK_BURST_MAX_SPEED, 0, 600)
	register_tunable(.Particles_Flame_Tick, "particle.flame_tick.min_lifetime", "Min Lifetime", &FLAME_TICK_BURST_MIN_LIFETIME, 0.01, 2)
	register_tunable(.Particles_Flame_Tick, "particle.flame_tick.max_lifetime", "Max Lifetime", &FLAME_TICK_BURST_MAX_LIFETIME, 0.01, 2)
	register_tunable(.Particles_Flame_Tick, "particle.flame_tick.min_radius", "Min Radius", &FLAME_TICK_BURST_MIN_RADIUS, 0.1, 20)
	register_tunable(.Particles_Flame_Tick, "particle.flame_tick.max_radius", "Max Radius", &FLAME_TICK_BURST_MAX_RADIUS, 0.1, 20)

	register_tunable(.Particles_Fire_Wand_Charge, "particle.charge.min_lifetime", "Min Lifetime", &FIRE_WAND_CHARGE_MIN_LIFETIME, 0.01, 2)
	register_tunable(.Particles_Fire_Wand_Charge, "particle.charge.max_lifetime", "Max Lifetime", &FIRE_WAND_CHARGE_MAX_LIFETIME, 0.01, 2)
	register_tunable(.Particles_Fire_Wand_Charge, "particle.charge.min_radius", "Min Radius", &FIRE_WAND_CHARGE_MIN_RADIUS, 0.1, 20)
	register_tunable(.Particles_Fire_Wand_Charge, "particle.charge.max_radius", "Max Radius", &FIRE_WAND_CHARGE_MAX_RADIUS, 0.1, 20)
	register_tunable(.Particles_Fire_Wand_Charge, "particle.charge.spread", "Spread", &FIRE_WAND_CHARGE_SPREAD, 0, 40)
	register_tunable(.Particles_Fire_Wand_Charge, "particle.charge.inward_pull", "Inward Pull", &FIRE_WAND_CHARGE_INWARD_PULL, 0, 30)

	register_tunable(.Particles_Muzzle, "particle.muzzle.streak_min_speed", "Streak Min Speed", &MUZZLE_STREAK_MIN_SPEED, 0, 1200)
	register_tunable(.Particles_Muzzle, "particle.muzzle.streak_max_speed", "Streak Max Speed", &MUZZLE_STREAK_MAX_SPEED, 0, 1200)
	register_tunable(.Particles_Muzzle, "particle.muzzle.streak_min_lifetime", "Streak Min Lifetime", &MUZZLE_STREAK_MIN_LIFETIME, 0.01, 1)
	register_tunable(.Particles_Muzzle, "particle.muzzle.streak_max_lifetime", "Streak Max Lifetime", &MUZZLE_STREAK_MAX_LIFETIME, 0.01, 1)
	register_tunable(.Particles_Muzzle, "particle.muzzle.streak_length", "Streak Length", &MUZZLE_STREAK_LENGTH, 0, 40)
	register_tunable(.Particles_Muzzle, "particle.muzzle.streak_width", "Streak Width", &MUZZLE_STREAK_WIDTH, 0, 20)
	register_tunable(.Particles_Muzzle, "particle.muzzle.flash_max_radius", "Flash Max Radius", &MUZZLE_FLASH_MAX_RADIUS, 0, 60)
	register_tunable(.Particles_Muzzle, "particle.muzzle.flash_lifetime", "Flash Lifetime", &MUZZLE_FLASH_LIFETIME, 0.01, 1)
	register_tunable(.Particles_Muzzle, "particle.muzzle.flash_alpha", "Flash Alpha", &MUZZLE_FLASH_ALPHA, 0, 1)

	register_tunable(.Particles_Lightning, "particle.lightning.bolt_lifetime", "Bolt Lifetime", &LIGHTNING_BOLT_LIFETIME, 0.01, 1)
	register_tunable(.Particles_Lightning, "particle.lightning.bolt_segment_length", "Segment Length", &LIGHTNING_BOLT_SEGMENT_LENGTH, 2, 80)
	register_tunable(.Particles_Lightning, "particle.lightning.bolt_jitter", "Jitter", &LIGHTNING_BOLT_JITTER, 0, 20)
	register_tunable(.Particles_Lightning, "particle.lightning.bolt_width", "Bolt Width", &LIGHTNING_BOLT_WIDTH, 0.5, 12)
	register_tunable(.Particles_Lightning, "particle.lightning.bolt_drift_speed", "Bolt Drift Speed", &LIGHTNING_BOLT_DRIFT_SPEED, 0, 60)
	register_tunable(.Particles_Lightning, "particle.lightning.charge_min_lifetime", "Charge Min Lifetime", &LIGHTNING_CHARGE_MIN_LIFETIME, 0.01, 1)
	register_tunable(.Particles_Lightning, "particle.lightning.charge_max_lifetime", "Charge Max Lifetime", &LIGHTNING_CHARGE_MAX_LIFETIME, 0.01, 1)
	register_tunable(.Particles_Lightning, "particle.lightning.charge_spread", "Charge Spread", &LIGHTNING_CHARGE_SPREAD, 0, 40)
	register_tunable(.Particles_Lightning, "particle.lightning.charge_speed", "Charge Speed", &LIGHTNING_CHARGE_SPEED, 0, 200)
	register_tunable(.Particles_Lightning, "particle.lightning.charge_length", "Charge Length", &LIGHTNING_CHARGE_LENGTH, 0, 30)
	register_tunable(.Particles_Lightning, "particle.lightning.charge_width", "Charge Width", &LIGHTNING_CHARGE_WIDTH, 0.2, 10)

	register_tunable(.Particles_Bullet_Trail, "particle.bullet_trail.min_lifetime", "Min Lifetime", &BULLET_TRAIL_MIN_LIFETIME, 0.01, 1)
	register_tunable(.Particles_Bullet_Trail, "particle.bullet_trail.max_lifetime", "Max Lifetime", &BULLET_TRAIL_MAX_LIFETIME, 0.01, 1)
	register_tunable(.Particles_Bullet_Trail, "particle.bullet_trail.min_radius", "Min Radius", &BULLET_TRAIL_MIN_RADIUS, 0.1, 10)
	register_tunable(.Particles_Bullet_Trail, "particle.bullet_trail.max_radius", "Max Radius", &BULLET_TRAIL_MAX_RADIUS, 0.1, 10)

	register_tunable(.Particles_Flame_Cone, "particle.flame_cone.min_lifetime", "Min Lifetime", &FLAME_CONE_MIN_LIFETIME, 0.01, 2)
	register_tunable(.Particles_Flame_Cone, "particle.flame_cone.max_lifetime", "Max Lifetime", &FLAME_CONE_MAX_LIFETIME, 0.01, 2)
	register_tunable(.Particles_Flame_Cone, "particle.flame_cone.min_radius", "Min Radius", &FLAME_CONE_MIN_RADIUS, 0.1, 20)
	register_tunable(.Particles_Flame_Cone, "particle.flame_cone.max_radius", "Max Radius", &FLAME_CONE_MAX_RADIUS, 0.1, 20)
	register_tunable(.Particles_Flame_Cone, "particle.flame_cone.min_drift_speed", "Min Drift Speed", &FLAME_CONE_MIN_DRIFT_SPEED, 0, 200)
	register_tunable(.Particles_Flame_Cone, "particle.flame_cone.max_drift_speed", "Max Drift Speed", &FLAME_CONE_MAX_DRIFT_SPEED, 0, 200)

	register_tunable(.Poison_Gas, "poison_gas.spawn_interval", "Spawn Interval", &POISON_GAS_SPAWN_INTERVAL, 0.01, 1)
	register_tunable(.Poison_Gas, "poison_gas.sprite_size", "Sprite Size", &POISON_GAS_SPRITE_SIZE, 1, 60)
	register_tunable(.Poison_Gas, "poison_gas.min_lifetime", "Min Lifetime", &POISON_GAS_MIN_LIFETIME, 0.01, 4)
	register_tunable(.Poison_Gas, "poison_gas.max_lifetime", "Max Lifetime", &POISON_GAS_MAX_LIFETIME, 0.01, 4)
	register_tunable(.Poison_Gas, "poison_gas.max_drift_speed", "Max Drift Speed", &POISON_GAS_MAX_DRIFT_SPEED, 0, 60)
	register_tunable(.Poison_Gas, "poison_gas.spawn_radius_fraction", "Spawn Radius Fraction", &POISON_GAS_SPAWN_RADIUS_FRACTION, 0, 1)
	register_tunable(.Poison_Gas, "poison_gas.cloud_fill_alpha", "Cloud Fill Alpha", &POISON_CLOUD_FILL_ALPHA, 0, 255)

	register_tunable(.Damage_Numbers, "damage_number.lifetime", "Lifetime", &DAMAGE_NUMBER_LIFETIME, 0.05, 4)
	register_tunable(.Damage_Numbers, "damage_number.rise_speed", "Rise Speed", &DAMAGE_NUMBER_RISE_SPEED, 0, 200)

	register_tunable(.World_Render, "world.wall_bevel_inset", "Wall Bevel Inset", &TILEMAP_WALL_BEVEL_INSET, 0, 8)
	register_tunable(.World_Render, "world.wall_bevel_thickness", "Wall Bevel Thickness", &TILEMAP_WALL_BEVEL_THICKNESS, 0, 8)
	register_tunable(.World_Render, "world.tell_zone.claim_alpha", "Tell Zone Claim Alpha", &TELL_ZONE_CLAIM_ALPHA, 0, 1)
	register_tunable(.World_Render, "world.tell_zone.fill_alpha", "Tell Zone Fill Alpha", &TELL_ZONE_FILL_ALPHA, 0, 1)
	register_tunable(.World_Render, "world.tell_zone.edge_alpha", "Tell Zone Edge Alpha", &TELL_ZONE_EDGE_ALPHA, 0, 1)

	// the ambient layers' alphas and motion (ambience.odin). Their colours
	// derive from the Map's own and are not tunable; their budgets are
	// constants
	register_tunable(.Ambience, "ambience.mote.drift_max", "Mote Drift Max", &AMBIENT_MOTE_DRIFT_MAX, 0, 40)
	register_tunable(.Ambience, "ambience.mote.radius_min", "Mote Radius Min", &AMBIENT_MOTE_RADIUS_MIN, 0.2, 4)
	register_tunable(.Ambience, "ambience.mote.radius_max", "Mote Radius Max", &AMBIENT_MOTE_RADIUS_MAX, 0.2, 6)
	register_tunable(.Ambience, "ambience.mote.alpha_base", "Mote Alpha Base", &AMBIENT_MOTE_ALPHA_BASE, 0, 1)
	register_tunable(.Ambience, "ambience.mote.alpha_shimmer", "Mote Alpha Shimmer", &AMBIENT_MOTE_ALPHA_SHIMMER, 0, 0.5)
	register_tunable(.Ambience, "ambience.mote.shimmer_rate", "Mote Shimmer Rate", &AMBIENT_MOTE_SHIMMER_RATE, 0, 10)
	register_tunable(.Ambience, "ambience.patch.alpha", "Patch Alpha", &AMBIENT_PATCH_ALPHA, 0, 1)
	register_tunable(.Ambience, "ambience.patch.darker_scale", "Patch Darker Scale", &AMBIENT_PATCH_DARKER_SCALE, 0, 1)
	register_tunable(.Ambience, "ambience.patch.lift_mix", "Patch Lift Mix", &AMBIENT_PATCH_LIFT_MIX, 0, 1)
	register_tunable(.Ambience, "ambience.wash.top_alpha", "Wash Top Alpha", &AMBIENT_WASH_TOP_ALPHA, 0, 0.5)
	register_tunable(.Ambience, "ambience.wash.bottom_alpha", "Wash Bottom Alpha", &AMBIENT_WASH_BOTTOM_ALPHA, 0, 0.5)
	register_tunable(.Ambience, "ambience.wash.bottom_scale", "Wash Bottom Scale", &AMBIENT_WASH_BOTTOM_SCALE, 0, 1)
}
