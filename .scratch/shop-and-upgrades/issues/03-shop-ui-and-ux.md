Type: prototype
Status: resolved

## Question

What does the Shop panel actually look like and how is it driven? Raise the fidelity with a rough, concrete UI prototype (reusing the `ui` library idiom from `draw_level_up_ui`/`draw_game_over_ui`/`draw_class_selection_ui` in `hud.odin`) covering:

- Layout: a Weapon tier ladder section (buy-next-tier, "Fully Upgraded" at max per the old weapon-types map's ticket 07) alongside an Upgrades section, split into general and Class-specific rows, each showing current stack/cap and next-purchase price, disabled or "Maxed" at cap.
- Open/close trigger: which key or button opens the Shop (the old weapon-types map punted this as build-session polish — mirroring `F1` for `ProgramMode.Editing` is the obvious default, but confirm), and how it's dismissed.
- The redesigned level-up popup: Continue-only per this map's decisions — confirm it still shows XP/Level context (progress toward next level?) or is genuinely just an acknowledgement with nothing to look at.
- Use [01-upgrade-catalog-contents](01-upgrade-catalog-contents.md)'s item list to mock up real rows, not placeholders — seeing actual Upgrade names/categories in the layout is the point of prototyping this now rather than later.

## Answer

Validated via an interactive prototype covering three structurally different layouts — [prototypes/03-shop-panel.html](../prototypes/03-shop-panel.html):

**Layout: B, two-column.** The Weapon tier ladder card sits in a left column, Upgrades (General section above, Class-specific section below) in a right column — both visible at once, no tab-switching needed to compare a weapon-tier purchase against an Upgrade purchase.

**Open/close trigger: a dedicated key**, mirroring `F1` for `ProgramMode.Editing`. Exact key (not `F1` itself, which is taken) is a build-session pick, same as the old weapon-types map left it — not a design fork worth blocking on.

**Level-up popup: Level number + XP bar + Continue.** Keeps the popup visually meaningful (progress toward next Level is still real, account-progression-relevant information) even though it grants nothing purchasable anymore.

**Fully Upgraded / Maxed states**: confirmed via the prototype's toggle — a maxed weapon tier shows a disabled "Fully Upgraded" button in place of the buy button; a capped Upgrade shows a disabled "MAXED" button, stack dots fully filled.
