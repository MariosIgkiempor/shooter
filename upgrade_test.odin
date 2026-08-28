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
test_apply_upgrades_gun_clip_size_derives_from_preset_plus_stacks :: proc(t: ^testing.T) {
	previous_stacks := game.player.upgrade_stacks
	defer game.player.upgrade_stacks = previous_stacks
	game.player.upgrade_stacks = {}
	game.player.upgrade_stacks[.Clip_Size] = 3

	weapon := weapon_create(.Pistol)

	gun, ok := weapon.variant.(Gun)
	testing.expect(t, ok, "sanity check: Pistol should be a Gun")

	bonus := int(apply_upgrade_effect(0, .Clip_Size, 3))
	testing.expectf(
		t,
		gun.clip_size == weapon_presets[.Pistol].variant.(Gun).clip_size + bonus,
		"clip_size should be preset base + Clip_Size stack bonus, got %v",
		gun.clip_size,
	)
	testing.expect(t, gun.ammo_in_clip == gun.clip_size, "a freshly created weapon should start with a full (upgraded) clip")
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
