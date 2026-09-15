# Verifying a web build

Type: grilling
Status: resolved
Blocked by: 06

## Question

What does "the web build works" mean before a deploy is trusted, and does a failing check block the deploy?

Graduated from the map's fog once Web toolchain recipe fixed the toolchain and Pages deploy pipeline fixed the CI shape: a single `build` job runs `./build.sh web` and hands `build/web/` to `deploy-pages`, so today a build that *links* deploys, whether or not it draws a frame. Candidates:

- **Manual smoke** — a checklist run by a human in Chrome, Firefox and Safari (the three Targets charting named; Safari is untested anywhere so far) after each deploy, or only before "releases". What's on it: page loads, first frame draws, a Run can be started and ended, a save survives a reload, export/import round-trips.
- **Headless check in CI** — a browser (Playwright or Chrome headless) loads `build/web/index.html` from a local server, waits for the shell page's loading state to clear (Shell page and loading fixes what that state is), asserts no console errors and that the canvas rendered non-blank pixels. Cheap to keep green; catches a broken link step and a WebGL-init failure, not gameplay.
- **Both**, with only the headless check gating the deploy.

Sub-questions: whether the check runs *before* `upload-pages-artifact` (a failing smoke blocks the deploy) or as a separate post-deploy job against the live URL (the deploy always happens; a failure is a notification); and whether the check lives in `build.sh` (runnable locally) or only in the workflow.

## Answer

**A headless Chrome smoke gates the deploy; Firefox and Safari are a manual checklist.** Gameplay is not re-verified on web — `run_objective_test.odin` already drives whole Runs windowless under `odin test` on Desktop — so the web check covers only what is web-specific: the build boots, draws, and persists.

1. **Gate, not notify.** A smoke step sits between `./build.sh web` and `upload-pages-artifact` in `deploy-pages.yml`; a failure means no deploy. A post-deploy check against the live URL was rejected because it leaves a blank site up until someone reads the notification.
2. **Playwright, driving the runner's Chrome.** `@playwright/test` with `channel: 'chrome'` (Ubuntu runners ship Chrome; nothing is downloaded), one spec, `build/web/` served by `python3 -m http.server`. Build-session caveat: new headless Chrome has no GPU, so launch with `--enable-unsafe-swiftshader` (or `--use-angle=swiftshader`) or WebGL init fails and the shell page shows its failure panel instead of the game.
3. **Four assertions, each a one-line failure:**
   1. the page loads with zero console errors and no uncaught exception;
   2. the shell page reaches its ready state within 15 s — Shell page and loading's canvas fade-in — which the shell exposes as `document.documentElement.dataset.state = "ready"` (set it in the shell page; the smoke reads it);
   3. after one keypress (Splash→Main Menu is a Save point), `localStorage["shooter:game_save:v1"]` exists and parses with a `player` key — the Save store and Save points proven end to end;
   4. the canvas is not uniform: read back a handful of pixels and assert more than one colour (the Splash image drew).
   Nothing else. Gameplay stays on the Desktop tests.
4. **Chrome only in CI.** Playwright's Firefox is an 80 MB download per run for a browser-independent question (is the build broken?). Firefox and Safari are covered by hand.
5. **Manual smoke** — recorded here, not as a doc (the build session may promote it). Run in **Safari** (CI can't reach it; it has ITP and the unverified file-picker activation) and Firefox, after any deploy that touches the shell page, the Target seam, or the save:
   - page loads; Splash → Main Menu on a keypress;
   - start a Run, end it (die or clear), reload → Main Menu shows the receipt's Gold and offers no Continue;
   - start a Run, close the tab mid-Run, reopen → Continue is offered (the unload hook);
   - Export downloads a `.json`; Import of that file shows the now-vs-file table and replaces; Copy → Paste round-trips;
   - Safari only: Import's file picker opens from the in-game button (the transient-activation question in Save export/import) — if it doesn't, the clipboard pair is the documented fallback.
6. **Lives in `web/smoke/`** — a `package.json` and one spec — run locally with `npx playwright test` and by the workflow as its own step. Not inside `build.sh`, which stays Odin + emcc so `./build.sh web` runs on a machine without Node.

Consequences: `deploy-pages.yml` gains `actions/setup-node`, `npm ci` in `web/smoke/`, a background `http.server`, and the test step, all before the upload; the shell page gains a `data-state` attribute on `<html>` (`loading` → `ready` / `failed`) that both the fade-in and the smoke key off. The first green run of this step is also the first time the `emcc` link and the wasm boot are executed anywhere — Web toolchain recipe's standing risk closes there.
