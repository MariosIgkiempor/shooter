package shooter

import "core:math"
import "core:math/linalg"
import "core:testing"

// Relic's pricing/unlock/cap table is pure data + arithmetic, but
// try_buy_relic and update_relics read and write game.player and
// game.enemies, and update_relics reaches the apply_hit_to_enemy seam (which
// also appends to game.pickups/particles/damage_numbers). Snapshot and
// restore every global each test touches, the same discipline
// upgrade_test.odin and debug_test.odin apply - this suite races the same
// way if run in parallel, hence ODIN_TEST_THREADS=1.

@(test)
test_relic_price_grows_geometrically_per_stack :: proc(t: ^testing.T) {
	preset := relic_presets[.Orbiting_Orb]

	price_0 := relic_price(.Orbiting_Orb, 0)
	price_1 := relic_price(.Orbiting_Orb, 1)
	price_2 := relic_price(.Orbiting_Orb, 2)

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
test_relic_maxed_true_only_at_or_above_cap :: proc(t: ^testing.T) {
	previous := game.player.relic_stacks[.Orbiting_Orb]
	defer game.player.relic_stacks[.Orbiting_Orb] = previous

	cap := relic_presets[.Orbiting_Orb].max_stack

	game.player.relic_stacks[.Orbiting_Orb] = cap - 1
	testing.expect(t, !relic_maxed(.Orbiting_Orb), "one below cap should not read as maxed")

	game.player.relic_stacks[.Orbiting_Orb] = cap
	testing.expect(t, relic_maxed(.Orbiting_Orb), "exactly at cap should read as maxed")
}

@(test)
test_relic_unlocked_gates_on_account_level :: proc(t: ^testing.T) {
	previous := game.player.level
	defer game.player.level = previous

	unlock := relic_presets[.Orbiting_Orb].unlock_level

	game.player.level = unlock - 1
	testing.expect(t, !relic_unlocked(.Orbiting_Orb), "below unlock_level the Relic should read as locked")

	game.player.level = unlock
	testing.expect(t, relic_unlocked(.Orbiting_Orb), "exactly at unlock_level the Relic should read as unlocked")
}

@(test)
test_try_buy_relic_deducts_gold_and_increments_stack :: proc(t: ^testing.T) {
	previous_player := game.player
	defer game.player = previous_player

	game.player.level = relic_presets[.Orbiting_Orb].unlock_level
	game.player.relic_stacks = {}
	price := relic_price(.Orbiting_Orb, 0)
	game.player.gold = price + 5

	testing.expect(t, try_buy_relic(.Orbiting_Orb), "an unlocked, unmaxed, affordable Relic should buy")
	testing.expectf(
		t,
		game.player.gold == 5,
		"buying should deduct exactly the quoted price, leaving 5, got %v",
		game.player.gold,
	)
	testing.expect(t, game.player.relic_stacks[.Orbiting_Orb] == 1, "buying should increment the stack count by one")
}

@(test)
test_try_buy_relic_refuses_when_locked_maxed_or_unaffordable :: proc(t: ^testing.T) {
	previous_player := game.player
	defer game.player = previous_player

	preset := relic_presets[.Orbiting_Orb]

	// locked: below unlock_level, however much Gold is in the wallet
	game.player.level = preset.unlock_level - 1
	game.player.relic_stacks = {}
	game.player.gold = 999999
	testing.expect(t, !try_buy_relic(.Orbiting_Orb), "a locked Relic should refuse to buy")
	testing.expect(t, game.player.relic_stacks[.Orbiting_Orb] == 0, "a refused buy should not increment the stack")

	// maxed: unlocked and affordable, but already at the cap
	game.player.level = preset.unlock_level
	game.player.relic_stacks[.Orbiting_Orb] = preset.max_stack
	testing.expect(t, !try_buy_relic(.Orbiting_Orb), "a maxed Relic should refuse to buy")
	testing.expect(
		t,
		game.player.relic_stacks[.Orbiting_Orb] == preset.max_stack,
		"a refused buy should not push the stack past the cap",
	)

	// unaffordable: unlocked and unmaxed, but one Gold short
	game.player.relic_stacks[.Orbiting_Orb] = 0
	game.player.gold = relic_price(.Orbiting_Orb, 0) - 1
	testing.expect(t, !try_buy_relic(.Orbiting_Orb), "an unaffordable Relic should refuse to buy")
	testing.expect(t, game.player.relic_stacks[.Orbiting_Orb] == 0, "a refused buy should not increment the stack")
}

@(test)
test_relic_orb_count_derives_from_relic_stacks :: proc(t: ^testing.T) {
	previous := game.player.relic_stacks
	defer game.player.relic_stacks = previous

	game.player.relic_stacks = {}
	testing.expect(t, relic_orb_count() == 0, "no purchased stacks should put no orbs on the ring")

	game.player.relic_stacks[.Orbiting_Orb] = 3
	testing.expect(t, relic_orb_count() == 3, "a stack should add a whole orb, so 3 stacks means 3 orbs")
}

@(test)
test_relic_orb_damage_scales_with_might_but_not_the_damage_upgrade :: proc(t: ^testing.T) {
	previous_account := game.player.account_stat_stacks
	previous_upgrades := game.player.upgrade_stacks
	defer {
		game.player.account_stat_stacks = previous_account
		game.player.upgrade_stacks = previous_upgrades
	}

	game.player.account_stat_stacks = {}
	game.player.upgrade_stacks = {}
	testing.expect(t, relic_orb_damage() == RELIC_ORB_BASE_DAMAGE, "with no Might, an orb should deal exactly its base damage")

	game.player.account_stat_stacks[.Might] = 3
	expected := apply_account_stat_effect(RELIC_ORB_BASE_DAMAGE, .Might, 3)
	testing.expectf(
		t,
		relic_orb_damage() == expected,
		"Might should scale orb damage the same way it scales weapon damage (expected %v, got %v)",
		expected,
		relic_orb_damage(),
	)

	// a Run-scoped Damage Upgrade is bought against the equipped Weapon
	// (apply_upgrades); an orb is not one, so it must not move
	with_might := relic_orb_damage()
	game.player.upgrade_stacks[.Damage] = 5
	testing.expect(
		t,
		relic_orb_damage() == with_might,
		"the Run-scoped Damage Upgrade applies to the equipped Weapon, not to an orb",
	)
}

@(test)
test_relic_orb_positions_are_evenly_spaced_on_the_ring :: proc(t: ^testing.T) {
	center := Vec2{100, -40}
	count := 4

	for index in 0 ..< count {
		position := relic_orb_position(index, count, center, 0)
		distance := linalg.length(position - center)
		testing.expectf(
			t,
			abs(distance - RELIC_ORB_ORBIT_RADIUS) < 0.01,
			"every orb should sit exactly RELIC_ORB_ORBIT_RADIUS from the center, orb %v was at %v",
			index,
			distance,
		)
	}

	// with an even count, opposite orbs are diametrically across the ring -
	// their midpoint is the center
	first := relic_orb_position(0, count, center, 0.7)
	opposite := relic_orb_position(count / 2, count, center, 0.7)
	midpoint := (first + opposite) / 2
	testing.expectf(
		t,
		linalg.length(midpoint - center) < 0.01,
		"orbs half the ring apart should be diametrically opposite, midpoint was %v not %v",
		midpoint,
		center,
	)
}

@(test)
test_update_relics_damages_an_enemy_the_ring_overlaps :: proc(t: ^testing.T) {
	previous_player := game.player
	previous_enemies := game.enemies
	previous_pickups := game.pickups
	previous_particles := game.particles
	previous_damage_numbers := game.damage_numbers
	previous_relic_state := game.relic_state
	previous_god_mode := game.debug.god_mode
	defer {
		game.player = previous_player
		game.enemies = previous_enemies
		game.pickups = previous_pickups
		game.particles = previous_particles
		game.damage_numbers = previous_damage_numbers
		game.relic_state = previous_relic_state
		game.debug.god_mode = previous_god_mode
	}

	game.enemies = {}
	game.pickups = {}
	game.particles = {}
	game.damage_numbers = {}
	game.debug.god_mode = false
	game.relic_state = {}
	game.player.x = 0
	game.player.y = 0
	game.player.account_stat_stacks = {}
	game.player.relic_stacks = {}
	game.player.relic_stacks[.Orbiting_Orb] = 1

	// a single orb starts at phase ~0, i.e. directly right of the ring's
	// center (relic_orbit_center is the player's mid-body, not their feet) -
	// park an enemy so its collision box covers exactly that point
	orb := relic_orb_position(0, 1, relic_orbit_center(), 0)
	append(&game.enemies, Enemy{rect = {x = orb.x, y = orb.y + ACTOR_SIZE.y / 2}, health = 100})

	update_relics(0.01) // orb_tick_timer starts at 0, so the first update ticks

	testing.expectf(
		t,
		game.enemies[0].health == 100 - relic_orb_damage(),
		"an enemy the orb overlaps should take exactly one tick of orb damage, health was %v",
		game.enemies[0].health,
	)

	// the tick rate gates re-hits: another update well inside the same tick
	// window must not land a second hit
	health_after_first_tick := game.enemies[0].health
	update_relics(0.01)
	testing.expect(
		t,
		game.enemies[0].health == health_after_first_tick,
		"a second update inside the same tick window should not re-hit - RELIC_ORB_TICK_RATE gates it",
	)

	clear(&game.enemies)
	clear(&game.pickups)
	clear(&game.particles)
	clear(&game.damage_numbers)
}

// the ring rotates roughly 0.73 radians in a single tick window, so an orb
// has swept well clear of a stationary enemy by the time it could tick
// again - the enemy is hit again only once the ring carries the orb back
// around to it. That sweep is the mechanic, so it's what this asserts.
@(test)
test_update_relics_re_hits_an_enemy_once_the_ring_sweeps_back_around :: proc(t: ^testing.T) {
	previous_player := game.player
	previous_enemies := game.enemies
	previous_pickups := game.pickups
	previous_particles := game.particles
	previous_damage_numbers := game.damage_numbers
	previous_relic_state := game.relic_state
	previous_god_mode := game.debug.god_mode
	defer {
		game.player = previous_player
		game.enemies = previous_enemies
		game.pickups = previous_pickups
		game.particles = previous_particles
		game.damage_numbers = previous_damage_numbers
		game.relic_state = previous_relic_state
		game.debug.god_mode = previous_god_mode
	}

	game.enemies = {}
	game.pickups = {}
	game.particles = {}
	game.damage_numbers = {}
	game.debug.god_mode = false
	game.relic_state = {}
	game.player.x = 0
	game.player.y = 0
	game.player.account_stat_stacks = {}
	game.player.relic_stacks = {}
	game.player.relic_stacks[.Orbiting_Orb] = 1

	orb := relic_orb_position(0, 1, relic_orbit_center(), 0)
	append(&game.enemies, Enemy{rect = {x = orb.x, y = orb.y + ACTOR_SIZE.y / 2}, health = 10000})

	// one full revolution takes TAU / RELIC_ORB_ANGULAR_SPEED seconds; run
	// comfortably past two of them, in frame-sized steps
	lap := math.TAU / RELIC_ORB_ANGULAR_SPEED
	steps := int((lap * 2.5) / 0.01)
	for _ in 0 ..< steps {
		update_relics(0.01)
	}

	damage_taken := 10000 - game.enemies[0].health
	testing.expectf(
		t,
		damage_taken > relic_orb_damage(),
		"over two full revolutions the orb should sweep back over the enemy and hit it more than the once, total damage was %v against a single tick of %v",
		damage_taken,
		relic_orb_damage(),
	)

	clear(&game.enemies)
	clear(&game.pickups)
	clear(&game.particles)
	clear(&game.damage_numbers)
}

@(test)
test_update_relics_is_inert_with_no_purchased_stacks :: proc(t: ^testing.T) {
	previous_player := game.player
	previous_enemies := game.enemies
	previous_relic_state := game.relic_state
	defer {
		game.player = previous_player
		game.enemies = previous_enemies
		game.relic_state = previous_relic_state
	}

	game.enemies = {}
	game.player.x = 0
	game.player.y = 0
	game.player.relic_stacks = {}
	game.relic_state = {orb_phase = 1.5, orb_tick_timer = 0.2}

	orb := relic_orb_position(0, 1, relic_orbit_center(), 1.5)
	append(&game.enemies, Enemy{rect = {x = orb.x, y = orb.y + ACTOR_SIZE.y / 2}, health = 100})

	update_relics(1.0)

	testing.expect(t, game.enemies[0].health == 100, "an unowned Relic should damage nothing")
	testing.expect(
		t,
		game.relic_state == Relic_State{},
		"with no orbs owned the ring should park at rest, so buying the first stack starts from a predictable phase",
	)

	clear(&game.enemies)
}

@(test)
test_update_relics_wraps_the_orbit_phase :: proc(t: ^testing.T) {
	previous_player := game.player
	previous_enemies := game.enemies
	previous_relic_state := game.relic_state
	defer {
		game.player = previous_player
		game.enemies = previous_enemies
		game.relic_state = previous_relic_state
	}

	game.enemies = {}
	game.player.relic_stacks = {}
	game.player.relic_stacks[.Orbiting_Orb] = 1
	game.relic_state = {}

	// long enough to lap the ring several times over
	for _ in 0 ..< 200 {
		update_relics(0.1)
	}

	testing.expectf(
		t,
		game.relic_state.orb_phase >= 0 && game.relic_state.orb_phase < math.TAU,
		"orb_phase should stay wrapped into [0, TAU) however long the ring spins, got %v",
		game.relic_state.orb_phase,
	)
}
