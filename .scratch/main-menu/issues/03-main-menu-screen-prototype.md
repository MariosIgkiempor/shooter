Type: prototype
Status: resolved
Blocked by: 01, 02

## Question

What does the new Main Menu screen actually look like, built with the existing `ui` library conventions used in `hud.odin` (`ui.begin_frame`/`row`/`begin(panel)`/`button`, `HUD_THEME`, `MENU_PANEL_SCALE`/`MENU_PANEL_MARGIN`)?

Settled content it must fit, per [Account Progression placement](01-account-progression-placement.md) and [Save and Continue semantics](02-save-and-continue-semantics.md):
- Title/branding.
- The XP/Level readout and all four Account_Stat spend rows (Vigor/Might/Swiftness/Fortune), always rendered even at 0 unspent XP.
- A "Continue" button, shown only when a Run is in progress (`Player.run_started == true`).
- An always-present "Start New Run" button — the one that leads to weapon-select (`Run_Start`). If a Run is in progress, pressing it needs a confirmation step (modal? inline "are you sure" swap? something else) before discarding that Run's Gold/weapon-tier/Upgrade-stacks.

That's a denser, more stateful screen than the map's original "simple main menu" framing anticipated (its layout differs depending on whether a Run is in progress, and it needs a confirmation flow, not just static buttons). Build a rough, concrete mock of both states (no Run in progress vs. Run in progress) to react to, per the `prototype` skill.

## Prototype (awaiting reaction)

Real, clickable Odin code on throwaway branch `prototype/main-menu` (commit `014633f`, worktree at `.claude/worktrees/prototype-main-menu/`) — not merged to main. Three structurally different layouts, live-switchable, each with a different confirm-step treatment for discarding a Run in progress:

- **A — Single stacked panel**: direct extension of today's `draw_account_progression_ui` — one panel, title/XP/stats stacked, actions at the bottom. Confirm step swaps the button row in place.
- **B — Two-column split**: left column = title + big primary actions (Continue/Start New Run); right column = smaller "Progression" side panel (XP/stats). Confirm step renders as a separate panel below.
- **C — Top strip + hero buttons**: title/XP/all four stats condense into one horizontal strip; a second panel below holds large centered action buttons. Confirm step swaps the button row in place (same treatment as A).

To try it: `cd .claude/worktrees/prototype-main-menu && odin run . -out:build/shooter.bin`, then press **F9** to jump to the Main Menu, **Left/Right** to cycle the three variants, **R** to toggle a simulated "Run in progress" state (shows/hides Continue and lets you try discarding via Start New Run). Clicking through actually navigates to the real weapon-select/map-select screens. No save file exists in the worktree yet, so Account level/XP will show as fresh (Lv. 1, 0 XP) unless you copy your own `data/game_save.json` in.

Awaiting the user's reaction before this ticket resolves — HITL.

## Answer

**Variant B (two-column split), flipped**: Progression panel (title-less — "Progression": Account Lv./XP/Unspent XP/four Account_Stat spend rows) on the **left**; the "Shooter" actions panel (Continue when a Run is in progress, always-present Start New Run) on the **right**. The confirm step (discarding a Run in progress) renders as a separate "Discard current Run?" panel below both columns, unchanged from the original Variant B draft — only the left/right orientation of the two main columns changed.

Winning tweak from reacting to the three built variants (A single stacked panel, B two-column, C top strip + hero buttons) — captured on throwaway branch `prototype/main-menu` (commit `25491c2`, worktree `.claude/worktrees/prototype-main-menu/`), which now holds only this flipped Variant B as the validated design (A and C remain in the branch's history for reference but aren't the answer).

This was the last open ticket on the [Main menu flow](../map.md) map — the way is now clear. Real implementation (wiring `ProgramMode`, retiring `Account_Progression` per ADR-0012, the Continue/Start New Run split per ADR-0013, all built against this validated layout) is a follow-up build, not part of this map — see the map's Notes.

Build a rough, concrete mock to react to (call the Skill tool with "prototype") rather than deciding the layout in the abstract. Capture it on a throwaway branch and link it as an asset from this ticket's answer, per the map's Notes.
