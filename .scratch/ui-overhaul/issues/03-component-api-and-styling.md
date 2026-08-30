Type: grilling
Blocked by: 02

## Question

Given the validated feel from [Prototype a hand-rolled Shop screen](02-prototype-shop-screen.md), what's the actual minimal, reusable component API and styling convention for the new UI layer, precise enough to implement all six screens?

Decide:
- The small helper-function set (e.g. a `button`, a panel-background helper, a text-drawing helper) and their exact Odin signatures/param structs — matching this codebase's existing naming conventions (`draw_*` prefix, `Options`-struct style used elsewhere).
- Whether any lightweight positioning convention is shared across screens (a running vertical-cursor helper) or each screen just hardcodes its own coordinates, per the "minimal, hand-rolled" decision already locked on the map.
- The theming/color/padding convention: a single shared constant table (mirroring `HUD_THEME`'s role today) vs per-screen constants, and how it interacts with `draw_ui_panel`'s existing nine-slice styling.
- Hover/press/click state handling with plain raylib input, confirmed against what the prototype validated.

## Answer
