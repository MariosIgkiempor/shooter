package shooter

import "core:math"
import "core:testing"

// enemy_gold_value/total_kills/account_stat_price/apply_account_stat_effect
// are pure data + arithmetic with no reliance on game.enemies/game.bullets
// etc, but try_buy_account_stat/bank_run_gold do read/mutate game.player -
// reset/restore it around each test the same way upgrade_test.odin's suite
// does (see weapon_test.odin's header comment on ODIN_TEST_THREADS=1).

@(test)
test_enemy_gold_value_applies_the_presets_multiplier :: proc(t: ^testing.T) {
	preset := enemy_gold_presets[.Basic]
	expected := int(f32(preset.base_gold) * preset.gold_multiplier)
	testing.expectf(t, enemy_gold_value(.Basic) == expected, "expected %v, got %v", expected, enemy_gold_value(.Basic))
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

// -- try_buy_account_stat ---------------------------------------------------

@(private = "file")
Account_Snapshot :: struct {
	gold:            int,
	stacks:          [Account_Stat]int,
	level:           int,
	banked_progress: int,
	max_health:      f32,
	health:          f32,
	upgrade_stacks:  [Upgrade_Kind]int,
	run_start_gold:  int,
	gold_earned:     int,
}

@(private = "file")
snapshot_account :: proc() -> Account_Snapshot {
	return {
		gold = game.player.gold,
		stacks = game.player.account_stat_stacks,
		level = game.player.level,
		banked_progress = game.player.banked_progress,
		max_health = game.player.max_health,
		health = game.player.health,
		upgrade_stacks = game.player.upgrade_stacks,
		run_start_gold = game.player.run_start_gold,
		gold_earned = game.player.gold_earned,
	}
}

@(private = "file")
restore_account :: proc(s: Account_Snapshot) {
	game.player.gold = s.gold
	game.player.account_stat_stacks = s.stacks
	game.player.level = s.level
	game.player.banked_progress = s.banked_progress
	game.player.max_health = s.max_health
	game.player.health = s.health
	game.player.upgrade_stacks = s.upgrade_stacks
	game.player.run_start_gold = s.run_start_gold
	game.player.gold_earned = s.gold_earned
}

// every Account_Stat is unlocked at some Level, so a purchase test that
// isn't specifically about the gate has to clear it first
@(private = "file")
UNLOCK_ALL_LEVEL :: 100

@(test)
test_try_buy_account_stat_fails_when_unaffordable :: proc(t: ^testing.T) {
	previous := snapshot_account()
	defer restore_account(previous)

	game.player.account_stat_stacks = {}
	game.player.level = UNLOCK_ALL_LEVEL
	game.player.gold = account_stat_price(.Fortune, 0) - 1

	bought := try_buy_account_stat(.Fortune)

	testing.expect(t, !bought, "an unaffordable purchase should fail")
	testing.expect(t, game.player.account_stat_stacks[.Fortune] == 0, "a failed purchase should not increment the stack")
}

@(test)
test_try_buy_account_stat_deducts_gold_and_increments_stack :: proc(t: ^testing.T) {
	previous := snapshot_account()
	defer restore_account(previous)

	game.player.account_stat_stacks = {}
	game.player.level = UNLOCK_ALL_LEVEL
	price := account_stat_price(.Fortune, 0)
	game.player.gold = price

	bought := try_buy_account_stat(.Fortune)

	testing.expect(t, bought, "an unlocked, affordable, uncapped purchase should succeed")
	testing.expect(t, game.player.gold == 0, "the exact price should be deducted from the Gold wallet")
	testing.expect(t, game.player.account_stat_stacks[.Fortune] == 1, "the stack should increment by one")
}

@(test)
test_try_buy_account_stat_refuses_a_stat_below_its_unlock_level :: proc(t: ^testing.T) {
	previous := snapshot_account()
	defer restore_account(previous)

	game.player.account_stat_stacks = {}
	game.player.level = account_stat_presets[.Fortune].unlock_level - 1
	game.player.gold = account_stat_price(.Fortune, 0) * 100 // affordability is not the constraint here

	bought := try_buy_account_stat(.Fortune)

	testing.expect(t, !bought, "a stat below its unlock_level should not be purchasable at any price")
	testing.expect(t, game.player.account_stat_stacks[.Fortune] == 0, "a locked purchase should not increment the stack")
	testing.expect(t, game.player.gold > 0, "a locked purchase should not deduct Gold")
}

@(test)
test_try_buy_account_stat_refuses_a_maxed_stat :: proc(t: ^testing.T) {
	previous := snapshot_account()
	defer restore_account(previous)

	game.player.account_stat_stacks = {}
	game.player.level = UNLOCK_ALL_LEVEL
	max_stack := account_stat_presets[.Fortune].max_stack
	game.player.account_stat_stacks[.Fortune] = max_stack
	game.player.gold = account_stat_price(.Fortune, max_stack) * 100

	bought := try_buy_account_stat(.Fortune)

	testing.expect(t, !bought, "Account_Stat purchases should stop at max_stack (ADR-0016)")
	testing.expectf(
		t,
		game.player.account_stat_stacks[.Fortune] == max_stack,
		"a maxed purchase should not increment the stack, got %v",
		game.player.account_stat_stacks[.Fortune],
	)
}

@(test)
test_try_buy_account_stat_vigor_heals_by_the_max_health_increase :: proc(t: ^testing.T) {
	previous := snapshot_account()
	defer restore_account(previous)

	game.player.account_stat_stacks = {}
	game.player.upgrade_stacks = {}
	game.player.level = UNLOCK_ALL_LEVEL
	game.player.max_health = PLAYER_BASE_MAX_HEALTH
	game.player.health = 10
	game.player.gold = account_stat_price(.Vigor, 0)

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

// -- bank_run_gold ----------------------------------------------------------

@(test)
test_bank_run_gold_banks_only_this_runs_net_take_not_the_whole_wallet :: proc(t: ^testing.T) {
	previous := snapshot_account()
	defer restore_account(previous)

	game.player.level = 1
	game.player.banked_progress = 0
	game.player.run_start_gold = 900 // savings carried in from earlier Runs
	game.player.gold = 1100 // ...plus 200 earned this Run
	game.player.gold_earned = 200

	receipt := bank_run_gold(false, 1.5)

	testing.expectf(t, receipt.banked == 200, "only the Run's net take should bank, got %v", receipt.banked)
	testing.expectf(t, game.player.gold == 1100, "the wallet should be unchanged by a face-value settle, got %v", game.player.gold)
	testing.expectf(
		t,
		game.player.banked_progress == 200,
		"carried-in savings must not be re-banked into Level progress, got %v",
		game.player.banked_progress,
	)
}

@(test)
test_bank_run_gold_subtracts_shop_spending_from_what_banks :: proc(t: ^testing.T) {
	previous := snapshot_account()
	defer restore_account(previous)

	// two Runs earning the same 500 Gold, one of which spent 300 in the Shop
	game.player.level = 1
	game.player.banked_progress = 0
	game.player.run_start_gold = 0
	game.player.gold = 500
	game.player.gold_earned = 500
	thrifty := bank_run_gold(false, 1.5)

	game.player.level = 1
	game.player.banked_progress = 0
	game.player.run_start_gold = 0
	game.player.gold = 200 // 500 earned, 300 spent
	game.player.gold_earned = 500
	spender := bank_run_gold(false, 1.5)

	testing.expectf(t, thrifty.spent == 0, "a Run that bought nothing should report no spend, got %v", thrifty.spent)
	testing.expectf(t, spender.spent == 300, "spend should be earned minus net, got %v", spender.spent)
	testing.expectf(
		t,
		spender.banked < thrifty.banked,
		"spending in the Shop must cost Account progression, got %v banked vs %v",
		spender.banked,
		thrifty.banked,
	)
}

@(test)
test_bank_run_gold_applies_the_victory_multiplier_only_when_cleared :: proc(t: ^testing.T) {
	previous := snapshot_account()
	defer restore_account(previous)

	game.player.level = 1
	game.player.banked_progress = 0
	game.player.run_start_gold = 0
	game.player.gold = 400
	game.player.gold_earned = 400
	lost := bank_run_gold(false, 1.5)

	game.player.level = 1
	game.player.banked_progress = 0
	game.player.run_start_gold = 0
	game.player.gold = 400
	game.player.gold_earned = 400
	won := bank_run_gold(true, 1.5)

	testing.expectf(t, lost.bonus == 0, "a Run that wasn't cleared should pay no bonus, got %v", lost.bonus)
	testing.expectf(t, lost.banked == 400, "an uncleared Run should bank its net take at face value, got %v", lost.banked)
	testing.expectf(t, won.banked == 600, "a cleared Run should bank net * multiplier, got %v", won.banked)
	testing.expectf(t, won.bonus == 200, "the bonus should be the multiplier's extra over net, got %v", won.bonus)
	testing.expectf(t, game.player.gold == 600, "the bonus should reach the wallet, got %v", game.player.gold)
}

@(test)
test_bank_run_gold_cascades_multiple_levels_in_one_settle :: proc(t: ^testing.T) {
	previous := snapshot_account()
	defer restore_account(previous)

	game.player.level = 1
	game.player.banked_progress = 0
	game.player.run_start_gold = 0

	// large enough to cross more than one Level threshold in a single settle
	level_1_requirement := gold_required_for_level(1)
	level_2_requirement := gold_required_for_level(2)
	game.player.gold = level_1_requirement + level_2_requirement + 3
	game.player.gold_earned = game.player.gold

	bank_run_gold(false, 1.5)

	testing.expect(t, game.player.level == 3, "a settle crossing two thresholds should advance two levels")
	testing.expectf(
		t,
		game.player.banked_progress == 3,
		"leftover progress should be the remainder, got %v",
		game.player.banked_progress,
	)
}

@(test)
test_bank_run_gold_never_runs_progression_backwards_when_a_run_overspends :: proc(t: ^testing.T) {
	previous := snapshot_account()
	defer restore_account(previous)

	game.player.level = 4
	game.player.banked_progress = 50
	game.player.run_start_gold = 1000
	game.player.gold = 700 // spent 300 more than this Run earned, out of savings
	game.player.gold_earned = 0

	receipt := bank_run_gold(true, 1.5)

	testing.expectf(t, receipt.banked == -300, "an overspending Run should settle as its net loss, got %v", receipt.banked)
	testing.expectf(t, game.player.gold == 700, "the wallet should keep exactly what's left, got %v", game.player.gold)
	testing.expect(t, game.player.level == 4, "an overspending Run should not lose Account Levels")
	testing.expectf(
		t,
		game.player.banked_progress == 50,
		"an overspending Run should not run Level progress backwards, got %v",
		game.player.banked_progress,
	)
	testing.expectf(t, receipt.bonus == 0, "a negative net take should never be amplified by a victory multiplier, got %v", receipt.bonus)
}
