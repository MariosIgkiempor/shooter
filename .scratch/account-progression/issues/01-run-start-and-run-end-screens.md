Type: prototype
Status: resolved

## Question

Mock the two new UI surfaces this rework introduces, replacing the two screens it retires:

- **Run-start starter-weapon picker**, replacing `draw_class_selection_ui` ([hud.odin:260-282](../../hud.odin)) and the `Choosing_Class` program mode. The player picks any of the 8 weapons (grouped by family — Ranged/Melee/Magic — per [D2](../map.md)) as that Run's starter, instead of picking a permanent Class. What does this screen show per weapon (name, family, base stats, an icon/preview)? Does grouping by family read as three columns, three tabs, or something else? Does confirming a pick immediately start the Run (mirroring today's Class-select → weapon-create → `Selecting` flow), or does it feed into the existing map-selection step first?
- **End-of-Run summary + `Account_Stat`-spend screen**, replacing the mid-run "Level Up → Continue" stub ([hud.odin:228-250](../../hud.odin)) entirely (per [D6](../map.md)). Shown once, at death, before returning to the starter-weapon picker for the next Run. What does it show (kills this Run, survival time, Gold earned, the resulting XP total, current Account XP/Level)? How does the player spend earned XP on the four `Account_Stat`s (Vigor/Might/Swiftness/Fortune) — a shop-style buy-per-stat list similar to `draw_shop_upgrades` ([hud.odin:397-413](../../hud.odin)), or something else? Can XP be banked unspent, or must it be spent before continuing?

Resolve via a throwaway HTML prototype (linked as an asset in `prototypes/`), same pattern as [`.scratch/shop-and-upgrades/prototypes/03-shop-panel.html`](../../shop-and-upgrades/prototypes/03-shop-panel.html).

Not blocked.

## Answer

Validated via two interactive prototypes, each covering three structurally different layouts — [prototypes/01-run-start-weapon-picker.html](../prototypes/01-run-start-weapon-picker.html) and [prototypes/01-run-end-summary-and-spend.html](../prototypes/01-run-end-summary-and-spend.html).

**Layout: Variant A on both screens.**

- **Run-start weapon picker**: three columns, one per family (Ranged / Melee / Magic), each column showing that family's weapons as vertical cards. Family grouping stays visually prominent in the UI even though the account-level lock is gone — reads as "pick a build for this Run," not a flat catalog.
- **Run-end summary + spend**: two-column — left column shows the Run summary tiles (Kills, Survived, Gold earned, XP earned) plus the Account Level/XP bar; right column is the `Account_Stat` spend list (Vigor/Might/Swiftness/Fortune, buy-per-stack rows mirroring the Shop's Upgrade rows).

**Screen 1 → flow**: confirming a weapon does **not** start the Run directly. It proceeds to the existing map-selection screen (today's `Selecting` `ProgramMode`), same as the current Class-select → map-select order — just re-entered every Run instead of once ever. [Save-data and program-mode flow](03-save-data-and-program-mode-flow.md) should build its new `ProgramMode` sequence on: weapon-pick → map-select → Playing, repeating from weapon-pick on every death.

**Screen 2 → banking**: spending is optional. "Continue" is never blocked on unspent XP — a player can carry XP forward unspent across as many Run-ends as they like, exactly as prototyped (the always-enabled Continue button, no forced-spend gate).
