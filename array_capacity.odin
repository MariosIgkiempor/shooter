#+feature global-context
package shooter

// odin test's memory-tracking allocator corrupts unrelated heap state when
// `game`'s shared dynamic arrays (game.enemies, game.particles, ...) grow via
// append mid-test - see weapon_test.odin's header comment on tests sharing
// this global. Pre-reserving capacity before any test runs avoids the
// growth/reallocation that triggers it. Scoped to test builds only (`when
// ODIN_TEST`, a builtin true only under `odin test`) so the real game's
// startup allocation behavior is unaffected.
when ODIN_TEST {
	@(init)
	reserve_game_arrays_for_tests :: proc() {
		reserve(&game.enemies, 64)
		reserve(&game.bullets, 128)
		reserve(&game.enemy_bullets, 64)
		reserve(&game.poison_clouds, 16)
		reserve(&game.pickups, 64)
		reserve(&game.particles, 1024)
		reserve(&game.damage_numbers, 64)
	}
}
