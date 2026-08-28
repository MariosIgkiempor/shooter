package shooter

import "core:math"
import "core:testing"

// compute_run_xp/total_kills/account_stat_price/apply_account_stat_effect
// are pure data + arithmetic with no reliance on game.enemies/game.bullets
// etc, but try_buy_account_stat/grant_account_xp do read/mutate game.player
// - reset/restore it around each test the same way upgrade_test.odin's
// suite does (see weapon_test.odin's header comment on ODIN_TEST_THREADS=1).

@(test)
test_compute_run_xp_sums_kills_survival_and_gold_terms :: proc(t: ^testing.T) {
	kills: [Enemy_Kind]int
	kills[.Basic] = 4

	xp := compute_run_xp(kills, 20, 50)

	preset := enemy_xp_presets[.Basic]
	kills_xp := f32(4) * f32(preset.base_xp) * preset.xp_multiplier
	survival_xp := f32(20) * XP_PER_SURVIVAL_SECOND
	gold_xp := f32(50) * XP_PER_GOLD_EARNED
	expected := int(kills_xp + survival_xp + gold_xp)

	testing.expectf(t, xp == expected, "expected %v, got %v", expected, xp)
}

@(test)
test_compute_run_xp_zero_everything_is_zero_xp :: proc(t: ^testing.T) {
	kills: [Enemy_Kind]int
	xp := compute_run_xp(kills, 0, 0)
	testing.expect(t, xp == 0, "no kills, no survival time, no gold should grant no xp")
}

@(test)
test_total_kills_sums_across_every_enemy_kind :: proc(t: ^testing.T) {
	kills: [Enemy_Kind]int
	kills[.Basic] = 7
	testing.expect(t, total_kills(kills) == 7, "total_kills should sum every Enemy_Kind's count")
}

@(test)
test_account_stat_price_grows_geometrically_per_stack :: proc(t: ^testing.T) {
	preset := account_stat_presets[.Vigor]

	price_0 := account_stat_price(.Vigor, 0)
	price_1 := account_stat_price(.Vigor, 1)
	price_2 := account_stat_price(.Vigor, 2)

	testing.expect(t, price_0 == preset.base_price, "the first purchase should cost exactly base_price")
	testing.expectf(
		t,
		price_1 > price_0 && price_2 > price_1,
		"price should strictly increase with each already-owned stack, got %v -> %v -> %v",
		price_0,
		price_1,
		price_2,
	)
}

@(test)
test_apply_account_stat_effect_compounds_via_pow_not_repeated_multiplication :: proc(t: ^testing.T) {
	base: f32 = 100
	result := apply_account_stat_effect(base, .Might, 3)

	mult := f32(account_stat_presets[.Might].effect)
	expected := base * math.pow(mult, f32(3))

	testing.expect(t, result == expected, "Account_Stat effects should compound as base * mult^n")
}

@(test)
test_try_buy_account_stat_fails_when_unaffordable :: proc(t: ^testing.T) {
	previous_unspent := game.player.unspent_xp
	previous_stacks := game.player.account_stat_stacks
	defer {
		game.player.unspent_xp = previous_unspent
		game.player.account_stat_stacks = previous_stacks
	}

	game.player.account_stat_stacks = {}
	game.player.unspent_xp = account_stat_price(.Fortune, 0) - 1

	bought := try_buy_account_stat(.Fortune)

	testing.expect(t, !bought, "an unaffordable purchase should fail")
	testing.expect(t, game.player.account_stat_stacks[.Fortune] == 0, "a failed purchase should not increment the stack")
}

@(test)
test_try_buy_account_stat_deducts_unspent_xp_and_increments_stack_with_no_cap :: proc(t: ^testing.T) {
	previous_unspent := game.player.unspent_xp
	previous_stacks := game.player.account_stat_stacks
	defer {
		game.player.unspent_xp = previous_unspent
		game.player.account_stat_stacks = previous_stacks
	}

	game.player.account_stat_stacks = {}
	game.player.account_stat_stacks[.Fortune] = 50 // well past Upgrade_Kind's max_stack of 10
	price := account_stat_price(.Fortune, 50)
	game.player.unspent_xp = price

	bought := try_buy_account_stat(.Fortune)

	testing.expect(t, bought, "Account_Stat purchases should have no max_stack cap")
	testing.expect(t, game.player.unspent_xp == 0, "the exact price should be deducted from unspent_xp")
	testing.expect(t, game.player.account_stat_stacks[.Fortune] == 51, "the stack should increment by one")
}

@(test)
test_try_buy_account_stat_vigor_heals_by_the_max_health_increase :: proc(t: ^testing.T) {
	previous_unspent := game.player.unspent_xp
	previous_stacks := game.player.account_stat_stacks
	previous_max := game.player.max_health
	previous_health := game.player.health
	previous_upgrade_stacks := game.player.upgrade_stacks
	defer {
		game.player.unspent_xp = previous_unspent
		game.player.account_stat_stacks = previous_stacks
		game.player.max_health = previous_max
		game.player.health = previous_health
		game.player.upgrade_stacks = previous_upgrade_stacks
	}

	game.player.account_stat_stacks = {}
	game.player.upgrade_stacks = {}
	game.player.max_health = PLAYER_BASE_MAX_HEALTH
	game.player.health = 10
	game.player.unspent_xp = account_stat_price(.Vigor, 0)

	bought := try_buy_account_stat(.Vigor)

	testing.expect(t, bought, "sanity check: purchase should succeed")
	expected_max := apply_account_stat_effect(PLAYER_BASE_MAX_HEALTH, .Vigor, 1)
	testing.expectf(t, game.player.max_health == expected_max, "expected max_health %v, got %v", expected_max, game.player.max_health)
	testing.expectf(
		t,
		game.player.health == 10 + (expected_max - PLAYER_BASE_MAX_HEALTH),
		"health should rise by exactly the max_health increase, got %v",
		game.player.health,
	)
}

@(test)
test_grant_account_xp_adds_to_unspent_and_cascades_multiple_levels_in_one_call :: proc(t: ^testing.T) {
	previous_unspent := game.player.unspent_xp
	previous_xp := game.player.xp
	previous_level := game.player.level
	defer {
		game.player.unspent_xp = previous_unspent
		game.player.xp = previous_xp
		game.player.level = previous_level
	}

	game.player.unspent_xp = 0
	game.player.xp = 0
	game.player.level = 1

	// large enough to cross more than one level threshold in a single grant,
	// unlike the retired real-time orb collection which only ever needed a
	// single `if`
	level_1_requirement := xp_required_for_level(1)
	level_2_requirement := xp_required_for_level(2)
	grant := level_1_requirement + level_2_requirement + 3

	grant_account_xp(grant)

	testing.expect(t, game.player.unspent_xp == grant, "unspent_xp should receive the full grant, uncapped by leveling")
	testing.expect(t, game.player.level == 3, "a grant crossing two thresholds should advance two levels")
	testing.expectf(t, game.player.xp == 3, "leftover xp-into-level should be the remainder, got %v", game.player.xp)
}
