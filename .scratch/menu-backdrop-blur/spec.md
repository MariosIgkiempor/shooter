# Menu backdrop blur

Status: ready-for-agent

## Problem Statement

When the Shop or Run End screens are open, the game world is still fully visible (and in sharp focus) behind the menu panel — a frozen frame of gameplay sitting right underneath the UI with nothing separating them. The panel has to compete visually with whatever was on screen the instant the wave paused (enemies, bullets, particles), which makes these two Screens feel like text pasted over a paused game rather than a deliberate, distinct menu state — unlike the rest of the game's UI, which just went through a full Reveal/Dismiss animation pass (ADR-0014) specifically to feel considered and polished.

## Solution

Whenever a Screen (ADR-0014's `Screen_Kind`) is showing on top of a populated game world, the world behind it renders blurred and lightly dimmed instead of sharp. The effect is driven off the exact same Reveal/Dismiss alpha the menu panel itself already animates with, so the world blurs in and out in lockstep with the panel fading in and out — no separate timer, no separate tuning pass to keep in sync. Because the trigger is "a Screen is showing over a real world," not a hardcoded list of Screens, this automatically covers Shop and Run_End today (the only two Screens with a populated world behind them) and will automatically cover any future overlay menu (e.g. a pause menu) the moment one exists, with no additional wiring.

## User Stories

1. As a player, when I open the Shop between waves, I want the game world behind the Shop panel to be visibly blurred, so that my attention is drawn to the shop instead of the frozen wave underneath it.
2. As a player, when a Run ends, I want the game world behind the Run End panel to be blurred, so that the results screen feels like a distinct interruption rather than text floating over unrelated background clutter.
3. As a player, I want the blur to fade in smoothly as the Shop/Run End panel reveals, rather than snapping instantly to full strength, so that opening a menu feels consistent with how every other menu element already animates in.
4. As a player, I want the blur to fade back out in sync with the panel's own dismiss animation as I close Shop/Run End, so that returning to gameplay doesn't feel like a jarring cut.
5. As a player, I want a subtle darkening over the blurred world in addition to the blur itself, so that panel text and buttons stay easy to read even over a busy scene.
6. As a player, I want the blur to never appear behind Splash, Main Menu, Run Start, or Map Selection, since there's no game world to show behind them yet, so that I never see a blurred blank screen that reads as a rendering bug.
7. As a player, if I resize the game window while a blurred menu is open, I want the blur to keep covering the full window without stretching, glitching, or leaving unblurred edges, so the effect doesn't break just because I changed my window size.
8. As a game developer, I want the "should blur be showing, and how strong" decision expressed as one pure function driven off existing Screen/Menu_Transition state, so that automated tests can cover the on/off/ramp logic without needing a raylib window or GPU.
9. As a game developer, I want that function to reuse the exact same alpha the panel's own Reveal/Dismiss animation already computes, rather than a separately-tuned blur timer, so blur and panel fade can never visually drift out of sync.
10. As a game developer, I want the blur/dim rendering path to only engage when that function reports non-zero strength, so every other Screen (and ordinary Playing/Editing) keeps rendering straight to the backbuffer with zero added cost, exactly as it does today.
11. As a game developer, I want the new render-texture and shader plumbing added as reusable procs in `renderer.odin` alongside the existing `begin_using_camera`/`begin_drawing` wrappers, so the raw raylib `RenderTexture2D`/shader calls stay wrapped the same way every other rendering primitive already is, instead of being inlined into `draw_game`.
12. As a game developer, I want a future pause menu (explicitly out of scope for this spec) to get this same blurred backdrop automatically the moment it starts using `current_screen()`/a populated `current_map`, so nobody has to remember to wire this feature up again later.
13. As a game developer, I want this feature's vocabulary ("blurred backdrop") and its trigger rule documented in `CONTEXT.md`'s glossary and a new ADR, matching the precedent ADR-0014 set for the rest of the Screen/Menu system, so future work in this area has settled terms to build on.
14. As a game developer, I want the offscreen render texture recreated only when the window's actual pixel size changes (not reallocated every frame), so resizing doesn't leak or thrash GPU resources the way an unconditional per-frame allocation would.

## Implementation Decisions

- New pure proc `blurred_backdrop_strength() -> f32`, living in `hud.odin` next to `menu_element_anim` (which it calls into). Returns `0` whenever `current_screen()` is `nil` (Playing/Editing — no menu at all) **or** `game.current_map.name == ""` (no world has been populated yet — true for Splash/Main_Menu/Run_Start/Map_Selection); otherwise returns `menu_element_anim(0, 0).alpha` — the same rank-0 alpha the panel's own fill/border already animate with. No new timer, no new field on `Menu_Transition`.
- `draw_game`'s world-drawing block (currently the `begin_using_camera(game.camera){...}end_using_camera()` block that draws tilemap/enemies/player/bullets/particles/etc.) branches on `blurred_backdrop_strength()`:
  - `0`: renders straight to the backbuffer exactly as it does today — no behavior change, no added cost, for Playing/Editing and for the four Screens with no world yet.
  - `> 0`: that same block renders into an offscreen `RenderTexture2D` first, which is then composited to the backbuffer through a blur shader pass, followed by a flat semi-transparent dim rectangle over it, before the existing UI-camera/menu-panel drawing continues unchanged after it.
- Both the blur radius (in pixels) and the dim rectangle's alpha scale linearly with `blurred_backdrop_strength()`'s `0..1` value, rather than snapping to a fixed strength once some threshold is crossed — this is what makes the fade continuous through the panel's own Reveal/Dismiss rather than a hard cut partway through it.
- New wrapper procs added to `renderer.odin` for the render-texture/shader plumbing (mirroring the existing `begin_drawing`/`begin_using_camera` wrapper style — raw `rl.BeginTextureMode`/`rl.BeginShaderMode`/etc. calls stay wrapped, not inlined into `draw_game`).
- The blur shader is a two-pass separable Gaussian (horizontal pass, then vertical), loaded once at startup from `initialize_renderer` alongside the atlas/font — not reloaded per frame.
- The offscreen `RenderTexture2D` is sized to `game.window_width`/`game.window_height` and only recreated when those differ from the texture's current size (checked once per frame before use) — mirroring how `game.window_width`/`window_height` themselves are already refreshed every frame from `get_screen_width()`/`get_screen_height()` (`main.odin:273-274`), not reallocated every frame regardless of whether the window actually changed size.
- No new persisted state and no `Save`-schema change: `blurred_backdrop_strength()` is derived fresh every frame from existing `Menu_Transition`/`current_screen`/`current_map` state, the same way `menu_element_anim` already is.
- Default blur radius / dim alpha are starting points to be tuned visually against Shop and Run_End during implementation (numbers not locked by this spec, consistent with how `weapon-action-feel`'s per-weapon timing constants were treated as tunable starting points, not final content).

## Testing Decisions

- A good test here asserts on `blurred_backdrop_strength()`'s external, observable contract — zero vs. non-zero, and the exact ramp value at a given `Menu_Transition` state — not on shader output, `RenderTexture2D` pixel contents, or any other raylib-dependent draw call. Rendering is validated visually against the running game (Shop and Run_End specifically), the same way `weapon-action-feel`'s `draw_weapon()` rendering was excluded from its test suite and validated by eye instead.
- Module under test: the new `blurred_backdrop_strength()` proc in `hud.odin`, driven directly by setting global `game` state and calling it — not through `request_screen_change`/`update_menu_transition`'s real Dismiss-window wait — following `hud_test.odin`'s existing snapshot/restore-globals discipline (see that file's header comment) rather than introducing a new testing convention.
- Worth covering concretely:
  - Strength is `0` on Playing/Editing (`current_screen() == nil`), even when `current_map` is populated.
  - Strength is `0` on Splash/Main_Menu/Run_Start/Map_Selection, even though `current_screen()` is non-nil, because `current_map.name == ""` at that point.
  - Strength is `> 0` while `game.shopping` is true and `current_map.name` is non-empty.
  - Strength is `> 0` while `game.run_ended` is true and `current_map.name` is non-empty.
  - Strength exactly matches `menu_element_anim(0, 0).alpha` at a given `Menu_Transition` state (mid-Reveal, Reveal complete, mid-Dismiss), confirming it's driven by the same alpha rather than a parallel calculation that could drift out of sync over time.
- Prior art: `hud_test.odin`'s `test_apply_screen_kind_*` tests (the same file this proc's tests would live in) and `weapon_test.odin`'s snapshot/restore-globals convention, referenced directly in `hud_test.odin`'s own header comment.

## Out of Scope

- Building an actual pause menu — none exists today; this spec only ensures the blur mechanism applies automatically if/when one is added later.
- Locking exact final blur radius / dim alpha values — starting points only, to be tuned visually during implementation.
- Applying blur behind Splash, Main_Menu, Run_Start, or Map_Selection — structurally impossible today since `current_map` is empty there, and not desired even if it weren't.
- Any blurred-backdrop treatment for the debug panel (`game.debug.panel_open`) — a separate, pre-existing overlay (`draw_debug_panel_ui`, still on the old `vendor/ui` path) outside the Screen/`Menu_Transition` system this feature hooks into.
- Sound design or any audio cue tied to the blur appearing/disappearing.
- Formal performance/frame-budget validation — this repo has no documented target frame rate or GPU budget to validate against; only "runs acceptably at this project's own resolution" is expected.

## Further Notes

- This spec is the synthesized output of a grilling session (all five open questions resolved in a single round) plus direct codebase exploration — no wayfinder map/ticket set was produced for this feature; it went straight from grilling to spec.
- Read `CONTEXT.md`'s Screen / Menu element / Reveal / Dismiss glossary entries and [ADR-0014](../../docs/adr/0014-menu-ui-flat-rect-and-reveal-dismiss-animation.md) before touching `hud.odin`'s Screen/`Menu_Transition` system — this feature builds directly on that system rather than introducing a parallel one.
- A new ADR (next number, 0015) should record why blur strength is driven by the panel's own Reveal/Dismiss alpha rather than a separate timer, and why the trigger condition is "a Screen is showing over a populated world" rather than a per-`Screen_Kind` whitelist.
