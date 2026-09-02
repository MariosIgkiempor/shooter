# Main menu flow

Label: wayfinder:map

## Destination

Every game launch shows a new, dedicated Main Menu screen — replacing today's behaviour where a returning save (`player.run_started == true`) skips straight from Splash to map-select. From the Main Menu: Start Game → select starting weapon → select map → run starts, every launch, regardless of save state. `Account_Progression`'s role in this flow is still open (see [Account Progression placement](issues/01-account-progression-placement.md)).

## Notes

- Odin + raylib game. The state machine lives in `main.odin` (`ProgramMode` enum: `Splash, Account_Progression, Run_Start, Selecting, Playing, Editing`; driven by `update_game`/`draw_game`). Today, `.Splash` transitions to `.Selecting` directly if `player.run_started`, else to `.Account_Progression` (`main.odin:25-35`, `:323-329`).
- Screen UI is built with the vendored immediate-mode `ui` library (`vendor/ui/ui/ui.odin`), following the pattern already used in `hud.odin`'s `draw_account_progression_ui` / `draw_run_start_ui` / `draw_map_selection_ui` (same `ui.begin_frame`/`row`/`begin(panel)`/`button` calls, `HUD_THEME`, `MENU_PANEL_SCALE`/`MENU_PANEL_MARGIN`).
- Text rendering is glyph-atlas based (`data/font.ttf` baked via `vendor/atlas-builder`; limited character set — no `/`, see the "Account Lv." workaround at `hud.odin:183-185`).
- This map is planning-only: tickets decide, they don't implement. Default wayfinder behavior applies, not overridden. Wiring the final `ProgramMode`/state-transition changes in `main.odin` happens after the map resolves.
- Prototype tickets call the Skill tool for "prototype" (HITL); grilling tickets call it twice for "grilling" and "domain-modeling", per the default.

## Decisions so far

- [Account Progression placement](issues/01-account-progression-placement.md): folded directly into the Main Menu screen (no separate `Account_Progression` screen) — title, XP/Level readout, all four Account_Stat spend rows, and a single "Start Game" button, always rendered even with 0 unspent XP. Recorded as [ADR-0012](../../docs/adr/0012-account-progression-folds-into-main-menu.md).
- [Save and Continue semantics](issues/02-save-and-continue-semantics.md): Main Menu shows "Continue" (only when a Run is in progress, preserves Gold/weapon/Upgrades, targets map-select) alongside an always-present "Start New Run" (fresh weapon-select; confirmation required + no XP if it discards a Run in progress). Replaces today's silent `run_started`-gated Splash skip with an explicit choice. Recorded as [ADR-0013](../../docs/adr/0013-main-menu-continue-vs-start-new-run.md).
- [Main Menu screen prototype](issues/03-main-menu-screen-prototype.md): two-column split, flipped — Progression (XP/Account_Stat rows) on the left, Start New Run/Continue actions on the right; confirm step for discarding a Run renders as a separate panel below. Captured on throwaway branch `prototype/main-menu`.

## Not yet specified

- Whether the Main Menu needs Settings/Quit buttons (or stubs for them) — depends on [Main Menu screen prototype](issues/03-main-menu-screen-prototype.md).
- Any menu backdrop/art, music/audio on the menu screen — not asked for yet, may surface once the prototype ticket is resolved.
- Exact mechanical wiring of the new `ProgramMode` case(s) and the Splash-mode transition logic in `main.odin` — this is implementation, not a decision, and happens after the map is resolved.

## Out of scope

- Full mid-dungeon Run resume — "Continue" targets map-select (`ProgramMode.Selecting`), same as today's behavior; it does not resume a player back into `Playing` at their exact prior position/enemies/state. That would be a materially larger save-system feature, not asked for here. See [Save and Continue semantics](issues/02-save-and-continue-semantics.md)'s Answer.
