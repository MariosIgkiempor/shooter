package shooter

import "core:math"
import "core:testing"

// Upgrade_Kind's catalog table/effect-application is pure data + arithmetic
// with no reliance on game.enemies/game.bullets etc, but apply_upgrades and
// upgrade_maxed do read game.player - reset/restore it around each test the
// same way weapon_test.odin's suite resets its own shared globals (see that
// file's header comment on ODIN_TEST_THREADS=1).

@(test)
test_upgrade_price_grows_geometrically_per_stack :: proc(t: ^testing.T) {
	preset := upgrade_presets[.Damage]

	price_0 := upgrade_price(.Damage, 0)
	price_1 := upgrade_price(.Damage, 1)
	price_2 := upgrade_price(.Damage, 2)

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
test_upgrade_maxed_true_only_at_or_above_cap :: proc(t: ^testing.T) {
	previous := game.player.upgrade_stacks[.Move_Speed]
	defer game.player.upgrade_stacks[.Move_Speed] = previous

	cap := upgrade_presets[.Move_Speed].max_stack

	game.player.upgrade_stacks[.Move_Speed] = cap - 1
	testing.expect(t, !upgrade_maxed(.Move_Speed), "one below cap should not read as maxed")

	game.player.upgrade_stacks[.Move_Speed] = cap
	testing.expect(t, upgrade_maxed(.Move_Speed), "exactly at cap should read as maxed")
}

@(test)
test_upgrade_available_to_family_gates_family_specific_upgrades :: proc(t: ^testing.T) {
	testing.expect(t, upgrade_available_to_family(.Damage, .Melee), "general Upgrades should be available to every family")
	testing.expect(t, upgrade_available_to_family(.Damage, .Ranged), "general Upgrades should be available to every family")

	testing.expect(t, upgrade_available_to_family(.Clip_Size, .Ranged), "Clip_Size should be available to Ranged")
	testing.expect(t, !upgrade_available_to_family(.Clip_Size, .Melee), "Clip_Size should be gated away from Melee")
	testing.expect(t, !upgrade_available_to_family(.Clip_Size, .Magic), "Clip_Size should be gated away from Magic")
}

@(test)
test_apply_upgrade_effect_multiplicative_compounds_via_pow_not_repeated_multiplication :: proc(t: ^testing.T) {
	base: f32 = 10
	result := apply_upgrade_effect(base, .Damage, 3)

	mult := f32(upgrade_presets[.Damage].effect.(Multiplicative))
	expected := base * math.pow(mult, f32(3))

	testing.expect(t, result == expected, "Multiplicative effects should compound as base * mult^n")
}

@(test)
test_apply_upgrade_effect_additive_scales_linearly :: proc(t: ^testing.T) {
	base: f32 = 5
	result := apply_upgrade_effect(base, .Max_Health, 4)

	amount := f32(upgrade_presets[.Max_Health].effect.(Additive))
	expected := base + amount * 4

	testing.expect(t, result == expected, "Additive effects should scale as base + amount*n")
}

@(test)
test_apply_upgrades_recomputes_from_preset_baseline_not_the_live_weapon :: proc(t: ^testing.T) {
	previous_stacks := game.player.upgrade_stacks
	defer game.player.upgrade_stacks = previous_stacks
	game.player.upgrade_stacks = {}
	game.player.upgrade_stacks[.Damage] = 2

	weapon := weapon_create(.Pistol) // applies the 2 stacks once via weapon_create

	// simulate a stale/mutated live value the way a bug (or another
	// subsystem) might leave it - apply_upgrades must ignore this and
	// re-derive from weapon_presets[.Pistol].damage instead, or a second
	// call here would double-count on top of it
	weapon.damage = 99999

	apply_upgrades(&weapon, game.player.upgrade_stacks, game.player.account_stat_stacks)

	expected := apply_upgrade_effect(weapon_presets[.Pistol].damage, .Damage, 2)
	testing.expectf(
		t,
		weapon.damage == expected,
		"apply_upgrades should derive damage from the preset baseline (expected %v), not compound on the live field (got %v)",
		expected,
		weapon.damage,
	)
}

@(test)
test_apply_upgrades_layers_might_account_stat_under_damage_upgrade :: proc(t: ^testing.T) {
	previous_upgrade_stacks := game.player.upgrade_stacks
	previous_account_stat_stacks := game.player.account_stat_stacks
	defer {
		game.player.upgrade_stacks = previous_upgrade_stacks
		game.player.account_stat_stacks = previous_account_stat_stacks
	}
	game.player.upgrade_stacks = {}
	game.player.upgrade_stacks[.Damage] = 2
	game.player.account_stat_stacks = {}
	game.player.account_stat_stacks[.Might] = 3

	weapon := weapon_create(.Pistol)

	might_base := apply_account_stat_effect(weapon_presets[.Pistol].damage, .Might, 3)
	expected := apply_upgrade_effect(might_base, .Damage, 2)
	testing.expectf(
		t,
		weapon.damage == expected,
		"Might should raise the preset baseline before Damage-Upgrade stacks compound on top (expected %v, got %v)",
		expected,
		weapon.damage,
	)

	testing.expectf(
		t,
		weapon.damage > apply_upgrade_effect(weapon_presets[.Pistol].damage, .Damage, 2),
		"Might should raise damage above what Damage-Upgrade stacks alone would produce",
	)
}

@(test)
test_apply_upgrades_scales_a_gun_s_clip_size_from_its_preset_baseline :: proc(t: ^testing.T) {
	previous_stacks := game.player.upgrade_stacks
	defer game.player.upgrade_stacks = previous_stacks
	game.player.upgrade_stacks = {}
	game.player.upgrade_stacks[.Clip_Size] = 3

	weapon := weapon_create(.Pistol)

	gun, ok := weapon.variant.(Gun)
	testing.expect(t, ok, "sanity check: Pistol should be a Gun")

	// spelled out rather than recomputed through upgraded_clip_size, so this
	// asserts the multiplier's actual arithmetic instead of restating it:
	// the Pistol's 12 * 1.15^3 = 18.25, rounded to 18. The baseline is pinned
	// first so retuning the Pistol fails with the reason rather than leaving
	// the message below claiming an arithmetic that no longer applies.
	testing.expect(
		t,
		weapon_presets[.Pistol].variant.(Gun).clip_size == 12,
		"this test's expected value is derived from a 12-round Pistol clip",
	)
	testing.expectf(
		t,
		gun.clip_size == 18,
		"12 * 1.15^3 rounds to 18, got %v",
		gun.clip_size,
	)
	testing.expect(t, gun.ammo_in_clip == gun.clip_size, "a freshly created weapon should start with a full (upgraded) clip")
}

@(test)
test_every_clip_size_stack_grows_every_gun_s_clip :: proc(t: ^testing.T) {
	// the guard rail on the rounding rule in upgraded_clip_size. A multiplier
	// on a small enough clip rounds back onto the same integer, and a stack
	// that costs gold and changes nothing is the failure mode a flat bonus
	// could never have. Runs over every Gun preset so a new low-clip weapon
	// (a rifle, say) fails here rather than in someone's hands.
	max_stack := upgrade_presets[.Clip_Size].max_stack
	for kind in Weapon_Kind {
		base, is_gun := weapon_presets[kind].variant.(Gun)
		if !is_gun {
			continue
		}

		previous := base.clip_size
		for stack in 1 ..= max_stack {
			current := upgraded_clip_size(base.clip_size, stack)
			testing.expectf(
				t,
				current > previous,
				"%v's Clip_Size stack %v buys nothing: clip stayed at %v",
				kind,
				stack,
				current,
			)
			previous = current
		}
	}
}

@(test)
test_clip_size_scales_in_proportion_rather_than_by_a_flat_amount :: proc(t: ^testing.T) {
	// the whole point of the change (issue 19-reach-and-clip-size): the same
	// purchase should be worth the same to a Shotgun and to an SMG, whose
	// clips differ five-fold. Under the retired Additive(2) these two ratios
	// were 4.3x and 1.7x.
	stacks := upgrade_presets[.Clip_Size].max_stack
	shotgun := weapon_presets[.Shotgun].variant.(Gun).clip_size
	smg := weapon_presets[.SMG].variant.(Gun).clip_size

	shotgun_ratio := f32(upgraded_clip_size(shotgun, stacks)) / f32(shotgun)
	smg_ratio := f32(upgraded_clip_size(smg, stacks)) / f32(smg)

	// tolerance covers rounding, which moves a six-round clip's ratio by up to
	// half a round in twelve
	testing.expectf(
		t,
		math.abs(shotgun_ratio - smg_ratio) < 0.2,
		"a maxed Clip_Size should multiply every clip alike: Shotgun %vx, SMG %vx",
		shotgun_ratio,
		smg_ratio,
	)
}

@(test)
test_apply_upgrades_extends_a_melee_weapon_s_reach :: proc(t: ^testing.T) {
	previous_stacks := game.player.upgrade_stacks
	defer game.player.upgrade_stacks = previous_stacks
	game.player.upgrade_stacks = {}
	game.player.upgrade_stacks[.Reach] = 2

	weapon := weapon_create(.Sword)

	melee, ok := weapon.variant.(Melee_Weapon)
	testing.expect(t, ok, "sanity check: Sword should be a Melee_Weapon")

	base := weapon_presets[.Sword].variant.(Melee_Weapon)
	expected := apply_upgrade_effect(base.range, .Reach, 2)
	testing.expectf(
		t,
		melee.range == expected,
		"Reach stacks should extend range from the preset baseline %v to %v, got %v",
		base.range,
		expected,
		melee.range,
	)
	testing.expect(t, melee.range > base.range, "a Reach stack that does not lengthen the weapon is not reach")
}

@(test)
test_apply_magic_range_upgrade_extends_fireball_via_bullet_lifetime :: proc(t: ^testing.T) {
	previous_stacks := game.player.upgrade_stacks
	defer game.player.upgrade_stacks = previous_stacks
	game.player.upgrade_stacks = {}
	game.player.upgrade_stacks[.Range] = 2

	weapon := weapon_create(.Fire_Wand)
	magic, ok := weapon.variant.(Magic)
	testing.expect(t, ok, "sanity check: Fire_Wand should be a Magic variant")

	base := weapon_presets[.Fire_Wand].variant.(Magic)
	extra_px := apply_upgrade_effect(0, .Range, 2)
	expected := base.bullet_lifetime + extra_px / base.projectile_speed

	testing.expectf(
		t,
		magic.bullet_lifetime == expected,
		"Fireball has no range field, so Range stacks should extend bullet_lifetime instead (expected %v, got %v)",
		expected,
		magic.bullet_lifetime,
	)
}
