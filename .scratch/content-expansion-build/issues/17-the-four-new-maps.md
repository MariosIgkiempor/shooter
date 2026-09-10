# 17: The four new Maps

**What to build:** Four more places to play, each a different shape of fight and
each pulling from the roster differently — so climbing the ladder means meeting
new enemies in rooms that suit them, not the same room with bigger numbers.

**Blocked by:** 14, 15, 11

**Status:** ready-for-agent

- [ ] Four Maps are authored beyond the existing one, filling rungs two through five
- [ ] Each has its own layout, palette, ambient set, time limit and payout multiplier
- [ ] Each has a composition timeline that introduces its rung's debuting Kinds
- [ ] All five pass the Map validity test

## Comments

Rung two is currently occupied by `data/maps/cold_hall.json`, a second Map
added while building ticket 13 so per-Map theming had two Maps to be tested
against. Its layout is generated (a colonnaded hall) rather than hand-drawn
and its timeline is the Desert Dungeon's re-paced, so it is a fixture, not
one of this ticket's four. Replace or rebuild it here rather than authoring
around it.
