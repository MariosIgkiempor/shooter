# Save points

Type: grilling
Status: resolved
Blocked by: 02

## Question

Which game moments are **Save points** — the moments at which the save is written — on both Targets?

Today `save_game` marshals the whole `game` struct to `data/game_save.json` exactly once, at process exit (`main.odin:184`), after `deinitialize_program`. A browser tab never reaches that line, and on desktop a crash loses everything since launch. Charting locked that Save points become explicit and shared by both Targets, with a web-only `visibilitychange` hook as belt-and-braces; this ticket names them.

Candidates, each a question of what state must be durable when:

- **Run end** — ADR-0009 makes XP a run-end grant and ADR-0017 defines the outcome; the moment progression actually changes.
- **Map clear** — ADR-0022 gates rungs by clears; a clear that isn't saved is a rung the player re-earns.
- **Shop purchase** — gold spent (ADR-0016) and upgrades bought (ADR-0007) between runs.
- **Return to main menu / start new run** — ADR-0013's Continue-vs-Start boundary.
- **Mid-run** — Continue (ADR-0013) needs run state; is a periodic or event-driven mid-run save wanted, or is Continue only promised across a *clean* exit? Browser Save store's sync/async answer decides whether the unload hook can carry this on web.

Sub-questions:

- Does `save_game` stay a whole-`game` marshal fired from the new points, or does each point save a narrower slice? (Whole-`game` is the standing shape; a slice would need a load path that tolerates partial files, a concept ADR-0028 explicitly avoids.)
- Does the process-exit save remain on desktop as well, or is it subsumed?
- Is a save allowed to fail silently mid-frame, or does a failed write surface somewhere?

Records **Save point** in `CONTEXT.md`.

## Answer

**A Save point is a Screen change.** `apply_screen_kind` — already the one writer for a Screen change — calls `save_game` after it has applied the change, on both Targets. That is every moment the player commits a choice or the game settles an outcome: Splash→Main Menu, Main Menu→Run Start, weapon pick→Map Selection, Map choice→Playing, Shop open and close, `end_run`→Run End, Run End Continue→Main Menu, Discard confirm→Run Start. Nothing else saves.

Decisions, in the order they were put:

1. **Screen changes only — not purchases, not a timer.** Every Shop/Main Menu purchase is followed by the Screen change that closes the panel, so a purchase is saved with the panel close; a crash before that rolls back the Gold *and* the purchase together, which is consistent. A second rule at the four `try_buy_*` sites protects only against a desktop crash with a panel open, at the cost of a rule every future purchase site has to remember. A periodic mid-Run save is ruled out for the same reason (see 3).
2. **Save on apply, not on request.** Every mutation that matters (`bank_run_gold`, `record_map_cleared`, `run_started = false`, `start_new_run`) already runs *before* `request_screen_change`, so both points see consistent state; `apply_screen_kind` is the documented single writer, so a Screen added later can't forget. The Dismiss window between request and apply is not a loss window worth naming.
3. **Mid-Run Continue is promised across a clean exit only.** It already resumes the player's Run-scoped state on a fresh field (enemies, bullets and Spawn Trigger latches are all `json:"-"`), so a mid-Run save protects nothing a periodic timer would make whole. If crash-safety is ever wanted it is one tunable timer added later, not a decision that has to be made now.
4. **Desktop keeps its process-exit save, reframed** as Desktop's belt-and-braces — the exact twin of Web's `visibilitychange`→`hidden` + `pagehide` hook (Browser save store). Save points are shared and are the source of truth; each Target additionally saves once at its own last-chance moment. This symmetry is what makes "clean exit" true on Desktop.
5. **`run_started` flips in `end_run`, at settle, not on the Run End screen's Continue button.** A Run ends when it is settled (ADR-0017's one exit from Playing); the Continue button becomes a pure receipt-dismiss that mutates nothing. Without this, the save at Playing→Run End persists `run_started = true` with `health <= 0`, and a relaunch offers a Continue-able dead Run — a quit-at-the-wrong-moment fluke today, a persisted state once Run End is a Save point. ADR-0013's "cleared by the Run End screen's Continue" is superseded on this one point; the Discard-confirm path already follows the same principle ("commit the abandonment now, not on the later click").
6. **Whole-`game` marshal, unchanged.** Every Save point writes the same blob `load_game` reads; a slice would need a load path that tolerates partial files, which ADR-0028 rules out, and the Save-store seam stays one `write(key, blob)`.
7. **A failed write: `save_game` returns `bool`.** Desktop stays log-only as today. Web surfaces it, and the *how* is one design question shared with a failed *read* (the natural offer is the same in both directions: export your save) — folded into the fog patch now named "Save failures on web".

Consequences worth knowing before the build session:

- Splash→Main Menu is a Screen change, so a first-ever launch writes a default save on both Targets before the player has done anything. Harmless, but it means "no save yet" on Web is a one-launch state — the failed-read fog must still treat an *empty* store as "no save", not an error (Safari's 7-day wipe recreates that state).
- `end_run` and the Run End Continue button both need the `run_started` change (5); `shop_test.odin:306` and `hud.odin:1131` are the sites.
- **Out of scope, filed separately** as [Continue re-fires every passed Spawn Trigger at once](../../continue-trigger-burst/issues/01-continue-refires-passed-triggers.md): on any mid-Run Continue, `survival_seconds` and `kills` are restored but every trigger's `fired` latch resets, so every `Time_Elapsed`/`Kills_Reached` trigger whose threshold has passed fires in a burst on the first frame. Pre-existing on Desktop; not caused by, and not waiting on, anything this map decides.

Records **Save point** (and **Save store**, pinned by Browser save store but not yet written) in `CONTEXT.md`.
