# Target seam and gating

Type: grilling
Status: resolved
Blocked by: 01

## Question

Where does the Desktop/Web boundary live in the source, and how is the editor kept out of the web build?

`platform.odin` already wraps raylib's screen size and input behind free functions, which is the natural seam. With the toolchain facts from Web toolchain recipe in hand, decide:

- **What moves behind the seam**: Save store read/write (replacing `os.read_entire_file`/`os.write_entire_file` at `main.odin:190,329`), logging (`logger.odin:7`), the exit key, window/canvas sizing (`main.odin:369-370` reads the saved window size), the main-loop entry (`main.odin:173-185` becomes a callback on web), and `tuning.json` (`tuning.odin:176` — `#load` it, skip it, or route it through the Save store?).
- **Gating mechanism**: `when` on a `-define:WEB` constant vs Odin's file-suffix build tags (`*_web.odin` / `*_desktop.odin`) vs `#+build` lines — for the editor (`editor.odin`, `map.odin:186,292`, `enemy_presets_source.odin:26`, `editor.odin:862`) and for anything else that imports `core:os`. `initialize_editor` is called unconditionally at `main.odin:373` and F1 is handled at `main.odin:408-435`; the F8 debug panel stays in per the map's Notes.
- **Tests**: `odin test .` is desktop-only; how the web-only files stay out of it and the desktop-only ones stay in.
- **Build entry**: a `build-web.sh` beside `build.sh`, or one script with a target flag — and what the CI workflow (Pages deploy pipeline) will call.

Records **Target** and **Save store** in `CONTEXT.md`. If the gating choice is hard to reverse and surprising to a later reader, it earns an ADR.

## Answer

**The boundary is Odin's own: `#+build js` / `#+build !js` at file level, `when ODIN_OS == .JS` for a single branch inside a shared file, and no custom define.** Target siblings are named by the glossary term, `*_desktop.odin` / `*_web.odin`, with the tag inside. The editor is compiled out by a **null editor**; every other `core:os` use collapses into **one desktop-only file**.

1. **Gating mechanism.** The target *is* the switch — a `-define:WEB` would let a "web" build that isn't `js_wasm32` exist — and Web toolchain recipe's test-file fix already commits to `#+build`. Rule for the build session: a whole file that exists on one Target gets a tag; a branch inside a shared file gets `when ODIN_OS == .JS`. The inline spots known today: `program_should_exit` (false on web), the `blur.fs` `#load` pick, and the F1 handler (below). Precedent in the repo: `when ODIN_TEST` at `array_capacity.odin:11`.
2. **Null editor.** `editor.odin` gets `#+build !js`; a new `editor_null.odin` (`#+build js`) defines the six procs `main.odin` calls — `initialize_editor`, `update_editor`, `draw_editor`, `draw_editor_world_overlay`, `open_editing_map`, `update_editor_camera` — as no-ops, so `main.odin`'s update/draw do not change. The one `when ODIN_OS != .JS` wraps the F1 handler (`main.odin:408-435`), so web can never set `program_mode = .Editing` — a null `update_editor` in `.Editing` would be a black-screen trap. `ProgramMode.Editing` and `game.editing_map` stay as dead cases on web; the `ambience`/`draw_world` reads of `editing_map` are never reached there. Rejected: `when` around all seven call sites, which sprays the Target through `main.odin` and every future editor hook has to remember it.
3. **One desktop-only I/O file.** `desktop_io.odin` (`#+build !js`) holds `load_map`, `save_map`, `export_enemy_presets`, `save_tuning` and the file half of `load_tuning`; the pure halves (`Map` marshal, `enemy_presets_source`, tuning's override-map ↔ JSON) stay where they are. Rule: **`core:os` is imported in `desktop_io.odin` and `save_store_desktop.odin` and nowhere else** — checkable with a one-line grep, which `build.sh web` runs. Rejected: per-domain siblings (three headers for the same fact) and moving them into `editor.odin` (tests call them as map/tuning concerns).
4. **`tuning.json` ships on web via `#load`.** Overrides are a tracked, reviewable balance pass (CONTEXT.md's Override entry), so the web build must carry them. `load_tuning` calls a Target proc `tuning_source() -> ([]byte, bool)`: desktop's (in `desktop_io.odin`) reads the file at runtime, web's returns `#load("data/tuning.json")`. Rejected: skipping it (silently different balance than desktop) and `#load` on both (breaks the desktop loop — Save Tuning → relaunch reads the file; `#load` would need a rebuild).
5. **Save-store seam.** `save_store_desktop.odin` / `save_store_web.odin` expose `save_store_read(allocator) -> (data: []byte, status: Save_Store_Status)` with `Save_Store_Status :: enum { Ok, Absent, Failed }`, and `save_store_write(data: []byte) -> bool`. `load_game` maps `Absent` → "no save yet", `initialize_default_game_state`, never an error (Browser save store: an empty store must read as no save); `Failed` → the same fail-the-load landing ADR-0028 already has. Desktop = the file at `SAVE_GAME_PATH` (missing file → `Absent`); web = Browser save store's four foreign procs (`save_store_length == -1` → `Absent`). `save_game`'s `bool` (Save points) is `save_store_write`'s. `save_store_delete` is deliberately *not* in the seam: nothing on the route deletes a save; Save export/import adds it if it needs it.
6. **Test files.** `#+build !js` on all 29 game test files and `vendor/ui`'s two (a submodule commit that has to be pushed — Pages deploy pipeline's checklist). The tax — every future test file needs the tag — is accepted because tests are in-package (they reach private state), so a separate `tests/` package is not available; `build.sh web` greps for any `*_test.odin` missing the tag and fails before invoking `odin`, turning a `core:testing` compile wall into a one-line error.
7. **Build entry: `build.sh` stays the one script; it builds by default and runs only with `--run`.** Positional target, default desktop: `./build.sh`, `./build.sh --run`, `./build.sh web`; CI calls `./build.sh web`. Desktop output stays `build/shooter.bin`; web goes to `build/web/`. `--run` on web is an error today (nothing to run outside a browser — Shell page and loading may give it a meaning later, e.g. serving `build/web/`). The generator steps (atlas, maps) and both guards (test tags, `core:os` grep) run for both targets. This changes today's dev loop, where a bare `./build.sh` builds *and* plays: it now needs `--run`. Rejected: a separate `build-web.sh` (two scripts that both run the generators and drift).
8. **Naming.** `_desktop` / `_web`, not `_js`: the glossary term is Target = Desktop | Web; the tag word inside the file is the implementation detail.

Consequences worth knowing before the build session:

- Web toolchain recipe's `main_desktop.odin` / `main_web.odin` split, `logger.odin` unchanged, canvas sizing untouched and the `blur.fs` twin all stand; this ticket adds `editor_null.odin`, `desktop_io.odin`, `save_store_desktop.odin`, `save_store_web.odin`, and a `tuning_source` pair (web's can live in `save_store_web.odin`'s sibling or its own `web_io.odin` — the build session's call).
- A save written on web carries the canvas size in `window_width`/`window_height`; imported on desktop it opens the window at the browser's viewport size. Accepted — the field is already ignored on web, and desktop is resizable.
- Files this touches for the record: `main.odin:8,190,329,373,408-435`, `map.odin:4,186,292`, `tuning.odin:6,163,176`, `enemy_presets_source.odin:4,26`, `editor.odin:6,862`, `build.sh`, every `*_test.odin`.

Records **Target** in `CONTEXT.md` (**Save store** was written by Save points).
