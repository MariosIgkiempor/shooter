package shooter

import "core:fmt"

import layout "vendor/ui"
import ui "vendor/ui/ui"

// each of main.odin's F8 dev-view overlays, independently toggleable from
// the debug panel below - replaces the old single debug_overlay bool that
// switched all of them on/off together.
Debug_Visualizer :: enum {
	Colliders,
	Weapon_Area,
	Attack_Ranges,
	Movement_Styles,
	Pathfinding,
}

visualizer_display_name := [Debug_Visualizer]string {
	.Colliders       = "Colliders",
	.Weapon_Area     = "Weapon Area",
	.Attack_Ranges   = "Attack Ranges",
	.Movement_Styles = "Movement Styles",
	.Pathfinding     = "Pathfinding",
}

Debug_State :: struct {
	panel_open:  bool,
	visualizers: [Debug_Visualizer]bool,
	// 1-shot kills enemies (apply_hit_to_enemy, bullet.odin) and makes the
	// player invulnerable (damage_player, main.odin) - a single flag for
	// both, since "god mode" is one dev concept even though it touches two
	// separate damage seams.
	god_mode:    bool,
}

DEBUG_GOLD_GRANT :: 500 // gold added to the player per click of the panel's Add Gold button

// F8 opens/closes this panel (main.odin's update_game). Mirrors
// draw_shop_ui's panel/pause pattern (hud.odin) - game.debug.panel_open
// pauses update_game_state the same way game.shopping does, so clicking a
// toggle here never also fires the equipped weapon or moves the player.
draw_debug_panel_ui :: proc() {
	previous_theme := ui.theme
	ui.theme = HUD_THEME
	defer ui.theme = previous_theme

	ui.set_pointer_state(game.mouse, is_mouse_button_down(.LEFT))
	ui.begin_frame(game.window_width, game.window_height)

	if ui.row({size = {layout.grow(0, 0), layout.grow(0, 0)}, align = {.Center, .Center}}) {
		if ui.begin("Debug", {panel = true, panel_margin = MENU_PANEL_MARGIN}) {
			ui.text("Gold: {}", game.player.gold)

			for visualizer in Debug_Visualizer {
				on := game.debug.visualizers[visualizer]
				label := fmt.tprintf("{}: {}", visualizer_display_name[visualizer], on ? "ON" : "OFF")
				if ui.button(label, {panel = true}) {
					game.debug.visualizers[visualizer] = !on
				}
			}

			// bumps run_start_gold by the same amount, and leaves gold_earned
			// alone - now that Gold is the single currency (ADR-0016), what
			// banks at Run end is the wallet's delta against run_start_gold,
			// so granting Gold without also moving that baseline would let a
			// dev cheat inflate real Account progression. Raising both hands
			// the tester spendable Gold that settles as exactly zero.
			if ui.button(fmt.tprintf("Add {} Gold", DEBUG_GOLD_GRANT), {panel = true}) {
				game.player.gold += DEBUG_GOLD_GRANT
				game.player.run_start_gold += DEBUG_GOLD_GRANT
			}

			// weapon silhouettes are per-kind now (ADR-0018) and the only
			// honest way to judge one is at gameplay zoom while it rotates
			// with your aim - so the global size multiplier is a live
			// slider rather than a constant to recompile against. Drives
			// Gun/Magic only; a melee blade's drawn length reports its real
			// reach and must not be scaled away from it.
			ui.text("Weapon size: {:.2f}x", weapon_visual_scale)
			ui.slider(
				"weapon_visual_scale",
				&weapon_visual_scale,
				WEAPON_VISUAL_SCALE_MIN,
				WEAPON_VISUAL_SCALE_MAX,
			)

			god_mode_label := fmt.tprintf("God Mode: {}", game.debug.god_mode ? "ON" : "OFF")
			if ui.button(god_mode_label, {panel = true}) {
				game.debug.god_mode = !game.debug.god_mode
			}

			if ui.button("Close", {panel = true}) {
				game.debug.panel_open = false
			}
		}
	}

	draw_ui_render_commands(ui.end_frame(), MENU_PANEL_SCALE)
}
