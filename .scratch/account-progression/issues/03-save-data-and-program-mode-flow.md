Type: grilling
Status: resolved

## Question

Two related structural decisions:

- **Save-data reset vs. migration**: `data/game_save.json` currently persists `Player.class` and `Player.class_chosen` ([main.odin:481-488](../../main.odin)), which this rework retires outright. Given this is unshipped, solo-dev software with no external save files to preserve, is a clean reset (delete the file, or drop the fields with no back-compat guard) acceptable — or is there a reason to write a migration path (e.g. `load_game`'s existing back-compat guards at [main.odin:142-147](../../main.odin) for a worked precedent)? This also settles what happens to the *existing* modified `data/game_save.json` currently sitting uncommitted in the working tree.
- **`ProgramMode` flow**: today's sequence is `Choosing_Class` (once ever) → `Selecting` (map pick, every launch) → `Playing`/`Editing`, and `restart_game` ([main.odin:554-571](../../main.odin)) resets Run state but does *not* return to map selection or reposition the player. What replaces `Choosing_Class`? Does the new starter-weapon picker ([Run-start and run-end screens](01-run-start-and-run-end-screens.md)) run once per Run (i.e. every death routes back through it, before or after map re-selection), and should Restart's behavior change to also return to it — given a Run no longer has a fixed weapon to simply recreate, unlike today's `class_weapon_kinds[class][0]` recreation?

Not blocked.

## Answer

Locked via grilling (this also resolved two standing map-level fog items — whether **Class** survives as a term, and how family-specific Upgrade slots get re-gated — both settled as direct consequences below):

**Class retires as a domain term, replaced by Weapon family.** "Class" implied a permanent, once-ever player choice, which is no longer true. `Weapon_Family` (renamed from `Class`) is purely descriptive of whichever weapon is currently equipped — nothing on `Player` stores it persistently anymore. `Upgrade_Preset.class: Maybe(Class)` becomes `Upgrade_Preset.family: Maybe(Weapon_Family)`, checked against the equipped weapon's family rather than a persistent field — this is the concrete answer to the map's "family-specific Shop Upgrade slot re-gating" fog item. See [ADR-0008](../../../docs/adr/0008-weapon-family-is-run-scoped.md) and CONTEXT.md's rewritten **Weapon family** entry.

**The old Game Over screen is fully retired**, not kept alongside the new Run End screen. `draw_game_over_ui` and its standalone "Restart" button go away entirely; death shows the "Run Ended" summary+spend screen from [Run-start and run-end screens](01-run-start-and-run-end-screens.md) directly, whose Continue button leads into the next Run.

**`ProgramMode` sequence**: `Choosing_Class` is replaced by `Run_Start` — deliberately not `Choosing_Weapon`, since this screen may end up doing more than just weapon selection over time. `Run_Start` is entered uniformly at the very first app launch *and* after every death (via the Run End screen's Continue), removing today's asymmetry where Class was gated once-ever but the Map picker (`Selecting`) already re-ran every launch. Full loop: `Run_Start` (weapon pick) → `Selecting` (map pick) → `Playing` → (death) → Run End screen → back to `Run_Start`. "Restart" retires as a named action/button — a Run now always ends by choosing the next Run's weapon, not by clicking a dedicated Restart control.

**Save-data reset**: a clean reset, no migration path. `Player.class`/`Player.class_chosen` drop from the struct entirely, `load_game` gets no back-compat guard for them, and the current uncommitted `data/game_save.json` in the working tree is discarded rather than hand-migrated — this is unshipped, solo-dev software with no external saves to protect. (Discarding the actual working-tree file is left to the implementation session, consistent with this map's Destination being a design spec, not code.)

This was the last open ticket — the map's route is clear. [ADR-0008](../../../docs/adr/0008-weapon-family-is-run-scoped.md) (supersedes ADR-0002) and [ADR-0009](../../../docs/adr/0009-xp-is-a-run-end-grant.md) (amends ADR-0006) are written, and CONTEXT.md's Class/Gold/Shop/Weapon tier ladder/Upgrade/Run/Account progression entries are updated to match.
