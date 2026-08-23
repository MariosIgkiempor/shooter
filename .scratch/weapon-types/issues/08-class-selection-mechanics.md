Type: grilling
Blocked by: 02
Status: resolved

## Question

How does Class selection work end-to-end: when it happens, whether it can ever change, how it gates the start of gameplay given the codebase has no title/menu screen or run concept today, and which Classes are offered given Magic currently has no implemented spell effects (ticket 04).

## Answer

Locked via grilling (2026-08-23), as part of the same session that redrew the map's destination (see [ADR-0002](../../../docs/adr/0002-class-locked-weapon-acquisition.md)):

**Picked once ever, no run-reset.** `main.odin` has no title screen and no "run" concept — death/`Restart` (`hud.odin`'s `draw_game_over_ui`) only heals the player and clears transient entities (enemies/bullets/pickups); it already leaves weapon/XP/level untouched. Class selection follows that same once-ever persistence model: chosen on a player's very first boot, never re-prompted, `Restart` stays exactly as it is today. A full roguelite run-reset (re-prompting Class, resetting Gold/weapon/XP on death) was explicitly considered and rejected as out of scope for this pivot — the existing codebase gives no signal that was wanted, and bundling it in would have redesigned the death/restart flow on top of an already-large pivot.

**New `ProgramMode.Class_Select`, not a boolean modal.** `main.odin`'s `ProgramMode :: enum { Playing, Editing }` gains a third case, `Class_Select`, dispatched from the existing `switch game.program_mode` in `update_game`/`draw_game` alongside `.Playing`/`.Editing` — not a boolean gate layered inside `.Playing` (the pattern `leveling_up`/`game_over` use). This was chosen over the boolean-gate pattern specifically because `initialize_default_game_state` today eagerly calls `weapon_create(.SMG)` before any modal could show; a bool gate would leave a temporary placeholder weapon on `game.player` while Class_Select is up, needing a second `weapon_create` call once confirmed. A real `ProgramMode` avoids that: `game.player` (and its `Weapon`) simply isn't constructed until Class_Select hands off to `.Playing`, at which point `weapon_create` is called exactly once, with the tier-1 `Weapon_Kind` for the chosen Class (per [10-weapon-shop-and-tier-ladder](10-weapon-shop-and-tier-ladder.md)).

Save/load implication (not fully speced here, flagged for the build session): a fresh save with no `Class` chosen yet boots into `Class_Select`; a save with a `Class` already recorded boots straight into `.Playing` as today. `Class` itself needs to persist on `Player` the same way `weapon`/`xp`/`level` already do.

**All three Classes offered now, including Magic.** Melee, Magic, and Ranged are all selectable immediately, even though Magic's `try_cast_magic` is currently a no-op with zero named `Weapon_Kind` content (ticket 04). This was a deliberate user call, not the recommended default (the recommendation was to withhold Magic until it has real content) — accepted as a known, explicit spec gap rather than a blocker: picking Magic today leaves a player with a functionally inert weapon until spell effects and at least one placeholder Magic `Weapon_Kind` exist (see the map's Not yet specified).

**UI shape:** reuses the existing `ui` library panel/button idiom exactly as `draw_level_up_ui`/`draw_game_over_ui` do — a `draw_class_select_ui` with one button per Class, no new UI infrastructure.
