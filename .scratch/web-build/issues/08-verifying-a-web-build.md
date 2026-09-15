# Verifying a web build

Type: grilling
Status:
Blocked by: 06

## Question

What does "the web build works" mean before a deploy is trusted, and does a failing check block the deploy?

Graduated from the map's fog once Web toolchain recipe fixed the toolchain and Pages deploy pipeline fixed the CI shape: a single `build` job runs `./build.sh web` and hands `build/web/` to `deploy-pages`, so today a build that *links* deploys, whether or not it draws a frame. Candidates:

- **Manual smoke** — a checklist run by a human in Chrome, Firefox and Safari (the three Targets charting named; Safari is untested anywhere so far) after each deploy, or only before "releases". What's on it: page loads, first frame draws, a Run can be started and ended, a save survives a reload, export/import round-trips.
- **Headless check in CI** — a browser (Playwright or Chrome headless) loads `build/web/index.html` from a local server, waits for the shell page's loading state to clear (Shell page and loading fixes what that state is), asserts no console errors and that the canvas rendered non-blank pixels. Cheap to keep green; catches a broken link step and a WebGL-init failure, not gameplay.
- **Both**, with only the headless check gating the deploy.

Sub-questions: whether the check runs *before* `upload-pages-artifact` (a failing smoke blocks the deploy) or as a separate post-deploy job against the live URL (the deploy always happens; a failure is a notification); and whether the check lives in `build.sh` (runnable locally) or only in the workflow.
