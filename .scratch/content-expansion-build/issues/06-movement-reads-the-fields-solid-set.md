# 06: Actor movement reads the field's solid set

**What to build:** Moving an actor costs a handful of lookups instead of a scan
of every tile on the Map, twice per actor per frame. Wall resolution consults
the cell-indexed set of solid cells the field already maintains, checking only
the cells the actor's box overlaps. Behaviour is unchanged: the player and
enemies still slide along walls one axis at a time.

**Blocked by:** 04

**Status:** ready-for-agent

- [ ] Actor movement resolves against the cells its box overlaps, not against every tile
- [ ] The player uses the same path as enemies
- [ ] Wall sliding, corner behaviour and collision results are unchanged
