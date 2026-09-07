# 05: Swarmers surround by contour

**What to build:** A swarming pack forms a ring around the player that wraps
walls instead of cutting through them. A Swarmer follows the shared field
inward until it reaches its surround distance, then drifts along the contour at
that distance rather than pressing further in.

**Blocked by:** 04

**Status:** ready-for-agent

- [ ] Pre-assigned surround slots are deleted
- [ ] A Swarmer approaches by the field and, at surround distance, drifts along the contour
- [ ] A Swarmer separated from the player by a wall moves around it rather than into it
