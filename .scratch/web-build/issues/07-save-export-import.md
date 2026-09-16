# Save export/import

Type: prototype
Status: resolved
Blocked by: 02, 03

## Question

How do the main menu's "Export save" and "Import save" work?

Charting locked that these exist and live in the main menu, as the mitigation for a player wiping site data and as desktop↔web save portability (same JSON blob). To lock: their placement in the hand-rolled menu (ADR-0010, ADR-0012's folded-in account progression), what export produces (a downloaded `.json` via the mechanism Browser save store recommends), what import accepts and how it confirms before overwriting the current save, and what a rejected import shows — ADR-0028 fails the load on an unknown identity, and on web there's no log for the player to read.

Build a rough menu prototype to react to. Links the prototype as an asset.

Lower priority than the tickets above it.

## Answer

**Variant A plus B's clipboard row: four small buttons under *Start New Run* in the Main Menu's navigation panel — *Export save*, *Import save…*, *Copy save*, *Paste save…* — with the file pair Web-only and the clipboard pair on both Targets.** Prototype: `web/prototype-save-export-import.html` on branch `prototype/shell-page` (commit `c85ed2c`; serve the repo root, `?variant=A|B|C`, the dropdown fakes what the imported file holds). Three variants were built: A (buttons in the navigation panel), B (a fourth "Save" panel with a status line and a clipboard row), C (export button only, import by drag-and-drop). A won with B's clipboard row; B's panel was rejected because four panels are 1088 px wide against the 960 px default window, and C because a drop target is undiscoverable from inside the game.

Locked:

1. **Placement.** The navigation panel (ADR-0012's third panel) gains a gap and four ghost-styled `MENU_BUTTON_HEIGHT`-ish small buttons below *Start New Run*: *Export save*, *Import save…*, *Copy save*, *Paste save…*. On Desktop the first two are not drawn — `data/game_save.json` is already a plain file the player can move, and a fixed export path would be a worse file dialog. The panel's height formula gains the rows (`shooter_h`), which is what keeps the row centred.
2. **Export (Web)** hands the current blob to a foreign proc that builds a `Blob` (`application/json`), a `URL.createObjectURL`, and a synthetic `<a download="shooter-save-YYYY-MM-DD.json">` click — the mechanism Browser save store named. The blob is exactly what `save_game` writes, so it loads on Desktop as `data/game_save.json` unchanged. A save is taken first (Save points: this is not a Screen change, so export calls `save_game` itself before reading the store, so the file matches the game).
3. **Import (Web)** opens `<input type="file" accept=".json,application/json">` via a foreign proc; the file's text comes back through the same `(ptr, len)`/caller-buffer convention as the store. **Caveat for the build session**: the click happens inside the Odin frame (inside `requestAnimationFrame`), not in the DOM click handler. Chrome and Firefox honour `input.click()` within the transient-activation window (~5 s after the canvas click); Safari is unverified — if it refuses, the fallback is the clipboard pair, which is why they exist on Web too and not only on Desktop.
4. **Copy / Paste (both Targets)** are `rl.SetClipboardText` / `rl.GetClipboardText` on Desktop and `navigator.clipboard.writeText` / `readText` on Web (both need a user gesture; `readText` prompts for permission in Chrome, is unsupported in Firefox without a flag — the prototype's Paste opens a text box the player pastes into with the keyboard, which works everywhere; keep that shape: *Paste save…* opens a one-field panel, the player ⌘V/Ctrl+V's, Import).
5. **Confirm before overwrite.** An imported blob is parsed into a *scratch* copy of the `game` struct type, never into `game`, through the same `json.unmarshal` + identity-string resolution `load_game` does. If it parses, a modal shows a now-vs-file table — Account level, Gold, Maps cleared, Run in progress — with "Replace" / "Cancel" and the line *"Your current save is overwritten. Export it first if you want to keep it."* Replace writes the blob through the Save store and then runs `load_game`, so the menu redraws from the imported state.
6. **Rejected import.** The modal *"That file couldn't be read as a save"*, the reason verbatim in a red-barred block (the same message the log gets — ADR-0028's `Weapon_Kind "Blaster" isn't a weapon this version knows`, or the JSON error, or *No "player" in the file — is this a shooter save?*), then *"Your current save is untouched."* and OK. This is the first place a browser player sees a load reason, so the `*_from_save` procs' messages need to be returned as strings, not only logged.
7. **Copy approved as written** in the prototype for the confirm and rejected modals and the four button labels.

Consequences: the Save-store seam (Target seam and gating) gains nothing — export/import read and write the same blob through `save_store_read`/`save_store_write`; the two file procs and the two clipboard procs are Web-Target foreign procs beside them, and `save_store_delete` is still not needed. The scratch-struct parse (5) is new machinery `load_game` doesn't have today and is the one non-trivial piece of the build.

## Comments

- 2026-09-16 — [Save failures on web](09-save-failures-on-web.md) adds the *Export old save* / *Discard* modal that reuses this ticket's rejected-import shape, and brings `save_store_delete` back for the `Rejected` slot.
