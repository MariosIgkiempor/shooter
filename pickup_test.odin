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
