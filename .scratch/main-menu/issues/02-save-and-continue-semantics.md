Type: grilling
Status: resolved

## Question

Today, `player.run_started` (persisted in `data/game_save.json`) gates the Splash-mode transition: once true, every subsequent launch skips weapon-select and `Account_Progression`, going straight to `.Selecting` (map pick) — implicitly treating "a run is in progress / has happened before" as "skip straight to picking the next map."

This map's destination makes weapon-select run on every launch, which raises the question this flag was quietly answering: once every launch starts with Main Menu → weapon-select → map-select, does a launch always begin a brand-new run (abandoning whatever run, if any, was in progress), or can a player resume a run already underway?

Decide:

- Does every launch unconditionally discard in-progress run state and start fresh from weapon-select, making `run_started` (or an equivalent flag) purely cosmetic/unused going forward?
- Or does the Main Menu need to branch — e.g. a "Continue" affordance distinct from "Start Game" when a run is in progress — and if so, what state does `game_save.json` need to carry to make that possible (currently chosen weapon, current map, in-run progress)?
- What happens to the existing `player.run_started` field and any other save fields that exist solely to support today's skip-to-`.Selecting` shortcut?

This decides whether the Main Menu (see [Main Menu screen prototype](03-main-menu-screen-prototype.md)) is a single-button screen or needs a second, conditional button.

## Answer

The Main Menu keeps a real "Continue" option, not a full always-discard model. Two buttons:
- **"Continue"** — shown only when a Run is in progress (`Player.run_started == true`); preserves Gold/weapon/Upgrade-stacks and skips straight to map-select, exactly matching today's actual behavior. Hidden entirely otherwise — a disabled button would misleadingly imply there's something to resume.
- **"Start New Run"** — always present; goes through weapon-select fresh (`Run_Start` → `Selecting`). If a Run is currently in progress, choosing this requires a confirmation step first (it discards that Run's Gold/weapon-tier/Upgrade-stacks), and grants no XP for the abandoned Run — XP stays strictly a Run-*end* grant tied to death (ADR-0009), never to a Run being discarded.

`Player.run_started` is **not** retired — it keeps meaning "a Run is in progress" and gains a second consumer (the Main Menu's "show Continue?" check) in place of its old sole consumer, the silent Splash-mode branch (`main.odin:328`), which goes away.

Recorded as [ADR-0013](../../../docs/adr/0013-main-menu-continue-vs-start-new-run.md). `CONTEXT.md`'s **Run** entry updated: a Run can now conclude either at death or by early abandonment (no XP either way for the latter); its `_Avoid_: Restart` note clarified to distinguish "Start New Run" (Main-Menu-only, always starts fresh) from the retired in-Playing Restart button. No change needed to ADR-0009 — this decision reaffirms its "Run-end (death)" framing rather than contradicting it.

Full mid-dungeon Run resume (returning to the exact position/enemies/state inside `Playing` across a relaunch, rather than back at map-select) was raised and explicitly not pursued — "Continue" targets map-select, same as today; see the map's Out of scope.
