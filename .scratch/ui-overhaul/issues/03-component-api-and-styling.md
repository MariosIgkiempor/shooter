Type: grilling
Status: resolved
Blocked by: 02

## Question

Given the validated feel from [Prototype a hand-rolled Shop screen](02-prototype-shop-screen.md), what's the actual minimal, reusable component API and styling convention for the new UI layer, precise enough to implement all six screens?

Decide:
- The small helper-function set (e.g. a `button`, a panel-background helper, a text-drawing helper) and their exact Odin signatures/param structs — matching this codebase's existing naming conventions (`draw_*` prefix, `Options`-struct style used elsewhere).
- Whether any lightweight positioning convention is shared across screens (a running vertical-cursor helper) or each screen just hardcodes its own coordinates, per the "minimal, hand-rolled" decision already locked on the map.
- The theming/color/padding convention: a single shared constant table (mirroring `HUD_THEME`'s role today) vs per-screen constants, and how it interacts with `draw_ui_panel`'s existing nine-slice styling.
- Hover/press/click state handling with plain raylib input, confirmed against what the prototype validated.

## Answer

Locked via grilling (all five recommendations accepted as-is) and recorded as [ADR-0010](../../../docs/adr/0010-hand-rolled-menu-ui-no-layout-engine.md).

**One new helper, positional params, matching this codebase's existing hand-rolled drawing helpers (not `vendor/ui`'s `Options`-struct style):**

```odin
Menu_Button_State :: enum { Normal, Hover, Pressed, Disabled }

draw_menu_button :: proc(rect: Rect, label: string, disabled: bool = false) -> (clicked: bool, state: Menu_Button_State)
```

Hover/press/click exactly as validated in the prototype's `proto_button` (`shop_ui_prototype.odin` on the `prototype/shop-screen-variants` branch): `rl.CheckCollisionPointRec(game.mouse.position, rect)` for hover, `is_mouse_button_down(.LEFT)` for pressed, `rl.IsMouseButtonReleased(.LEFT)` while hovered for `clicked` — no press-began-here tracking, since these are static, rebuilt-every-frame menus with no overlapping or moving buttons.

**Nothing else new.** `draw_ui_panel` (`hud.odin:23`) and `draw_text` (`renderer.odin:96`) are reused as-is for panel backgrounds and every label/title — a screen's title is just its own first `draw_text` call, not a dedicated window/title-bar primitive. No "purchasable row" helper: `draw_account_stat_row`/`draw_shop_weapon_ladder`/`draw_shop_upgrade_row` (the three recurring name+price+button call sites per [01-audit-menu-screen-widgets](01-audit-menu-screen-widgets.md)) each hand-assemble from `draw_menu_button` + `draw_text`, since their three shapes don't actually match closely enough to share one signature (weapon ladder has no stack count; Account Progression rows never go disabled; Shop rows carry a `stack-max` badge).

**Positioning: convention, not a function**, for both cases —
- Five screens (Splash excepted — it already has zero UI calls): a plain running `y` cursor per screen, `y += row_height + gap` after each element, exactly as the prototype's Variant B did before it lost to Variant C.
- Shop only: inline manual row/col grid math, exactly as the validated Variant C — `tx := x0 + f32(col) * (tile_w + gap)`, `ty := grid_top + f32(row) * (tile_h + gap)`, built from a flat per-tile item list.

Neither is wrapped in a shared procedure — each is only used by the screens that need it, and both are simple enough to read inline.

**Theming — a new first-party `Menu_Theme` constant table**, replacing `HUD_THEME`'s current `ui.Theme` typing, values carried straight from the validated prototype:

```odin
Menu_Theme :: struct {
	button:          Color,
	button_hover:    Color,
	button_pressed:  Color,
	button_disabled: Color,
	text:            Color,
	text_disabled:   Color,
	font_size:       f32,
	padding:         f32,
	gap:             f32,
}

MENU_THEME :: Menu_Theme {
	button          = {74, 80, 94, 255},
	button_hover    = {96, 104, 122, 255},
	button_pressed  = {110, 118, 138, 255},
	button_disabled = {50, 52, 58, 180},
	text            = rl.WHITE,
	text_disabled   = {150, 150, 150, 255},
	font_size       = 18,
	padding         = 24,
	gap             = 8,
}
```

Drops the window-chrome fields `ui.Theme` forced onto `HUD_THEME` (`title_bar`, `title_text`, `window_background`) that the hand-rolled screens have no use for. `draw_ui_panel`'s existing tint/corner_scale params are how `draw_menu_button` expresses its four states — no separate styling mechanism needed.

**Cross-screen validation**: this settles the map's "Not yet specified" question of validating the API against the five screens beyond the one prototyped — by convention rather than by prototyping each one individually. Every one of the six screens' widget needs (per the audit ticket) reduces to `draw_menu_button` + `draw_text` + `draw_ui_panel` composed via a per-screen `y` cursor, with Shop as the sole grid exception already prototyped directly. No screen needs anything this API doesn't already cover.

This is the map's last open ticket — the route to the destination is clear.
