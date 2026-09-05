package shooter

import "core:math/linalg"
import "core:testing"

// Every test drives try_use_weapon/update_weapon/resolve_weapon_action
// directly with controlled dt steps - no real game loop, no rendering, no
// raylib window needed (see spec's Testing Decisions). Tests assert on
// external, observable behavior: timer-driven phase transitions and emitted
// side effects (a bullet spawned, an enemy took damage, a cloud was placed,
// ammo was consumed) - never on draw_weapon()'s rendering math.
//
// resolve_weapon_action's Melee/Magic paths mutate game.enemies/game.bullets/
// game.poison_clouds via existing globals, so each test resets the slice of
// global state it depends on at the top rather than relying on it being
// empty by default. Odin's test runner parallelizes @(test) procs across
// threads by default, which races on that shared game global (two tests
// touching game.bullets at once) - run this suite with
// `odin test . -define:ODIN_TEST_THREADS=1` (or ODIN_TEST_THREADS=1 in the
// environment) to get deterministic results.

TEST_ORIGIN :: Vec2{0, 0}
TEST_AIM :: Vec2{1, 0}
TEST_MOUSE :: Vec2{50, 0}

@(test)
test_semi_automatic_never_resolves_before_windup_completes :: proc(t: ^testing.T) {
	clear(&game.bullets)
	defer clear(&game.bullets)
	// try_fire_gun also spawns a muzzle streak burst/flash (art-revamp
	// ticket 02) - clean those up too so they don't bleed into whichever
	// unrelated test runs next in the suite
	clear(&game.particles)
	defer clear(&game.particles)

	weapon := weapon_create(.Pistol)
	try_use_weapon(&weapon, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])

	testing.expect(t, len(game.bullets) == 0, "Pistol should not fire on Trigger, only start Winding Up")
	testing.expect(t, weapon.windup_timer > 0, "Pistol should have a running windup_timer after Trigger")

	windup_duration := weapon.windup_fraction / weapon.action_rate
	update_weapon(&weapon, windup_duration - 0.01, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
	testing.expect(t, len(game.bullets) == 0, "Pistol should not resolve before Windup completes")

	update_weapon(&weapon, 0.02, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
	testing.expect(t, len(game.bullets) == 1, "Pistol should resolve the instant Windup completes")
}

@(test)
test_automatic_resolves_immediately_with_no_windup :: proc(t: ^testing.T) {
	clear(&game.bullets)
	defer clear(&game.bullets)
	// try_fire_gun also spawns a muzzle streak burst/flash (art-revamp
	// ticket 02) - clean those up too so they don't bleed into whichever
	// unrelated test runs next in the suite
	clear(&game.particles)
	defer clear(&game.particles)

	weapon := weapon_create(.SMG)
	try_use_weapon(&weapon, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])

	testing.expect(t, len(game.bullets) == 1, "SMG (Automatic) should resolve immediately on Trigger")
	testing.expect(t, weapon.windup_timer == 0, "Automatic weapons should never observe a Windup")
	testing.expect(t, weapon.follow_through_timer > 0, "SMG should start its Follow-through after resolving")
}

@(test)
test_completed_windup_resolves_exactly_once :: proc(t: ^testing.T) {
	clear(&game.bullets)
	defer clear(&game.bullets)
	// try_fire_gun also spawns a muzzle streak burst/flash (art-revamp
	// ticket 02) - clean those up too so they don't bleed into whichever
	// unrelated test runs next in the suite
	clear(&game.particles)
	defer clear(&game.particles)

	weapon := weapon_create(.Pistol)
	try_use_weapon(&weapon, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])

	windup_duration := weapon.windup_fraction / weapon.action_rate
	update_weapon(&weapon, windup_duration + 0.01, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
	testing.expect(t, len(game.bullets) == 1, "Windup completion should resolve exactly one bullet")

	// several more frames sitting at windup_timer <= 0 - must not re-resolve
	for _ in 0 ..< 5 {
		update_weapon(&weapon, 0.05, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
	}
	testing.expect(t, len(game.bullets) == 1, "a completed Windup must not resolve again on subsequent frames")
}

@(test)
test_cooldown_and_windup_start_together_at_trigger :: proc(t: ^testing.T) {
	weapon := weapon_create(.Pistol)
	try_use_weapon(&weapon, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])

	expected_cooldown := 1.0 / weapon.action_rate
	expected_windup := weapon.windup_fraction / weapon.action_rate

	testing.expect(t, weapon.cooldown_timer == expected_cooldown, "cooldown_timer should start at 1/action_rate")
	testing.expect(
		t,
		weapon.windup_timer == expected_windup,
		"windup_timer should start at windup_fraction/action_rate, the same instant as cooldown_timer",
	)
}

@(test)
test_total_cycle_length_unaffected_by_windup :: proc(t: ^testing.T) {
	clear(&game.bullets)
	defer clear(&game.bullets)
	clear(&game.poison_clouds)
	defer clear(&game.poison_clouds)
	// Gun/Fireball resolves also spawn muzzle particles (art-revamp ticket
	// 02) - clean those up too so they don't bleed into whichever unrelated
	// test runs next in the suite
	clear(&game.particles)
	defer clear(&game.particles)

	dt: f32 = 1.0 / 60.0

	for kind in Weapon_Kind {
		preset := weapon_presets[kind]
		if preset.fire_mode != .Semi_Automatic {
			continue
		}

		weapon := weapon_create(kind)
		try_use_weapon(&weapon, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])

		cycle := 1.0 / weapon.action_rate
		elapsed: f32 = 0
		for weapon.cooldown_timer > 0 {
			update_weapon(&weapon, dt, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
			elapsed += dt
		}

		diff := elapsed - cycle
		if diff < 0 {
			diff = -diff
		}
		testing.expectf(
			t,
			diff < dt,
			"%v's total cycle length should stay ~1/action_rate (%v) regardless of Windup, got %v",
			kind,
			cycle,
			elapsed,
		)
	}
}

@(test)
test_empty_clip_never_starts_windup_or_cooldown :: proc(t: ^testing.T) {
	weapon := weapon_create(.Pistol)
	switch &v in weapon.variant {
	case Gun:
		v.ammo_in_clip = 0
	case Melee_Weapon, Magic:
	}

	try_use_weapon(&weapon, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])

	testing.expect(t, weapon.windup_timer == 0, "an empty clip should never start a Windup")
	testing.expect(t, weapon.cooldown_timer == 0, "an empty clip should never start the cooldown either")

	gun, ok := weapon.variant.(Gun)
	testing.expect(t, ok && gun.reload_timer > 0, "an empty clip should still trigger a reload, same as today")
}

@(test)
test_stacked_upgrades_never_let_windup_exceed_cooldown_window :: proc(t: ^testing.T) {
	previous_stacks := game.player.upgrade_stacks
	defer game.player.upgrade_stacks = previous_stacks

	for kind in Weapon_Kind {
		preset := weapon_presets[kind]
		if preset.fire_mode != .Semi_Automatic {
			continue
		}

		game.player.upgrade_stacks[.Action_Rate] = upgrade_presets[.Action_Rate].max_stack
		weapon := weapon_create(kind)

		windup_duration := weapon.windup_fraction / weapon.action_rate
		cycle := 1.0 / weapon.action_rate
		testing.expectf(
			t,
			windup_duration <= cycle,
			"%v's derived Windup duration (%v) must never exceed its cooldown window (%v), even at max Action_Rate stacks",
			kind,
			windup_duration,
			cycle,
		)
	}
}

@(test)
test_switching_weapon_mid_windup_leaves_no_dangling_state :: proc(t: ^testing.T) {
	weapon := weapon_create(.Pistol)
	try_use_weapon(&weapon, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
	testing.expect(t, weapon.windup_timer > 0, "sanity check: Pistol should be mid-Windup")

	// weapon_create overwrites the Weapon struct outright, as it already
	// does today for the dev/debug weapon-switching cycle
	weapon = weapon_create(.SMG)

	testing.expect(t, weapon.windup_timer == 0, "switching mid-Windup should leave no dangling windup_timer")
	testing.expect(t, weapon.cooldown_timer == 0, "switching mid-Windup should leave no dangling cooldown_timer")
	testing.expect(t, weapon.follow_through_timer == 0, "switching mid-Windup should leave no dangling follow_through_timer")
}

@(test)
test_poison_cloud_target_locks_at_trigger_not_resolve :: proc(t: ^testing.T) {
	clear(&game.poison_clouds)
	defer clear(&game.poison_clouds)

	weapon := weapon_create(.Poison_Staff)
	trigger_mouse := Vec2{40, 0}
	try_use_weapon(&weapon, TEST_ORIGIN, TEST_AIM, trigger_mouse, game.enemies[:])

	windup_duration := weapon.windup_fraction / weapon.action_rate
	moved_mouse := Vec2{-30, 70} // mouse moves elsewhere before Resolve
	update_weapon(&weapon, windup_duration + 0.01, TEST_ORIGIN, TEST_AIM, moved_mouse, game.enemies[:])

	testing.expect(t, len(game.poison_clouds) == 1, "Poison_Staff should resolve into exactly one cloud")
	testing.expect(
		t,
		game.poison_clouds[0].position == trigger_mouse,
		"Poison_Cloud should land at the Trigger-time mouse position, unaffected by mouse_world moving during Windup",
	)
}

@(test)
test_fireball_target_tracks_live_aim_through_windup :: proc(t: ^testing.T) {
	clear(&game.bullets)
	defer clear(&game.bullets)
	// Fireball's Resolve also spawns a muzzle flash (art-revamp ticket 02) -
	// clean that up too so it doesn't bleed into whichever unrelated test
	// runs next in the suite
	clear(&game.particles)
	defer clear(&game.particles)

	weapon := weapon_create(.Fire_Wand)
	trigger_aim := Vec2{1, 0}
	try_use_weapon(&weapon, TEST_ORIGIN, trigger_aim, TEST_MOUSE, game.enemies[:])

	windup_duration := weapon.windup_fraction / weapon.action_rate
	resolve_aim := Vec2{0, 1} // aim changes before Resolve
	update_weapon(&weapon, windup_duration + 0.01, TEST_ORIGIN, resolve_aim, TEST_MOUSE, game.enemies[:])

	testing.expect(t, len(game.bullets) == 1, "Fire_Wand should resolve into exactly one fireball bullet")

	gun_variant, is_magic := weapon.variant.(Magic)
	testing.expect(t, is_magic, "sanity check: Fire_Wand should be a Magic variant")

	expected_velocity := resolve_aim * gun_variant.projectile_speed
	testing.expect(
		t,
		game.bullets[0].velocity == expected_velocity,
		"Fireball should launch toward the live aim_dir at Resolve, not the aim_dir at Trigger",
	)
}

@(test)
test_flamethrower_uses_this_ticks_live_aim :: proc(t: ^testing.T) {
	clear(&game.enemies)
	defer clear(&game.enemies)
	clear(&game.particles)
	defer clear(&game.particles)

	// Flame_Staff's range/arc_degrees = 50/50 - place one enemy along +x
	// (hit by aim_dir {1,0}) and another along +y (hit by aim_dir {0,1})
	append(&game.enemies, Enemy{rect = {x = 30, y = 0}, health = 100})
	append(&game.enemies, Enemy{rect = {x = 0, y = 30}, health = 100})

	weapon := weapon_create(.Flame_Staff)

	try_use_weapon(&weapon, TEST_ORIGIN, Vec2{1, 0}, TEST_MOUSE, game.enemies[:])
	testing.expect(t, game.enemies[0].health < 100, "the enemy along the live aim_dir should take tick damage")
	testing.expect(t, game.enemies[1].health == 100, "the enemy off the live aim_dir should be untouched")

	weapon.cooldown_timer = 0 // force-ready so the second Trigger below can act again
	try_use_weapon(&weapon, TEST_ORIGIN, Vec2{0, 1}, TEST_MOUSE, game.enemies[:])
	testing.expect(t, game.enemies[1].health < 100, "switching aim_dir on the next tick should hit the newly-aimed-at enemy")
}

// -- muzzle position (the bug: effects spawned at the player's feet) --------
//
// `origin` threaded through try_use_weapon is the player's bottom-center
// anchor (see actor_collision_rect's note, main.odin), which is where the
// player *stands*, not where the weapon *points from*. Bullets and muzzle
// effects belong at the far end of the drawn weapon shape - these lock that
// down at the observable-side-effect seam (a spawned Bullet / Particle)
// rather than against draw_weapon's rendering math.

// where TEST_ORIGIN/TEST_AIM put `kind`'s business end, re-derived from the
// glyph tables (weapon_visuals/weapon_icon_reach) rather than by calling
// weapon_muzzle_position, which would assert nothing about itself
test_expected_muzzle :: proc(kind: Weapon_Kind) -> Vec2 {
	reach := weapon_visuals[kind].length * weapon_visual_scale * weapon_icon_reach[kind]
	return TEST_ORIGIN + Vec2{0, -ACTOR_SIZE.y / 2} + TEST_AIM * reach
}

@(test)
test_gun_bullets_spawn_at_the_muzzle_not_the_player_anchor :: proc(t: ^testing.T) {
	clear(&game.bullets)
	defer clear(&game.bullets)
	clear(&game.particles)
	defer clear(&game.particles)

	weapon := weapon_create(.SMG) // Automatic - resolves immediately on Trigger
	try_use_weapon(&weapon, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])

	testing.expect(t, len(game.bullets) == 1, "sanity check: SMG should have fired one bullet")

	expected := test_expected_muzzle(.SMG)
	testing.expectf(
		t,
		linalg.length(game.bullets[0].position - expected) < 0.01,
		"bullet should spawn at the gun's muzzle %v, got %v",
		expected,
		game.bullets[0].position,
	)
}

@(test)
test_gun_muzzle_flash_spawns_at_the_muzzle_not_the_player_anchor :: proc(t: ^testing.T) {
	clear(&game.bullets)
	defer clear(&game.bullets)
	clear(&game.particles)
	defer clear(&game.particles)

	weapon := weapon_create(.SMG)
	try_use_weapon(&weapon, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])

	expected := test_expected_muzzle(.SMG)

	flash_found := false
	for particle in game.particles {
		if _, is_flash := particle.visual.(Particle_Flash); !is_flash {
			continue
		}
		flash_found = true
		testing.expectf(
			t,
			linalg.length(particle.position - expected) < 0.01,
			"muzzle flash should spawn at the gun's muzzle %v, got %v",
			expected,
			particle.position,
		)
	}
	testing.expect(t, flash_found, "sanity check: firing should have spawned a muzzle flash")
}

@(test)
test_fireball_spawns_at_the_magic_orb_not_the_player_anchor :: proc(t: ^testing.T) {
	clear(&game.bullets)
	defer clear(&game.bullets)
	clear(&game.particles)
	defer clear(&game.particles)

	weapon := weapon_create(.Fire_Wand) // Semi_Automatic - resolves on Windup completion
	try_use_weapon(&weapon, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])
	windup_duration := weapon.windup_fraction / weapon.action_rate
	update_weapon(&weapon, windup_duration + 0.01, TEST_ORIGIN, TEST_AIM, TEST_MOUSE, game.enemies[:])

	testing.expect(t, len(game.bullets) == 1, "sanity check: Fire_Wand should have cast one fireball")

	expected := test_expected_muzzle(.Fire_Wand)
	testing.expectf(
		t,
		linalg.length(game.bullets[0].position - expected) < 0.01,
		"fireball should spawn at the wand's orb %v, got %v",
		expected,
		game.bullets[0].position,
	)
}
