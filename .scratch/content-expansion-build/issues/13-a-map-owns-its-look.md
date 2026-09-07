# 13: A Map owns its look

**What to build:** Each Map looks like its own place. A Map carries its floor
and wall colours, its ambient set, and the rung it sits at on the ladder, so
adding a Map does not mean editing a table somewhere else to give it a colour.
The Map Selection screen's swatch is derived from the Map's own wall colour.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] A Map carries rung, floor colour, wall colour and its ambient set
- [ ] The separate per-Map icon colour table is deleted; the selection swatch derives from the Map
- [ ] Tile drawing reads the current Map's colours
- [ ] The existing Map keeps the palette it has today
