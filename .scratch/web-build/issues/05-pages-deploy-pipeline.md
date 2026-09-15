# Pages deploy pipeline

Type: task
Status: resolved
Blocked by: 01, 04

## Question

Provision GitHub Pages on this repo and write the GitHub Actions workflow that builds the web Target on every push to `main` and deploys it.

The workflow needs: the Odin toolchain at the version this repo builds with, Emscripten, the `vendor/ui` submodule checked out, the atlas and map builders run first (as `build.sh` does), the wasm build via `./build.sh web` (Target seam and gating — it runs the generators and both guards itself, and writes `build/web/`), and a Pages deploy step. Enabling Pages and choosing the deployment source is a human click in repo settings — hand the human a precise checklist for that part.

Preconditions Web toolchain recipe exposed: the `vendor/ui` pin is a commit that exists only in the main checkout's `.git/modules`, not on its remote, so CI's `git submodule update --init` will fail until it is pushed (the human's checklist starts there; `vendor/atlas-builder` was vendored into the tree on 2026-09-15 and is no longer a submodule); and the Odin version must be pinned to one whose `vendor/raylib/wasm/libraylib.a` matches its bindings (5.5 today; upstream master is already 6.0).

The answer records: the live URL, the workflow file path, the pinned Odin and Emscripten versions, and anything a human had to click or set.

## Answer

**Provisioned.** The workflow is [`.github/workflows/deploy-pages.yml`](../../../.github/workflows/deploy-pages.yml); the site is **https://mariosigkiempor.github.io/shooter/** (Pages source: GitHub Actions, HTTPS enforced). It goes green the moment `./build.sh web` exists — until then every push to `main` fails at the "Build the Web Target" step, which is expected (shipping is the follow-on effort).

What was done, 2026-09-15:

- **The repo had no remote at all**, so step one was `gh repo create MariosIgkiempor/shooter --public` (public because Pages on the free plan is public-only, and the map's storage argument leans on `<owner>.github.io` as a stable origin) and pushing `main`.
- **`vendor/ui`**'s pin `e2f7876` (6 commits) pushed to `MariosIgkiempor/ui` `main`; `.gitmodules` switched from `git@github.com:` to `https://github.com/MariosIgkiempor/ui.git` so `actions/checkout` with `submodules: true` works on the default token (SSH would need a deploy key). Your local clone keeps its SSH remote unless you `git submodule sync`. `vendor/atlas-builder` stopped being a submodule on `main` the same day (vendored into the tree), so its unpushable pin is moot.
- **Pins**: Odin `dev-2026-05` via `laytan/setup-odin@v2` — the local `dev-2026-05-nightly:ea5175d` *is* that tag's commit, and it is the last release whose `vendor/raylib/wasm/libraylib.a` matches its 5.5 bindings (`dev-2026-09` ships `libraylib.web.a` with 6.0 bindings); the workflow asserts the file exists so a bump fails loudly. Emscripten `6.0.9` via `mymindstorm/setup-emsdk@v14`. `actions/checkout@v7`, `upload-pages-artifact@v5`, `deploy-pages@v5`. `concurrency: pages` with cancel-in-progress; `workflow_dispatch` for manual runs.
- **CI facts the two runs proved** ([first](https://github.com/MariosIgkiempor/shooter/actions/runs/34971979133), [second](https://github.com/MariosIgkiempor/shooter/actions/runs/34972190568)): the Linux Odin tarball ships STB's C sources but not the compiled libs the atlas builder needs (`vendor:stb/image`, `rect_pack`, `truetype`) — hence a `make -C "$(odin root)/vendor/stb/src"` step; `ubuntu-latest` has the `clang`/`make` Odin's native link needs; with that, the atlas and maps build and the **desktop** game compiles and links on Ubuntu, dying only because today's `build.sh` ignores `web` and tries to `odin run` a window with no `DISPLAY`. So everything up to `./build.sh web` is verified; the wasm compile + `emcc` link remain unexecuted anywhere (Web toolchain recipe's standing risk).
- **Human click**: Settings → Pages → Source: GitHub Actions (done; verified via `GET /repos/MariosIgkiempor/shooter/pages`: `build_type=workflow`).

Nothing else had to be clicked, set, or secreted.
