# Pages deploy pipeline

Type: task
Status: claimed
Blocked by: 01, 04

## Question

Provision GitHub Pages on this repo and write the GitHub Actions workflow that builds the web Target on every push to `main` and deploys it.

The workflow needs: the Odin toolchain at the version this repo builds with, Emscripten, submodules checked out (`vendor/ui`, `vendor/atlas-builder`), the atlas and map builders run first (as `build.sh` does), the wasm build via `./build.sh web` (Target seam and gating — it runs the generators and both guards itself, and writes `build/web/`), and a Pages deploy step. Enabling Pages and choosing the deployment source is a human click in repo settings — hand the human a precise checklist for that part.

Preconditions Web toolchain recipe exposed: both submodule pins (`vendor/ui`, `vendor/atlas-builder`) are commits that exist only in the main checkout's `.git/modules`, not on their remotes, so CI's `git submodule update --init` will fail until they are pushed (the human's checklist starts there); and the Odin version must be pinned to one whose `vendor/raylib/wasm/libraylib.a` matches its bindings (5.5 today; upstream master is already 6.0).

The answer records: the live URL, the workflow file path, the pinned Odin and Emscripten versions, and anything a human had to click or set.
