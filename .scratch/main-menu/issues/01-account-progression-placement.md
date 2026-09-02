Type: grilling
Status: resolved

## Question

The existing `Account_Progression` screen (`draw_account_progression_ui` in `hud.odin`, shows progression/upgrade info and today's "Start Game" button) currently only ever appears once per save — on a player's very first-ever run (`main.odin:25-35`/`:323-329` route every subsequent launch straight past it to `.Selecting`).

This map's destination puts a new Main Menu screen at the front of every launch instead, feeding into weapon-select → map-select every time. Where does `Account_Progression` fit into that now? Options to weigh, and any others that surface during grilling:

- Shown every launch, between the new Main Menu and weapon-select (so the full chain becomes Main Menu → Account Progression → Run Start → Selecting → Playing).
- Reachable via a separate button from the Main Menu (e.g. "Progression"), off the main Start Game path — so Start Game skips straight to weapon-select.
- Folded into the new Main Menu screen itself, rather than remaining a separate screen.
- Dropped from the automatic flow entirely and shown only under some other condition (e.g. first-ever launch only, same as today, just now downstream of the new Main Menu rather than upstream of it).

Read `CONTEXT.md` and any relevant ADRs first if they cover account progression's purpose, so the decision fits the wider account/save model rather than just this flow.

## Answer

Folded directly into the Main Menu screen itself — no separate `Account_Progression` screen. The Main Menu shows title, the XP/Level readout and all four Account_Stat spend rows (Vigor/Might/Swiftness/Fortune), and a single "Start Game" button leading to weapon-select (`Run_Start`). The spend section renders unconditionally, even when `unspent_xp == 0` — a stable, predictable layout beat the marginal benefit of hiding an empty section. Rejected: mandatory separate screen every launch (extra tap for nothing), off-path "Progression" button (players might never notice unspent XP), and conditional display (unstable layout).

Recorded as [ADR-0012](../../../docs/adr/0012-account-progression-folds-into-main-menu.md). Consequences: `ProgramMode.Account_Progression` retires in favor of a new `Main_Menu` case; `draw_account_progression_ui` is absorbed into a new `draw_main_menu_ui`; the Run End screen's "Continue" button will route to `.Main_Menu` instead of `.Account_Progression` once implemented. No `CONTEXT.md` changes needed — the existing "Account progression" glossary entry already describes the persisted *state* (XP/Level/Account_Stat), not a screen, and menu screens aren't separately glossaried in this repo (same as Splash/Run_Start/Selecting today).

Interacts with, but does not decide, [Save and Continue semantics](02-save-and-continue-semantics.md): whether the Main Menu (now carrying Account Progression's content) truly shows on *every* launch depends on that ticket's resolution of the current mid-Run relaunch skip.
