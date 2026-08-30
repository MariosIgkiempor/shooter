# In-Game Menu UI Overhaul

Label: wayfinder:map

## Destination

An implementation-ready spec for a minimal, hand-rolled, first-party UI layer — no generic layout engine — that replaces `vendor/ui` in the six existing in-game menu screens in `hud.odin` (`draw_splash_ui`, `draw_account_progression_ui`, `draw_run_start_ui`, `draw_map_selection_ui`, `draw_run_end_ui`, `draw_shop_ui` + its sub-panels): the component API (button/panel/text helpers), the styling/theming convention, and the per-screen positioning approach, all precise enough that a build session could implement it directly with no open design questions left. `debug.odin` and `editor.odin` keep `vendor/ui` untouched.

## Notes

- Odin + raylib. `vendor/ui` (`vendor/ui/layout.odin` + `vendor/ui/ui/ui.odin`) is a first-party git submodule providing immediate-mode layout/widgets; it stays exactly as-is for `debug.odin` (F8 panel) and `editor.odin` (level editor) — not touched by this map.
- Reuse `draw_ui_panel` ([hud.odin:23](../../hud.odin)) and `draw_nine_slice` ([renderer.odin:67](../../renderer.odin)) as the vendor-free panel-background primitive rather than reinventing nine-slice rendering.
- The gameplay HUD (health bar, ammo, etc. — `draw_hud_bar`/`draw_hud_label_row`/`draw_hud_icon_row` in `hud.odin`) already never used `vendor/ui`; it's the existing reference for what "simple, hand-rolled" looks like in this codebase.
- No generic layout engine — decided during charting (see Decisions so far). Positioning is per-screen, not a `vendor/ui`-style flex/grow system.
- This map is a **spec to hand off**, not execution — tickets decide, they don't implement the migration. Default wayfinder behavior applies, not overridden.
- Grilling tickets: call the Skill tool twice, for "grilling" and "domain-modeling". The prototype ticket: call the Skill tool for "prototype".

## Decisions so far

- [Naming the destination + mapping the frontier](map.md): scope is the six existing menu screens only — no pause menu or other new screens (doesn't exist today, stays out of scope). The new UI layer is minimal and hand-rolled per screen, explicitly not a generic layout engine like `vendor/ui`'s `layout.odin` — closer in spirit to the existing `draw_hud_bar`-style code. This map plans; it doesn't build — the spec is the deliverable, migration is a follow-up effort.
- [Audit exact per-screen widget & visual needs](issues/01-audit-menu-screen-widgets.md): every screen only ever uses `ui.begin`(panel)/`ui.row`/`ui.column`/`ui.text`/`ui.button` — nothing beyond plain button/panel/text is technically used, `ui.slider` is unused in all six screens (only `editor.odin` calls it), but `draw_shop_upgrade_row`/`draw_account_stat_row` encode stack/max state as plain interpolated text (no dedicated stack indicator widget) and maxed states render as a bare text label with the button omitted entirely since `vendor/ui` has no disabled-button state — both worth deciding on explicitly in the new component API.
- [Prototype a hand-rolled Shop screen](issues/02-prototype-shop-screen.md): tile-grid layout wins (manual row/col grid math, not a running-cursor helper or a generic layout engine), with a numeric `stack-max` badge per tile rather than a pip row or progress bar, and a real disabled/grayed "MAXED" button rather than today's bare text label — validated live via `shop_ui_prototype.odin` on the throwaway `prototype/shop-screen-variants` branch. The shared hover/press/disabled `proto_button` primitive is locked regardless of layout.
- [Component API & styling convention](issues/03-component-api-and-styling.md): one new helper, `draw_menu_button(rect, label, disabled = false) -> (clicked, state)`, positional params, reusing `draw_ui_panel`/`draw_text` as-is for everything else — no purchasable-row helper despite the shape recurring 3x, no positioning-helper procedure (a documented running-`y`-cursor convention for five screens, Shop's inline grid math for the sixth), and a new first-party `Menu_Theme` constant table replacing `HUD_THEME`'s `ui.Theme` typing. Recorded as [ADR-0010](../../docs/adr/0010-hand-rolled-menu-ui-no-layout-engine.md). This is the map's last ticket — the route to the destination is clear.

## Not yet specified

Empty — every branch the frontier surfaced has either resolved into a ticket or been settled directly; nothing is left unspecified.

## Out of scope

- A pause menu — doesn't exist today; excluded from this effort's scope per the initial charting decision above.
- `debug.odin` / `editor.odin` — stay on `vendor/ui`, unchanged.
- Actual implementation/migration of the six screens' Odin code — this map's destination is the spec, not the code; a separate effort executes it.
