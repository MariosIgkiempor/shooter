package shooter

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

import layout "vendor/ui"
import ui "vendor/ui/ui"

// -- legacy nine-slice/vendor-ui support -------------------------------------
// ADR-0014 moved every real Screen below off vendor/ui and nine-slice panels
// onto the flat-rect Menu component set (see "Screens & Reveal/Dismiss
// transitions" further down). This block is all that's left of the old
// approach, kept alive solely because debug.odin's F8 panel (out of scope
// for ADR-0014 - it's not one of the six Screens, see CONTEXT.md's Screen
// entry) still draws through it.

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

// debug.odin's panel renders in real screen pixels (see ui.begin_frame
// below), not the small 180px-tall HUD camera, so it's drawn a couple of
// tile-lengths larger than native to stay proportionate against a full
// window
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
// couples debug.odin's panel to whatever the editor's palette happens to
// be, so it gets its own theme: a desaturated dark blue-gray family that
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

// shared by debug.odin's panel: walks the ui library's render commands,
// drawing any node opted into `panel = true` (see the ui.begin/ui.button
// calls there) as a tinted nine-slice panel instead of a flat rect. The
// editor uses the same ui library but never sets `panel`, so its
// windows/buttons keep rendering as plain flat rects untouched by any of
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

// -- Screens & Reveal/Dismiss transitions (ADR-0014) -------------------------
// See CONTEXT.md's Screen / Menu element / Reveal / Dismiss / Reveal delay
// entries for the vocabulary below, and .scratch/menu-ui-polish/issues/
// 02-component-api-and-state-model.md for the design this implements.

// one of the six full-window menu UI states the game can be in - Playing and
// Editing are deliberately not included (see current_screen below); a
// Screen change Dismisses every Menu element on the outgoing Screen and
// Reveals every Menu element on the incoming one, driven by the shared
// Menu_Transition record.
Screen_Kind :: enum {
	Splash,
	Main_Menu,
	Run_Start,
	Map_Selection,
	Shop,
	Run_End,
}

// resolved from whichever of program_mode/run_ended/shopping is currently
// authoritative - those three are already mutually exclusive (shopping can
// only be true while run_ended is false, and both only ever apply while
// program_mode == .Playing), so this is just a read, never a second source
// of truth.
current_screen :: proc() -> Maybe(Screen_Kind) {
	if game.run_ended {
		return .Run_End
	}
	if game.shopping {
		return .Shop
	}
	switch game.program_mode {
	case .Splash:
		return .Splash
	case .Main_Menu:
		return .Main_Menu
	case .Run_Start:
		return .Run_Start
	case .Selecting:
		return .Map_Selection
	case .Playing, .Editing:
		return nil // not a Screen
	}
	return nil
}

// Reveal/Dismiss timer state is not per-element (ticket 02's Answer): one
// shared record is enough, since every Menu element's alpha/scale is a pure
// function of elapsed time plus its ordinal rank (menu_element_anim below).
//
// `dismissing_to` targets Maybe(Screen_Kind) rather than a bare Screen_Kind
// (deviating from ticket 02's literal signature) because Shop's Close button
// needs to Dismiss back to Playing, which has no Screen_Kind - Shop<->Playing
// is the one Screen<->non-Screen pair request_screen_change must still cover
// (Playing<->Editing is excluded from this mechanism entirely, see F1's
// handling in main.odin's update_game). A bare Maybe(Screen_Kind) can't tell
// "no change in flight" apart from "in flight, targeting nil" though, so
// `transitioning` carries that instead - dismissing_to is only ever read
// once `transitioning` is true.
Menu_Transition :: struct {
	current:            Screen_Kind, // zero value .Splash matches ProgramMode's own zero value
	current_entered_at: f32, // rl.GetTime() when `current`'s Reveal began
	transitioning:      bool,
	dismissing_to:      Maybe(Screen_Kind),
	dismiss_started_at: f32,
}

// the one chokepoint every real Screen change goes through - defers the
// actual program_mode/run_ended/shopping write until the outgoing Screen's
// Dismiss finishes, so no call site can skip playing one by assigning those
// fields directly. `to` of nil targets Playing/gameplay rather than another
// Screen (see Menu_Transition's doc comment above).
request_screen_change :: proc(to: Maybe(Screen_Kind)) {
	if game.menu_transition.transitioning {
		return // a change is already in flight
	}
	game.menu_transition.transitioning = true
	game.menu_transition.dismissing_to = to
	game.menu_transition.dismiss_started_at = f32(rl.GetTime())
}

// true while a Screen change targeting exactly `screen` is pending (the
// request has fired but program_mode/run_ended/shopping haven't flipped
// yet). damage_player's re-entrancy guard (main.odin) needs this rather
// than game.run_ended itself, since run_ended no longer flips the instant
// death happens - see damage_player's comment.
screen_change_pending_to :: proc(screen: Screen_Kind) -> bool {
	target, pending := game.menu_transition.dismissing_to.?
	return pending && target == screen
}

// called once per frame from update_game. Waits out the outgoing Screen's
// full Dismiss window (every element's stagger included - see
// dismiss_window_for) before actually flipping program_mode/run_ended/
// shopping, which is what lets every Menu element on the outgoing Screen
// finish playing its Dismiss instead of vanishing the instant the
// underlying mode field changes.
update_menu_transition :: proc() {
	if !game.menu_transition.transitioning {
		return
	}

	now := f32(rl.GetTime())
	if now - game.menu_transition.dismiss_started_at < dismiss_window_for(game.menu_transition.current) {
		return // outgoing Screen still Dismissing
	}

	to := game.menu_transition.dismissing_to
	apply_screen_kind(to) // the one place that actually writes program_mode/run_ended/shopping

	if screen, has_screen := to.?; has_screen {
		game.menu_transition.current = screen
		game.menu_transition.current_entered_at = now
	}
	// to == nil (back to Playing) leaves current/current_entered_at as they
	// are - nothing Reveals afterward, so nothing reads them again until the
	// next request_screen_change

	game.menu_transition.transitioning = false
	game.menu_transition.dismissing_to = nil
}

// the mirror image of current_screen's mapping - the one place that
// actually writes program_mode/run_ended/shopping for a Screen change.
// Always rewrites run_ended/shopping together (rather than e.g. only ever
// setting `shopping = true` for .Shop) so they can never drift out of the
// mutual exclusivity current_screen already assumes.
apply_screen_kind :: proc(to: Maybe(Screen_Kind)) {
	screen, has_screen := to.?

	game.run_ended = has_screen && screen == .Run_End
	game.shopping = has_screen && screen == .Shop

	if !has_screen {
		return // back to Playing - program_mode is already .Playing
	}

	switch screen {
	case .Splash:
		game.program_mode = .Splash
	case .Main_Menu:
		game.program_mode = .Main_Menu
	case .Run_Start:
		game.program_mode = .Run_Start
	case .Map_Selection:
		game.program_mode = .Selecting
	case .Shop, .Run_End:
	// layered over Playing (see current_screen) - program_mode stays
	// .Playing, run_ended/shopping above already carry the state
	}
}

// how many distinct ranks the outgoing Screen's Dismiss must stagger
// across - only Main Menu stages a stagger (its Continue/Start New Run
// buttons, this map's one worked cascading-reveal example - see
// draw_main_menu_ui), so it's the only case with more than one rank; every
// other Screen's elements all share rank 0 (see menu_element_anim).
rank_count :: proc(screen: Screen_Kind) -> int {
	switch screen {
	case .Main_Menu:
		buttons := 1 // "Start New Run" is always shown
		if game.player.run_started {
			buttons += 1 // "Continue" only shows with a Run in progress
		}
		return buttons + 1 // + the panel itself, rank 0
	case .Splash, .Run_Start, .Map_Selection, .Shop, .Run_End:
		return 1
	}
	return 1
}

// total time the outgoing Screen's Dismiss needs before program_mode/
// run_ended/shopping can actually flip - the last-ranked element's Dismiss
// start (rank_count-1 stagger steps in) plus its own duration.
dismiss_window_for :: proc(screen: Screen_Kind) -> f32 {
	return MENU_THEME.duration + f32(rank_count(screen) - 1) * MENU_THEME.stagger_step
}

// -- Menu element component set (ADR-0014) -----------------------------------

Menu_Element_Anim :: struct {
	alpha: f32,
	scale: f32,
}

// stateless: alpha/scale for one Menu element, computed fresh every frame
// from the shared Menu_Transition record plus this element's own rank -
// mirrors the prototype's proto_animate (see .scratch/menu-ui-polish/
// issues/01-prototype-flat-rect-visual-and-motion.md). Reveal ranks count
// up from the panel (0); Dismiss ranks count the reverse way for a
// staggered Screen (Main Menu) so its buttons cascade closed before the
// panel does - every other Screen just passes reveal_rank = dismiss_rank =
// 0 for everything (see rank_count).
menu_element_anim :: proc(reveal_rank, dismiss_rank: int) -> Menu_Element_Anim {
	now := f32(rl.GetTime())

	if game.menu_transition.transitioning {
		start := game.menu_transition.dismiss_started_at + f32(dismiss_rank) * MENU_THEME.stagger_step
		e := MENU_THEME.ease(clamp((now - start) / MENU_THEME.duration, 0, 1))
		return {alpha = 1 - e, scale = MENU_THEME.scale_from + (1 - MENU_THEME.scale_from) * (1 - e)}
	}

	start := game.menu_transition.current_entered_at + f32(reveal_rank) * MENU_THEME.stagger_step
	e := MENU_THEME.ease(clamp((now - start) / MENU_THEME.duration, 0, 1))
	return {alpha = e, scale = MENU_THEME.scale_from + (1 - MENU_THEME.scale_from) * e}
}

Menu_Theme :: struct {
	fill, fill_hover, fill_pressed, fill_disabled: Color,
	border_color:                                  Color,
	border_width:                                  f32,
	text, text_disabled:                           Color,
	font_size, padding, gap:                       f32,
	duration:                                       f32,
	ease:                                           proc(t: f32) -> f32,
	scale_from:                                     f32,
	stagger_step:                                   f32,
}

// Variant C from the prototype (01-prototype-flat-rect-visual-and-motion.md)
// - dark flat fill, 2px accent border instead of a shadow, ease_out_cubic
// scale-in from 0.9 -> 1.0 over 0.20s. Replaces HUD_THEME for every real
// Screen; HUD_THEME itself stays above since debug.odin's panel is still on
// the old nine-slice/vendor-ui path.
MENU_THEME :: Menu_Theme {
	fill          = {40, 44, 52, 255},
	fill_hover    = {52, 58, 68, 255},
	fill_pressed  = {30, 33, 39, 255},
	fill_disabled = {40, 41, 45, 180},
	border_color  = {130, 170, 230, 255},
	border_width  = 2,
	text          = rl.WHITE,
	text_disabled = {130, 130, 130, 255},
	font_size     = 18,
	padding       = 24,
	gap           = 8,
	duration      = 0.20,
	ease          = ease_out_cubic,
	scale_from    = 0.9,
	stagger_step  = 0.05,
}

// derived line heights every screen below lays its running y-cursor out
// with - plain globals (not MENU_THEME fields) since they're purely a
// positioning convenience, not part of the visual/motion theme itself
MENU_BUTTON_HEIGHT :: 32
MENU_TEXT_LINE_HEIGHT := MENU_THEME.font_size + MENU_THEME.gap
MENU_BUTTON_LINE_HEIGHT := MENU_BUTTON_HEIGHT + MENU_THEME.gap

Menu_Button_State :: enum {
	Normal,
	Hover,
	Pressed,
	Disabled,
}

// grows/shrinks `rect` around its own center by `scale` - how Variant C's
// scale-in applies scale_from without moving the rect's anchor point around
menu_scaled_rect :: proc(rect: Rect, scale: f32) -> Rect {
	w := rect.width * scale
	h := rect.height * scale
	return {rect.x + (rect.width - w) / 2, rect.y + (rect.height - h) / 2, w, h}
}

menu_with_alpha :: proc(c: Color, alpha: f32) -> Color {
	return {c.r, c.g, c.b, u8(f32(c.a) * clamp(alpha, 0, 1))}
}

// flat-rect panel background (ADR-0014, Variant C): dark fill + 2px accent
// border, no shadow - the nine-slice Menu_Panel_Variant.Container treatment
// above is debug.odin's holdout now, not this.
draw_menu_panel :: proc(rect: Rect, anim: Menu_Element_Anim) {
	if anim.alpha <= 0 {
		return
	}
	dest := menu_scaled_rect(rect, anim.scale)
	draw_rectangle(dest, menu_with_alpha(MENU_THEME.fill, anim.alpha))
	draw_rectangle_lines(dest, menu_with_alpha(MENU_THEME.border_color, anim.alpha), MENU_THEME.border_width)
}

// flat-rect button: fill varies by normal/hover/pressed/disabled state, same
// accent border as the panel, no shadow. Click fires on release while
// hovered (rl.CheckCollisionPointRec + IsMouseButtonDown/Released, ADR-0010
// unchanged) - gated by anim.alpha > 0.8 so a still-animating button can't
// be clicked mid-Reveal/Dismiss (mirrors the prototype's `interactive :=
// alpha > 0.8`); this only suppresses hover/click detection, not drawing.
draw_menu_button :: proc(
	rect: Rect,
	label: string,
	anim: Menu_Element_Anim,
	disabled: bool = false,
) -> (
	clicked: bool,
	state: Menu_Button_State,
) {
	if anim.alpha <= 0 {
		return false, .Disabled
	}

	dest := menu_scaled_rect(rect, anim.scale)

	interactive := anim.alpha > 0.8
	hovered := interactive && !disabled && rl.CheckCollisionPointRec(game.mouse.position, dest)
	pressed := hovered && is_mouse_button_down(.LEFT)
	clicked = hovered && rl.IsMouseButtonReleased(.LEFT)

	switch {
	case disabled:
		state = .Disabled
	case pressed:
		state = .Pressed
	case hovered:
		state = .Hover
	case:
		state = .Normal
	}

	fill: Color
	switch state {
	case .Normal:
		fill = MENU_THEME.fill
	case .Hover:
		fill = MENU_THEME.fill_hover
	case .Pressed:
		fill = MENU_THEME.fill_pressed
	case .Disabled:
		fill = MENU_THEME.fill_disabled
	}

	draw_rectangle(dest, menu_with_alpha(fill, anim.alpha))
	draw_rectangle_lines(dest, menu_with_alpha(MENU_THEME.border_color, anim.alpha), MENU_THEME.border_width)

	text_color := disabled ? MENU_THEME.text_disabled : MENU_THEME.text
	text_size := rl.MeasureTextEx(font, strings.clone_to_cstring(label, context.temp_allocator), MENU_THEME.font_size, 0)
	text_pos := Vec2{dest.x + (dest.width - text_size.x) / 2, dest.y + (dest.height - text_size.y) / 2}
	draw_text(label, text_pos, MENU_THEME.font_size, 0, menu_with_alpha(text_color, anim.alpha))

	return clicked, state
}

// -- the six Screens ----------------------------------------------------------

// shown once per process launch (ProgramMode.Splash - the zero value, so a
// fresh or stale save always starts here) ahead of everything else. Purely
// cosmetic - loading is already synchronous and effectively instant (the
// atlas is #load'd into the binary, maps are pre-baked - see renderer.odin),
// so there's nothing real to report progress on, just the Splash_Background
// atlas tile (data/textures/splash_background.png) drawn full-window and
// faded by its own Reveal/Dismiss (ADR-0014's ticket 01: alpha only, no
// scale - a scale-in on a full-window cover image would just visibly
// resize/crop it, unlike a panel/button). update_game's .Splash case
// advances program_mode on a timer or the first key/click, so there's
// nothing here to be clickable.
draw_splash_ui :: proc() {
	anim := menu_element_anim(0, 0)
	if anim.alpha <= 0 {
		return
	}

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

	draw_atlas_tile(tex.rect, dest, {}, 0, menu_with_alpha(rl.WHITE, anim.alpha))
}

MENU_MAIN_MENU_PANEL_WIDTH :: 260

// shown on every process launch, right after Splash (see update_game's
// .Splash case). Two panels side by side: "Progression" carries the old
// draw_account_progression_ui content (Account Level/XP-into-level, unspent
// XP balance, the Account_Stat spend list - see CONTEXT.md's Account
// progression entry) unconditionally, even at unspent_xp == 0 (ADR-0012);
// "Shooter" carries the actions - "Continue" (only when a Run is in
// progress, straight to Map_Selection, Gold/weapon/Upgrades intact)
// alongside an always-present "Start New Run" (through weapon-pick,
// Run_Start) that requires a confirm step first if it would discard a Run
// already in progress (ADR-0013).
//
// This is the map's one worked cascading-reveal example (ADR-0014): the two
// panels are rank 0 (reveal first, dismiss last), Continue/Start New Run
// cascade in after at rank 1..N in reveal order (reverse on Dismiss) - see
// rank_count. The Progression panel's Account_Stat buy buttons stay
// unstaggered at rank 0 alongside their panel; only the two primary
// navigation buttons are "Main Menu's buttons" this map's stagger example
// is about (a deviation call - see this migration's summary).
draw_main_menu_ui :: proc() {
	pad := MENU_THEME.padding
	panel_gap := MENU_THEME.gap * 2
	panel_w: f32 = MENU_MAIN_MENU_PANEL_WIDTH

	progression_h :=
		pad * 2 +
		3 * MENU_TEXT_LINE_HEIGHT +
		f32(len(Account_Stat)) * (MENU_TEXT_LINE_HEIGHT + MENU_BUTTON_LINE_HEIGHT)

	button_count := 1 // "Start New Run" always shows
	if game.player.run_started {
		button_count += 1 // "Continue" only with a Run in progress
	}
	shooter_h := pad * 2 + f32(button_count) * MENU_BUTTON_LINE_HEIGHT

	row_h := max(progression_h, shooter_h)
	row_w := panel_w * 2 + panel_gap
	row_x := (game.window_width - row_w) / 2
	row_y := (game.window_height - row_h) / 2

	progression_rect := Rect{row_x, row_y, panel_w, progression_h}
	shooter_rect := Rect{row_x + panel_w + panel_gap, row_y, panel_w, shooter_h}

	panel_anim := menu_element_anim(0, button_count) // panel reveals first, dismisses last (rank button_count)
	draw_menu_panel(progression_rect, panel_anim)
	draw_menu_panel(shooter_rect, panel_anim)

	y := progression_rect.y + pad
	draw_text(
		fmt.tprintf("Account Lv. {}", game.player.level),
		Vec2{progression_rect.x + pad, y},
		MENU_THEME.font_size,
		0,
		menu_with_alpha(MENU_THEME.text, panel_anim.alpha),
	)
	y += MENU_TEXT_LINE_HEIGHT
	// no slash in the HUD font's glyph set (atlas.odin's LETTERS_IN_FONT) -
	// it renders as "?", hence "of" instead
	draw_text(
		fmt.tprintf("XP: {} of {}", game.player.xp, xp_required_for_level(game.player.level)),
		Vec2{progression_rect.x + pad, y},
		MENU_THEME.font_size,
		0,
		menu_with_alpha(MENU_THEME.text, panel_anim.alpha),
	)
	y += MENU_TEXT_LINE_HEIGHT
	draw_text(
		fmt.tprintf("Unspent: {} XP", game.player.unspent_xp),
		Vec2{progression_rect.x + pad, y},
		MENU_THEME.font_size,
		0,
		menu_with_alpha(MENU_THEME.text, panel_anim.alpha),
	)
	y += MENU_TEXT_LINE_HEIGHT

	for stat in Account_Stat {
		y = draw_account_stat_row(stat, progression_rect.x + pad, y, panel_w - pad * 2, panel_anim)
	}

	sy := shooter_rect.y + pad
	rank := 1
	if game.player.run_started {
		continue_rect := Rect{shooter_rect.x + pad, sy, panel_w - pad * 2, MENU_BUTTON_HEIGHT}
		continue_anim := menu_element_anim(rank, button_count - rank)
		if clicked, _ := draw_menu_button(continue_rect, "Continue", continue_anim); clicked {
			request_screen_change(.Map_Selection)
		}
		sy += MENU_BUTTON_LINE_HEIGHT
		rank += 1
	}

	start_rect := Rect{shooter_rect.x + pad, sy, panel_w - pad * 2, MENU_BUTTON_HEIGHT}
	start_anim := menu_element_anim(rank, button_count - rank)
	if clicked, _ := draw_menu_button(start_rect, "Start New Run", start_anim); clicked {
		if game.player.run_started {
			game.confirming_new_run = true
		} else {
			request_screen_change(.Run_Start)
		}
	}

	if game.confirming_new_run {
		draw_confirm_new_run_dialog()
	}
}

// current stack plus a buy button - never a MAXED label (unlike
// draw_shop_upgrade_row), since Account_Stat purchases have no cap and are
// always available, just costing more XP the more of it is already owned.
// Returns the cursor's new y, mirroring the running-y-cursor convention
// every screen below uses.
draw_account_stat_row :: proc(stat: Account_Stat, x, y, width: f32, anim: Menu_Element_Anim) -> f32 {
	preset := account_stat_presets[stat]
	stack := game.player.account_stat_stacks[stat]
	cursor := y

	label := fmt.tprintf("{} [{}]", preset.display_name, stack)
	draw_text(label, Vec2{x, cursor}, MENU_THEME.font_size, 0, menu_with_alpha(MENU_THEME.text, anim.alpha))
	cursor += MENU_TEXT_LINE_HEIGHT

	button_rect := Rect{x, cursor, width, MENU_BUTTON_HEIGHT}
	button_label := fmt.tprintf("Spend {} XP", account_stat_price(stat, stack))
	if clicked, _ := draw_menu_button(button_rect, button_label, anim); clicked {
		try_buy_account_stat(stat)
	}
	cursor += MENU_BUTTON_LINE_HEIGHT

	return cursor
}

// the Main Menu's "Discard current Run?" confirm step (ADR-0013), toggled by
// game.confirming_new_run - not itself tied to a Screen change (it's a
// sub-panel within the Main Menu Screen, not a Screen of its own), so it's
// drawn at full opacity/scale rather than through menu_element_anim, which
// only ever answers for the current Screen's own Reveal/Dismiss.
draw_confirm_new_run_dialog :: proc() {
	pad := MENU_THEME.padding
	w: f32 = 360
	h := pad * 2 + MENU_TEXT_LINE_HEIGHT + MENU_BUTTON_LINE_HEIGHT
	rect := Rect{(game.window_width - w) / 2, game.window_height - h - 40, w, h}
	anim := Menu_Element_Anim{alpha = 1, scale = 1}

	draw_menu_panel(rect, anim)
	draw_text(
		"Your Gold, weapon tier, and Upgrades will be lost.",
		Vec2{rect.x + pad, rect.y + pad},
		MENU_THEME.font_size,
		0,
		MENU_THEME.text,
	)

	button_w := (w - pad * 2 - MENU_THEME.gap) / 2
	button_y := rect.y + pad + MENU_TEXT_LINE_HEIGHT

	yes_rect := Rect{rect.x + pad, button_y, button_w, MENU_BUTTON_HEIGHT}
	if clicked, _ := draw_menu_button(yes_rect, "Yes, discard", anim); clicked {
		// commit the abandonment now, not on the later weapon-pick click
		// (start_new_run) - otherwise quitting between this confirm and
		// picking a weapon leaves run_started stale-true, and the
		// "discarded" Run silently reappears as Continue-able on next launch
		game.player.run_started = false
		game.confirming_new_run = false
		request_screen_change(.Run_Start)
	}

	cancel_rect := Rect{rect.x + pad + button_w + MENU_THEME.gap, button_y, button_w, MENU_BUTTON_HEIGHT}
	if clicked, _ := draw_menu_button(cancel_rect, "Cancel", anim); clicked {
		game.confirming_new_run = false
	}
}

// shown once per Run (ProgramMode.Run_Start) between Main_Menu and
// Map_Selection/Playing/Editing: three columns, one per Weapon_Family,
// each listing that family's Weapon_Kinds as buttons. Picking a weapon
// starts a fresh Run (start_new_run) and proceeds to the existing map-select
// screen, not straight into Playing - mirrors the old Class-select ->
// map-select order, just re-entered every Run instead of once ever.
// game.player.run_started drives the Main Menu's "Continue" button
// (draw_main_menu_ui), which bypasses this screen entirely when a Run is
// already in progress (see CONTEXT.md's Run entry and ADR-0008, ADR-0013);
// the Run End screen's Continue clears run_started again after death.
// Unstaggered (reveal_rank = dismiss_rank = 0 throughout) - only Main Menu
// gets a worked stagger example, per this migration's scope.
draw_run_start_ui :: proc() {
	pad := MENU_THEME.padding
	col_w: f32 = 200
	col_gap := MENU_THEME.gap * 2
	family_count := len(Weapon_Family)

	max_kinds := 0
	for family in Weapon_Family {
		if n := len(weapon_family_kinds[family]); n > max_kinds {
			max_kinds = n
		}
	}

	col_content_h := MENU_TEXT_LINE_HEIGHT + f32(max_kinds) * MENU_BUTTON_LINE_HEIGHT
	panel_w := col_w * f32(family_count) + col_gap * f32(family_count - 1) + pad * 2
	panel_h := pad * 2 + (MENU_THEME.font_size + 4) + MENU_THEME.gap + col_content_h

	rect := Rect{(game.window_width - panel_w) / 2, (game.window_height - panel_h) / 2, panel_w, panel_h}
	anim := menu_element_anim(0, 0)
	draw_menu_panel(rect, anim)

	draw_text(
		"Choose a Weapon",
		Vec2{rect.x + pad, rect.y + pad},
		MENU_THEME.font_size + 4,
		0,
		menu_with_alpha(MENU_THEME.text, anim.alpha),
	)

	col_x := rect.x + pad
	col_y := rect.y + pad + (MENU_THEME.font_size + 4) + MENU_THEME.gap

	for family in Weapon_Family {
		y := col_y
		draw_text(
			weapon_family_display_name[family],
			Vec2{col_x, y},
			MENU_THEME.font_size,
			0,
			menu_with_alpha(MENU_THEME.text, anim.alpha),
		)
		y += MENU_TEXT_LINE_HEIGHT

		for kind in weapon_family_kinds[family] {
			button_rect := Rect{col_x, y, col_w, MENU_BUTTON_HEIGHT}
			if clicked, _ := draw_menu_button(button_rect, weapon_display_name[kind], anim); clicked {
				start_new_run(kind)
				request_screen_change(.Map_Selection)
			}
			y += MENU_BUTTON_LINE_HEIGHT
		}

		col_x += col_w + col_gap
	}
}

// shown at every launch (ProgramMode.Selecting) before Playing/Editing
// become reachable - one button per Map_Name, labeled by that case's baked
// display name. Map choice is one-shot per launch: once game.program_mode
// leaves .Selecting here, there's no in-game way back. Unstaggered, like
// Run_Start above. Transitions to Playing on pick - not a Screen (see
// current_screen), so request_screen_change(nil) rather than a Screen_Kind.
draw_map_selection_ui :: proc() {
	pad := MENU_THEME.padding
	w: f32 = 300
	button_count := len(Map_Name)
	h := pad * 2 + (MENU_THEME.font_size + 4) + MENU_THEME.gap + f32(button_count) * MENU_BUTTON_LINE_HEIGHT

	rect := Rect{(game.window_width - w) / 2, (game.window_height - h) / 2, w, h}
	anim := menu_element_anim(0, 0)
	draw_menu_panel(rect, anim)

	draw_text(
		"Select a Map",
		Vec2{rect.x + pad, rect.y + pad},
		MENU_THEME.font_size + 4,
		0,
		menu_with_alpha(MENU_THEME.text, anim.alpha),
	)

	y := rect.y + pad + (MENU_THEME.font_size + 4) + MENU_THEME.gap
	for name in Map_Name {
		chosen := maps[name]

		button_rect := Rect{rect.x + pad, y, w - pad * 2, MENU_BUTTON_HEIGHT}
		if clicked, _ := draw_menu_button(button_rect, chosen.name, anim); clicked {
			// clone_map, never a plain value copy - game.current_map would
			// otherwise alias the shared baked table's backing tile/spawner
			// memory (see clone_map's doc comment)
			game.current_map = clone_map(chosen)
			apply_chosen_map(chosen, map_identity_string(name))
			request_screen_change(nil) // Playing isn't a Screen - see current_screen
		}
		y += MENU_BUTTON_LINE_HEIGHT
	}
}

// shown once at death (game.run_ended, set by damage_player via
// request_screen_change(.Run_End) - see CONTEXT.md's Account progression
// entry and ADR-0009), replacing the old Game Over screen entirely rather
// than stacking alongside it. Run summary only (Kills/Survived/Gold
// earned/XP earned) - the Account Level/XP bar and Account_Stat spend list
// that used to live here moved to the Main Menu (see draw_main_menu_ui),
// since spending is now a pre-Run decision rather than something squeezed
// in right after death. Continue leads there instead of straight to
// weapon-pick. Unstaggered, like Run_Start/Map_Selection above.
draw_run_end_ui :: proc() {
	pad := MENU_THEME.padding
	w: f32 = 320
	h := pad * 2 + (MENU_THEME.font_size + 4) + MENU_THEME.gap + 4 * MENU_TEXT_LINE_HEIGHT + MENU_THEME.gap + MENU_BUTTON_LINE_HEIGHT

	rect := Rect{(game.window_width - w) / 2, (game.window_height - h) / 2, w, h}
	anim := menu_element_anim(0, 0)
	draw_menu_panel(rect, anim)

	draw_text(
		"Run Ended",
		Vec2{rect.x + pad, rect.y + pad},
		MENU_THEME.font_size + 4,
		0,
		menu_with_alpha(MENU_THEME.text, anim.alpha),
	)

	y := rect.y + pad + (MENU_THEME.font_size + 4) + MENU_THEME.gap
	text_color := menu_with_alpha(MENU_THEME.text, anim.alpha)
	draw_text(fmt.tprintf("Kills: {}", total_kills(game.player.kills)), Vec2{rect.x + pad, y}, MENU_THEME.font_size, 0, text_color)
	y += MENU_TEXT_LINE_HEIGHT
	draw_text(fmt.tprintf("Survived: {}s", int(game.player.survival_seconds)), Vec2{rect.x + pad, y}, MENU_THEME.font_size, 0, text_color)
	y += MENU_TEXT_LINE_HEIGHT
	draw_text(fmt.tprintf("Gold earned: {}", game.player.gold_earned), Vec2{rect.x + pad, y}, MENU_THEME.font_size, 0, text_color)
	y += MENU_TEXT_LINE_HEIGHT
	draw_text(fmt.tprintf("XP earned: {}", game.last_run_xp_earned), Vec2{rect.x + pad, y}, MENU_THEME.font_size, 0, text_color)
	y += MENU_TEXT_LINE_HEIGHT + MENU_THEME.gap

	button_rect := Rect{rect.x + pad, y, w - pad * 2, MENU_BUTTON_HEIGHT}
	if clicked, _ := draw_menu_button(button_rect, "Continue", anim); clicked {
		game.player.run_started = false
		request_screen_change(.Main_Menu)
	}
}

MENU_SHOP_COLUMN_WIDTH :: 260

// on-demand panel (a dedicated TAB key - see main.odin's update_game),
// pausing the game while open (game.shopping - see update_game_state).
// Two-column grid: the Weapon tier ladder on the left, Upgrades (general
// above, the equipped weapon's family's one family-specific slot below) on
// the right - both visible at once so a tier purchase and an Upgrade
// purchase stay directly comparable without tab-switching. Unstaggered.
// Closing goes back to Playing, not a Screen - request_screen_change(nil).
draw_shop_ui :: proc() {
	pad := MENU_THEME.padding
	col_w: f32 = MENU_SHOP_COLUMN_WIDTH
	col_gap := MENU_THEME.gap * 2
	w := col_w * 2 + col_gap + pad * 2

	content_h := max(shop_weapon_ladder_height(), shop_upgrades_height())
	h := pad * 2 + MENU_TEXT_LINE_HEIGHT + MENU_THEME.gap + content_h + MENU_THEME.gap + MENU_BUTTON_LINE_HEIGHT

	rect := Rect{(game.window_width - w) / 2, (game.window_height - h) / 2, w, h}
	anim := menu_element_anim(0, 0)
	draw_menu_panel(rect, anim)

	draw_text(
		fmt.tprintf("Shop - Gold: {}", game.player.gold),
		Vec2{rect.x + pad, rect.y + pad},
		MENU_THEME.font_size,
		0,
		menu_with_alpha(MENU_THEME.text, anim.alpha),
	)

	col_y := rect.y + pad + MENU_TEXT_LINE_HEIGHT + MENU_THEME.gap
	left_x := rect.x + pad
	right_x := left_x + col_w + col_gap

	draw_shop_weapon_ladder(left_x, col_y, col_w, anim)
	draw_shop_upgrades(right_x, col_y, col_w, anim)

	close_rect := Rect{rect.x + pad, rect.y + h - pad - MENU_BUTTON_HEIGHT, w - pad * 2, MENU_BUTTON_HEIGHT}
	if clicked, _ := draw_menu_button(close_rect, "Close", anim); clicked {
		request_screen_change(nil) // Playing isn't a Screen - see current_screen
	}
}

// fixed regardless of state: title + current weapon name + either a buy
// button or a "Fully Upgraded" line, always three lines worth of height -
// keeps draw_shop_ui's panel sizing a single pass instead of needing to
// pre-walk this column's content
shop_weapon_ladder_height :: proc() -> f32 {
	return 2 * MENU_TEXT_LINE_HEIGHT + MENU_BUTTON_LINE_HEIGHT
}

// current weapon plus either a "buy next tier" button or, at the ladder's
// top, a "Fully Upgraded" label in place of one (disabled-in-spirit - see
// draw_shop_upgrade_row for the same MAXED-label tradeoff on Upgrades)
draw_shop_weapon_ladder :: proc(x, y, width: f32, anim: Menu_Element_Anim) {
	cursor := y
	text_color := menu_with_alpha(MENU_THEME.text, anim.alpha)

	draw_text("Weapon Ladder", Vec2{x, cursor}, MENU_THEME.font_size, 0, text_color)
	cursor += MENU_TEXT_LINE_HEIGHT
	draw_text(weapon_display_name[game.player.weapon.kind], Vec2{x, cursor}, MENU_THEME.font_size, 0, text_color)
	cursor += MENU_TEXT_LINE_HEIGHT

	if next, has_next := weapon_next_tier(game.player.weapon.kind).?; has_next {
		price := weapon_tier_price(weapon_tier_index(next))
		label := fmt.tprintf("Buy {} - {}g", weapon_display_name[next], price)
		button_rect := Rect{x, cursor, width, MENU_BUTTON_HEIGHT}
		if clicked, _ := draw_menu_button(button_rect, label, anim); clicked {
			try_buy_next_weapon_tier()
		}
	} else {
		draw_text("Fully Upgraded", Vec2{x, cursor}, MENU_THEME.font_size, 0, text_color)
	}
}

// counts how many Upgrade_Kinds draw_shop_upgrades will draw in one of its
// two buckets (general/family-gated), mirroring its own filter exactly, so
// draw_shop_ui can size the panel before drawing into it
shop_upgrade_kind_count :: proc(family: Weapon_Family, gated: bool) -> int {
	count := 0
	for kind in Upgrade_Kind {
		_, has_family := upgrade_presets[kind].family.?
		if has_family == gated && upgrade_available_to_family(kind, family) {
			count += 1
		}
	}
	return count
}

shop_upgrades_height :: proc() -> f32 {
	family := weapon_kind_family[game.player.weapon.kind]
	row_count := shop_upgrade_kind_count(family, false) + shop_upgrade_kind_count(family, true)
	return 2 * MENU_TEXT_LINE_HEIGHT + f32(row_count) * (MENU_TEXT_LINE_HEIGHT + MENU_BUTTON_LINE_HEIGHT)
}

// general Upgrades first, then the equipped weapon's family's one
// family-specific slot - both queries reuse upgrade_available_to_family
// rather than re-inlining its upgrade_presets[kind].family.? check, so the
// gating rule only lives in one place (upgrade.odin)
draw_shop_upgrades :: proc(x, y, width: f32, anim: Menu_Element_Anim) {
	family := weapon_kind_family[game.player.weapon.kind]
	text_color := menu_with_alpha(MENU_THEME.text, anim.alpha)
	cursor := y

	draw_text("General", Vec2{x, cursor}, MENU_THEME.font_size, 0, text_color)
	cursor += MENU_TEXT_LINE_HEIGHT
	for kind in Upgrade_Kind {
		_, gated := upgrade_presets[kind].family.?
		if !gated && upgrade_available_to_family(kind, family) {
			cursor = draw_shop_upgrade_row(kind, x, cursor, width, anim)
		}
	}

	draw_text(weapon_family_display_name[family], Vec2{x, cursor}, MENU_THEME.font_size, 0, text_color)
	cursor += MENU_TEXT_LINE_HEIGHT
	for kind in Upgrade_Kind {
		_, gated := upgrade_presets[kind].family.?
		if gated && upgrade_available_to_family(kind, family) {
			cursor = draw_shop_upgrade_row(kind, x, cursor, width, anim)
		}
	}
}

// current stack/cap plus either a buy button or, at the cap, a "MAXED" label
// in place of one (see draw_shop_weapon_ladder's note on the same tradeoff).
// Returns the cursor's new y, like draw_account_stat_row above.
draw_shop_upgrade_row :: proc(kind: Upgrade_Kind, x, y, width: f32, anim: Menu_Element_Anim) -> f32 {
	preset := upgrade_presets[kind]
	stack := game.player.upgrade_stacks[kind]
	cursor := y

	// parens/slash aren't in the HUD font's glyph set (atlas.odin's
	// LETTERS_IN_FONT) and render as "?" - brackets/hyphen are
	label := fmt.tprintf("{} [{}-{}]", preset.display_name, stack, preset.max_stack)
	draw_text(label, Vec2{x, cursor}, MENU_THEME.font_size, 0, menu_with_alpha(MENU_THEME.text, anim.alpha))
	cursor += MENU_TEXT_LINE_HEIGHT

	if upgrade_maxed(kind) {
		draw_text("MAXED", Vec2{x, cursor}, MENU_THEME.font_size, 0, menu_with_alpha(MENU_THEME.text_disabled, anim.alpha))
	} else {
		price := upgrade_price(kind, stack)
		button_rect := Rect{x, cursor, width, MENU_BUTTON_HEIGHT}
		if clicked, _ := draw_menu_button(button_rect, fmt.tprintf("Buy - {}g", price), anim); clicked {
			try_buy_upgrade(kind)
		}
	}
	cursor += MENU_BUTTON_LINE_HEIGHT

	return cursor
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
