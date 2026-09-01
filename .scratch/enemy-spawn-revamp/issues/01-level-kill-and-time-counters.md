Type: grilling
Status: resolved

## Question

Introduce new per-level runtime state — kills this level and elapsed time
this level — distinct from the existing Run-scoped `Player.kills` /
`Player.survival_seconds` (`main.odin:521,525`), which stay as-is for the
Run End screen. This new state resets on map change and is drawn live,
top-right, on screen.

Needs to settle:

- **Where the state lives.** Likely new fields directly on `Game` (e.g.
  `level_kills: int`, `level_elapsed_seconds: f32`) rather than on `Map`
  (per the [Maps map](../../level-maps/map.md), `Map` mixes blueprint and
  runtime fields today only for things that persist to the map file —
  these counters never do). Confirm the exact field names and location.
- **Reset hook.** These must reset whenever `apply_chosen_map` runs
  (`map.odin:96-102`) — on every map switch, not just the first map of a
  Run. Confirm this is the single reset site (vs. also needing a reset in
  `start_new_run`).
- **Increment hooks.** Kills increment alongside the existing
  `game.player.kills[enemy.kind] += 1` in `apply_hit_to_enemy`
  (`bullet.odin:175`). Elapsed time increments alongside the existing
  `game.player.survival_seconds += rl.GetFrameTime()` in
  `update_game_state` (`main.odin:346`), under the same
  shopping/run-ended/debug-panel guard that already wraps it.
- **Draw format and placement.** Top-right corner, in `game.ui_camera`
  space (`PIXEL_WINDOW_HEIGHT :: 180` virtual coordinate system,
  `main.odin:16,773`), mirroring the existing top-left `draw_text("Editing",
  10, 10, ...)` screen-space pattern (`main.odin:796`) but anchored to the
  virtual width (`window_width/zoom`) minus a margin instead of a fixed
  x. Settle the exact text (e.g. "Kills: N   Time: MM:SS"), and remember
  the font atlas has no `/` glyph (`LETTERS_IN_FONT`, `atlas.odin:26`) —
  use `hud.odin`'s existing "X of Y"-style workaround convention if the
  format needs a separator.
- **Visibility during overlays.** Confirm whether the counter stays drawn
  while shopping or on the run-ended overlay, or is hidden then (matching
  whatever the "Editing" text's own visibility rule is, if any).

## Answer

**No new state — this isn't "per-level," it's Run-scoped, and Run-scoped
state already exists.** Domain correction that came out of grilling this:
"Level" is reserved by CONTEXT.md for Account-XP progression (unrelated,
never touched by this map); the thing that resets when the player starts
over is a **Run** (pick a Weapon, pick a Map, play until death — see
CONTEXT.md's `Run` entry). Since a Run today always goes through Map
selection exactly once (`Selecting` → `Playing`, confirmed via
`start_new_run`/`ProgramMode` sequencing in main.odin), "resets on Map
switch" and "resets on Run start" are the same event in practice — and
`Player.kills`/`Player.survival_seconds` (main.odin:521,525) are *already*
that Run-scoped state, reset in `start_new_run` (main.odin:602-624) and
incremented at `bullet.odin:175` / `main.odin:346`. Introducing parallel
`level_kills`/`level_elapsed_seconds` fields would just be a second name
for the same lifetime — rejected.

**Concretely:**
- **State:** none new. Read `total_kills(game.player.kills)`
  (`account_progression.odin:48`) and `game.player.survival_seconds`
  directly at draw time.
- **Reset hook:** none new — already handled by `start_new_run`.
- **Increment hooks:** none new — already happening at the existing call
  sites, already paused under the existing shopping/run-ended/debug-panel
  guard in `update_game_state`.
- **Draw:** replace the no-op `.Playing` case inside the `game.ui_camera`
  block (main.odin:786-790) with a top-right-anchored `draw_text` call —
  anchor x = `window_width/zoom` (virtual width) minus a margin, y = a
  small fixed margin (mirroring the top-left `"Editing"` text's `10, 10`
  placement, main.odin:791). Text: `"Kills: {}   Time: {}"`, kills from
  `total_kills(...)`, time formatted MM:SS zero-padded from
  `survival_seconds`. Plain white text, no icon/particle treatment (this
  is a screen-space meta-stat readout, not a world-space Resource
  indicator — see this map's Notes on ADR-0011).
- **Visibility:** stays drawn under both `game.shopping` and
  `game.run_ended` overlays with no hide logic needed — both are centered
  modal panels (`hud.odin:282-306,330-357`), not full-screen fills, so the
  top-right corner is never covered.

**Ripple effect on this map:** the [Spawn Trigger data model](03-spawn-trigger-data-model.md)
ticket's Condition variants (`Time_Elapsed`/`Kills_Reached`) now read
against these existing Run-scoped `Player` fields directly, not a
nonexistent per-level state — updated on that ticket. It no longer needs
to be blocked by this one; unblocked accordingly.
