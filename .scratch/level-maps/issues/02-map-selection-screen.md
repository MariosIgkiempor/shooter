Type: grilling
Status: resolved
Blocked by: 01, 04

## Question

Specify the UI flow and mechanics for the new `ProgramMode.Selecting`, shown at every launch before Playing or Editing become reachable.

Needs to settle:

- **Discovery and listing.** [Ticket 4](04-map-baking-tool.md) settled that Playing mode consumes a compiled-in `Map_Name` enum + baked `[Map_Name]Map` table, not a runtime directory scan — discovery here means enumerating `Map_Name`, and each entry displays its baked `Map.name`.
- **UI idiom.** Which existing pattern this reuses — the immediate-mode `ui` package already driving editor.odin's `ui.begin("Tilemap Editor")` panel and hud.odin — with a concrete widget/button layout for a list-and-pick flow.
- **On selection.** Instantiates `game.current_map` from the baked table via ticket 1's `clone_map` (never a naive value copy — see ticket 1's aliasing note), applies `apply_chosen_map` (ticket 1) to resolve resume-vs-reset player positioning against `game_save.json`'s active-map pointer, and transitions `game.program_mode` to `.Playing`.
- **Boot sequence placement.** `initialize_program`/`load_game` currently loads straight into `.Playing`. Confirm exactly where `.Selecting` is inserted — does `load_game` still run first to recover player/camera/active-map-pointer state, with `.Selecting` shown after and nothing pre-selected until the user picks?
- **Empty `Map_Name` handling.** Already settled that this is out of scope to design for (assume ≥1 map always exists, per the map's Notes) — confirm this still holds now that the set of maps is a compile-time enum rather than a runtime directory listing (it necessarily has ≥1 case for the binary to even compile meaningfully, if the generator errors on zero source files).

## Answer

**UI idiom.** A new `draw_map_selection_ui`, mirroring `draw_game_over_ui`/`draw_level_up_ui` (hud.odin:224-278) exactly — same centered-modal construction (`ui.row({size = {layout.grow(0,0), layout.grow(0,0)}, align = {.Center, .Center}})` wrapping `ui.begin("Select a Map", {panel = true, panel_margin = MENU_PANEL_MARGIN})`), same `HUD_THEME`/`draw_ui_render_commands(ui.end_frame(), MENU_PANEL_SCALE)` bracketing. One `ui.button(map_name_string, {panel = true})` per `Map_Name` case, iterating the enum, labeled by that case's baked `maps[case].name`.

**On selection.** The clicked button's handler:

```odin
chosen := maps[name] // the Map_Name case that was clicked
game.current_map = clone_map(chosen)
apply_chosen_map(chosen, map_identity_string(name)) // ticket 1's resume-vs-reset proc
game.program_mode = .Playing
```

(`map_identity_string` — trivial string conversion of the `Map_Name` value, however ticket 1's `active_map_pointer` field ultimately compares; Odin's `fmt`/`reflect` can stringify an enum value directly, no separate lookup table needed beyond what ticket 4 already generates.)

**Boot sequence.** `ProgramMode :: enum { Selecting, Playing, Editing }` (`Selecting` first → zero value), `program_mode` tagged `json:"-"`. `initialize_default_game_state` sets `program_mode = .Selecting` explicitly (was `.Playing`); `load_game`'s success path sets `game.program_mode = .Selecting` explicitly right after `json.unmarshal` returns, for the same reason — never trust a stale persisted value even though the tag alone would already prevent it. `load_game` is otherwise unchanged: player/camera/`game_save.json`'s active-map pointer are recovered immediately, before `.Selecting` is ever drawn, so `apply_chosen_map` has something to compare against the moment the user picks.

**Empty `Map_Name`.** Confirmed out of scope, unchanged from the map's Notes — the generator (ticket 4) is expected to error on zero source `data/maps/*.json` files rather than emit a valid-but-empty enum, so `Map_Name` having ≥1 case is a build-time invariant, not something `draw_map_selection_ui` needs to guard against at runtime.

This closes the Maps map — all four tickets resolved, nothing left to decide before implementation starts.
