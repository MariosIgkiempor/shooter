package shooter

import "core:testing"

// Pickups are collected through collect_pickup, which is driven from
// update_pickups' proximity check - these tests call it directly with a
// constructed Pickup rather than walking one into the player, since the
// homing/collection geometry is not what's under test. Same shared-`game`
// caveat as weapon_test.odin: run with ODIN_TEST_THREADS=1.

// The roster rule from CONTEXT.md's Pickup entry: "a pickup that restores
// nothing is worse than no pickup, because it teaches the player to walk
// toward things that do not matter". This walks every Pickup_Kind rather
// than naming them, so a kind added later that moves none of what the
// current roster moves - health, wallet, run earnings - fails here instead
// of shipping inert, which is exactly how the Ammo kind survived as long as
// it did. A kind that deliberately grants something else (a Relic, say)
// should widen the check below rather than be excused from it.
@(test)
test_every_pickup_kind_changes_something_the_player_can_read :: proc(t: ^testing.T) {
	previous_player := game.player
	defer game.player = previous_player

	for kind in Pickup_Kind {
		game.player.max_health = 100
		game.player.health = 1 // room for a Health pickup to land
		game.player.gold = 0
		game.player.gold_earned = 0
		game.player.account_stat_stacks = {}

		before := game.player
		collect_pickup(Pickup{kind = kind, gold = 10})

		changed :=
			game.player.health != before.health ||
			game.player.gold != before.gold ||
			game.player.gold_earned != before.gold_earned
		testing.expectf(
			t,
			changed,
			"collecting a %v pickup should change the player's health, gold or gold_earned - it does nothing",
			kind,
		)
	}
}

// the Boss's drop is guaranteed and it is Gold: rolled through the ordinary
// path a Boss would pay out roughly one kill in eight (PICKUP_DROP_CHANCE,
// then a coin flip between kinds), and a Boss that drops nothing reads as a
// bug. Every other Kind still rolls.
@(test)
test_a_boss_kill_always_drops_its_gold :: proc(t: ^testing.T) {
	// flagged for the test, so this pins the drop to the flag and not to
	// whichever Kind currently carries it
	boss := Enemy_Kind.Gazer // not the zero Kind: the blank fillers below would otherwise all be Bosses
	previous_preset := enemy_presets[boss]
	defer enemy_presets[boss] = previous_preset
	enemy_presets[boss].boss = true

	previous_pickups := game.pickups
	defer {
		delete(game.pickups)
		game.pickups = previous_pickups
	}
	game.pickups = {}

	for _ in 0 ..< 20 {
		maybe_spawn_pickup({10, 10}, boss)
	}

	testing.expect_value(t, len(game.pickups), 20)
	for pickup in game.pickups {
		testing.expect(t, pickup.kind == .Gold, "a Boss drop is always Gold")
		testing.expect_value(t, pickup.gold, enemy_gold_value(boss))
	}
}
