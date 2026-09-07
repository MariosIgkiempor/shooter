# 18: A weapon hits only what it touches

**What to build:** What a melee weapon hits is the shape the player can see it
sweep. A dagger's short stab and a greatsword's wide arc differ because their
drawn shapes differ, not because a hidden cone was widened. A fast swing past a
body still connects — the volume is swept between frames rather than sampled
once — and one swing damages a given body once, however long the shape overlaps
it.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Each melee weapon kind has a hit volume matching its drawn silhouette
- [ ] The volume is swept between consecutive frames; a body crossed mid-swing is caught
- [ ] One swing damages one body at most once, tracked per swing
- [ ] Follow-through carries both fire modes
- [ ] The swing arc becomes part of the weapon's visual record
- [ ] The generic cone is gone except where a cone is genuinely the shape
