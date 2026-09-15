# Save failures on web

Type: grilling
Status:
Blocked by:

## Question

What does a Web player see when the save can't be read or can't be written, and what can they do about it?

Graduated from the map's fog once Save export/import fixed the shape of a "your save has a problem" modal (the rejected-import panel: title, the ADR-0028 reason verbatim, what happens to the current save, one button). Two directions:

- **Read failure.** `save_store_read` returns `Ok` with a blob `load_game` can't parse (JSON error, or an identity string no enum case carries — ADR-0028). Desktop logs the reason and starts from `initialize_default_game_state`; a browser player sees nothing and their progress is silently gone. Candidates: the rejected-import modal on first reaching the Main Menu, with the reason and an *Export the old save* button that downloads the raw blob so it can be repaired by hand or loaded by a later version; or a quieter one-line notice on the navigation panel. An *empty* store (`Absent`) is never this — it's "no save yet" (Browser save store: Safari's 7-day wipe recreates it).
- **The ordering hazard.** Save points write a default save at Splash→Main Menu. If the unparseable blob was replaced by a default save *before* the player reaches the Main Menu, there is nothing left to export. Decide where the failed blob survives until the player has been told: keep it in memory and skip the Splash→Main Menu save on a failed load, or write it to a second key (`shooter:game_save:v1:rejected`) before the default overwrites the first.
- **Write failure.** `save_store_write` returns false (quota, private mode, a sibling project's script clearing storage between Save points). Desktop logs. On Web: a persistent marker on the navigation panel (*"Couldn't save — export a copy"*) until a write succeeds again, or nothing.
- **Desktop parity.** Whether the read-failure modal is Web-only or both Targets show it (a Desktop player also never reads the log unless they launched from a terminal).

Records nothing new in `CONTEXT.md` unless a term for the rejected blob emerges.
