package shooter

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

import layout "vendor/ui"
import ui "vendor/ui/ui"

// which nine-slice source a panel-flagged render command draws, keyed by the
// ui library's opaque `panel_variant` int (see BUTTON_PANEL_VARIANT /
// BUTTON_PANEL_VARIANT_PRESSED in vendor/ui/ui/ui.odin) - 0 is every
// non-button panel (just the window/container background today). Each
// texture is its own single square-grid source (see draw_nine_slice),
// sliced into its 3x3 grid automatically - no per-tile source art needed.
Menu_Panel_Variant :: enum {
	Container,
	Button_Normal,
	Button_Pressed,
}

menu_panel_variant_textures: [Menu_Panel_Variant]Texture_Name = {
	.Container      = .Ui_9square_Panel,
	.Button_Normal  = .Ui_9square_Button,
	.Button_Pressed = .Ui_9square_Button_Pressed,
}

// -- modals: level-up / game-over -------------------------------------------

// modals render in real screen pixels (see ui.begin_frame below), not the
// small 180px-tall HUD camera, so panels are drawn a couple of tile-lengths
// larger than native to stay proportionate against a full window
MENU_PANEL_SCALE :: 2

// the native nine-slice corners are Ui_9square_Panel's own size / 3 (sliced
// into even thirds - see draw_nine_slice); scaled up by MENU_PANEL_SCALE,
// that's roughly how far the title bar/content must be inset from the
// window's edge so the outer panel's border stays visible all the way
// around instead of being drawn over edge-to-edge
MENU_PANEL_MARGIN :: 16 * MENU_PANEL_SCALE

// how far a pressed button sinks down: both its drawn background (see
// draw_ui_render_commands) and, via HUD_THEME.button_press_offset below, the
// label text laid out inside it (see layout.Node.press_offset_y) move by
// this exact same amount, so the label stays put relative to the button
// instead of drifting - one constant so the two can't fall out of sync
BUTTON_PRESS_SINK :: 3

// how much a pressed button's drawn background additionally shrinks - taken
// evenly off the top and bottom, so it doesn't shift the box's vertical
// center and needs no matching adjustment on the label (unlike SINK above)
BUTTON_PRESS_SHRINK :: 4

// the ui library's `theme` is a single shared global, and its default values
// are tuned for the editor's flat-rect windows (a saturated blue accent).
// tinting the nine-slice panel art with those same colors reads muddy and
// couples the in-game menus to whatever the editor's palette happens to be,
// so the HUD gets its own theme: a desaturated dark blue-gray family that
// matches the panel art, varying only in lightness across states.
HUD_THEME :: ui.Theme {
	window_background   = {58, 63, 74, 255},
	title_bar           = {46, 50, 60, 255},
	title_text          = {240, 240, 240, 255},
	text                = {225, 225, 225, 255},
	button              = {74, 80, 94, 255},
	button_hot          = {96, 104, 122, 255},
	button_active       = {110, 118, 138, 255},
	button_text         = {240, 240, 240, 255},
	font_size           = 22,
	title_font_size     = 22,
	padding             = 10,
	gap                 = 8,
	button_press_offset = BUTTON_PRESS_SINK,
}

// shared by every modal/full-screen panel below: walks the ui library's
// render commands, drawing any node opted into `panel = true` (see the
// ui.begin/ui.button calls below) as a tinted nine-slice panel instead of a
// flat rect. the editor uses the same ui library but never sets `panel`, so
// its windows/buttons keep rendering as plain flat rects untouched by any of
// this.
draw_ui_render_commands :: proc(commands: layout.RenderCommands, panel_scale: f32) {
	for cmd in commands {
		switch cmd.kind {
		case .Rectangle:
			dest := Rect{cmd.pos.x, cmd.pos.y, cmd.size.x, cmd.size.y}
			tint := rl.Color(cmd.color)

			if cmd.panel {
				variant := Menu_Panel_Variant(cmd.panel_variant)
				texture := atlas_textures[menu_panel_variant_textures[variant]]
				// the button textures are real drawn art (normal/pressed), not a
				// flat shape meant to be recolored - the theme's button/button_hot/
				// button_active tints only ever made sense against the single
				// generic panel texture, so they're ignored here to keep the art's
				// own colors intact; the container keeps its theme tint as before
				panel_tint := variant == .Container ? tint : rl.WHITE

				if variant == .Button_Pressed {
					// purely a draw-time visual effect on the drawn rect, not the
					// layout node itself (which would risk reflowing sibling buttons
					// just because one got pressed). Two separate moves, deliberately
					// not collapsed into one: SINK translates the whole box down by
					// the exact amount the label (a separate layout node, moved via
					// HUD_THEME.button_press_offset - see layout.Node.press_offset_y)
					// also moves, so the two stay aligned; SHRINK then takes evenly
					// off the top and bottom of that already-moved box, which doesn't
					// need a matching label adjustment since a symmetric shrink never
					// moves the center SINK already aligned it to. Collapsing these
					// into a single bottom-anchored shrink (translate the top only,
					// leave the bottom fixed) is what caused the earlier bug: that
					// moves the box's center by SINK/2, not SINK, so the label (moved
					// by the full SINK) drifted out of alignment with it.
					dest.y += BUTTON_PRESS_SINK + BUTTON_PRESS_SHRINK / 2
					dest.height -= BUTTON_PRESS_SHRINK
				}

				draw_nine_slice(texture, dest, panel_tint, panel_scale)
			} else {
				rl.DrawRectangleV(rl.Vector2(cmd.pos), rl.Vector2(cmd.size), tint)
			}
		case .Text:
			rl.DrawTextEx(
				font,
				strings.clone_to_cstring(cmd.text, context.temp_allocator),
				rl.Vector2(cmd.pos),
				f32(cmd.font_size),
				0,
				rl.Color(cmd.color),
			)
		}
	}
}

// shown once per process launch (ProgramMode.Splash - the zero value, so a
// fresh or stale save always starts here) ahead of everything else. Purely
// cosmetic - loading is already synchronous and effectively instant (the
// atlas is #load'd into the binary, maps are pre-baked - see renderer.odin),
// so there's nothing real to report progress on, just the Splash_Background
// atlas tile (data/textures/splash_background.png) drawn full-window. No ui
// library involvement at all (unlike every other screen in this file) -
// update_game's .Splash case advances program_mode on a timer or the first
// key/click, so there's nothing here to be clickable.
draw_splash_ui :: proc() {
	tex := atlas_textures[.Splash_Background]
	tex_size := Vec2{tex.rect.width, tex.rect.height}
	window_size := Vec2{game.window_width, game.window_height}

	// scale to cover the whole window with no letterboxing, cropping
	// whichever axis overflows (background-size: cover), rather than
	// stretching non-uniformly to fit
	scale := max(window_size.x / tex_size.x, window_size.y / tex_size.y)
	dest_size := tex_size * scale
	dest := Rect {
		(window_size.x - dest_size.x) / 2,
		(window_size.y - dest_size.y) / 2,
		dest_size.x,
		dest_size.y,
	}

	draw_atlas_tile(tex.rect, dest, {})
}

// shown once per process launch, right after Splash, when there's no Run
// already in progress (see update_game's .Splash case - a resumed Run skips
// straight past this to Selecting, same as it always skipped Run_Start).
// Single-column panel: Account Level/XP-into-level bar, unspent-XP balance,
// then the Account_Stat spend list - moved here from the old Run End screen
// (see CONTEXT.md's Account progression entry) since spending is now a
// pre-Run decision rather than something squeezed in right after death.
// "Start Game" hands off to the existing weapon-pick screen.
draw_account_progression_ui :: proc() {
	previous_theme := ui.theme
	ui.theme = HUD_THEME
	defer ui.theme = previous_theme

	ui.set_pointer_state(game.mouse, is_mouse_button_down(.LEFT))
	ui.begin_frame(game.window_width, game.window_height)

	if ui.row({size = {layout.grow(0, 0), layout.grow(0, 0)}, align = {.Center, .Center}}) {
		if ui.begin("Account Progression", {panel = true, panel_margin = MENU_PANEL_MARGIN}) {
			ui.text("Account Lv. {}", game.player.level)
			// no slash in the HUD font's glyph set (atlas.odin's
			// LETTERS_IN_FONT) - it renders as "?", hence "of" instead
			ui.text("XP: {} of {}", game.player.xp, xp_required_for_level(game.player.level))
			ui.text("Unspent: {} XP", game.player.unspent_xp)

			if ui.column({gap = ui.theme.gap}) {
				for stat in Account_Stat {
					draw_account_stat_row(stat)
				}
			}

			if ui.button("Start Game", {panel = true}) {
				game.program_mode = .Run_Start
			}
		}
	}

	draw_ui_render_commands(ui.end_frame(), MENU_PANEL_SCALE)
}

// shown once per Run (ProgramMode.Run_Start) between Account_Progression and
// Selecting/Playing/Editing: three columns, one per Weapon_Family (Decision
// 01, Variant A), each listing that family's Weapon_Kinds as buttons.
// Picking a weapon starts a fresh Run (start_new_run) and proceeds to the
// existing map-select screen, not straight into Playing - mirrors the old
// Class-select -> map-select order, just re-entered every Run instead of
// once ever. game.player.run_started makes load_game (via Splash) skip
// straight past this screen when resuming a Run already in progress (see
// CONTEXT.md's Run entry and ADR-0008); the Run End screen's Continue clears
// it again after death.
draw_run_start_ui :: proc() {
	previous_theme := ui.theme
	ui.theme = HUD_THEME
	defer ui.theme = previous_theme

	ui.set_pointer_state(game.mouse, is_mouse_button_down(.LEFT))
	ui.begin_frame(game.window_width, game.window_height)

	if ui.row({size = {layout.grow(0, 0), layout.grow(0, 0)}, align = {.Center, .Center}}) {
		if ui.begin("Choose a Weapon", {panel = true, panel_margin = MENU_PANEL_MARGIN}) {
			if ui.row({gap = ui.theme.gap}) {
				for family in Weapon_Family {
					if ui.column({gap = ui.theme.gap}) {
						ui.text("{}", weapon_family_display_name[family])
						for kind in weapon_family_kinds[family] {
							if ui.button(weapon_display_name[kind], {panel = true}) {
								start_new_run(kind)
								game.program_mode = .Selecting
							}
						}
					}
				}
			}
		}
	}

	draw_ui_render_commands(ui.end_frame(), MENU_PANEL_SCALE)
}

// shown at every launch (ProgramMode.Selecting) before Playing/Editing
// become reachable - one button per Map_Name, labeled by that case's baked
// display name. Map choice is one-shot per launch: once game.program_mode
// leaves .Selecting here, there's no in-game way back.
draw_map_selection_ui :: proc() {
	previous_theme := ui.theme
	ui.theme = HUD_THEME
	defer ui.theme = previous_theme

	ui.set_pointer_state(game.mouse, is_mouse_button_down(.LEFT))
	ui.begin_frame(game.window_width, game.window_height)

	if ui.row({size = {layout.grow(0, 0), layout.grow(0, 0)}, align = {.Center, .Center}}) {
		if ui.begin("Select a Map", {panel = true, panel_margin = MENU_PANEL_MARGIN}) {
			for name in Map_Name {
				chosen := maps[name]

				if ui.button(chosen.name, {panel = true}) {
					// clone_map, never a plain value copy - game.current_map
					// would otherwise alias the shared baked table's backing
					// tile/spawner memory (see clone_map's doc comment)
					game.current_map = clone_map(chosen)
					apply_chosen_map(chosen, map_identity_string(name))
					game.program_mode = .Playing
				}
			}
		}
	}

	draw_ui_render_commands(ui.end_frame(), MENU_PANEL_SCALE)
}

// shown once at death (game.run_ended, set by damage_player - see
// CONTEXT.md's Account progression entry and ADR-0009), replacing the old
// Game Over screen entirely rather than stacking alongside it. Run summary
// only (Kills/Survived/Gold earned/XP earned) - the Account Level/XP bar and
// Account_Stat spend list that used to live here moved to the pre-Run
// Account_Progression screen (see draw_account_progression_ui), since
// spending is now a pre-Run decision rather than something squeezed in right
// after death. Continue leads there instead of straight to weapon-pick.
draw_run_end_ui :: proc() {
	previous_theme := ui.theme
	ui.theme = HUD_THEME
	defer ui.theme = previous_theme

	ui.set_pointer_state(game.mouse, is_mouse_button_down(.LEFT))
	ui.begin_frame(game.window_width, game.window_height)

	if ui.row({size = {layout.grow(0, 0), layout.grow(0, 0)}, align = {.Center, .Center}}) {
		if ui.begin("Run Ended", {panel = true, panel_margin = MENU_PANEL_MARGIN}) {
			if ui.column({gap = ui.theme.gap}) {
				ui.text("Kills: {}", total_kills(game.player.kills))
				ui.text("Survived: {}s", int(game.player.survival_seconds))
				ui.text("Gold earned: {}", game.player.gold_earned)
				ui.text("XP earned: {}", game.last_run_xp_earned)
			}

			if ui.button("Continue", {panel = true}) {
				game.run_ended = false
				game.player.run_started = false
				game.program_mode = .Account_Progression
			}
		}
	}

	draw_ui_render_commands(ui.end_frame(), MENU_PANEL_SCALE)
}

// current stack plus a buy button - never a MAXED label (unlike
// draw_shop_upgrade_row), since Account_Stat purchases have no cap and are
// always available, just costing more XP the more of it is already owned
draw_account_stat_row :: proc(stat: Account_Stat) {
	preset := account_stat_presets[stat]
	stack := game.player.account_stat_stacks[stat]

	ui.text("{} [{}]", preset.display_name, stack)
	if ui.button(fmt.tprintf("Spend {} XP", account_stat_price(stat, stack)), {panel = true}) {
		try_buy_account_stat(stat)
	}
}

// on-demand panel (a dedicated TAB key - see main.odin's update_game),
// pausing the game while open (game.shopping - see update_game_state).
// Two-column layout validated via prototypes/03-shop-panel.html: the Weapon
// tier ladder on the left, Upgrades (general above, the equipped weapon's
// family's one family-specific slot below) on the right - both visible at once so a tier
// purchase and an Upgrade purchase stay directly comparable without
// tab-switching (issue 03-shop-ui-and-ux).
draw_shop_ui :: proc() {
	previous_theme := ui.theme
	ui.theme = HUD_THEME
	defer ui.theme = previous_theme

	ui.set_pointer_state(game.mouse, is_mouse_button_down(.LEFT))
	ui.begin_frame(game.window_width, game.window_height)

	if ui.row({size = {layout.grow(0, 0), layout.grow(0, 0)}, align = {.Center, .Center}}) {
		if ui.begin("Shop", {panel = true, panel_margin = MENU_PANEL_MARGIN}) {
			ui.text("Gold: {}", game.player.gold)

			if ui.row({gap = ui.theme.gap}) {
				if ui.column({gap = ui.theme.gap}) {
					draw_shop_weapon_ladder()
				}
				if ui.column({gap = ui.theme.gap}) {
					draw_shop_upgrades()
				}
			}

			if ui.button("Close", {panel = true}) {
				game.shopping = false
			}
		}
	}

	draw_ui_render_commands(ui.end_frame(), MENU_PANEL_SCALE)
}

// current weapon plus either a "buy next tier" button or, at the ladder's
// top, a disabled-in-spirit "Fully Upgraded" label (the ui library has no
// disabled-button state, so a maxed tier renders as plain text with no
// button at all rather than an unclickable one - see draw_shop_upgrade_row
// for the same tradeoff on Upgrades)
draw_shop_weapon_ladder :: proc() {
	ui.text("Weapon Ladder")
	ui.text("{}", weapon_display_name[game.player.weapon.kind])

	if next, has_next := weapon_next_tier(game.player.weapon.kind).?; has_next {
		price := weapon_tier_price(weapon_tier_index(next))
		if ui.button(fmt.tprintf("Buy {} - {}g", weapon_display_name[next], price), {panel = true}) {
			try_buy_next_weapon_tier()
		}
	} else {
		ui.text("Fully Upgraded")
	}
}

// general Upgrades first, then the equipped weapon's family's one
// family-specific slot - both queries reuse upgrade_available_to_family
// rather than re-inlining its upgrade_presets[kind].family.? check, so the
// gating rule only lives in one place (upgrade.odin)
draw_shop_upgrades :: proc() {
	family := weapon_kind_family[game.player.weapon.kind]

	ui.text("General")
	for kind in Upgrade_Kind {
		_, gated := upgrade_presets[kind].family.?
		if !gated && upgrade_available_to_family(kind, family) {
			draw_shop_upgrade_row(kind)
		}
	}

	ui.text("{}", weapon_family_display_name[family])
	for kind in Upgrade_Kind {
		_, gated := upgrade_presets[kind].family.?
		if gated && upgrade_available_to_family(kind, family) {
			draw_shop_upgrade_row(kind)
		}
	}
}

// current stack/cap plus either a buy button or, at the cap, a "MAXED" label
// in place of one (see draw_shop_weapon_ladder's note on the ui library
// having no disabled-button state)
draw_shop_upgrade_row :: proc(kind: Upgrade_Kind) {
	preset := upgrade_presets[kind]
	stack := game.player.upgrade_stacks[kind]

	// parens/slash aren't in the HUD font's glyph set (atlas.odin's
	// LETTERS_IN_FONT) and render as "?" - brackets/hyphen are
	ui.text("{} [{}-{}]", preset.display_name, stack, preset.max_stack)

	if upgrade_maxed(kind) {
		ui.text("MAXED")
	} else {
		price := upgrade_price(kind, stack)
		if ui.button(fmt.tprintf("Buy - {}g", price), {panel = true}) {
			try_buy_upgrade(kind)
		}
	}
}

// -- live Run-scoped meta-stats ---------------------------------------------

HUD_COUNTER_FONT_SIZE :: 10
HUD_COUNTER_MARGIN :: 10 // mirrors the top-left "Editing" text's margin

// top-right "Kills: N   Time: MM:SS" readout, drawn every frame while
// Playing (main.odin's game.ui_camera block). Reads the existing Run-scoped
// Player fields directly - see CONTEXT.md's Run entry and the enemy-spawn-
// revamp map's ticket 01 - the same total_kills/survival_seconds the Run
// End screen and Spawn Trigger Kills_Reached/Time_Elapsed conditions use.
// No slash in the HUD font's glyph set (atlas.odin's LETTERS_IN_FONT), so
// spaces separate the two stats instead of a "/"-joined format.
draw_hud_counters :: proc() {
	kills := total_kills(game.player.kills)
	total_seconds := int(game.player.survival_seconds)
	minutes := total_seconds / 60
	seconds := total_seconds % 60
	text := fmt.tprintf("Kills: {}   Time: {:02d}:{:02d}", kills, minutes, seconds)

	size := rl.MeasureTextEx(font, strings.clone_to_cstring(text, context.temp_allocator), HUD_COUNTER_FONT_SIZE, 0)
	virtual_width := game.window_width / game.ui_camera.zoom
	pos := Vec2{virtual_width - size.x - HUD_COUNTER_MARGIN, HUD_COUNTER_MARGIN}

	draw_text(text, pos, HUD_COUNTER_FONT_SIZE, 0, rl.WHITE)
}
