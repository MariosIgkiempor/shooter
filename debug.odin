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

DEBUG_GOLD_GRANT: int = 500 // gold added to the player per click of the panel's Add Gold button

// F8 opens/closes this panel (main.odin's update_game). Unlike draw_shop_ui
// and the Run End modal, it does not pause update_game_state (ADR-0021): the
// simulation runs underneath it so a visualizer can be toggled against a live
// scene. What keeps a click on a toggle from also firing the equipped weapon
// is the shared ui_hovered flag (hud.odin) instead, the same one the Tilemap
// Editor uses to keep a click on its chrome from painting a tile.
//
// Scope: dev *views and cheats* only. Every balance/feel number lives in the
// editor's Tuning mode instead (tuning.odin) - one surface per knob, so the
// two can't drift. That's why the weapon_visual_scale slider that used to sit
// here is gone: it's a Tunable now.
draw_debug_panel_ui :: proc() {
	previous_theme := ui.theme
	ui.theme = HUD_THEME
	defer ui.theme = previous_theme

	ui.set_pointer_state(game.mouse, is_mouse_button_down(.LEFT))
	ui.begin_frame(game.window_width, game.window_height)

	// anchored to the bottom-left corner rather than offset into it: the
	// top-right is already taken by draw_hud_counters (hud.odin), and an
	// offset would couple this panel's position to that row's height. The
	// only other bottom-anchored surface is the Confirm New Run dialog, which
	// is Main Menu only and so can never coexist with this panel.
	if ui.row(
		{size = {layout.grow(0, 0), layout.grow(0, 0)}, align = {.Left, .Bottom}, padding = 12},
	) {
		if ui.begin("Debug") {
			record_ui_hover()

			for visualizer in Debug_Visualizer {
				on := game.debug.visualizers[visualizer]
				label := fmt.tprintf("{}: {}", visualizer_display_name[visualizer], on ? "ON" : "OFF")
				if ui.button(label) {
					game.debug.visualizers[visualizer] = !on
				}
			}

			// bumps run_start_gold by the same amount, and leaves gold_earned
			// alone - now that Gold is the single currency (ADR-0016), what
			// banks at Run end is the wallet's delta against run_start_gold,
			// so granting Gold without also moving that baseline would let a
			// dev cheat inflate real Account progression. Raising both hands
			// the tester spendable Gold that settles as exactly zero.
			if ui.button(fmt.tprintf("Add {} Gold", DEBUG_GOLD_GRANT)) {
				game.player.gold += DEBUG_GOLD_GRANT
				game.player.run_start_gold += DEBUG_GOLD_GRANT
			}

			god_mode_label := fmt.tprintf("God Mode: {}", game.debug.god_mode ? "ON" : "OFF")
			if ui.button(god_mode_label) {
				game.debug.god_mode = !game.debug.god_mode
			}

			if ui.button("Close") {
				game.debug.panel_open = false
			}
		}
	}

	draw_ui_render_commands(ui.end_frame())
}
