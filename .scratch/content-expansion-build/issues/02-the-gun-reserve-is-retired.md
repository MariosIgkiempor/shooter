# 02: The gun reserve is retired

**What to build:** Every pickup the player walks over does something. The Ammo
pickup is gone, and with it the reserve pool it fed: a gun reloads from nothing,
so the ammo indicator only ever shows a state the player can change.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] The reserve count, its refill, both clip constants and the reload arithmetic that drew from it are gone
- [ ] The Ammo pickup kind is gone; no drop table, spawn path or icon still names it
- [ ] Reloading refills the clip outright
- [ ] The weapon indicator has no unreachable "out of ammo entirely" state
