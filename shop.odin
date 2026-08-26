package shooter

import "core:math"

WEAPON_TIER_BASE_PRICE :: 150 // gold cost of a Class's first tier-up purchase
WEAPON_TIER_PRICE_GROWTH :: 1.6 // multiplier per tier step up the ladder

// 0-based position of `kind` within its Class's weapon tier ladder
// (class_weapon_kinds) - tier 0 is always the Class's starting weapon,
// equipped for free on Class_Select, never purchased
weapon_tier_index :: proc(kind: Weapon_Kind) -> int {
	kinds := class_weapon_kinds[weapon_kind_class[kind]]
	for k, i in kinds {
		if k == kind {
			return i
		}
	}
	return 0
}

// the next Weapon_Kind up from `kind` in its Class's tier ladder, or nil if
// `kind` is already the ladder's top tier
weapon_next_tier :: proc(kind: Weapon_Kind) -> Maybe(Weapon_Kind) {
	kinds := class_weapon_kinds[weapon_kind_class[kind]]
	index := weapon_tier_index(kind)
	if index + 1 >= len(kinds) {
		return nil
	}
	return kinds[index + 1]
}

// gold cost to buy into `tier_index` (the tier being bought into, not the
// tier bought from) - grows geometrically per step up the ladder
weapon_tier_price :: proc(tier_index: int) -> int {
	return int(f32(WEAPON_TIER_BASE_PRICE) * math.pow(f32(WEAPON_TIER_PRICE_GROWTH), f32(tier_index - 1)))
}

// buys the next Weapon_Kind up in the equipped weapon's Class ladder, if
// affordable and not already at the top tier: discards the current weapon
// outright and equips the new tier fresh - weapon_create reapplies
// upgrade_stacks automatically (ADR-0007), so purchased Upgrades survive the
// swap. False (no-op) if already at the top tier or unaffordable.
try_buy_next_weapon_tier :: proc() -> bool {
	next, has_next := weapon_next_tier(game.player.weapon.kind).?
	if !has_next {
		return false
	}

	price := weapon_tier_price(weapon_tier_index(next))
	if game.player.gold < price {
		return false
	}

	game.player.gold -= price
	game.player.weapon = weapon_create(next)

	return true
}

// buys one stack of `kind`, if it's available to the equipped Class,
// affordable, and not already at its max stack: deducts Gold, increments the
// stack count, and applies the effect - directly to Player for
// Move_Speed/Max_Health, or by re-deriving the equipped Weapon's stats from
// its preset baseline for everything else (see apply_upgrades), so the
// purchase takes effect immediately without waiting for the next tier
// purchase or reload. False (no-op) if class-gated away, maxed, or
// unaffordable. The Shop UI already only ever offers a Class-gated kind to
// begin with (upgrade_available_to_class), but this guard keeps that
// invariant enforced here too, not just by the UI's own filtering.
try_buy_upgrade :: proc(kind: Upgrade_Kind) -> bool {
	if !upgrade_available_to_class(kind, game.player.class) {
		return false
	}

	if upgrade_maxed(kind) {
		return false
	}

	price := upgrade_price(kind, game.player.upgrade_stacks[kind])
	if game.player.gold < price {
		return false
	}

	game.player.gold -= price
	game.player.upgrade_stacks[kind] += 1

	switch kind {
	case .Move_Speed:
		game.player.move_speed = apply_upgrade_effect(PLAYER_BASE_MOVE_SPEED, kind, game.player.upgrade_stacks[kind])
	case .Max_Health:
		old_max := game.player.max_health
		game.player.max_health = apply_upgrade_effect(PLAYER_BASE_MAX_HEALTH, kind, game.player.upgrade_stacks[kind])
		// heals by the same amount the cap rose, so buying mid-fight always
		// reads as a net improvement rather than just a bigger empty cap
		// (issue 01-upgrade-catalog-contents)
		game.player.health += game.player.max_health - old_max
	case .Damage, .Action_Rate, .Clip_Size, .Arc_Width, .Range:
		old_clip_size := 0
		if gun, ok := game.player.weapon.variant.(Gun); ok {
			old_clip_size = gun.clip_size
		}

		apply_upgrades(&game.player.weapon, game.player.upgrade_stacks)

		// clip_size is recomputed from scratch above like every other stat,
		// but ammo_in_clip is a runtime counter, not a preset-derived one -
		// only a Clip_Size purchase should hand the player the capacity
		// delta as usable rounds, not top the clip back up to full
		switch &v in game.player.weapon.variant {
		case Gun:
			v.ammo_in_clip += v.clip_size - old_clip_size
		case Melee_Weapon, Magic:
		}
	}

	return true
}
