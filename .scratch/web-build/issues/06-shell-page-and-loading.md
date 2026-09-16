# Shell page and loading

Type: prototype
Status: resolved
Blocked by: 01

## Question

What surrounds the canvas? Web toolchain recipe confirmed the shell page is ours (`--shell-file`, driving `main_start`/`main_update`/`main_end` from `requestAnimationFrame`), so the loading splash — what the player sees before the first frame while the ~1.2 MB wasm + atlas arrives — graduated from the map's fog into this ticket. The page needs: a viewport-filling canvas, a loading state while the ~1.2 MB wasm + atlas arrives, a page background that suits the game, and a sane message when WebGL is unavailable.

Build a throwaway shell page to react to — rough HTML/CSS with a fake loading bar is enough — and lock: whether loading shows progress or a static splash, what the page looks like around the canvas at odd aspect ratios, and what the WebGL-failure state says. Links the prototype as an asset.

Lower priority than the tickets above it.

## Answer

**Variant A — the splash cover with a real progress bar.** Prototype: `web/prototype-shell.html` on branch `prototype/shell-page` (commit `cb775cd`; serve the repo root and open `/web/prototype-shell.html?variant=A`, `?state=loading|ready|nowebgl`). Three variants were built and judged: A (the game's own splash image at `cover` with a progress bar), B (flat mint, an indeterminate hopping sprite), C (a dark menu-styled panel stepping through a boot log). A won.

Locked:

1. **The page background is the game's splash tile** (`data/textures/splash_background.png`, 1920×1200, ~300 KB) at `background-size: cover`, centred, on the mint `#4cd3a5` it fades to — the same cover-and-crop `draw_splash_ui` does, so the canvas's first frame (the in-game Splash drawing the same image) lands on top of a page that already looks like it. The handoff is a 400 ms opacity fade of the canvas from 0 to 1 once `main_start` returns; nothing is removed, the page simply sits underneath. Odd aspect ratios are therefore a non-question: the canvas fills the viewport (locked by charting) and the page beneath crops the same way the game does.
2. **Loading shows real progress**, not a static splash: a white-bordered bar low on the page (`bottom: 18%`, `min(360px, 70vw)` wide) with `loading N%` under it. Progress is real because Web toolchain recipe has *us* implementing `Module.instantiateWasm`: fetch `game.wasm`, read the body as a stream, and report bytes received against `Content-Length`. **Caveat the build session must honour**: GitHub Pages serves gzip, so `Content-Length` is the compressed size while the stream yields decompressed bytes — clamp the ratio at 100% (it will reach it early rather than overshoot), and if `Content-Length` is absent fall back to an indeterminate bar rather than a frozen 0%. The last stretch (instantiate + `main_start`) has no bytes to report; hold at 100% until the canvas fades in.
3. **WebGL failure** is a `MENU_THEME`-styled panel (`#282c34` fill, 2 px `#82aae6` border, 24 px padding, `min(420px, 80vw)`) centred over the splash, replacing the bar. Copy, approved as written: *"This browser can't run the game"* / *"It needs WebGL, which is switched off or unavailable here."* / *"Try a current Chrome, Firefox or Safari on a desktop, or turn hardware acceleration back on in the browser's settings."* Detection is a `canvas.getContext('webgl')` probe before the wasm is fetched, so a failing browser never downloads 1.2 MB it can't use.
4. **Nothing else on the page.** No title, no controls, no footer — the game's own Main Menu is the first thing with buttons. The loading state's only text is the percentage.

Rejected: B (indeterminate) sidestepped the gzip caveat but told the player nothing during a slow fetch; C (boot log) read as a developer tool and put a dark panel between the player and the game's own colours.
