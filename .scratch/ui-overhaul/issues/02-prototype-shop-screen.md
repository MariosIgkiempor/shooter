Type: prototype
Status: resolved
Blocked by: 01

## Question

What does a hand-rolled (no `vendor/ui`, no generic layout engine) version of the Shop screen actually look like and feel like to use?

Build a rough, concrete Odin/raylib mockup of `draw_shop_ui` (chosen as the most visually complex of the six screens — weapon tier ladder plus general and Class-specific upgrade rows) using ad-hoc hand-rolled drawing, reusing `draw_ui_panel`/`draw_nine_slice` for panel backgrounds. Use [Audit exact per-screen widget & visual needs](01-audit-menu-screen-widgets.md)'s inventory so the mockup covers real rows (weapon tiers, upgrade stacks, maxed states), not placeholders.

Cover:
- How buttons look and give hover/press feedback with plain raylib (`rl.CheckCollisionPointRec` + `rl.IsMouseButtonPressed`/`IsMouseButtonDown`) instead of `vendor/ui`'s node-based hot/active state.
- How panel/section backgrounds and text are positioned without a generic layout engine — fully manual pixel coordinates, or some lightweight running-cursor helper.
- How a disabled/"maxed" row state reads visually.

This raises the fidelity of discussion for [Component API & styling convention](03-component-api-and-styling.md), which decides the actual reusable API from what gets validated here.

## Answer

Validated live, in-game, against real `Player`/`Upgrade_Kind`/weapon-ladder data via an interactive prototype (`shop_ui_prototype.odin`, reachable with `F9` while Playing, `1`/`2`/`3` to switch) covering three structurally different variants — primary source preserved on the throwaway branch `prototype/shop-screen-variants`, not on `main`.

**Winner: Variant C, the tile grid.**

- **Layout**: a grid of fixed-size tiles — the weapon tier's next purchase gets its own tile alongside every Upgrade available to the equipped weapon's family — rather than the two-column card layout (Variant A) or a single flat vertical list (Variant B).
- **Positioning convention**: manual row/col grid math computed from a flat item list (`tx = x0 + col*(tile_w+gap)`, `ty = grid_top + row*(tile_h+gap)`), not a running-cursor helper and not a generic layout engine. This is the answer to the map's "fully manual coordinates vs lightweight running-cursor" open question — manual, confirmed.
- **Stack/max indicator**: a small numeric badge (`"{stack}-{max}"`) in the tile's corner — not the pip row (Variant A) or the inline progress bar (Variant B). Settles the audit's "no stack/level indicator widget" gap in favor of a plain compact badge, not a new visual-fill widget.
- **Disabled/"maxed" state**: a real grayed-out, unclickable button (not a bare text label like today's `vendor/ui`-based screen) — validated across all three variants via the shared `proto_button` primitive, so this part of the answer isn't Variant-C-specific, it's locked regardless of which layout won. Settles the audit's "no disabled-button state" gap: the new UI layer should have one.
- **Button feedback**: the shared `proto_button` helper (hover/press/disabled via `rl.CheckCollisionPointRec` + `IsMouseButtonDown`/`IsMouseButtonReleased`, rendered through `draw_ui_panel` with a per-state tint) read well in all three variants and is validated as the shared primitive — every variant's *layout* differed, but they all composed on top of this one button primitive without it constraining their structure.

This is a **visual/interaction answer, not code to fold in** — the map's destination is a spec, not implementation (see map.md's Notes). [Component API & styling convention](03-component-api-and-styling.md) should take Variant C's grid/badge/disabled-button/`proto_button` approach as its validated starting point when it designs the actual reusable function signatures.
