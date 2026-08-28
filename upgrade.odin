package shooter

import "core:math"

// One repeatable Shop purchase per member - four general (any Weapon_Family)
// plus one per family, gated by upgrade_presets[kind].family (see
// CONTEXT.md's Upgrade entry and issue 01-upgrade-catalog-contents). Player.upgrade_stacks
// tracks how many times each has been bought; stacks are Run-scoped
// (ADR-0006) and the sole source of truth an equipped Weapon's live stats
// are recomputed from - never mutated in place (ADR-0007).
Upgrade_Kind :: enum {
	Move_Speed,
	Max_Health,
	Damage,
	Action_Rate,
	Clip_Size, // Ranged only - Gun.clip_size/ammo_in_clip
	Arc_Width, // Melee only - Melee_Weapon.arc_degrees
	Range, // Magic only - Magic.range/cast_range/bullet_lifetime, per spell_kind (see apply_magic_range_upgrade)
}

// per-stack effect shape (ADR-0007): Multiplicative compounds (recomputed
// via math.pow from the preset baseline every time, never repeated
// multiplication, so float drift never accumulates across purchases),
// Additive adds a flat amount per stack - matching how the retired
// upgrade_weapon already mixed both without issue
Multiplicative :: distinct f32 // per-stack multiplier, e.g. 1.15 = +15%/stack
Additive :: distinct f32 // per-stack flat amount

Upgrade_Effect :: union {
	Multiplicative,
	Additive,
}

Upgrade_Preset :: struct {
	display_name: string,
	base_price:   int,
	price_growth: f32, // price multiplier per stack already owned
	max_stack:    int,
	effect:       Upgrade_Effect,
	family:       Maybe(Weapon_Family), // nil = general, available to any family
}

// exact prices/growth/caps stay placeholder content-authoring (map's "Not
// yet specified") - only the item list, categorization, and effect shape are
// locked (issue 01-upgrade-catalog-contents)
upgrade_presets: [Upgrade_Kind]Upgrade_Preset = {
	.Move_Speed = {
		display_name = "Move Speed",
		base_price   = 80,
		price_growth = 1.15,
		max_stack    = 10,
		effect       = Multiplicative(1.05),
	},
	.Max_Health = {
		display_name = "Max Health",
		base_price   = 60,
		price_growth = 1.15,
		max_stack    = 10,
		effect       = Additive(20),
	},
	.Damage = {
		display_name = "Damage",
		base_price   = 140,
		price_growth = 1.15,
		max_stack    = 10,
		// matches the retired upgrade_weapon's WEAPON_UPGRADE_DAMAGE_MULT
		effect = Multiplicative(1.15),
	},
	.Action_Rate = {
		display_name = "Action Rate",
		base_price   = 120,
		price_growth = 1.15,
		max_stack    = 10,
		// matches the retired upgrade_weapon's WEAPON_UPGRADE_ACTION_RATE_MULT
		effect = Multiplicative(1.10),
	},
	.Clip_Size = {
		display_name = "Clip Size",
		base_price   = 90,
		price_growth = 1.15,
		max_stack    = 10,
		effect       = Additive(2),
		family       = .Ranged,
	},
	.Arc_Width = {
		display_name = "Arc Width",
		base_price   = 90,
		price_growth = 1.15,
		max_stack    = 10,
		effect       = Additive(10),
		family       = .Melee,
	},
	.Range = {
		display_name = "Range",
		base_price   = 90,
		price_growth = 1.15,
		max_stack    = 10,
		effect       = Additive(10),
		family       = .Magic,
	},
}

// true if `kind` is buyable by `family` - general Upgrades (family == nil)
// are buyable by any Weapon_Family, family-specific ones only by their
// matching family
upgrade_available_to_family :: proc(kind: Upgrade_Kind, family: Weapon_Family) -> bool {
	gated_family, gated := upgrade_presets[kind].family.?
	return !gated || gated_family == family
}

// gold cost of the next purchase of `kind`, given how many stacks are
// already owned
upgrade_price :: proc(kind: Upgrade_Kind, current_stack: int) -> int {
	preset := upgrade_presets[kind]
	return int(f32(preset.base_price) * math.pow(preset.price_growth, f32(current_stack)))
}

upgrade_maxed :: proc(kind: Upgrade_Kind) -> bool {
	return game.player.upgrade_stacks[kind] >= upgrade_presets[kind].max_stack
}

// applies Upgrade_Kind's per-stack effect n times onto `base`, always
// recomputed from `base` fresh (math.pow for Multiplicative, not repeated
// multiplication) rather than accumulated - this is what makes re-deriving a
// Weapon's stats after every purchase, or after a tier purchase discards and
// recreates the Weapon outright, safe to call repeatedly without drift or
// double-counting (ADR-0007)
apply_upgrade_effect :: proc(base: f32, kind: Upgrade_Kind, n: int) -> f32 {
	switch e in upgrade_presets[kind].effect {
	case Multiplicative:
		return base * math.pow(f32(e), f32(n))
	case Additive:
		return base + f32(e) * f32(n)
	}
	return base
}

// derives a Weapon's live damage/action_rate and variant-specific stat from
// weapon_presets[weapon.kind]'s baseline, layered under Account_Stat's Might
// (permanent, CONTEXT.md's Account_Stat entry) and then owned Run-scoped
// Upgrade stacks - run every time a Weapon is (re)created (a fresh Run's
// starter pick, a tier purchase's weapon_create, load from save) and again
// after every relevant Upgrade purchase so the Shop's effect is immediate
// without recreating the Weapon (ADR-0007). Gun's ammo_in_clip is
// deliberately untouched here - it's a runtime counter, not a preset-derived
// stat, and callers that need the Clip_Size delta reflected in it apply that
// separately (see try_buy_upgrade).
apply_upgrades :: proc(weapon: ^Weapon, upgrade_stacks: [Upgrade_Kind]int, account_stat_stacks: [Account_Stat]int) {
	preset := weapon_presets[weapon.kind]

	might_base := apply_account_stat_effect(preset.damage, .Might, account_stat_stacks[.Might])
	weapon.damage = apply_upgrade_effect(might_base, .Damage, upgrade_stacks[.Damage])
	weapon.action_rate = apply_upgrade_effect(preset.action_rate, .Action_Rate, upgrade_stacks[.Action_Rate])

	switch &v in weapon.variant {
	case Gun:
		base := preset.variant.(Gun)
		v.clip_size = base.clip_size + int(apply_upgrade_effect(0, .Clip_Size, upgrade_stacks[.Clip_Size]))
	case Melee_Weapon:
		base := preset.variant.(Melee_Weapon)
		v.arc_degrees = apply_upgrade_effect(base.arc_degrees, .Arc_Width, upgrade_stacks[.Arc_Width])
	case Magic:
		base := preset.variant.(Magic)
		apply_magic_range_upgrade(&v, base, upgrade_stacks[.Range])
	}
}

// Range's per-stack additive amount means a different field depending on
// spell_kind: Flamethrower's cone reach and Poison_Cloud's placement range
// are both already literal px fields, but Fireball has no equivalent field -
// its travel distance is projectile_speed * bullet_lifetime (see
// bullet.odin's cast_fireball) - so its Range stacks extend bullet_lifetime
// by the equivalent extra seconds (extra px / projectile_speed) instead
apply_magic_range_upgrade :: proc(magic: ^Magic, base: Magic, n: int) {
	switch magic.spell_kind {
	case .Flamethrower:
		magic.range = apply_upgrade_effect(base.range, .Range, n)
	case .Poison_Cloud:
		magic.cast_range = apply_upgrade_effect(base.cast_range, .Range, n)
	case .Fireball:
		extra_px := apply_upgrade_effect(0, .Range, n)
		if base.projectile_speed > 0 {
			magic.bullet_lifetime = base.bullet_lifetime + extra_px / base.projectile_speed
		}
	}
}
