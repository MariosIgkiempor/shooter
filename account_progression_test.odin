package shooter

import "core:math"
import "core:strings"
import "core:testing"

// enemy_gold_value/total_kills/account_stat_price/apply_account_stat_effect
// are pure data + arithmetic with no reliance on game.enemies/game.bullets
// etc, but try_buy_account_stat/bank_run_gold do read/mutate game.player -
// reset/restore it around each test the same way upgrade_test.odin's suite
// does (see weapon_test.odin's header comment on ODIN_TEST_THREADS=1).

// the payout now lives on the Kind's own Enemy_Preset rather than in a
// parallel table, so what this pins is that the Pickup is priced from the
// preset the enemy was stamped from - not from a second table that could
// drift out of step with it
@(test)
test_enemy_gold_value_reads_the_kinds_own_preset :: proc(t: ^testing.T) {
	for kind in Enemy_Kind {
		testing.expectf(
			t,
			enemy_gold_value(kind) == enemy_presets[kind].gold,
			"%v should be worth its preset's %v Gold, got %v",
			kind,
			enemy_presets[kind].gold,
			enemy_gold_value(kind),
		)
	}
}

@(test)
test_total_kills_sums_across_every_enemy_kind :: proc(t: ^testing.T) {
	kills: [Enemy_Kind]int
	kills[.Grunt] = 7
	kills[.Mite] = 5
	testing.expect(t, total_kills(kills) == 12, "total_kills should sum every Enemy_Kind's count")
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

// -- Map ladder (ADR-0022, ticket 16) ----------------------------------------
//
// map_rung_open/record_map_cleared read and write game.player.maps_cleared -
// snapshot and restore it around each test. Rungs are looked up through
// map_name_at_rung rather than named, so adding Maps to the ladder (ticket
// 17) doesn't rewrite these.

// second checkbox of ticket 16, first half: a fresh Account can walk onto
// rung 1 and nothing else
@(test)
test_rung_one_is_open_on_a_fresh_account :: proc(t: ^testing.T) {
	previous_cleared := game.player.maps_cleared
	defer game.player.maps_cleared = previous_cleared
	game.player.maps_cleared = {}

	first, first_ok := map_name_at_rung(1)
	testing.expect(t, first_ok, "the baked ladder should carry a rung 1")
	testing.expect(t, map_rung_open(first), "rung 1 should be open on a fresh Account")

	for name in Map_Name {
		if maps[name].rung > 1 {
			testing.expectf(t, !map_rung_open(name), "%v (rung %v) should be closed on a fresh Account", name, maps[name].rung)
		}
	}
}

// second checkbox of ticket 16, second half - "and nothing further" is the
// load-bearing part: a clear opens the rung directly above and no other
@(test)
test_clearing_a_rung_opens_exactly_the_next_one :: proc(t: ^testing.T) {
	previous_cleared := game.player.maps_cleared
	defer game.player.maps_cleared = previous_cleared
	game.player.maps_cleared = {}

	first, _ := map_name_at_rung(1)
	second, second_ok := map_name_at_rung(2)
	testing.expect(t, second_ok, "the baked ladder should carry a rung 2")

	record_map_cleared(first)

	testing.expect(t, map_rung_open(second), "clearing rung 1 should open rung 2")
	for name in Map_Name {
		if maps[name].rung > 2 {
			testing.expectf(t, !map_rung_open(name), "%v (rung %v) should stay closed after only rung 1 is cleared", name, maps[name].rung)
		}
	}
}

// the "nothing further" half again, without waiting for ticket 17's third
// rung: the baked ladder has only rungs 1 and 2 today, so the loop above
// has nothing to check. Lifting rung 2's Map to rung 3 leaves a gap at 2,
// and a clear of rung 1 must not reach across it.
@(test)
test_clearing_a_rung_does_not_open_a_rung_two_above_it :: proc(t: ^testing.T) {
	previous_cleared := game.player.maps_cleared
	defer game.player.maps_cleared = previous_cleared
	game.player.maps_cleared = {}

	first, _ := map_name_at_rung(1)
	second, _ := map_name_at_rung(2)
	previous_rung := maps[second].rung
	defer maps[second].rung = previous_rung
	maps[second].rung = 3

	record_map_cleared(first)

	testing.expect(t, !map_rung_open(second), "clearing rung 1 should not open rung 3")
}

// fourth checkbox of ticket 16: the set is one bool per Map, so a second
// clear of the same rung is the same write
@(test)
test_clearing_a_map_already_cleared_changes_nothing :: proc(t: ^testing.T) {
	previous_cleared := game.player.maps_cleared
	defer game.player.maps_cleared = previous_cleared
	game.player.maps_cleared = {}

	first, _ := map_name_at_rung(1)
	record_map_cleared(first)
	after_first := game.player.maps_cleared

	record_map_cleared(first)

	testing.expect(t, game.player.maps_cleared == after_first, "clearing an already-Cleared Map should leave the cleared set exactly as it was")
}

// third checkbox of ticket 16, the mechanical half: the gate is enforced
// at the choice itself, not only in the screen that grays the row - the
// same way try_buy_account_stat re-checks its own unlock
@(test)
test_a_closed_rung_cannot_be_chosen :: proc(t: ^testing.T) {
	previous_cleared := game.player.maps_cleared
	previous_map := game.current_map
	previous_pointer := game.active_map_pointer
	previous_rect := game.player.rect
	defer {
		game.player.maps_cleared = previous_cleared
		game.current_map = previous_map
		game.active_map_pointer = previous_pointer
		game.player.rect = previous_rect
	}
	game.player.maps_cleared = {}
	game.active_map_pointer = ""

	first, _ := map_name_at_rung(1)
	second, _ := map_name_at_rung(2)

	testing.expect(t, !try_choose_map(second), "a closed rung should refuse the choice")
	testing.expect(t, game.active_map_pointer == "", "a refused choice should leave the active-map pointer alone")

	record_map_cleared(first)

	testing.expect(t, try_choose_map(second), "an open rung should accept the choice")
	defer delete_map(game.current_map)
	testing.expectf(
		t,
		game.active_map_pointer == enum_identity_string(second),
		"an accepted choice should point the Account at that Map, got `%v`",
		game.active_map_pointer,
	)
}

// Map Selection lists the ladder in rung order, which Map_Name's own order
// is not - the enum is generated from a filename-sorted listing. Every Map
// exactly once, so a mis-authored table can't silently drop one.
@(test)
test_maps_in_rung_order_lists_every_map_once_lowest_rung_first :: proc(t: ^testing.T) {
	order := maps_in_rung_order()

	seen: [Map_Name]int
	for name, i in order {
		seen[name] += 1
		if i > 0 {
			testing.expectf(
				t,
				maps[order[i - 1]].rung <= maps[name].rung,
				"%v (rung %v) should not come before %v (rung %v)",
				order[i - 1], maps[order[i - 1]].rung, name, maps[name].rung,
			)
		}
	}
	for name in Map_Name {
		testing.expectf(t, seen[name] == 1, "%v should be listed exactly once, was listed %v times", name, seen[name])
	}
}

// third checkbox of ticket 16, the wording half: a locked rung says which
// Map to clear, not which Level to reach
@(test)
test_map_rung_requirement_names_the_rung_below :: proc(t: ^testing.T) {
	first, _ := map_name_at_rung(1)
	second, _ := map_name_at_rung(2)

	requirement := map_rung_requirement(second)

	testing.expectf(
		t,
		strings.contains(requirement, maps[first].name),
		"rung 2's requirement should name rung 1's Map, got `%v`",
		requirement,
	)
}
