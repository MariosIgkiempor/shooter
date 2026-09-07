# 16: The ladder gates on clears

**What to build:** Maps are a ladder, not a menu. The first rung is open on a
fresh Account; clearing a rung opens the next and nothing further. Map Selection
shows the locked rungs with what they need, so the player can see where the
ladder goes before they can walk it.

**Blocked by:** 13, 03

**Status:** ready-for-agent

- [ ] The Account records which Maps have been cleared, persisted by identity string
- [ ] Rung one is always available; clearing rung n opens exactly rung n+1
- [ ] Locked rungs render with a lock glyph and their requirement, and cannot be selected
- [ ] Clearing a Map already cleared changes nothing
