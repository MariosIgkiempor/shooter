# 01: Share one UI hover flag between the editor and the debug panel

**What to build:** Nothing observable changes. The Tilemap Editor keeps behaving
exactly as it does today — painting, erasing, rectangle-dragging and camera
panning are all still suppressed while the pointer is over one of the editor's
own windows. The only difference is that the mechanism doing the suppressing now
lives somewhere both the editor and the debug panel can reach it.

This is a prefactor. Ticket 03 needs the same "the UI owns this pointer, do not
let the world act on it" behaviour for the debug panel, and the codebase should
not grow a second copy of it. The shared HUD module is already documented as the
home for what the debug panel and the editor both use, so the hover-recording
helper and its flag belong there.

Two properties of the existing mechanism must survive the move: it is recorded
from just inside a window's begin call, and it is one frame stale by
construction, because the UI is declared during the draw phase and read during
the next update. The comment explaining why that staleness is correct — it
describes where the pointer *is*, not that an event arrived, so it holds steady
across a trackpad gesture's gaps — should travel with the code.

A single shared flag is safe rather than needing one per surface, because the
editor and the debug panel remain mutually exclusive: at most one UI surface is
live in any frame.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] The hover-recording helper and the hovered flag live in the shared HUD module, not in the editor
- [ ] The editor's own copy of the flag is deleted, and every editor read points at the shared one
- [ ] The flag is reset at the start of each frame that draws a UI surface
- [ ] The comment explaining the one-frame staleness moves with the code
- [ ] Editor behaviour is unchanged: pencil, erase, rectangle drag and camera pan are all still suppressed under editor windows
- [ ] A rectangle drag started in the world still continues over editor windows; only starting one there is blocked
- [ ] The full test suite passes
