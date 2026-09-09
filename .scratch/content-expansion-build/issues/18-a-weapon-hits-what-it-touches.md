# 18: A weapon hits only what it touches

**What to build:** What a melee weapon hits is the shape the player can see it
sweep. A dagger's short stab and a greatsword's wide arc differ because their
drawn shapes differ, not because a hidden cone was widened. A fast swing past a
body still connects — the volume is swept between frames rather than sampled
once — and one swing damages a given body once, however long the shape overlaps
it.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] Each melee weapon kind has a hit volume matching its drawn silhouette
- [x] The volume is swept between consecutive frames; a body crossed mid-swing is caught
- [x] One swing damages one body at most once, tracked per swing
- [x] Follow-through carries both fire modes
- [x] The swing arc becomes part of the weapon's visual record
- [x] The generic cone is gone except where a cone is genuinely the shape

## Comments

Built in `hit_volume.odin`: a per-kind `weapon_hit_volumes` table of polygons in
the glyph's own unit space, mapped to the world through `icon_at` and the same
`icon_frame_pivot` the silhouette rides, so a volume mirrors and rotates with
the blade and cannot be somewhere else. `swing_hit_check` runs every frame of
the Follow-through from `update_weapon`, testing each polygon between its
previous and current pose — the current pose plus one quad per edge spanning the
two, which is the swept region rather than a convex hull that would over-cover
near the pivot. `Enemy.last_hit_swing_id` against a monotonic swing identity
keeps one swing to one hit per body.

Three things settled beyond the ADR, all recorded there or here:

- **No `range` retune was needed.** The ADR's "12px up the screen" cost cancels
  once the blade is tested against a body's *centre* rather than its feet — a
  body's centre sits the same `ACTOR_SIZE.y / 2` above its anchor that the
  weapon pivot sits above the player's. ADR-0026's consequences are corrected.
- **One swing curve for both fire modes.** `melee_swing_angle_offset` is
  normalised over `follow_through_time` rather than the absolute
  `SWORD_SWING_OUT_TIME`/`SWORD_SWING_RETURN_TIME` pair, so a weapon's swing and
  its active window are the same length by construction. Dagger's separate
  linear Follow-through sweep retires with them; its swing now draws back, snaps
  out and eases home like every other blade.
- **The Follow-through tick moved ahead of the Windup block in `update_weapon`.**
  A Semi_Automatic weapon Resolves from inside that block, and ticking a
  freshly-set timer by the same frame's `dt` ate the front of the swing it had
  just started. Both fire modes now agree: the timer is set at the end of a
  frame, and the next frame is the swing's first.

`Arc_Width` repoints to `Melee_Weapon.range` — the minimum that compiles once
`arc_degrees` is deleted. The rename to **Reach** is issue 19's, deliberately
left alone here.

`Melee.attack_range` is now surface-to-surface, which ADR-0026's answer called
for and no ticket had picked up.
