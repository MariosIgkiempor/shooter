package shooter

import "core:testing"

// The one rung-level proof for the Warden: Pale Keep's own baked timeline,
// driven headlessly through the frame loop's pieces in the order
// update_game_state calls them. The pure seams (phases, the reserved slot,
// the drop, the obstacle stamp) each have their own tests; this checks that
// they are wired to each other on the Map that ships them. Drives `game`,
// so it needs ODIN_TEST_THREADS=1 like the other wiring tests.
@(test)
test_pale_keep_opens_on_the_warden_which_the_field_routes_around_and_which_steers_by_its_own :: proc(t: ^testing.T) {
	previous_map := game.current_map
	previous_player := game.player
	previous_enemies := game.enemies
	previous_camera := game.camera
	previous_pickups := game.pickups
	previous_particles := game.particles
	previous_damage_numbers := game.damage_numbers
	previous_god_mode := game.debug.god_mode
	previous_field := game.flow_field
	previous_boss_field := game.boss_flow_field
	defer {
		delete_map(game.current_map)
		delete(game.enemies)
		delete(game.pickups)
		delete(game.particles)
		delete(game.damage_numbers)
		flow_field_destroy(&game.flow_field)
		flow_field_destroy(&game.boss_flow_field)
		game.current_map = previous_map
		game.player = previous_player
		game.enemies = previous_enemies
		game.camera = previous_camera
		game.pickups = previous_pickups
		game.particles = previous_particles
		game.damage_numbers = previous_damage_numbers
		game.debug.god_mode = previous_god_mode
		game.flow_field = previous_field
		game.boss_flow_field = previous_boss_field
	}
	game.current_map = clone_map(maps[.Pale_Keep])
	game.player = Player{}
	game.player.rect = {game.current_map.player_start.x, game.current_map.player_start.y, 0, 0}
	game.player.health = 100
	game.player.max_health = 100
	game.enemies = {}
	game.pickups = {}
	game.particles = {}
	game.damage_numbers = {}
	game.camera = Camera{zoom = 1, target = game.current_map.player_start}
	game.debug.god_mode = false
	game.flow_field = {}
	game.boss_flow_field = {}

	tilemap := &game.current_map.tilemap
	player_pos := Vec2{game.player.x, game.player.y}
	STEP :: f32(1.0 / 60)

	// frame 1: the field is fresh, the timeline fires at t=0
	flow_field_ensure(&game.flow_field, tilemap, player_pos, i32(FLOW_FIELD_INFLATION_RADIUS), enemy_flow_obstacles(game.enemies[:]))
	update_spawn_triggers(STEP)

	boss_index, has_boss := find_boss(game.enemies[:])
	if !testing.expect(t, has_boss, "Pale Keep should put the Warden on the field on its first frame") {
		return
	}
	testing.expect_value(t, game.enemies[boss_index].kind, Enemy_Kind.Warden)
	testing.expect(t, len(game.enemies) > 1, "the adds should arrive alongside it")

	// headless there is no window, so "off-screen" lands the spawn beside
	// the player; walk the Boss out into the open court so the player's own
	// cell is not inside its stamp (a source under the stamp floods out of
	// it by design, which is a different test)
	game.enemies[boss_index].x = player_pos.x + 200
	game.enemies[boss_index].y = player_pos.y

	// the Boss's own field builds at its size-derived radius; the shared
	// field, ensured with the Boss on it, stamps its cell as an obstacle
	ensure_boss_flow_field()
	testing.expect(t, game.boss_flow_field.built, "a Boss alive should have its own field")
	testing.expect_value(t, game.boss_flow_field.radius, i32(2))
	rebuilt := flow_field_ensure(&game.flow_field, tilemap, player_pos, i32(FLOW_FIELD_INFLATION_RADIUS), enemy_flow_obstacles(game.enemies[:]))
	testing.expect(t, rebuilt, "the shared field should re-flood once the Boss is on it")
	boss := game.enemies[boss_index]
	boss_cell := world_to_cell_coord({boss.x, boss.y}, tilemap.tile_size)
	stamped, _ := flow_field_cell(&game.flow_field, boss_cell)
	testing.expect(t, stamped.obstacle, "the Boss's own cell should be stamped as an obstacle in the shared field")
	_, shared_ok := flow_field_step_target(&game.flow_field, {boss.x, boss.y})
	_, own_ok := flow_field_step_target(&game.boss_flow_field, {boss.x, boss.y})
	testing.expect(t, !shared_ok, "the shared field has no step for the Boss from inside its own stamp")
	testing.expect(t, own_ok, "the Boss's own field does")

	// shot to half: the next tick between Tells enters phase 1
	apply_hit_to_enemy(boss_index, 111, {boss.x, boss.y})
	update_enemies(STEP)
	boss_index, has_boss = find_boss(game.enemies[:])
	if !testing.expect(t, has_boss, "111 damage should not kill a 220 health Boss") {
		return
	}
	a, is_tell := game.enemies[boss_index].attack.(Tell_Area)
	testing.expect(t, is_tell, "the Warden carries a Tell_Area")
	testing.expect_value(t, a.phase_index, 1)

	// killed: the drop is Gold, every time
	pickups_before := len(game.pickups)
	apply_hit_to_enemy(boss_index, 1000, {boss.x, boss.y})
	_, has_boss = find_boss(game.enemies[:])
	testing.expect(t, !has_boss, "the Boss should be dead")
	testing.expect_value(t, len(game.pickups), pickups_before + 1)
	testing.expect(t, game.pickups[len(game.pickups) - 1].kind == .Gold, "the Boss's drop is Gold")
	testing.expect_value(t, game.pickups[len(game.pickups) - 1].gold, enemy_presets[.Warden].gold)
}
