# Save failures on web

Type: grilling
Status: resolved
Blocked by:

## Question

What does a Web player see when the save can't be read or can't be written, and what can they do about it?

Graduated from the map's fog once Save export/import fixed the shape of a "your save has a problem" modal (the rejected-import panel: title, the ADR-0028 reason verbatim, what happens to the current save, one button). Two directions:

- **Read failure.** `save_store_read` returns `Ok` with a blob `load_game` can't parse (JSON error, or an identity string no enum case carries — ADR-0028). Desktop logs the reason and starts from `initialize_default_game_state`; a browser player sees nothing and their progress is silently gone. Candidates: the rejected-import modal on first reaching the Main Menu, with the reason and an *Export the old save* button that downloads the raw blob so it can be repaired by hand or loaded by a later version; or a quieter one-line notice on the navigation panel. An *empty* store (`Absent`) is never this — it's "no save yet" (Browser save store: Safari's 7-day wipe recreates it).
- **The ordering hazard.** Save points write a default save at Splash→Main Menu. If the unparseable blob was replaced by a default save *before* the player reaches the Main Menu, there is nothing left to export. Decide where the failed blob survives until the player has been told: keep it in memory and skip the Splash→Main Menu save on a failed load, or write it to a second key (`shooter:game_save:v1:rejected`) before the default overwrites the first.
- **Write failure.** `save_store_write` returns false (quota, private mode, a sibling project's script clearing storage between Save points). Desktop logs. On Web: a persistent marker on the navigation panel (*"Couldn't save — export a copy"*) until a write succeeds again, or nothing.
- **Desktop parity.** Whether the read-failure modal is Web-only or both Targets show it (a Desktop player also never reads the log unless they launched from a terminal).

Records nothing new in `CONTEXT.md` unless a term for the rejected blob emerges.

## Answer

**A failed read moves the blob to a second Save-store slot and shows a modal on the next Main Menu; a failed write shows a marker on the navigation panel; both Targets, same code.**

1. **Read failure surface.** When `load_game` lands on either of its failure paths (unmarshal error, or an identity string no case carries — ADR-0028), the first Main Menu afterwards opens a modal in the shape Save export/import fixed: *"Your save couldn't be read"*, the reason verbatim (the same string the log gets — so the `*_from_save` procs and `load_game` return their messages, not only log them), *"The game has started fresh. Your old save is kept until you choose:"*, then **Export old save** / **Discard**. On Desktop, where the file pair is hidden, the modal instead says *"It's kept at `data/game_save.rejected.json`"* with only **Discard**. An `Absent` store is never this — it is "no save yet" (Browser save store).
2. **The rejected blob survives in a second slot.** The Save-store seam (Target seam and gating) grows one parameter: `Save_Slot :: enum { Current, Rejected }` on `save_store_read(slot, allocator)`, `save_store_write(slot, data) -> bool`, and `save_store_delete(slot)` — the delete Target seam and gating deferred, now with its reason. Web keys: `shooter:game_save:v1` and `shooter:game_save:v1:rejected`; Desktop files: `data/game_save.json` and `data/game_save.rejected.json`. `load_game` writes the unreadable bytes to `Rejected` *before* returning to `initialize_default_game_state`, so the default save Save points writes at Splash→Main Menu lands on `Current` with nothing lost. The modal shows whenever `Rejected` is non-empty at Main Menu, so a reload before acting re-shows it. **Discard** deletes the slot; **Export old save** downloads it and then deletes it. Rejected: in-memory only (gone on reload or crash) and suppressing saves until dismissed (the game would run unsaved, which Save points said never happens).
3. **Write failure.** `save_game`'s `false` sets `game.last_save_failed` (`json:"-"`); while true the navigation panel draws one red line above its buttons — *"Couldn't save — export a copy"* — cleared by the next successful write. Nothing else; export is the only recourse in the cases that produce it (quota, private mode, a sibling `<owner>.github.io` project clearing storage).
4. **Both Targets.** The modal and the marker are shared menu code; the only Target difference is the modal's button set (1). A Desktop player launched from Finder never sees the log either.
5. **Rejected save** is recorded in `CONTEXT.md`.

Consequences: `data/game_save.rejected.json` joins `data/game_save.json` in `.gitignore`; the Desktop save store's `Rejected` slot is the one place `os.remove` is used; the smoke (Verifying a web build) needs no change — it only ever sees a fresh store.
