Type: prototype
Status: resolved

## Question

What does a flat rectangle panel/button look like without nine-slice art — fill color, border, corner treatment, drop shadow (if any), and normal/hover/press/disabled states for buttons — and how does the Reveal/Dismiss fade actually look and feel (easing curve, duration)?

Build a cheap, rough, concrete throwaway demo (Odin/raylib) to react to live, on its own branch — not folded into `main`, per this map's Notes on how prototypes are handled. Reuse `exp_approach` ([editor.odin:155](../../../editor.odin)) or `ease_out_cubic` ([main.odin:717](../../../main.odin)) as a starting easing primitive if either fits the feel; propose a new curve if not.

Cover at minimum:
- A flat-rect panel background.
- A button in each of its normal/hover/press/disabled states (disabled = the "MAXED" case from [ui-overhaul](../../ui-overhaul/map.md)'s inherited widget needs).
- A visible Reveal-in and Dismiss-out sequence for a small group of elements, staggered rather than simultaneous, to validate Main Menu's cascading-reveal worked example (see this map's Out of scope: only Main Menu gets an explicit stagger example, so the demo should cover that case directly).
- Splash's background image ([hud.odin:145](../../../hud.odin)) fading in/out alongside foreground elements, since it's in scope for Reveal/Dismiss.

This raises the fidelity of discussion for [Component API & Reveal/Dismiss state model](02-component-api-and-state-model.md), which locks the actual reusable API and theme values from whatever's validated here.

## Answer

**Variant C wins: accent border, scale-in.** A dark flat fill (`{40, 44, 52, 255}`), a 2px accent border (`{130, 170, 230, 255}`) instead of a drop shadow, and a Reveal/Dismiss driven by the existing `ease_out_cubic` (main.odin:717) over 0.20s with a scale animation from 0.9 → 1.0 — no shadow, no slide. Validated live via `menu_ui_polish_prototype.odin` (F9 to open, `[1]`/`[2]`/`[3]` to switch variant, `[F10]` to toggle the Main-Menu-style mockup vs. the Splash-background preview) — primary source moves to the throwaway branch `prototype/menu-ui-polish`, not `main`.

Structural pieces validated regardless of which variant won (all three shared them):
- A real disabled/grayed, unclickable button state (not a text label) — confirms `ui-overhaul`'s inherited "MAXED" requirement reads correctly once flattened.
- Panel-first, buttons-cascade-after reveal ordering; buttons-cascade-first, panel-last dismiss ordering (reverse of reveal) — this is the mechanism behind the map's Main Menu cascading-reveal worked example.
- Splash's background image fades via the exact same mechanism as any other Menu element, unstaggered (a single element), keeping its current raster art.

This is a **visual/motion answer, not code to fold in** — the map's destination is a spec, not implementation (see map.md's Notes). [Component API & Reveal/Dismiss state model](02-component-api-and-state-model.md) should take Variant C's border/scale-in/`ease_out_cubic` approach, its validated hover/press/disabled palette, and the panel-first/buttons-cascade stagger ordering as its starting point.
