Type: grilling
Status: resolved
Blocked by: 01

## Question

Given the validated look and feel from [Prototype flat-rect visual style + Reveal/Dismiss motion feel](01-prototype-flat-rect-visual-and-motion.md), design the successor component API to [ADR-0010](../../../docs/adr/0010-hand-rolled-menu-ui-no-layout-engine.md)'s — now also needing to carry Reveal/Dismiss animation state, not just draw a static panel/button.

Decide:
- What `draw_menu_panel`/`draw_menu_button` (or their successors) look like: signatures, param structs, matching this codebase's existing hand-rolled `draw_*` conventions.
- Where per-Menu-element Reveal/Dismiss timer/phase state persistently lives, given this is immediate-mode UI redrawn every frame with no persistent widget tree today — a per-screen state struct (in ADR-0010's hand-rolled spirit) versus any alternative, and how Reveal delay gets set per element.
- How a Screen change sequences "outgoing elements' Dismiss finishes → `ProgramMode` switches → incoming elements' Reveal starts."
- What replaces `HUD_THEME`'s current `vendor/ui`-typed `ui.Theme`, folding in the validated colors/border/shadow treatment from the prototype.
- How Main Menu's worked stagger example (per this map's Out of scope) is expressed through the API — a per-element delay parameter, an ordered list, or something else.

This ticket's resolution must also:
- Record a new ADR marking [ADR-0010](../../../docs/adr/0010-hand-rolled-menu-ui-no-layout-engine.md) as superseded — its "no generic layout engine" decision stands unchanged; its "reuse `draw_nine_slice`" line is overturned.
- Append an amendment pointer into [ui-overhaul](../../ui-overhaul/map.md)'s Decisions-so-far, per domain-modeling's flag-conflicts rule (not a silent override).

## Answer

Recorded as [ADR-0014](../../../docs/adr/0014-menu-ui-flat-rect-and-reveal-dismiss-animation.md), superseding [ADR-0010](../../../docs/adr/0010-hand-rolled-menu-ui-no-layout-engine.md) (amendment pointer appended to [ui-overhaul](../../ui-overhaul/map.md)'s Notes).

**Screen unification** — one enum covering all six Screens, resolved from whichever of `program_mode`/`run_ended`/`shopping` is currently authoritative (confirmed mutually exclusive already — `shopping` can only toggle on while `run_ended` is false):

```odin
Screen_Kind :: enum { Splash, Main_Menu, Run_Start, Map_Selection, Shop, Run_End }

current_screen :: proc() -> Maybe(Screen_Kind) {
	if game.run_ended do return .Run_End
	if game.shopping do return .Shop
	switch game.program_mode {
	case .Splash:            return .Splash
	case .Main_Menu:         return .Main_Menu
	case .Run_Start:         return .Run_Start
	case .Selecting:         return .Map_Selection
	case .Playing, .Editing: return nil // not a Screen
	}
	return nil
}
```

Scoped narrowly: only the menu-drawing/transition code uses `Screen_Kind`. Every existing `program_mode`/`run_ended`/`shopping` check elsewhere in the codebase (gameplay logic, spawn conditions, etc.) is untouched.

**Shared transition state** — no per-element fields; one record, held once (e.g. `game.menu_transition`), since only one Screen ever transitions at a time:

```odin
Menu_Transition :: struct {
	current:            Screen_Kind,
	current_entered_at: f32,          // rl.GetTime() when the current Screen's Reveal began
	dismissing_to:      Maybe(Screen_Kind),
	dismiss_started_at: f32,
}
```

**Screen-change chokepoint** — replaces every direct `program_mode =` / `run_ended = true` / `shopping = !shopping` assignment that represents an actual Screen change (not `Playing`↔`Editing`, which isn't a Screen) across `hud.odin`/`main.odin`:

```odin
request_screen_change :: proc(to: Screen_Kind) {
	if game.menu_transition.dismissing_to != nil do return // a change is already in flight
	game.menu_transition.dismissing_to = to
	game.menu_transition.dismiss_started_at = f32(rl.GetTime())
}

// called once per frame from update_game
update_menu_transition :: proc() {
	to := game.menu_transition.dismissing_to.? or_return
	if f32(rl.GetTime()) - game.menu_transition.dismiss_started_at < dismiss_window_for(game.menu_transition.current) {
		return // outgoing Screen still Dismissing
	}
	apply_screen_kind(to) // the one place that actually writes program_mode/run_ended/shopping
	game.menu_transition.current = to
	game.menu_transition.current_entered_at = f32(rl.GetTime())
	game.menu_transition.dismissing_to = nil
}
```

`dismiss_window_for` and `apply_screen_kind` are small, exhaustive switches over `Screen_Kind` — the former returns `MENU_THEME.duration + (rank_count(screen)-1) * MENU_THEME.stagger_step`, the latter is the mirror image of `current_screen`'s mapping (e.g. `.Shop → game.shopping = false` when leaving Shop, `.Main_Menu → game.program_mode = .Main_Menu` when entering it).

**Per-element animation timing** — stateless, computed from rank + the shared transition record; mirrors the prototype's `proto_animate`/`proto_button` split (drawing stays "dumb"):

```odin
Menu_Element_Anim :: struct { alpha: f32, scale: f32 }

menu_element_anim :: proc(reveal_rank, dismiss_rank: int) -> Menu_Element_Anim {
	now := f32(rl.GetTime())
	if to, dismissing := game.menu_transition.dismissing_to.?; dismissing {
		start := game.menu_transition.dismiss_started_at + f32(dismiss_rank) * MENU_THEME.stagger_step
		e := MENU_THEME.ease(clamp((now - start) / MENU_THEME.duration, 0, 1))
		return {alpha = 1 - e, scale = MENU_THEME.scale_from + (1 - MENU_THEME.scale_from) * (1 - e)}
	}
	start := game.menu_transition.current_entered_at + f32(reveal_rank) * MENU_THEME.stagger_step
	e := MENU_THEME.ease(clamp((now - start) / MENU_THEME.duration, 0, 1))
	return {alpha = e, scale = MENU_THEME.scale_from + (1 - MENU_THEME.scale_from) * e}
}
```

Rank convention: the panel is rank 0 (reveals first), buttons are reveal-rank 1..N in order; on dismiss, buttons rank 0..N-1 in reverse order, panel ranks last (N) — this *is* Main Menu's worked cascading-reveal example. Every other screen just passes `reveal_rank = dismiss_rank = 0` for every element (synchronized, no stagger) — per this map's Out of scope, no other screen's choreography is pre-authored.

**`Menu_Theme` (replaces `HUD_THEME`)** — values are Variant C, straight from the prototype:

```odin
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

MENU_THEME :: Menu_Theme {
	fill = {40, 44, 52, 255}, fill_hover = {52, 58, 68, 255},
	fill_pressed = {30, 33, 39, 255}, fill_disabled = {40, 41, 45, 180},
	border_color = {130, 170, 230, 255}, border_width = 2,
	text = rl.WHITE, text_disabled = {130, 130, 130, 255},
	font_size = 18, padding = 24, gap = 8,
	duration = 0.20, ease = ease_out_cubic, scale_from = 0.9, stagger_step = 0.05,
}
```

**Draw functions** — keep ADR-0010's positional-param convention; take `anim` explicitly rather than computing it themselves:

```odin
draw_menu_panel :: proc(rect: Rect, anim: Menu_Element_Anim)

draw_menu_button :: proc(rect: Rect, label: string, anim: Menu_Element_Anim, disabled: bool = false) -> (clicked: bool, state: Menu_Button_State)
```

Hover/press mechanics unchanged from ADR-0010 (`rl.CheckCollisionPointRec` + plain `IsMouseButtonDown`/`Released`), gated additionally by `anim.alpha` above a threshold (mirrors the prototype's `interactive := alpha > 0.8`) so a still-animating button can't be clicked mid-fade — this only suppresses hover/click detection, not drawing.

**Positioning** is unchanged from ADR-0010 (per-screen running-`y`-cursor; Shop's inline grid math) — out of this ticket's scope, the loop only additionally tracks each element's rank alongside its position.

This is the map's last ticket — the route to the destination is clear.
