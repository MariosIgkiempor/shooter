package shooter

import "core:math"

// -- Run-end XP grant (ADR-0009) --------------------------------------------

// per-Enemy_Kind XP payout - a single placeholder entry today (see
// enemy.odin's Enemy_Kind), but base_xp/xp_multiplier is intentionally
// richer than a flat int so a future enemy-variety effort has a multiplier
// to tune without a data-shape migration (Account Progression Rework map's
// XP formula ticket)
Enemy_XP_Preset :: struct {
	base_xp:       int,
	xp_multiplier: f32,
}

enemy_xp_presets: [Enemy_Kind]Enemy_XP_Preset = {
	.Basic = {base_xp = 5, xp_multiplier = 1.0}, // placeholder, content-authoring
}

// exact weights stay placeholder/content-authoring, same as
// enemy_xp_presets above - only the formula's shape (a weighted linear sum,
// no diminishing returns per term) is locked. gold_xp is deliberately
// discounted relative to kills/survival since Gold already partly derives
// from kills via the existing Pickup_Kind.Gold drop chance and shouldn't
// fully double-count the same underlying behavior.
XP_PER_SURVIVAL_SECOND :: 0.5
XP_PER_GOLD_EARNED :: 0.2

// xp = kills_xp + survival_xp + gold_xp, granted once at Run end (death) -
// see ADR-0009. Pure function of a Run's tallied stats, no game global
// reads, so it's directly testable.
compute_run_xp :: proc(kills: [Enemy_Kind]int, survival_seconds: f32, gold_earned: int) -> int {
	kills_xp: f32 = 0
	for kind in Enemy_Kind {
		preset := enemy_xp_presets[kind]
		kills_xp += f32(kills[kind]) * f32(preset.base_xp) * preset.xp_multiplier
	}

	survival_xp := survival_seconds * XP_PER_SURVIVAL_SECOND
	gold_xp := f32(gold_earned) * XP_PER_GOLD_EARNED

	return int(kills_xp + survival_xp + gold_xp)
}

// summed across every Enemy_Kind - the Run End screen shows a single "Kills"
// tile (Decision 01), not a per-kind breakdown
total_kills :: proc(kills: [Enemy_Kind]int) -> int {
	total := 0
	for kind in Enemy_Kind {
		total += kills[kind]
	}
	return total
}

// adds a Run-end XP grant to both the Account Level/XP-into-level progress
// (game.player.xp/level, cascading past however many level thresholds a
// single lump crosses - unlike the retired collect_xp's single `if`, which
// only ever needed to handle one small real-time orb at a time) and the
// separate spendable unspent_xp balance (CONTEXT.md's Account progression
// entry: Level is a milestone only, purchasing power lives entirely in
// unspent_xp/Account_Stat).
grant_account_xp :: proc(amount: int) {
	game.player.unspent_xp += amount
	game.player.xp += amount

	for game.player.xp >= xp_required_for_level(game.player.level) {
		game.player.xp -= xp_required_for_level(game.player.level)
		game.player.level += 1
	}
}

// -- Account_Stat (see CONTEXT.md's Account_Stat entry) ---------------------

// the permanent stat taxonomy Account progression's XP buys into - spent on
// the Run End screen (hud.odin's draw_run_end_ui), layered underneath a
// Run's Upgrade stacks (see upgrade.odin's apply_upgrades and main.odin's
// recompute_player_stats)
Account_Stat :: enum {
	Vigor,
	Might,
	Swiftness,
	Fortune,
}

Account_Stat_Preset :: struct {
	display_name: string,
	base_price:   int,
	price_growth: f32, // gentler than Upgrade_Preset's Run-scoped growth, and no max_stack (ticket 02)
	effect:       Multiplicative, // all four are Multiplicative (ticket 02), even Vigor
}

// exact prices/growth stay placeholder content-authoring, same as
// upgrade_presets - only the shape (geometric, no cap) is locked
account_stat_presets: [Account_Stat]Account_Stat_Preset = {
	.Vigor     = {display_name = "Vigor", base_price = 100, price_growth = 1.08, effect = Multiplicative(1.05)},
	.Might     = {display_name = "Might", base_price = 120, price_growth = 1.08, effect = Multiplicative(1.05)},
	.Swiftness = {display_name = "Swiftness", base_price = 100, price_growth = 1.08, effect = Multiplicative(1.03)},
	.Fortune   = {display_name = "Fortune", base_price = 90, price_growth = 1.08, effect = Multiplicative(1.05)},
}

// xp cost of the next purchase of `stat`, given how many stacks are already
// owned - same geometric mechanism as upgrade_price, but no max_stack cap:
// an Account_Stat purchase is always available, just costing meaningfully
// more the more of it a player already owns
account_stat_price :: proc(stat: Account_Stat, current_stack: int) -> int {
	preset := account_stat_presets[stat]
	return int(f32(preset.base_price) * math.pow(preset.price_growth, f32(current_stack)))
}

// applies `stat`'s per-stack Multiplicative effect n times onto `base`,
// always recomputed fresh via math.pow rather than accumulated - same
// recompute-not-mutate discipline as apply_upgrade_effect (ADR-0007)
apply_account_stat_effect :: proc(base: f32, stat: Account_Stat, n: int) -> f32 {
	return base * math.pow(f32(account_stat_presets[stat].effect), f32(n))
}

// buys one stack of `stat`, if affordable: deducts unspent_xp, increments
// the stack count, and applies the effect - directly to Player for
// Vigor/Swiftness (via recompute_player_stats), or left to take effect via
// the next weapon_create/Gold pickup for Might/Fortune, since there's no
// live weapon or pickup to update from the Run End screen this purchase is
// only ever made from. False (no-op) if unaffordable. No max-stack guard -
// Account_Stat purchases have no cap (ticket 02).
try_buy_account_stat :: proc(stat: Account_Stat) -> bool {
	price := account_stat_price(stat, game.player.account_stat_stacks[stat])
	if game.player.unspent_xp < price {
		return false
	}

	game.player.unspent_xp -= price
	game.player.account_stat_stacks[stat] += 1

	switch stat {
	case .Vigor:
		old_max := game.player.max_health
		recompute_player_stats()
		// heals by the same amount the cap rose, mirroring the Max_Health
		// Upgrade's identical treatment (shop.odin's try_buy_upgrade)
		game.player.health += game.player.max_health - old_max
	case .Swiftness:
		recompute_player_stats()
	case .Might, .Fortune:
	}

	return true
}
