package shooter

import "core:fmt"
import "core:math"
import "core:slice"

// -- Gold payouts (ADR-0016) ------------------------------------------------

// the Gold a `kind` kill is worth before Fortune scaling - the amount
// carried on the Pickup it drops (see pickup.odin's maybe_spawn_pickup).
//
// The payout is one of the authored facts of an Enemy Kind, so it lives on
// that Kind's Enemy_Preset (enemy.odin) rather than in a parallel table
// keyed by the same enum - the separate enemy_gold_presets this replaces
// was a second place a new Kind had to be remembered in. Its
// base-gold-times-multiplier pair collapsed to the single figure it always
// evaluated to; a Kind whose payout should change is edited, not scaled.
enemy_gold_value :: proc(kind: Enemy_Kind) -> int {
	return enemy_presets[kind].gold
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

// -- Map ladder (ADR-0022) ---------------------------------------------------
//
// Maps are an ordered ladder, one Map per rung, and a rung is playable only
// once the rung below it has been Cleared at least once. Gated on clears
// rather than Account Level deliberately: Level advances on banked Gold, so
// a Level gate would ask "have you saved enough?" where the ladder means
// to ask "can you do this?" - and Fortune would compound straight into
// ladder access. The evidence is game.player.maps_cleared.

// the Map that carries `rung`, if any. A linear scan of the baked table
// rather than an index: Map_Name is generated in filename order, so ordinal
// N is not rung N and never will be. ok is false for a rung no Map carries
// - a broken ladder table, which ticket 15's validity sweep (rungs are 1..N
// with no gaps and no duplicates) is what asserts against.
map_name_at_rung :: proc(rung: int) -> (name: Map_Name, ok: bool) {
	for candidate in Map_Name {
		if maps[candidate].rung == rung {
			return candidate, true
		}
	}
	return {}, false
}

// whether `name`'s rung is open: rung 1 always is, and every rung above it
// is opened by a Cleared on the rung directly below. `rung <= 1` rather than
// `== 1` so an unauthored rung-0 Map fails open - an authoring mistake
// should make the ladder wrong, not make a Map permanently unreachable. A
// gap below (no Map at rung-1) closes this one: nothing to clear, so
// nothing can open it.
map_rung_open :: proc(name: Map_Name) -> bool {
	rung := maps[name].rung
	if rung <= 1 {
		return true
	}

	below, below_ok := map_name_at_rung(rung - 1)
	if !below_ok {
		return false
	}
	return game.player.maps_cleared[below]
}

// records a Cleared Map on the Account - the only permanent mark a Run
// outcome leaves (CONTEXT.md's Run outcome entry). Idempotent by
// construction: one bool per Map, so a second clear of the same rung writes
// the same true. Called from end_run, inside its double-fire guard.
record_map_cleared :: proc(name: Map_Name) {
	game.player.maps_cleared[name] = true
}

// what a locked rung asks for, as Map Selection states it - here rather
// than in the drawing so the sentence is assertable without a window.
// Names the Map to clear, not a Level to reach (ADR-0022). Temp-allocated,
// like every other menu label.
map_rung_requirement :: proc(name: Map_Name) -> string {
	below, below_ok := map_name_at_rung(maps[name].rung - 1)
	if !below_ok {
		return "Locked"
	}
	return fmt.tprintf("Clear {} to open", maps[below].name)
}

// the Map ladder in rung order, which Map_Name's own order is not: the enum
// is generated from a filename-sorted listing, so today Cold_Hall (rung 2)
// sorts above Desert_Dungeon (rung 1). Sorted rather than walked
// rung-by-rung so a mis-authored table still lists every Map exactly once -
// a Map that vanished from Map Selection would be unplayable with no
// visible cause.
maps_in_rung_order :: proc() -> (order: [len(Map_Name)]Map_Name) {
	i := 0
	for name in Map_Name {
		order[i] = name
		i += 1
	}
	slice.sort_by(order[:], proc(a, b: Map_Name) -> bool {
		return maps[a].rung < maps[b].rung
	})
	return
}
