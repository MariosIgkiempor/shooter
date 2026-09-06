package shooter

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

import layout "vendor/ui"
import ui "vendor/ui/ui"

// -- shared vendor/ui render backend -----------------------------------------
// ADR-0014 moved every real Screen below off vendor/ui onto the flat-rect
// Menu component set (see "Screens & Reveal/Dismiss transitions" further
// down). What survives here is the small backend the two remaining vendor/ui
// surfaces share: debug.odin's F8 panel and editor.odin's Tilemap Editor,
// neither of which is one of the six Screens (see CONTEXT.md's Screen entry).
// The nine-slice panel art that used to sit behind the F8 panel is gone -
// both surfaces now draw the library's Rectangle commands as plain flat
// fills, so they render identically apart from their theme.

// how far a pressed button (and its label) sinks down. Purely a *layout*
// offset - it feeds HUD_THEME.button_press_offset, which the ui library
// applies to the button's label node (see layout.Node.press_offset_y) so the
// label tracks the box instead of drifting. Nothing draw-time depends on it.
BUTTON_PRESS_SINK :: 3

// the ui library's `theme` is a single shared global, and its default values
// are tuned for the editor's windows (a saturated blue accent, 18px text).
// debug.odin's panel draws in real screen pixels rather than the small 180px
// HUD camera, and reads better dark and a size up, so it gets its own theme:
// a desaturated dark blue-gray family varying only in lightness across
// states. Swapped in and restored around the panel's draw (see debug.odin).
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
	scrollbar_track     = {40, 44, 52, 255},
	scrollbar_thumb     = {96, 104, 122, 255},
}

// the whole backend: walks the ui library's render commands and draws them.
// Shared by debug.odin's F8 panel and editor.odin, so the two can't drift
// apart. The library's `panel`/`panel_variant` fields are deliberately opaque
// to it (layout.odin) and simply ignored - there is no decorative panel style
// anymore, only flat fills in whichever theme is current.
draw_ui_render_commands :: proc(commands: layout.RenderCommands) {
	for cmd in commands {
		// scroll containers are the library's business, not this backend's: it
		// gets told the rect each command is visible through and scissors to
		// it, and only when the command actually crosses that rect's edge -
		// which, outside a scroll container, is never
		clipped := layout.command_needs_clip(cmd)
		if clipped {
			rl.BeginScissorMode(
				i32(cmd.clip.x),
				i32(cmd.clip.y),
				i32(cmd.clip.width),
				i32(cmd.clip.height),
			)
		}

		switch cmd.kind {
		case .Rectangle:
			rl.DrawRectangleV(rl.Vector2(cmd.pos), rl.Vector2(cmd.size), rl.Color(cmd.color))
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

		if clipped {
			rl.EndScissorMode()
		}
	}
}

// whether the pointer was over one of the two vendor/ui surfaces last frame.
// A gesture a ui surface owns must not also act on the world: the editor
// suppresses tile painting and camera panning while true (editor.odin), and
// the F8 panel suppresses weapon firing (main.odin), so a click that presses
// a panel button never also fires the equipped weapon.
//
// One shared flag rather than one per surface, because the two are mutually
// exclusive - F8 requires .Playing and the editor only draws in .Editing, so
// at most one of them is live in any frame. Each surface clears it before its
// own begin_frame and records into it from inside its window.
//
// One frame stale by construction: the ui is declared during the draw phase,
// so the newest answer available to an update is the one last frame's layout
// produced - and it's about where the pointer *is*, not about an event having
// arrived, so it holds steady across a trackpad gesture's gaps rather than
// flickering between them.
ui_hovered: bool

// called just inside ui.begin: the current open node is the window content,
// whose parent is the window itself (title bar included)
record_ui_hover :: proc() {
	content := layout.get_node(layout.current_open_node())
	window := layout.get_node(content.parent)

	if layout.is_node_with_id_hovered(window.id) {
		ui_hovered = true
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
		if game.menu_transition.current == .Map_Selection {
			game.program_mode = .Playing
		}
		return // Shop/Run_End close back to Playing - program_mode is already .Playing there
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

// 0 whenever there's no Screen at all (Playing/Editing) or the current
// Screen has no populated world behind it (Splash/Main_Menu/Run_Start/
// Map_Selection - program_mode is .Splash/.Main_Menu/.Run_Start/.Selecting
// there, never .Playing, per apply_screen_kind) - otherwise reuses
// menu_element_anim's own rank-0 alpha (the same value the Screen's panel
// fill/border already animate with), so the backdrop blur can never drift
// out of sync with the panel's own Reveal/Dismiss - see ADR-0015.
//
// Deliberately checks program_mode == .Playing rather than
// current_map.name != "" - current_screen's own doc comment already
// establishes that shopping/run_ended only ever apply while program_mode ==
// .Playing, so this is an equivalent, always-current read. current_map.name
// would instead go stale: current_map is never reset once a map's been
// played (see hud.odin's clone_map call site), so it would still read
// non-empty on returning to Main_Menu after a Run ends, incorrectly
// blurring behind it.
blurred_backdrop_strength :: proc() -> f32 {
	if _, has_screen := current_screen().?; !has_screen {
		return 0
	}
	if game.program_mode != .Playing {
		return 0
	}
	return menu_element_anim(0, 0).alpha
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

// -- icon slots (icon.odin) --------------------------------------------------
//
// Icons sit *above* their label, centered, on anything the player browses
// and picks between - weapon tiers, upgrades, account stats, maps - so the
// glyph is the target and the text is its caption. Read-only `label: value`
// readouts (the Run End receipt) are the exception and keep their icon
// inline to the left: a receipt line is read left-to-right as a sentence,
// and centering it under a mark makes it slower to read, not faster.
MENU_ICON_SIZE :: 20
MENU_ICON_GAP :: 4 // between a stacked icon and the label under it

// the Shop is the one screen where the stacked treatment doesn't fit at the
// default 960x540 window - it was already ~512px tall with plain text rows.
// A smaller glyph there buys back most of the difference (the rest comes
// from draw_shop_ui balancing the two Upgrade blocks across both columns).
MENU_SHOP_ICON_SIZE :: 15

// an icon stacked above a single text line, as one row
MENU_ICON_TEXT_LINE_HEIGHT := MENU_ICON_SIZE + MENU_ICON_GAP + MENU_TEXT_LINE_HEIGHT
MENU_SHOP_ICON_TEXT_LINE_HEIGHT := MENU_SHOP_ICON_SIZE + MENU_ICON_GAP + MENU_TEXT_LINE_HEIGHT

// a button carrying a stacked icon+label instead of a bare label
MENU_ICON_BUTTON_HEIGHT :: MENU_BUTTON_HEIGHT + MENU_ICON_SIZE + MENU_ICON_GAP
MENU_ICON_BUTTON_LINE_HEIGHT := MENU_ICON_BUTTON_HEIGHT + MENU_THEME.gap

// draws `icon` centered in a MENU_ICON_SIZE-tall band at the top of `width`,
// then returns the y the caption below it should start at. The one place
// the stacked-icon geometry lives, so every row using it can't drift.
draw_menu_stacked_icon :: proc(
	icon: Icon_Proc,
	x, y, width: f32,
	size: f32,
	tint: Maybe(Color),
	alpha: f32,
) -> f32 {
	icon(icon_frame_rect({x + (width - size) / 2, y, size, size}), tint, alpha)
	return y + size + MENU_ICON_GAP
}

// horizontally centers `text` in `width` and draws it - the caption half of
// a stacked icon row
draw_menu_centered_text :: proc(text: string, x, y, width: f32, color: Color) {
	size := rl.MeasureTextEx(font, strings.clone_to_cstring(text, context.temp_allocator), MENU_THEME.font_size, 0)
	draw_text(text, Vec2{x + (width - size.x) / 2, y}, MENU_THEME.font_size, 0, color)
}

// the Run End receipt's inline treatment: a glyph in the left gutter, the
// line's text starting after it. Returns the x the text should start at.
MENU_INLINE_ICON_SIZE :: 16
MENU_INLINE_ICON_GAP :: 6

draw_menu_inline_icon :: proc(icon: Icon_Proc, x, y: f32, tint: Maybe(Color), alpha: f32) -> f32 {
	// centered against the text line's own height, not the icon's, so glyphs
	// sit on the same optical baseline as the words beside them
	iy := y + (MENU_THEME.font_size - MENU_INLINE_ICON_SIZE) / 2
	icon(icon_frame_rect({x, iy, MENU_INLINE_ICON_SIZE, MENU_INLINE_ICON_SIZE}), tint, alpha)
	return x + MENU_INLINE_ICON_SIZE + MENU_INLINE_ICON_GAP
}

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
// border, no shadow - the retired nine-slice container panel treatment
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
// `icon` is optional: nil keeps the original single-centered-label layout
// (Close/Continue/Spend buttons have nothing meaningful to depict), while a
// supplied glyph stacks above the label per the MENU_ICON_SIZE block above -
// so the button must be sized MENU_ICON_BUTTON_HEIGHT by its caller.
draw_menu_button :: proc(
	rect: Rect,
	label: string,
	anim: Menu_Element_Anim,
	disabled: bool = false,
	icon: Icon_Proc = nil,
	icon_tint: Maybe(Color) = nil,
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

	if icon == nil {
		text_pos := Vec2{dest.x + (dest.width - text_size.x) / 2, dest.y + (dest.height - text_size.y) / 2}
		draw_text(label, text_pos, MENU_THEME.font_size, 0, menu_with_alpha(text_color, anim.alpha))
		return clicked, state
	}

	// a disabled button flattens its glyph to the same gray as its label, so
	// the icon can't keep reading as live while the text says otherwise
	// (icon.odin's tint-replaces-rather-than-multiplies note)
	tint := icon_tint
	if disabled {
		tint = MENU_THEME.text_disabled
	}

	// the icon scales with the button so a shorter MENU_BUTTON_HEIGHT button
	// that opted into an icon still fits both halves
	icon_size := min(f32(MENU_ICON_SIZE) * anim.scale, dest.height - text_size.y - MENU_ICON_GAP)
	stack_h := icon_size + MENU_ICON_GAP + text_size.y
	top := dest.y + (dest.height - stack_h) / 2

	icon(icon_frame_rect({dest.x + (dest.width - icon_size) / 2, top, icon_size, icon_size}), tint, anim.alpha)
	draw_text(
		label,
		Vec2{dest.x + (dest.width - text_size.x) / 2, top + icon_size + MENU_ICON_GAP},
		MENU_THEME.font_size,
		0,
		menu_with_alpha(text_color, anim.alpha),
	)

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
// draw_account_progression_ui content (Account Level, banked progress into
// the next one, the Gold wallet, the Account_Stat spend list - see CONTEXT.md's Account
// progression entry) unconditionally, even at zero Gold (ADR-0012);
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
		f32(len(Account_Stat)) * (MENU_ICON_TEXT_LINE_HEIGHT + MENU_BUTTON_LINE_HEIGHT)

	// Relics are Account progression too (ADR-0019) but get their own panel
	// rather than more rows on Progression's: the two are different kinds of
	// purchase, and one panel carrying both ladders already stands 482px
	// tall against the 540px default window, overflowing outright the moment
	// a second Relic exists.
	relics_h :=
		pad * 2 +
		MENU_TEXT_LINE_HEIGHT +
		f32(len(Relic_Kind)) * (MENU_TEXT_LINE_HEIGHT + MENU_BUTTON_LINE_HEIGHT)

	button_count := 1 // "Start New Run" always shows
	if game.player.run_started {
		button_count += 1 // "Continue" only with a Run in progress
	}
	shooter_h := pad * 2 + f32(button_count) * MENU_BUTTON_LINE_HEIGHT

	row_h := max(progression_h, relics_h, shooter_h)
	row_w := panel_w * 3 + panel_gap * 2
	row_x := (game.window_width - row_w) / 2
	row_y := (game.window_height - row_h) / 2

	// the two progression panels sit together on the left, the panel
	// carrying the actual navigation last
	progression_rect := Rect{row_x, row_y, panel_w, progression_h}
	relics_rect := Rect{row_x + panel_w + panel_gap, row_y, panel_w, relics_h}
	shooter_rect := Rect{row_x + (panel_w + panel_gap) * 2, row_y, panel_w, shooter_h}

	panel_anim := menu_element_anim(0, button_count) // panel reveals first, dismisses last (rank button_count)
	draw_menu_panel(progression_rect, panel_anim)
	draw_menu_panel(relics_rect, panel_anim)
	draw_menu_panel(shooter_rect, panel_anim)

	y := progression_rect.y + pad
	// both of these are `label: value` readouts, so their glyphs sit inline
	// to the left rather than stacked above (see the MENU_ICON_SIZE block)
	text_x := draw_menu_inline_icon(icon_level, progression_rect.x + pad, y, nil, panel_anim.alpha)
	draw_text(
		fmt.tprintf("Account Lv. {}", game.player.level),
		Vec2{text_x, y},
		MENU_THEME.font_size,
		0,
		menu_with_alpha(MENU_THEME.text, panel_anim.alpha),
	)
	y += MENU_TEXT_LINE_HEIGHT
	// no slash in the HUD font's glyph set (atlas.odin's LETTERS_IN_FONT) -
	// it renders as "?", hence "of" instead
	text_x = draw_menu_inline_icon(icon_gold, progression_rect.x + pad, y, nil, panel_anim.alpha)
	draw_text(
		fmt.tprintf("Banked: {} of {}", game.player.banked_progress, gold_required_for_level(game.player.level)),
		Vec2{text_x, y},
		MENU_THEME.font_size,
		0,
		menu_with_alpha(MENU_THEME.text, panel_anim.alpha),
	)
	y += MENU_TEXT_LINE_HEIGHT
	draw_text(
		fmt.tprintf("Gold: {}", game.player.gold),
		Vec2{progression_rect.x + pad, y},
		MENU_THEME.font_size,
		0,
		menu_with_alpha(MENU_THEME.text, panel_anim.alpha),
	)
	y += MENU_TEXT_LINE_HEIGHT

	for stat in Account_Stat {
		y = draw_account_stat_row(stat, progression_rect.x + pad, y, panel_w - pad * 2, panel_anim)
	}

	ry := relics_rect.y + pad
	draw_text(
		"Relics",
		Vec2{relics_rect.x + pad, ry},
		MENU_THEME.font_size,
		0,
		menu_with_alpha(MENU_THEME.text, panel_anim.alpha),
	)
	ry += MENU_TEXT_LINE_HEIGHT

	for kind in Relic_Kind {
		ry = draw_relic_row(kind, relics_rect.x + pad, ry, panel_w - pad * 2, panel_anim)
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

// current stack plus a buy button, or a label in place of the button when
// the row can't be bought - now in all three of draw_shop_upgrade_row's
// states rather than always-buyable, since ADR-0016 gave Account_Stat both a
// max_stack and an Account-Level unlock gate. A locked row is still drawn
// rather than hidden, so the ladder banking is buying stays visible.
// Returns the cursor's new y, mirroring the running-y-cursor convention
// every screen below uses.
draw_account_stat_row :: proc(stat: Account_Stat, x, y, width: f32, anim: Menu_Element_Anim) -> f32 {
	preset := account_stat_presets[stat]
	stack := game.player.account_stat_stacks[stat]
	cursor := y

	unlocked := account_stat_unlocked(stat)
	maxed := account_stat_maxed(stat)
	affordable := game.player.gold >= account_stat_price(stat, stack)

	// locked / maxed / unaffordable all flatten the glyph to the row's own
	// disabled gray - a locked row stays drawn rather than hidden so the
	// ladder banking is buying stays visible, and its icon has to say so too
	tint: Maybe(Color) = nil
	text_color := MENU_THEME.text
	if !unlocked || maxed || !affordable {
		tint = MENU_THEME.text_disabled
		text_color = MENU_THEME.text_disabled
	}

	// Vigor/Might/Swiftness share the Max_Health/Damage/Move_Speed Upgrade
	// glyphs outright - same stat, bought on the other progression axis
	cursor = draw_menu_stacked_icon(account_stat_icons[stat], x, cursor, width, MENU_ICON_SIZE, tint, anim.alpha)

	label := fmt.tprintf("{} [{} of {}]", preset.display_name, stack, preset.max_stack)
	draw_menu_centered_text(label, x, cursor, width, menu_with_alpha(text_color, anim.alpha))
	cursor += MENU_TEXT_LINE_HEIGHT

	switch {
	case !unlocked:
		draw_menu_centered_text(
			fmt.tprintf("Unlocks at Lv. {}", preset.unlock_level),
			x,
			cursor,
			width,
			menu_with_alpha(MENU_THEME.text_disabled, anim.alpha),
		)
	case maxed:
		draw_menu_centered_text("MAXED", x, cursor, width, menu_with_alpha(MENU_THEME.text_disabled, anim.alpha))
	case:
		button_rect := Rect{x, cursor, width, MENU_BUTTON_HEIGHT}
		button_label := fmt.tprintf("Spend {} Gold", account_stat_price(stat, stack))
		// no icon on the button - the row's glyph is already above it
		clicked, _ := draw_menu_button(button_rect, button_label, anim, disabled = !affordable)
		if clicked {
			try_buy_account_stat(stat)
		}
	}
	cursor += MENU_BUTTON_LINE_HEIGHT

	return cursor
}

// the Relic ladder's equivalent of draw_account_stat_row, in the same three
// states (locked / MAXED / buyable) and the same two-line shape, since a
// Relic reuses Account_Stat's whole purchase mechanism - geometric price,
// hard cap, Account-Level unlock gate - and only differs in what a stack
// buys (ADR-0019). Drawn into its own panel beside Progression's rather
// than continuing its rows, since the two are different kinds of purchase.
// Returns the cursor's new y, same convention.
draw_relic_row :: proc(kind: Relic_Kind, x, y, width: f32, anim: Menu_Element_Anim) -> f32 {
	preset := relic_presets[kind]
	stack := game.player.relic_stacks[kind]
	cursor := y

	label := fmt.tprintf("{} [{} of {}]", preset.display_name, stack, preset.max_stack)
	draw_text(label, Vec2{x, cursor}, MENU_THEME.font_size, 0, menu_with_alpha(MENU_THEME.text, anim.alpha))
	cursor += MENU_TEXT_LINE_HEIGHT

	switch {
	case !relic_unlocked(kind):
		draw_text(
			fmt.tprintf("Unlocks at Lv. {}", preset.unlock_level),
			Vec2{x, cursor},
			MENU_THEME.font_size,
			0,
			menu_with_alpha(MENU_THEME.text_disabled, anim.alpha),
		)
	case relic_maxed(kind):
		draw_text(
			"MAXED",
			Vec2{x, cursor},
			MENU_THEME.font_size,
			0,
			menu_with_alpha(MENU_THEME.text_disabled, anim.alpha),
		)
	case:
		button_rect := Rect{x, cursor, width, MENU_BUTTON_HEIGHT}
		button_label := fmt.tprintf("Spend {} Gold", relic_price(kind, stack))
		if clicked, _ := draw_menu_button(button_rect, button_label, anim); clicked {
			try_buy_relic(kind)
		}
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
		"Your weapon tier and Upgrades will be lost. Gold is kept.",
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

	col_content_h := MENU_TEXT_LINE_HEIGHT + f32(max_kinds) * MENU_ICON_BUTTON_LINE_HEIGHT
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
			button_rect := Rect{col_x, y, col_w, MENU_ICON_BUTTON_HEIGHT}
			// per-kind glyph, not per-family: Pistol/SMG/Shotgun are three
			// distinct silhouettes here, which is the whole of ADR-0018
			clicked, _ := draw_menu_button(
				button_rect,
				weapon_display_name[kind],
				anim,
				icon = weapon_icons[kind],
			)
			if clicked {
				start_new_run(kind)
				request_screen_change(.Map_Selection)
			}
			y += MENU_ICON_BUTTON_LINE_HEIGHT
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
	h := pad * 2 + (MENU_THEME.font_size + 4) + MENU_THEME.gap + f32(button_count) * MENU_ICON_BUTTON_LINE_HEIGHT

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

		// a flat swatch in the Map's own color - passed as the icon's tint
		// rather than baked into a glyph, since a swatch's color *is* its
		// content (see icon_swatch). A placeholder vocabulary while Map_Name
		// has one case; worth designing properly at map two.
		button_rect := Rect{rect.x + pad, y, w - pad * 2, MENU_ICON_BUTTON_HEIGHT}
		clicked, _ := draw_menu_button(
			button_rect,
			chosen.name,
			anim,
			icon = icon_swatch,
			icon_tint = map_icon_colors[name],
		)
		if clicked {
			// clone_map, never a plain value copy - game.current_map would
			// otherwise alias the shared baked table's backing tile/spawner
			// memory (see clone_map's doc comment)
			game.current_map = clone_map(chosen)
			apply_chosen_map(chosen, map_identity_string(name))
			request_screen_change(nil) // Playing isn't a Screen - see current_screen
		}
		y += MENU_ICON_BUTTON_LINE_HEIGHT
	}
}

// shown once a Run finishes, however it finished (game.run_ended, set by
// end_run via request_screen_change(.Run_End) - see ADR-0017). One screen
// with a per-outcome header rather than a separate Victory Screen_Kind, so
// no new wiring through current_screen/apply_screen_kind/rank_count is
// needed for the two endings ADR-0017 added.
//
// The body is a receipt, not a summary: earned - spent = net, net + bonus =
// banked. The "Gold spent" line is the whole point - with Gold as the single
// currency (ADR-0016), a Shop purchase is paid for out of Account
// progression, and this is the only place that cost is ever shown. The
// Account Level/Account_Stat spend list stays on the Main Menu (ADR-0012);
// Continue leads there.
run_end_title :: proc(outcome: Run_Outcome) -> string {
	switch outcome {
	case .Cleared:
		return "Map Cleared"
	case .Timed_Out:
		return "Out of Time"
	case .Killed:
		return "Killed"
	}
	return "Run Ended" // unreachable: outcome is always one of the above
}

draw_run_end_ui :: proc() {
	receipt := game.last_run_receipt
	// the bonus line only exists on a cleared Run
	line_count := 5
	if receipt.bonus > 0 {
		line_count += 1
	}

	pad := MENU_THEME.padding
	w: f32 = 320
	h :=
		pad * 2 +
		(MENU_THEME.font_size + 4) +
		MENU_THEME.gap +
		f32(line_count) * MENU_TEXT_LINE_HEIGHT +
		MENU_THEME.gap +
		MENU_BUTTON_LINE_HEIGHT

	rect := Rect{(game.window_width - w) / 2, (game.window_height - h) / 2, w, h}
	anim := menu_element_anim(0, 0)
	draw_menu_panel(rect, anim)

	draw_text(
		run_end_title(game.last_run_outcome),
		Vec2{rect.x + pad, rect.y + pad},
		MENU_THEME.font_size + 4,
		0,
		menu_with_alpha(MENU_THEME.text, anim.alpha),
	)

	y := rect.y + pad + (MENU_THEME.font_size + 4) + MENU_THEME.gap
	text_color := menu_with_alpha(MENU_THEME.text, anim.alpha)

	// a receipt is read left-to-right as a sentence, so its glyphs stay
	// inline in the left gutter rather than stacked above centered text -
	// the exception to the icon-above-label rule the browsable screens use
	line :: proc(icon: Icon_Proc, text: string, x: f32, y: ^f32, color: Color, alpha: f32) {
		text_x := draw_menu_inline_icon(icon, x, y^, nil, alpha)
		draw_text(text, Vec2{text_x, y^}, MENU_THEME.font_size, 0, color)
		y^ += MENU_TEXT_LINE_HEIGHT
	}

	// all four money lines take Gold's own circle. The repetition groups
	// them as "these are the money lines" against Kills and Account Lv.,
	// which is what a receipt wants - and four near-identical modifier
	// glyphs at this size is where legibility would collapse.
	a := anim.alpha
	line(icon_kills, fmt.tprintf("Kills: {}", total_kills(game.player.kills)), rect.x + pad, &y, text_color, a)
	line(icon_gold, fmt.tprintf("Gold earned: {}", receipt.earned), rect.x + pad, &y, text_color, a)
	line(icon_gold, fmt.tprintf("Gold spent: {}", receipt.spent), rect.x + pad, &y, text_color, a)
	if receipt.bonus > 0 {
		line(icon_gold, fmt.tprintf("Victory bonus: {}", receipt.bonus), rect.x + pad, &y, text_color, a)
	}
	line(icon_gold, fmt.tprintf("Banked: {}", receipt.banked), rect.x + pad, &y, text_color, a)
	line(icon_level, fmt.tprintf("Account Lv. {}", game.player.level), rect.x + pad, &y, text_color, a)

	y += MENU_THEME.gap

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

	// the family-gated Upgrade block rides in the left column under the
	// weapon ladder rather than under the general block on the right.
	// Stacking each row's glyph above its caption grew every row by ~19px,
	// and the Shop was already ~512px tall at the default 960x540 window -
	// balancing the two columns is what keeps it on screen without
	// scrolling (ADR-0010: no layout engine to scroll with).
	content_h := max(
		shop_weapon_ladder_height() + shop_family_upgrades_height(),
		shop_general_upgrades_height(),
	)
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
	family := weapon_kind_family[game.player.weapon.kind]
	draw_shop_upgrade_block(
		weapon_family_display_name[family],
		true,
		left_x,
		col_y + shop_weapon_ladder_height(),
		col_w,
		anim,
	)
	draw_shop_upgrade_block("General", false, right_x, col_y, col_w, anim)

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
	return MENU_TEXT_LINE_HEIGHT + MENU_SHOP_ICON_TEXT_LINE_HEIGHT + MENU_ICON_BUTTON_LINE_HEIGHT
}

// current weapon plus either a "buy next tier" button or, at the ladder's
// top, a "Fully Upgraded" label in place of one (disabled-in-spirit - see
// draw_shop_upgrade_row for the same MAXED-label tradeoff on Upgrades)
draw_shop_weapon_ladder :: proc(x, y, width: f32, anim: Menu_Element_Anim) {
	cursor := y
	text_color := menu_with_alpha(MENU_THEME.text, anim.alpha)

	draw_text("Weapon Ladder", Vec2{x, cursor}, MENU_THEME.font_size, 0, text_color)
	cursor += MENU_TEXT_LINE_HEIGHT

	// the equipped weapon's own glyph above its name - the same mark the
	// world draws in the player's hands (ADR-0018)
	kind := game.player.weapon.kind
	cursor = draw_menu_stacked_icon(weapon_icons[kind], x, cursor, width, MENU_SHOP_ICON_SIZE, nil, anim.alpha)
	draw_menu_centered_text(weapon_display_name[kind], x, cursor, width, text_color)
	cursor += MENU_TEXT_LINE_HEIGHT

	if next, has_next := weapon_next_tier(kind).?; has_next {
		price := weapon_tier_price(weapon_tier_index(next))
		label := fmt.tprintf("Buy {} - {}g", weapon_display_name[next], price)
		button_rect := Rect{x, cursor, width, MENU_ICON_BUTTON_HEIGHT}
		// the *next* tier's glyph, so the button shows what you're buying
		// rather than what you already have
		clicked, _ := draw_menu_button(button_rect, label, anim, icon = weapon_icons[next])
		if clicked {
			try_buy_next_weapon_tier()
		}
	} else {
		draw_menu_centered_text("Fully Upgraded", x, cursor, width, text_color)
	}
}

// counts how many Upgrade_Kinds draw_shop_upgrade_block will draw in one of its
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

// one Upgrade row: its glyph, its name+stack caption, then a buy button or
// a MAXED label in the button's place
shop_upgrade_row_height :: proc() -> f32 {
	return MENU_SHOP_ICON_TEXT_LINE_HEIGHT + MENU_BUTTON_LINE_HEIGHT
}

// a header line plus `row_count` Upgrade rows - the shape of both the
// general and the family-gated block
shop_upgrade_block_height :: proc(row_count: int) -> f32 {
	return MENU_TEXT_LINE_HEIGHT + f32(row_count) * shop_upgrade_row_height()
}

shop_general_upgrades_height :: proc() -> f32 {
	family := weapon_kind_family[game.player.weapon.kind]
	return shop_upgrade_block_height(shop_upgrade_kind_count(family, false))
}

shop_family_upgrades_height :: proc() -> f32 {
	family := weapon_kind_family[game.player.weapon.kind]
	return shop_upgrade_block_height(shop_upgrade_kind_count(family, true))
}

// one block of Upgrade rows under a header: `gated` picks the general
// (false) or family-specific (true) bucket. Both queries reuse
// upgrade_available_to_family rather than re-inlining its
// upgrade_presets[kind].family.? check, so the gating rule only lives in
// one place (upgrade.odin). Returns the cursor's new y.
draw_shop_upgrade_block :: proc(header: string, gated: bool, x, y, width: f32, anim: Menu_Element_Anim) -> f32 {
	family := weapon_kind_family[game.player.weapon.kind]
	cursor := y

	draw_text(header, Vec2{x, cursor}, MENU_THEME.font_size, 0, menu_with_alpha(MENU_THEME.text, anim.alpha))
	cursor += MENU_TEXT_LINE_HEIGHT

	for kind in Upgrade_Kind {
		_, kind_gated := upgrade_presets[kind].family.?
		if kind_gated == gated && upgrade_available_to_family(kind, family) {
			cursor = draw_shop_upgrade_row(kind, x, cursor, width, anim)
		}
	}
	return cursor
}

// current stack/cap plus either a buy button or, at the cap, a "MAXED" label
// in place of one (see draw_shop_weapon_ladder's note on the same tradeoff).
// Returns the cursor's new y, like draw_account_stat_row above.
draw_shop_upgrade_row :: proc(kind: Upgrade_Kind, x, y, width: f32, anim: Menu_Element_Anim) -> f32 {
	preset := upgrade_presets[kind]
	stack := game.player.upgrade_stacks[kind]
	cursor := y

	maxed := upgrade_maxed(kind)
	price := upgrade_price(kind, stack)
	affordable := game.player.gold >= price

	// a maxed or unaffordable row flattens its glyph to the same gray its
	// text already uses, so the icon can't keep reading as purchasable while
	// the row isn't (icon.odin's tint-replaces note)
	tint: Maybe(Color) = nil
	text_color := MENU_THEME.text
	if maxed || !affordable {
		tint = MENU_THEME.text_disabled
		text_color = MENU_THEME.text_disabled
	}

	cursor = draw_menu_stacked_icon(upgrade_icons[kind], x, cursor, width, MENU_SHOP_ICON_SIZE, tint, anim.alpha)

	// parens/slash aren't in the HUD font's glyph set (atlas.odin's
	// LETTERS_IN_FONT) and render as "?" - brackets/hyphen are
	label := fmt.tprintf("{} [{}-{}]", preset.display_name, stack, preset.max_stack)
	draw_menu_centered_text(label, x, cursor, width, menu_with_alpha(text_color, anim.alpha))
	cursor += MENU_TEXT_LINE_HEIGHT

	if maxed {
		draw_menu_centered_text("MAXED", x, cursor, width, menu_with_alpha(MENU_THEME.text_disabled, anim.alpha))
	} else {
		button_rect := Rect{x, cursor, width, MENU_BUTTON_HEIGHT}
		// no icon on the button - the row's glyph is already directly above
		// it. `disabled` when unaffordable stops the button claiming a
		// purchase try_buy_upgrade would reject anyway.
		clicked, _ := draw_menu_button(button_rect, fmt.tprintf("Buy - {}g", price), anim, disabled = !affordable)
		if clicked {
			try_buy_upgrade(kind)
		}
	}
	cursor += MENU_BUTTON_LINE_HEIGHT

	return cursor
}

// -- live Run-scoped meta-stats ---------------------------------------------

HUD_COUNTER_FONT_SIZE :: 10
HUD_COUNTER_MARGIN :: 10 // mirrors the top-left "Editing" text's margin

// matches RESOURCE_BAR_ICON_SIZE - the Resource indicator's glyph slot is
// the only other place an Icon is drawn at world/HUD scale rather than menu
// scale, and the two reading at the same size keeps the screen coherent
HUD_COUNTER_ICON_SIZE :: 9
HUD_COUNTER_ICON_GAP :: 3 // between a counter's glyph and its number
HUD_COUNTER_GAP :: 10 // between counters

// one top-right Run-scoped readout: a glyph and a bare number, no label.
// The glyph carries what the words used to.
Hud_Counter :: struct {
	icon: Icon_Proc,
	text: string,
}

// top-right Kills / Time / Gold readout, drawn every frame while Playing
// (main.odin's game.ui_camera block). Reads the existing Run-scoped Player
// fields directly - see CONTEXT.md's Run entry and the enemy-spawn-revamp
// map's ticket 01 - the same total_kills/survival_seconds the Run End screen
// and Spawn Trigger Kills_Reached/Time_Elapsed conditions use, plus the same
// `gold` the Shop spends.
//
// Each counter is an Icon and a bare number, no label: three glyphs read
// faster at a glance mid-fight than "Kills:"/"Time:" ever did, and dropping
// the words is what buys the room for a third counter without crowding the
// corner. Icons sit inline-left of their value, the same treatment the Run
// End receipt's readout lines use (see the MENU_ICON_SIZE block).
//
// Time counts *down* against the Map's time_limit now that running it out
// ends the Run (ADR-0017), clamped at zero so the last frame before the
// Timed_Out check fires never renders a negative clock. An untimed Map
// (time_limit <= 0) keeps the original count-up.
draw_hud_counters :: proc() {
	total_seconds := int(game.player.survival_seconds)
	if limit := game.current_map.time_limit; limit > 0 {
		total_seconds = max(0, int(limit) - total_seconds)
	}

	counters := [?]Hud_Counter {
		{icon_kills, fmt.tprintf("{}", total_kills(game.player.kills))},
		{icon_clock, fmt.tprintf("{:02d}:{:02d}", total_seconds / 60, total_seconds % 60)},
		{icon_gold, fmt.tprintf("{}", game.player.gold)},
	}

	// measured up front so the whole row can be right-aligned as a unit -
	// otherwise a counter growing a digit would push the others sideways
	// rather than the row growing leftward off its fixed right edge
	text_widths: [len(counters)]f32
	row_width: f32
	for counter, i in counters {
		text_widths[i] =
			rl.MeasureTextEx(
				font,
				strings.clone_to_cstring(counter.text, context.temp_allocator),
				HUD_COUNTER_FONT_SIZE,
				0,
			).x
		row_width += HUD_COUNTER_ICON_SIZE + HUD_COUNTER_ICON_GAP + text_widths[i]
	}
	row_width += HUD_COUNTER_GAP * f32(len(counters) - 1)

	virtual_width := game.window_width / game.ui_camera.zoom
	x := virtual_width - row_width - HUD_COUNTER_MARGIN
	y: f32 = HUD_COUNTER_MARGIN

	// glyphs centered against the text line's height, not their own, so they
	// sit on the same optical baseline as the numbers beside them
	icon_y := y + (HUD_COUNTER_FONT_SIZE - HUD_COUNTER_ICON_SIZE) / 2

	for counter, i in counters {
		counter.icon(icon_frame_rect({x, icon_y, HUD_COUNTER_ICON_SIZE, HUD_COUNTER_ICON_SIZE}), nil, 1)
		x += HUD_COUNTER_ICON_SIZE + HUD_COUNTER_ICON_GAP

		draw_text(counter.text, Vec2{x, y}, HUD_COUNTER_FONT_SIZE, 0, rl.WHITE)
		x += text_widths[i] + HUD_COUNTER_GAP
	}
}
