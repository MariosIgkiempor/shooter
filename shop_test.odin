package shooter

import "core:testing"

// try_buy_upgrade/try_buy_next_weapon_tier/restart_game all read and mutate
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

	bonus := int(apply_upgrade_effect(0, .Clip_Size, 1))
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

	game.player.weapon = weapon_create(.Shotgun) // Ranged's top tier
	game.player.gold = 999999

	bought := try_buy_next_weapon_tier()

	testing.expect(t, !bought, "a weapon already at the top tier should have no next tier to buy")
	testing.expect(t, game.player.gold == 999999, "a failed (no next tier) purchase should not deduct gold")
}

@(test)
test_restart_game_resets_run_scoped_state_but_not_account_progression :: proc(t: ^testing.T) {
	previous_gold := game.player.gold
	previous_stacks := game.player.upgrade_stacks
	previous_speed := game.player.move_speed
	previous_max := game.player.max_health
	previous_health := game.player.health
	previous_weapon := game.player.weapon
	previous_class := game.player.class
	previous_xp := game.player.xp
	previous_level := game.player.level
	defer {
		game.player.gold = previous_gold
		game.player.upgrade_stacks = previous_stacks
		game.player.move_speed = previous_speed
		game.player.max_health = previous_max
		game.player.health = previous_health
		game.player.weapon = previous_weapon
		game.player.class = previous_class
		game.player.xp = previous_xp
		game.player.level = previous_level
		game.game_over = false
	}

	game.player.class = .Ranged
	game.player.xp = 42
	game.player.level = 7
	game.player.gold = 500
	game.player.upgrade_stacks = {}
	game.player.upgrade_stacks[.Damage] = 4
	game.player.move_speed = 250
	game.player.max_health = 300
	game.player.health = 3
	game.player.weapon = weapon_create(.Shotgun)
	game.game_over = true

	restart_game()

	testing.expect(t, game.player.gold == 0, "Restart should zero Gold")
	testing.expect(t, game.player.upgrade_stacks[.Damage] == 0, "Restart should zero every Upgrade stack")
	testing.expect(t, game.player.move_speed == PLAYER_BASE_MOVE_SPEED, "Restart should reset move_speed to base")
	testing.expect(t, game.player.max_health == PLAYER_BASE_MAX_HEALTH, "Restart should reset max_health to base")
	testing.expect(t, game.player.health == game.player.max_health, "Restart should heal to the reset max_health")
	testing.expect(
		t,
		game.player.weapon.kind == class_weapon_kinds[.Ranged][0],
		"Restart should re-equip the Class's tier-1 weapon",
	)
	testing.expect(t, !game.game_over, "Restart should close the game-over modal")

	testing.expect(t, game.player.class == .Ranged, "Restart must not touch Class (Account progression)")
	testing.expect(t, game.player.xp == 42, "Restart must not touch xp (Account progression)")
	testing.expect(t, game.player.level == 7, "Restart must not touch level (Account progression)")
}
