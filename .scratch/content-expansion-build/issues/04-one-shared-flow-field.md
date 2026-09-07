# 04: One shared flow field replaces per-enemy pathfinding

**What to build:** Enemies chase the player correctly with hundreds of bodies on
screen. Instead of every enemy running its own search, the Map holds a single
field flooded outward from the player's cell, rebuilt only when the player
crosses into a new cell; an enemy reads the direction stored in its own cell.
Styles that do not collide with walls ignore the field entirely and steer
straight at the player as they always did.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] A field covering the Map's cells is built by flooding from the player's cell and rebuilt when that cell changes
- [ ] Colliding movement styles steer by the field; non-colliding styles steer directly and are unaffected
- [ ] Per-enemy path storage, the path search, and its node budget are deleted
- [ ] The debug visualiser shows the field rather than per-enemy paths, and is renamed to match
- [ ] A flood descends toward the player, and an enclosed pocket is never filled
