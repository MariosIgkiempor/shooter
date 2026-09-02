# Flat-Rect Menu UI: Transitions & Animation

Label: wayfinder:map

## Destination

An implementation-ready spec for replacing `vendor/ui` and nine-slice panel/button art across all six existing menu Screens (Splash, Main Menu, Run Start, Map Selection, Run End, Shop — all in [hud.odin](../../hud.odin)) with a flat-rectangle, first-party component set, plus a single per-element animation mechanism: every Menu element (a panel, a button, or the Splash background image) has a Reveal (fade-in) and Dismiss (fade-out) phase, each carrying its own Reveal delay (start offset) — `delay = 0` for every element on a Screen gives a synchronized whole-Screen transition on a Screen change (`ProgramMode` switch); staggered delays give a cascading within-Screen reveal (e.g. Main Menu's buttons popping in one after another). One mechanism handles both cases — not a separate full-screen overlay effect, chosen specifically because it composes with future staggered/sequenced reveals and an overlay wouldn't. Splash's background image keeps its current raster art (not converted to shapes) but participates in Reveal/Dismiss like any other Menu element.

Supersedes [ADR-0010](../../docs/adr/0010-hand-rolled-menu-ui-no-layout-engine.md) in full: its "no generic layout engine, hand-rolled component set" decision carries forward unchanged; its "reuse `draw_nine_slice`" line is overturned. Inherits [ui-overhaul](../ui-overhaul/map.md)'s already-settled per-screen widget/content needs unchanged (button/panel/text widget types only, disabled "MAXED" button state, numeric stack-max badges) — not re-litigated here.

This map is a **spec to hand off**, not execution — tickets decide, they don't implement. Default wayfinder behavior applies, not overridden.

## Notes

- Odin + raylib. Domain terms — **Screen**, **Menu element**, **Reveal** / **Dismiss**, **Reveal delay**, **Screen change** — are now formally defined in [CONTEXT.md](../../CONTEXT.md)'s `## Language` section, added while charting this map.
- Supersession bookkeeping: whichever ticket locks the new component API must also record a new ADR marking [ADR-0010](../../docs/adr/0010-hand-rolled-menu-ui-no-layout-engine.md) as superseded (its layout-engine decision stands; its nine-slice-reuse line doesn't) and append an amendment pointer into [ui-overhaul](../ui-overhaul/map.md)'s Decisions-so-far — per domain-modeling's flag-conflicts rule, not a silent override.
- Reuse pointers: `draw_nine_slice` ([renderer.odin:156](../../renderer.odin)) is what's being replaced. `exp_approach` ([editor.odin:155](../../editor.odin)) and `ease_out_cubic` ([main.odin:717](../../main.odin)) are the only existing hand-rolled easing primitives in the codebase (no generic tween/animation-sequencing system exists) — the closest prior art for a Reveal/Dismiss curve. `HUD_THEME` ([hud.odin](../../hud.odin)), currently typed against `vendor/ui`'s `ui.Theme`, is due for replacement alongside `Menu_Theme` (see ADR-0010).
- Splash's background image (`data/textures/splash_background.png`, added in commit `f15a7c7`, drawn full-window in `draw_splash_ui` at [hud.odin:145](../../hud.odin)) is the one non-nine-slice texture among the six screens — in scope for Reveal/Dismiss, not for shape conversion.
- `debug.odin`/`editor.odin`'s own `vendor/ui` usage stays exactly as-is — not touched by this map, same as `ui-overhaul` left it.
- Grilling tickets: call the Skill tool twice, for "grilling" and "domain-modeling". The prototype ticket: call the Skill tool for "prototype".

## Decisions so far

- [Naming the destination + mapping the frontier](map.md): scope is the six existing menu Screens, superseding ADR-0010 in full (drops `vendor/ui` entirely, not just the nine-slice art). One per-element Reveal/Dismiss mechanism handles both within-Screen element appearance and whole-Screen transitions — a Screen change is just every element's Reveal/Dismiss triggered together (`delay = 0`), not a separate overlay effect, chosen because it composes with future staggered/cascading reveals and an overlay wouldn't. Splash's background image is in scope for Reveal/Dismiss but not for shape conversion. Pause menu, the gameplay HUD, and dev tooling stay out of scope. The remaining work sorts into two tickets: a Prototype (visual style + motion feel) feeding a Grilling ticket (component API + state model), with the spec committing to one worked stagger example (Main Menu) rather than choreographing all six screens individually. This map is a spec to hand off, matching `ui-overhaul`/`art-revamp`'s convention.
- [Prototype flat-rect visual style + Reveal/Dismiss motion feel](issues/01-prototype-flat-rect-visual-and-motion.md): Variant C wins — dark flat fill, a 2px accent border (no drop shadow), Reveal/Dismiss via the existing `ease_out_cubic` over 0.20s with a scale animation from 0.9 → 1.0 (no slide). Validated live via `menu_ui_polish_prototype.odin`, primary source on throwaway branch `prototype/menu-ui-polish`. Also locks, regardless of variant: a real disabled/grayed button state, panel-first/buttons-cascade reveal ordering with the reverse on dismiss, and Splash's background fading via the same unstaggered mechanism as any other Menu element.
- [Component API & Reveal/Dismiss state model](issues/02-component-api-and-state-model.md): recorded as [ADR-0014](../../docs/adr/0014-menu-ui-flat-rect-and-reveal-dismiss-animation.md), superseding [ADR-0010](../../docs/adr/0010-hand-rolled-menu-ui-no-layout-engine.md) in full. A `Screen_Kind` enum unifies `program_mode`/`run_ended`/`shopping` (scoped only to menu-drawing code). No per-element state — one shared `Menu_Transition` record (current Screen, when its Reveal began, and an in-flight Dismiss's start/target) drives every element's alpha/scale as a pure function of elapsed time + rank. A `request_screen_change` chokepoint replaces every direct `program_mode`/`run_ended`/`shopping` assignment, deferring the actual write until the outgoing Screen's Dismiss finishes — required for Dismiss to be able to play at all. `draw_menu_panel`/`draw_menu_button` take the computed `Menu_Element_Anim` explicitly rather than computing it themselves. `Menu_Theme`/`MENU_THEME` replaces `HUD_THEME`, carrying Variant C's validated values. This is the map's last ticket — the route to the destination is clear.

## Not yet specified

Empty — every branch the frontier surfaced sorted into a ticket or a scope boundary below; nothing is left unspecified.

## Out of scope

- A pause menu — doesn't exist today; excluded per the initial charting decision above.
- [resource_indicator.odin](../../resource_indicator.odin)'s persistent world-space gameplay HUD — continuous display, not an appearing/disappearing Screen.
- `debug.odin` / `editor.odin` — stay on `vendor/ui`, unchanged.
- Converting Splash's background image to shape-based art — it keeps its current raster art; only Reveal/Dismiss applies to it.
- Per-Screen Reveal-delay choreography beyond Main Menu's worked example — the other five Screens are single/few-element enough that pre-authoring a stagger pattern for each wouldn't be a real design decision; left to implementation-time judgment using the mechanism as specified.
- Actual implementation of the six Screens' Odin code — this map's destination is the spec, not the code; a separate effort executes it.
