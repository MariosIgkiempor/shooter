package shooter

import "core:testing"

// try_buy_upgrade/try_buy_next_weapon_tier/start_new_run all read and mutate
// game.player - snapshot and restore whatever fields each test touches, same
// discipline weapon_test.odin's suite already applies to game.bullets/etc
// (see that file's header comment on ODIN_TEST_THREADS=1).

@(test)
test_try_buy_upgrade_fails_when_unaffordable :: proc(t: ^testing.T) {
	previous_gold := game.player.gold
	previous_stacks := game.player.upgrade_stacks
	defer {
		game.player.gold = previous_gold
		game.player.upgrade_stacks = previous_stacks
	}

	game.player.gold = 0
	game.player.upgrade_stacks = {}

	bought := try_buy_upgrade(.Move_Speed)

	testing.expect(t, !bought, "an unaffordable purchase should fail")
	testing.expect(t, game.player.gold == 0, "a failed purchase should not deduct gold")
	testing.expect(t, game.player.upgrade_stacks[.Move_Speed] == 0, "a failed purchase should not increment the stack")
}

@(test)
test_try_buy_upgrade_deducts_gold_and_increments_stack :: proc(t: ^testing.T) {
	previous_gold := game.player.gold
	previous_stacks := game.player.upgrade_stacks
	previous_speed := game.player.move_speed
	defer {
		game.player.gold = previous_gold
		game.player.upgrade_stacks = previous_stacks
		game.player.move_speed = previous_speed
	}

	game.player.upgrade_stacks = {}
	game.player.move_speed = PLAYER_BASE_MOVE_SPEED
	game.player.gold = upgrade_price(.Move_Speed, 0)

	bought := try_buy_upgrade(.Move_Speed)

	testing.expect(t, bought, "an affordable purchase should succeed")
	testing.expect(t, game.player.gold == 0, "the exact price should be deducted")
	testing.expect(t, game.player.upgrade_stacks[.Move_Speed] == 1, "the stack should increment by one")
	testing.expectf(
		t,
		game.player.move_speed == apply_upgrade_effect(PLAYER_BASE_MOVE_SPEED, .Move_Speed, 1),
		"move_speed should be re-derived from the base constant, got %v",
		game.player.move_speed,
	)
}

@(test)
test_try_buy_upgrade_max_health_heals_by_the_cap_increase :: proc(t: ^testing.T) {
	previous_gold := game.player.gold
	previous_stacks := game.player.upgrade_stacks
	previous_max := game.player.max_health
	previous_health := game.player.health
	defer {
		game.player.gold = previous_gold
		game.player.upgrade_stacks = previous_stacks
		game.player.max_health = previous_max
		game.player.health = previous_health
	}

	game.player.upgrade_stacks = {}
	game.player.max_health = PLAYER_BASE_MAX_HEALTH
	game.player.health = 10 // deliberately damaged, to prove this heals rather than just raising an empty cap
	game.player.gold = upgrade_price(.Max_Health, 0)

	bought := try_buy_upgrade(.Max_Health)
	testing.expect(t, bought, "sanity check: purchase should succeed")

	testing.expect(t, game.player.max_health > PLAYER_BASE_MAX_HEALTH, "max_health should rise")
	expected_health: f32 = 10 + (game.player.max_health - PLAYER_BASE_MAX_HEALTH)
	testing.expectf(
		t,
		game.player.health == expected_health,
		"health should rise by exactly the cap increase, expected %v got %v",
		expected_health,
		game.player.health,
	)
}

@(test)
test_try_buy_upgrade_fails_at_max_stack :: proc(t: ^testing.T) {
	previous_gold := game.player.gold
	previous_stacks := game.player.upgrade_stacks
	defer {
		game.player.gold = previous_gold
		game.player.upgrade_stacks = previous_stacks
	}

	game.player.upgrade_stacks = {}
	game.player.upgrade_stacks[.Move_Speed] = upgrade_presets[.Move_Speed].max_stack
	game.player.gold = 999999

	bought := try_buy_upgrade(.Move_Speed)

	testing.expect(t, !bought, "a purchase at the stack cap should fail regardless of gold")
	testing.expect(t, game.player.gold == 999999, "a failed (maxed) purchase should not deduct gold")
}

@(test)
test_try_buy_upgrade_damage_applies_immediately_to_the_live_weapon :: proc(t: ^testing.T) {
	previous_gold := game.player.gold
	previous_stacks := game.player.upgrade_stacks
	previous_weapon := game.player.weapon
	defer {
		game.player.gold = previous_gold
		game.player.upgrade_stacks = previous_stacks
		game.player.weapon = previous_weapon
	}

	game.player.upgrade_stacks = {}
	game.player.weapon = weapon_create(.Pistol)
	base_damage := game.player.weapon.damage
	game.player.gold = upgrade_price(.Damage, 0)

	bought := try_buy_upgrade(.Damage)

	testing.expect(t, bought, "sanity check: purchase should succeed")
	testing.expectf(
		t,
		game.player.weapon.damage == apply_upgrade_effect(base_damage, .Damage, 1),
		"the equipped weapon's damage should update immediately on purchase, got %v",
		game.player.weapon.damage,
	)
}

@(test)
test_try_buy_upgrade_clip_size_grants_the_bonus_as_usable_ammo_not_a_refill :: proc(t: ^testing.T) {
	previous_gold := game.player.gold
	previous_stacks := game.player.upgrade_stacks
	previous_weapon := game.player.weapon
	defer {
		game.player.gold = previous_gold
		game.player.upgrade_stacks = previous_stacks
		game.player.weapon = previous_weapon
	}

	game.player.upgrade_stacks = {}
	game.player.weapon = weapon_create(.Pistol)

	// fire off some ammo first, so a full-refill side effect would be
	// detectable if try_buy_upgrade accidentally recreated the weapon
	switch &v in game.player.weapon.variant {
	case Gun:
		v.ammo_in_clip -= 3
	case Melee_Weapon, Magic:
	}
	ammo_before_gun, _ := game.player.weapon.variant.(Gun)
	ammo_before := ammo_before_gun.ammo_in_clip

	game.player.gold = upgrade_price(.Clip_Size, 0)
	bought := try_buy_upgrade(.Clip_Size)
	testing.expect(t, bought, "sanity check: purchase should succeed")

	base := weapon_presets[.Pistol].variant.(Gun).clip_size
	bonus := upgraded_clip_size(base, 1) - base
	testing.expect(t, bonus > 0, "sanity check: a Clip_Size stack should raise the Pistol's capacity")

	new_gun, ok := game.player.weapon.variant.(Gun)
	testing.expect(t, ok, "sanity check: still a Gun")
	testing.expectf(
		t,
		new_gun.ammo_in_clip == ammo_before + bonus,
		"ammo_in_clip should rise by exactly the new capacity bonus (%v), not refill to full - expected %v got %v",
		bonus,
		ammo_before + bonus,
		new_gun.ammo_in_clip,
	)
}

@(test)
test_try_buy_next_weapon_tier_swaps_weapon_and_deducts_gold :: proc(t: ^testing.T) {
	previous_gold := game.player.gold
	previous_weapon := game.player.weapon
	defer {
		game.player.gold = previous_gold
		game.player.weapon = previous_weapon
	}

	game.player.weapon = weapon_create(.Pistol)
	price := weapon_tier_price(weapon_tier_index(.SMG))
	game.player.gold = price

	bought := try_buy_next_weapon_tier()

	testing.expect(t, bought, "an affordable tier purchase should succeed")
	testing.expect(t, game.player.weapon.kind == .SMG, "the next tier should be equipped")
	testing.expect(t, game.player.gold == 0, "the exact tier price should be deducted")
}

@(test)
test_try_buy_next_weapon_tier_reapplies_owned_upgrade_stacks :: proc(t: ^testing.T) {
	previous_gold := game.player.gold
	previous_weapon := game.player.weapon
	previous_stacks := game.player.upgrade_stacks
	defer {
		game.player.gold = previous_gold
		game.player.weapon = previous_weapon
		game.player.upgrade_stacks = previous_stacks
	}

	game.player.upgrade_stacks = {}
	game.player.upgrade_stacks[.Damage] = 3
	game.player.weapon = weapon_create(.Pistol) // applies the 3 stacks
	game.player.gold = weapon_tier_price(weapon_tier_index(.SMG))

	bought := try_buy_next_weapon_tier()
	testing.expect(t, bought, "sanity check: purchase should succeed")

	expected := apply_upgrade_effect(weapon_presets[.SMG].damage, .Damage, 3)
	testing.expectf(
		t,
		game.player.weapon.damage == expected,
		"purchased Upgrade stacks should survive a tier purchase, reapplied onto the new tier (expected %v got %v)",
		expected,
		game.player.weapon.damage,
	)
}

@(test)
test_try_buy_next_weapon_tier_fails_at_top_tier :: proc(t: ^testing.T) {
	previous_gold := game.player.gold
	previous_weapon := game.player.weapon
	defer {
		game.player.gold = previous_gold
		game.player.weapon = previous_weapon
	}

	// walked rather than named, so a ladder gaining a rung moves this test with
	// it instead of quietly leaving it asserting about a mid-ladder weapon
	top := weapon_family_starter(.Ranged)
	for next, has_next := weapon_next_tier(top).?; has_next; next, has_next = weapon_next_tier(top).? {
		top = next
	}

	game.player.weapon = weapon_create(top)
	game.player.gold = 999999

	bought := try_buy_next_weapon_tier()

	testing.expectf(t, !bought, "%v is Ranged's top tier and should have no next tier to buy", top)
	testing.expect(t, game.player.gold == 999999, "a failed (no next tier) purchase should not deduct gold")
}

@(test)
test_start_new_run_resets_run_scoped_state_but_not_account_progression :: proc(t: ^testing.T) {
	previous_gold := game.player.gold
	previous_gold_earned := game.player.gold_earned
	previous_kills := game.player.kills
	previous_survival := game.player.survival_seconds
	previous_stacks := game.player.upgrade_stacks
	previous_speed := game.player.move_speed
	previous_max := game.player.max_health
	previous_health := game.player.health
	previous_weapon := game.player.weapon
	previous_run_started := game.player.run_started
	previous_banked := game.player.banked_progress
	previous_level := game.player.level
	previous_run_start_gold := game.player.run_start_gold
	previous_account_stat_stacks := game.player.account_stat_stacks
	defer {
		game.player.gold = previous_gold
		game.player.gold_earned = previous_gold_earned
		game.player.kills = previous_kills
		game.player.survival_seconds = previous_survival
		game.player.upgrade_stacks = previous_stacks
		game.player.move_speed = previous_speed
		game.player.max_health = previous_max
		game.player.health = previous_health
		game.player.weapon = previous_weapon
		game.player.run_started = previous_run_started
		game.player.banked_progress = previous_banked
		game.player.level = previous_level
		game.player.run_start_gold = previous_run_start_gold
		game.player.account_stat_stacks = previous_account_stat_stacks
		game.run_ended = false
	}

	game.player.account_stat_stacks = {}
	game.player.banked_progress = 42
	game.player.level = 7
	game.player.run_start_gold = 0
	game.player.gold = 500
	game.player.gold_earned = 500
	game.player.kills = {}
	game.player.kills[.Grunt] = 9
	game.player.survival_seconds = 123
	game.player.upgrade_stacks = {}
	game.player.upgrade_stacks[.Damage] = 4
	game.player.move_speed = 250
	game.player.max_health = 300
	game.player.health = 3
	game.player.weapon = weapon_create(.Shotgun)
	game.player.run_started = false
	game.run_ended = true

	start_new_run(weapon_family_starter(.Ranged))

	testing.expect(t, game.player.gold_earned == 0, "start_new_run should zero gold_earned")
	testing.expect(t, total_kills(game.player.kills) == 0, "start_new_run should zero kills")
	testing.expect(t, game.player.survival_seconds == 0, "start_new_run should zero survival_seconds")
	testing.expect(t, game.player.upgrade_stacks[.Damage] == 0, "start_new_run should zero every Upgrade stack")
	testing.expect(t, game.player.move_speed == PLAYER_BASE_MOVE_SPEED, "start_new_run should reset move_speed to base")
	testing.expect(t, game.player.max_health == PLAYER_BASE_MAX_HEALTH, "start_new_run should reset max_health to base")
	testing.expect(t, game.player.health == game.player.max_health, "start_new_run should heal to the reset max_health")
	testing.expect(
		t,
		game.player.weapon.kind == weapon_family_starter(.Ranged),
		"start_new_run should equip the picked starter weapon",
	)
	testing.expect(t, game.player.run_started, "start_new_run should mark the Run as started")
	testing.expect(t, !game.run_ended, "start_new_run should close the Run End modal")

	testing.expect(t, game.player.banked_progress == 42, "start_new_run must not touch banked_progress (Account progression)")
	testing.expect(t, game.player.level == 7, "start_new_run must not touch level (Account progression)")

	// Gold is Account-scoped now (ADR-0016): a new Run inherits the wallet
	// intact and only records the balance it started from, so bank_run_gold
	// can tell this Run's take from savings carried in.
	testing.expect(t, game.player.gold == 500, "start_new_run must not zero Gold (ADR-0016)")
	testing.expect(
		t,
		game.player.run_start_gold == 500,
		"start_new_run should record the wallet's balance as this Run's starting baseline",
	)
}
