# Account Progression folds into the Main Menu, not a separate screen

Status: accepted

The [Main menu flow](../../.scratch/main-menu/map.md) map's [Account Progression placement](../../.scratch/main-menu/issues/01-account-progression-placement.md) ticket decided where the existing `Account_Progression` screen (XP/Level readout, Account_Stat spend rows) sits now that a new Main Menu screen shows on every launch, feeding into weapon-select every time (not just first-ever/post-death). Rather than keep `Account_Progression` as its own mandatory screen ahead of the Main Menu, gate it conditionally on unspent XP, or move it behind a separate off-path button, its content is folded directly into the Main Menu screen itself: the XP/Level readout and Account_Stat spend rows render on the same screen as the title and "Start Game" button, unconditionally (not hidden when `unspent_xp == 0`), with a single "Start Game" button leading into weapon-select (`Run_Start`).

Considered and rejected:
- Mandatory separate screen every launch (Main Menu → Account Progression → Run Start) — an extra tap every launch even with nothing to spend.
- Off the main path, via a separate "Progression" button — risks players never noticing they have unspent XP to allocate.
- Conditional display, only shown when `unspent_xp > 0` — a less stable, launch-to-launch-varying layout for marginal benefit.

Consequences: `ProgramMode.Account_Progression` (`main.odin`) retires in favor of a new `Main_Menu` case; `draw_account_progression_ui` (`hud.odin`) is absorbed into a new `draw_main_menu_ui` rather than kept as a separate proc. The Run End screen's "Continue" button (`hud.odin:299-303`), which today routes to `.Account_Progression` after death, routes to `.Main_Menu` instead once implemented. This is a decision record only — the actual `ProgramMode`/`hud.odin` wiring happens after the [Main menu flow](../../.scratch/main-menu/map.md) map resolves, not as part of this ticket.
