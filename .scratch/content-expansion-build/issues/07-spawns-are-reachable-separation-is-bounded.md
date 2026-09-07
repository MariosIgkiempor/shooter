# 07: Spawns are reachable and separation is bounded

**What to build:** An enemy never spawns somewhere it cannot walk out of, so a
Map cannot be left permanently uncleared by one body stranded in a sealed
pocket. Crowd separation costs the same per enemy whether ten or three hundred
are alive.

**Blocked by:** 04

**Status:** ready-for-agent

- [ ] A candidate spawn position is rejected if the field never reached its cell
- [ ] Separation samples a bounded number of neighbours rather than every other enemy
- [ ] Crowding still pushes bodies apart at the densities the roster produces
