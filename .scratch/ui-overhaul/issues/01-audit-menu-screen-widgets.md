Type: research
Status: resolved

## Question

Exactly what does each of the six in-game menu screens in `hud.odin` (`draw_splash_ui`, `draw_account_progression_ui`, `draw_run_start_ui`, `draw_map_selection_ui`, `draw_run_end_ui`, `draw_shop_ui` + its sub-panels `draw_shop_weapon_ladder`/`draw_shop_upgrades`/`draw_shop_upgrade_row`/`draw_account_stat_row`) actually draw with `vendor/ui`?

For each screen, list every `vendor/ui`/`ui.*` call it makes and what visual element it produces (panel/window, row/column grouping, text, button, slider, anything else). Flag anything beyond plain button/panel/text — in particular, check whether the shop's upgrade rows (`draw_shop_upgrade_row`, `draw_account_stat_row`) need something like a stack/level indicator, a disabled "maxed" state, or a slider (`ui.slider` exists in the library — is it actually used anywhere?).

The goal is a precise per-screen widget inventory that [Prototype a hand-rolled Shop screen](02-prototype-shop-screen.md) and [Component API & styling convention](03-component-api-and-styling.md) can design against, instead of guessing from a summary.

Not blocked — this only requires reading `hud.odin`.

## Answer

Source: `hud.odin` (510 lines total), read in full. All six screens share the same
frame boilerplate: swap in `HUD_THEME` (`hud.odin:177-190`), call
`ui.set_pointer_state`/`ui.begin_frame`, wrap everything in a centered
`ui.row({size = {layout.grow(0,0), layout.grow(0,0)}, align = {.Center,.Center}})`,
then `draw_ui_render_commands(ui.end_frame(), MENU_PANEL_SCALE)` which turns any
node with `panel = true` into a nine-slice panel (`hud.odin:198-221`) instead of a
flat rect — everything else (plain `ui.text`, non-panel containers) renders as
flat rects/text via that same walker. Every screen in the inventory below only
ever uses four `ui.*` calls: `ui.begin` (panel window), `ui.row`/`ui.column`
(layout grouping, no visuals of their own), `ui.text` (label), and `ui.button`
(panel-tinted clickable). `ui.slider` is never called anywhere in these six
screens or their sub-panels — repo-wide it is used only in `editor.odin` (the
level editor), e.g. `editor.odin:579` `ui.slider("interval", &spawner.interval, 0.1, 10)`.

1. **`draw_splash_ui`** (`hud.odin:232-250`) — no `vendor/ui` involvement at all,
   confirmed by the function's own doc comment (`hud.odin:223-231`). Draws only
   `atlas_textures[.Splash_Background]` via `draw_atlas_tile`, scaled
   cover-style to fill the window. No panel, no text, no button.

2. **`draw_account_progression_ui`** (`hud.odin:260-289`) — one `ui.begin("Account Progression", {panel=true, ...})` panel (line 269) containing:
   - `ui.text("Account Lv. {}", ...)` (270) — plain label
   - `ui.text("XP: {} of {}", ...)` (273) — plain label
   - `ui.text("Unspent: {} XP", ...)` (274) — plain label
   - `ui.column({gap=...})` (276) looping `Account_Stat` and calling `draw_account_stat_row(stat)` (278) for each — see item 8 below
   - `ui.button("Start Game", {panel=true})` (282) — panel button

3. **`draw_run_start_ui`** (`hud.odin:301-328`) — one `ui.begin("Choose a Weapon", {panel=true,...})` panel (310) containing:
   - `ui.row({gap=...})` (311) of, per `Weapon_Family`, a `ui.column({gap=...})` (313) holding `ui.text("{}", weapon_family_display_name[family])` (314, family header) and one `ui.button(weapon_display_name[kind], {panel=true})` (316) per `Weapon_Kind` in that family. Pure nested row/column of text-headers + buttons, nothing else.

4. **`draw_map_selection_ui`** (`hud.odin:334-360`) — one `ui.begin("Select a Map", {panel=true,...})` panel (343) containing a loop over `Map_Name` each producing one `ui.button(chosen.name, {panel=true})` (347). No text, no nested layout — flattest of the six screens.

5. **`draw_run_end_ui`** (`hud.odin:370-396`) — one `ui.begin("Run Ended", {panel=true,...})` panel (379) containing:
   - `ui.column({gap=...})` (380) of four plain `ui.text` stat lines: Kills (381), Survived (382), Gold earned (383), XP earned (384)
   - `ui.button("Continue", {panel=true})` (387)

6. **`draw_shop_ui`** (`hud.odin:418-446`) — one `ui.begin("Shop", {panel=true,...})` panel (427) containing:
   - `ui.text("Gold: {}", ...)` (428) — plain label
   - `ui.row({gap=...})` (430) of two `ui.column({gap=...})`s (431, 434): left calls `draw_shop_weapon_ladder()` (432), right calls `draw_shop_upgrades()` (435) — see items 7/9 below
   - `ui.button("Close", {panel=true})` (439)

7. **`draw_shop_weapon_ladder`** (`hud.odin:453-465`, sub-panel of Shop, left column) —
   `ui.text("Weapon Ladder")` (454) header, `ui.text("{}", weapon_display_name[...])` (455) current weapon, then either `ui.button("Buy {} - {}g", {panel=true})` (459) if a next tier exists, or `ui.text("Fully Upgraded")` (463) if not. The function's own comment (448-452) states explicitly: *"the ui library has no disabled-button state, so a maxed tier renders as plain text with no button at all rather than an unclickable one."* No stack/level indicator widget — "current weapon" is just one text line, not a filled-segment ladder/progress visual.

8. **`draw_account_stat_row`** (`hud.odin:401-409`, called per `Account_Stat` from Account Progression) —
   `ui.text("{} [{}]", preset.display_name, stack)` (405): name plus stack count baked into one text string via `[N]` bracket notation (no dedicated stack/pip/level widget), then always `ui.button("Spend {N} XP", {panel=true})` (406) — never a maxed state, since the comment at 398-400 notes Account_Stat purchases are uncapped.

9. **`draw_shop_upgrades`** (`hud.odin:471-489`, sub-panel of Shop, right column) — pure layout/filtering, no widgets of its own: two `ui.text` section headers ("General" at 474, family name at 482) each followed by a loop calling `draw_shop_upgrade_row(kind)` for upgrades matching `upgrade_available_to_family`.

10. **`draw_shop_upgrade_row`** (`hud.odin:494-510`, called per `Upgrade_Kind` from `draw_shop_upgrades`) —
    `ui.text("{} [{}-{}]", preset.display_name, stack, preset.max_stack)` (500): name plus "current-of-max" stack encoded as bracketed text, same pattern as `draw_account_stat_row` — again no dedicated stack/pip/progress widget, just a text string. Then `if upgrade_maxed(kind) { ui.text("MAXED") } else { ui.button("Buy - {}g", {panel=true}) }` (502-509) — same no-disabled-button tradeoff as `draw_shop_weapon_ladder`, called out explicitly by the comment at 491-493.

### What's beyond plain button/panel/text

Nothing beyond plain text/panel/button/row/column is technically *used* by any
of the six screens — the widget surface is genuinely just those four `ui.*`
calls everywhere. But two things the ticket asked to flag are real gaps against
what a polished hand-rolled UI would want:

- **No stack/level indicator widget.** Both `draw_account_stat_row` (405) and
  `draw_shop_upgrade_row` (500) encode "current [/max]" stack state purely as
  interpolated text (`"{} [{}]"` / `"{} [{}-{}]"`), not as a visual
  pip/segment/progress-bar element. The hand-rolled replacement should decide
  whether to keep this as text or promote it to a real stack/level indicator
  component (the HUD's own `draw_hud_bar`/`draw_hud_label_row`,
  `hud.odin:92-105`, already show the pattern for a bar-based indicator, so
  prior art for this exists in the file — it's just never applied to shop
  rows).
- **No disabled-button state exists in `vendor/ui`.** Confirmed by both
  in-code comments (`hud.odin:448-452` and `491-493`) and by the actual code:
  a maxed weapon tier or upgrade renders as `ui.text("Fully Upgraded"/"MAXED")`
  with the button omitted entirely, not a grayed-out unclickable button. Any
  spec building on this audit should treat a real disabled/"maxed" button
  state as a new capability to design in, not something to port from the
  existing library.
- **`ui.slider` is confirmed unused in all six screens** (and unused anywhere
  outside `editor.odin`). The new component API does not need to support a
  slider for these menu screens.
