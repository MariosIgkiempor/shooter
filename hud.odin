package shooter

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

import layout "vendor/ui"
import ui "vendor/ui/ui"

// the nine ui_9square_* tiles, in the row-major order draw_nine_slice expects
UI_PANEL_TEXTURES :: [9]Texture_Name {
	.Ui_9square_Top_Left,
	.Ui_9square_Top_Middle,
	.Ui_9square_Top_Right,
	.Ui_9square_Middle_Left,
	.Ui_9square_Middle_Middle,
	.Ui_9square_Middle_Right,
	.Ui_9square_Bottom_Left,
	.Ui_9square_Bottom_Middle,
	.Ui_9square_Bottom_Right,
}

draw_ui_panel :: proc(dest: Rect, tint: Color = rl.WHITE, corner_scale: f32 = 1) {
	pieces: [9]Atlas_Texture
	for name, i in UI_PANEL_TEXTURES {
		pieces[i] = atlas_textures[name]
	}
	draw_nine_slice(pieces, dest, tint, corner_scale)
}

// -- in-game HUD: level/health/ammo as slim centered bars ------------------

HUD_BAR_WIDTH :: 80
HUD_BAR_HEIGHT :: 5
HUD_ROW_HEIGHT :: 10
HUD_ROW_GAP :: 3
HUD_ICON_SIZE :: 8
HUD_ELEMENT_GAP :: 4
HUD_BOTTOM_MARGIN :: 6
HUD_FONT_SIZE :: 10

HUD_BAR_BG :: Color{30, 32, 38, 255}
HUD_XP_COLOR :: Color{110, 180, 240, 255}
HUD_HEALTHY_COLOR :: Color{100, 200, 120, 255}
HUD_CRITICAL_COLOR :: Color{210, 60, 60, 255}
HUD_AMMO_COLOR :: Color{215, 215, 225, 255}
HUD_RELOADING_COLOR :: Color{230, 150, 40, 255}
HUD_EMPTY_COLOR :: Color{210, 60, 60, 255}

// all player stats read bottom-center as a stack of slim bars, mirroring
// the original xp bar's look instead of the bulkier panel-per-stat layout
draw_hud :: proc(player: Player) {
	visible_width := game.window_width * PIXEL_WINDOW_HEIGHT / game.window_height
	center_x := visible_width / 2

	total_height: f32 = HUD_ROW_HEIGHT * 3 + HUD_ROW_GAP * 2
	y := PIXEL_WINDOW_HEIGHT - HUD_BOTTOM_MARGIN - total_height

	xp_required := xp_required_for_level(player.level)
	xp_frac := clamp(f32(player.xp) / f32(xp_required), 0, 1)
	draw_hud_label_row(center_x, y, fmt.tprintf("Lv{}", player.level), xp_frac, HUD_XP_COLOR)
	y += HUD_ROW_HEIGHT + HUD_ROW_GAP

	health_frac := clamp(player.health / player.max_health, 0, 1)
	health_color := rl.ColorLerp(HUD_CRITICAL_COLOR, HUD_HEALTHY_COLOR, health_frac)
	draw_hud_icon_row(center_x, y, .Pickup_Heart, health_frac, health_color, "")
	y += HUD_ROW_HEIGHT + HUD_ROW_GAP

	weapon := player.weapon
	ammo_frac: f32 = 0
	ammo_color := HUD_AMMO_COLOR
	reserve_text := ""

	// Gun-only for now; ticket 07 gives Melee_Weapon/Magic their own HUD row
	switch v in weapon.variant {
	case Gun:
		if v.clip_size > 0 {
			ammo_frac = clamp(f32(v.ammo_in_clip) / f32(v.clip_size), 0, 1)
		}
		if v.reload_timer > 0 {
			ammo_color = HUD_RELOADING_COLOR
		} else if v.ammo_in_clip <= 0 && v.reserve_ammo <= 0 {
			ammo_color = HUD_EMPTY_COLOR
		}
		reserve_text = fmt.tprintf("+{}", v.reserve_ammo)
	case Melee_Weapon, Magic:
	}

	draw_hud_icon_row(center_x, y, .Pickup_Ammo, ammo_frac, ammo_color, reserve_text)
}

draw_hud_bar :: proc(pos: Vec2, frac: f32, fill: Color) {
	draw_rectangle({pos.x, pos.y, HUD_BAR_WIDTH, HUD_BAR_HEIGHT}, HUD_BAR_BG)
	draw_rectangle({pos.x, pos.y, HUD_BAR_WIDTH * clamp(frac, 0, 1), HUD_BAR_HEIGHT}, fill)
}

// a text label (e.g. "Lv3") followed by a bar, the pair centered on center_x
draw_hud_label_row :: proc(center_x, y: f32, label: string, frac: f32, fill: Color) {
	label_size := rl.MeasureTextEx(font, strings.clone_to_cstring(label, context.temp_allocator), HUD_FONT_SIZE, 0)
	row_width := label_size.x + HUD_ELEMENT_GAP + HUD_BAR_WIDTH
	x := center_x - row_width / 2

	draw_text(label, {x, y + (HUD_ROW_HEIGHT - HUD_FONT_SIZE) / 2}, HUD_FONT_SIZE, 0, rl.WHITE)
	draw_hud_bar({x + label_size.x + HUD_ELEMENT_GAP, y + (HUD_ROW_HEIGHT - HUD_BAR_HEIGHT) / 2}, frac, fill)
}

// an icon followed by a bar and optional trailing text (e.g. reserve ammo),
// the whole row centered on center_x
draw_hud_icon_row :: proc(
	center_x, y: f32,
	icon_texture: Texture_Name,
	frac: f32,
	fill: Color,
	trailing_text: string,
) {
	trailing_size: Vec2
	if trailing_text != "" {
		trailing_size = rl.MeasureTextEx(
			font,
			strings.clone_to_cstring(trailing_text, context.temp_allocator),
			HUD_FONT_SIZE,
			0,
		)
	}

	row_width := f32(HUD_ICON_SIZE) + HUD_ELEMENT_GAP + HUD_BAR_WIDTH
	if trailing_text != "" {
		row_width += HUD_ELEMENT_GAP + trailing_size.x
	}
	x := center_x - row_width / 2

	icon := atlas_textures[icon_texture]
	icon_y := y + (HUD_ROW_HEIGHT - HUD_ICON_SIZE) / 2
	draw_atlas_tile(icon.rect, {x, icon_y, HUD_ICON_SIZE, HUD_ICON_SIZE}, {})

	bar_x := x + HUD_ICON_SIZE + HUD_ELEMENT_GAP
	draw_hud_bar({bar_x, y + (HUD_ROW_HEIGHT - HUD_BAR_HEIGHT) / 2}, frac, fill)

	if trailing_text != "" {
		text_x := bar_x + HUD_BAR_WIDTH + HUD_ELEMENT_GAP
		draw_text(trailing_text, {text_x, y + (HUD_ROW_HEIGHT - HUD_FONT_SIZE) / 2}, HUD_FONT_SIZE, 0, rl.WHITE)
	}
}

draw_health_bar :: proc(enemy: Enemy) {
	WIDTH: f32 = 16
	HEIGHT: f32 = 2
	GAP_ABOVE_SPRITE: f32 = 5

	doc := animation_atlas_texture(enemy.animation).document_size
	pos := Vec2{enemy.x - WIDTH / 2, enemy.y - doc.y - GAP_ABOVE_SPRITE}
	fill := WIDTH * clamp(enemy.health / ENEMY_MAX_HEALTH, 0, 1)

	draw_rectangle({pos.x, pos.y, WIDTH, HEIGHT}, rl.BLACK)
	draw_rectangle({pos.x, pos.y, fill, HEIGHT}, rl.RED)
}

// -- modals: level-up / game-over -------------------------------------------

// modals render in real screen pixels (see ui.begin_frame below), not the
// small 180px-tall HUD camera, so panels are drawn a couple of tile-lengths
// larger than native to stay proportionate against a full window
MENU_PANEL_SCALE :: 2

// the native nine-slice tiles are 16x16 (see UI_PANEL_TEXTURES); scaled up
// by MENU_PANEL_SCALE, that's how far the title bar/content must be inset
// from the window's edge so the outer panel's border stays visible all the
// way around instead of being drawn over edge-to-edge
MENU_PANEL_MARGIN :: 16 * MENU_PANEL_SCALE

// the ui library's `theme` is a single shared global, and its default values
// are tuned for the editor's flat-rect windows (a saturated blue accent).
// tinting the nine-slice panel art with those same colors reads muddy and
// couples the in-game menus to whatever the editor's palette happens to be,
// so the HUD gets its own theme: a desaturated dark blue-gray family that
// matches the panel art, varying only in lightness across states.
HUD_THEME :: ui.Theme {
	window_background = {58, 63, 74, 255},
	title_bar         = {46, 50, 60, 255},
	title_text        = {240, 240, 240, 255},
	text              = {225, 225, 225, 255},
	button            = {74, 80, 94, 255},
	button_hot        = {96, 104, 122, 255},
	button_active     = {110, 118, 138, 255},
	button_text       = {240, 240, 240, 255},
	font_size         = 18,
	title_font_size   = 18,
	padding           = 10,
	gap               = 8,
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
				draw_ui_panel(dest, tint, panel_scale)
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
