package shooter

import "core:math"

// -- Gold payouts (ADR-0016) ------------------------------------------------

// per-Enemy_Kind Gold payout - a single placeholder entry today (see
// enemy.odin's Enemy_Kind), but base_gold/gold_multiplier is intentionally
// richer than a flat int so a future enemy-variety effort has a multiplier
// to tune without a data-shape migration. Replaces the retired
// enemy_xp_presets: with XP gone (ADR-0016), the per-kind payout table this
// shape existed for is now denominated in Gold, dropped as a Pickup at the
// moment of death rather than tallied into a Run-end formula.
Enemy_Gold_Preset :: struct {
	base_gold:       int,
	gold_multiplier: f32,
}

enemy_gold_presets: [Enemy_Kind]Enemy_Gold_Preset = {
	.Basic = {base_gold = 30, gold_multiplier = 1.0}, // placeholder, content-authoring
}

// the Gold a `kind` kill is worth before Fortune scaling - the amount
// carried on the Pickup it drops (see pickup.odin's maybe_spawn_pickup)
enemy_gold_value :: proc(kind: Enemy_Kind) -> int {
	preset := enemy_gold_presets[kind]
	return int(f32(preset.base_gold) * preset.gold_multiplier)
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

// -- Run-end banking (ADR-0016, ADR-0017) -----------------------------------

RUN_LOSS_MULTIPLIER :: 1.0 // death and timeout both bank at face value (ADR-0017)

// how a finished Run settled, as shown on the Run End screen. Every figure
// is in Gold - the single currency (ADR-0016) - so the receipt reads as one
// arithmetic chain: earned - spent = net, net + bonus = banked.
Run_Receipt :: struct {
	earned: int, // gross Gold picked up this Run
	spent:  int, // Gold spent in the Shop this Run (earned - net)
	net:    int, // this Run's take before any victory multiplier
	bonus:  int, // extra Gold a cleared Run's multiplier added on top of net
	banked: int, // net + bonus - what actually reached the wallet
}

// settles a finished Run into Account progression and returns its receipt.
// Gold is the single currency (ADR-0016) and is *not* reset between Runs, so
// what banks is only this Run's net take - everything picked up minus
// everything spent in the Shop - measured against the wallet's balance at
// Run start (Player.run_start_gold). Measuring the delta rather than the
// whole wallet is what stops savings carried in from being re-banked (and
// re-levelled) every Run.
//
// That subtraction is the point of the design: a Shop purchase is paid for
// out of Account progression, so two Runs with identical kills end at
// different Account Levels if one of them spent.
//
// Only a positive net take is multiplied and banked. A Run that spends more
// than it earns (dipping into savings) still shrinks the wallet by exactly
// what it overspent, but never runs the Level cascade backwards and never
// has its losses amplified by a victory multiplier.
bank_run_gold :: proc(cleared: bool, victory_multiplier: f32) -> Run_Receipt {
	net := game.player.gold - game.player.run_start_gold

	receipt := Run_Receipt {
		earned = game.player.gold_earned,
		spent  = game.player.gold_earned - net,
		net    = net,
		banked = net,
	}

	if net > 0 {
		if cleared {
			receipt.banked = int(f32(net) * victory_multiplier)
			receipt.bonus = receipt.banked - net
		}

		game.player.banked_progress += receipt.banked
		for game.player.banked_progress >= gold_required_for_level(game.player.level) {
			game.player.banked_progress -= gold_required_for_level(game.player.level)
			game.player.level += 1
		}
	}

	game.player.gold = game.player.run_start_gold + receipt.banked
	return receipt
}

// -- Account_Stat (see CONTEXT.md's Account_Stat entry) ---------------------

// the permanent stat taxonomy Account progression's Gold buys into - spent
// on the Main Menu's Progression panel (hud.odin's draw_main_menu_ui, see
// ADR-0012), layered underneath a Run's Upgrade stacks (see upgrade.odin's
// apply_upgrades and main.odin's recompute_player_stats)
Account_Stat :: enum {
	Vigor,
	Might,
	Swiftness,
	Fortune,
}

Account_Stat_Preset :: struct {
	display_name: string,
	base_price:   int,
	price_growth: f32,
	max_stack:    int,
	// the Account Level this stat becomes purchasable at (ADR-0016). Level
	// is no longer a bare milestone: it is fed by banked Gold and gates
	// access here, which is what gives banking a payoff a Shop purchase
	// can't buy.
	unlock_level: int,
	effect:       Multiplicative, // all four are Multiplicative, even Vigor
}

// exact prices/growth/caps stay placeholder content-authoring, same as
// upgrade_presets - only the shape is locked. Growth now matches
// Upgrade_Preset's own 1.15 rather than the retired 1.08: once Gold is the
// single currency (ADR-0016) an Account_Stat competes directly with a Shop
// Upgrade for the same coin, and 1.08-uncapped let a banked wallet buy
// depth far too cheaply.
//
// Fortune is deliberately the shallowest and the last unlocked: it raises
// Gold gain, and Gold is now Account progression itself, so it compounds
// into its own purchase price. Left uncapped and early it makes "bank into
// Fortune until it stops paying, then play" the strictly correct opening.
account_stat_presets: [Account_Stat]Account_Stat_Preset = {
	.Vigor     = {
		display_name = "Vigor",
		base_price = 400,
		price_growth = 1.15,
		max_stack = 10,
		unlock_level = 1,
		effect = Multiplicative(1.05),
	},
	.Might     = {
		display_name = "Might",
		base_price = 480,
		price_growth = 1.15,
		max_stack = 10,
		unlock_level = 4,
		effect = Multiplicative(1.05),
	},
	.Swiftness = {
		display_name = "Swiftness",
		base_price = 400,
		price_growth = 1.15,
		max_stack = 10,
		unlock_level = 8,
		effect = Multiplicative(1.03),
	},
	.Fortune   = {
		display_name = "Fortune",
		base_price = 360,
		price_growth = 1.15,
		max_stack = 5,
		unlock_level = 12,
		effect = Multiplicative(1.05),
	},
}

// gold cost of the next purchase of `stat`, given how many stacks are
// already owned - same geometric mechanism as upgrade_price
account_stat_price :: proc(stat: Account_Stat, current_stack: int) -> int {
	preset := account_stat_presets[stat]
	return int(f32(preset.base_price) * math.pow(preset.price_growth, f32(current_stack)))
}

// whether the Account has reached `stat`'s unlock_level - the Main Menu
// still draws a locked row rather than hiding it, so the ladder ahead stays
// visible as something banking buys
account_stat_unlocked :: proc(stat: Account_Stat) -> bool {
	return game.player.level >= account_stat_presets[stat].unlock_level
}

// mirrors upgrade_maxed - Account_Stat purchases now have a hard per-stat
// cap, unlike the uncapped ladder that preceded ADR-0016
account_stat_maxed :: proc(stat: Account_Stat) -> bool {
	return game.player.account_stat_stacks[stat] >= account_stat_presets[stat].max_stack
}

// applies `stat`'s per-stack Multiplicative effect n times onto `base`,
// always recomputed fresh via math.pow rather than accumulated - same
// recompute-not-mutate discipline as apply_upgrade_effect (ADR-0007)
apply_account_stat_effect :: proc(base: f32, stat: Account_Stat, n: int) -> f32 {
	return base * math.pow(f32(account_stat_presets[stat].effect), f32(n))
}

// buys one stack of `stat`, if unlocked, not maxed, and affordable: deducts
// Gold - the same wallet the Shop spends from (ADR-0016) - increments the
// stack count, and applies the effect directly to Player for
// Vigor/Swiftness (via recompute_player_stats), or leaves it to take effect
// via the next weapon_create/Gold pickup for Might/Fortune, since there's
// no live weapon or pickup to update from the Main Menu this purchase is
// only ever made from. False (no-op) if locked, maxed, or unaffordable -
// the same guard order try_buy_upgrade uses, enforced here rather than only
// in the UI that filters these rows.
try_buy_account_stat :: proc(stat: Account_Stat) -> bool {
	if !account_stat_unlocked(stat) {
		return false
	}

	if account_stat_maxed(stat) {
		return false
	}

	price := account_stat_price(stat, game.player.account_stat_stacks[stat])
	if game.player.gold < price {
		return false
	}

	game.player.gold -= price
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
