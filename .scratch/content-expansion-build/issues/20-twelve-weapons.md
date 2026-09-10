# 20: Twelve weapons

**What to build:** Four weapons per family, four rungs of a ladder each, so a
Run's weapon choice keeps mattering into its late Shop. The new arrivals each
answer something the roster does: a piercing rifle for lines of bodies, a spear
that outranges what closes on you, a greatsword that trades speed for a wide
sweep, and a lightning staff that hits instantly at range. Run Start offers one
free weapon per family — the bottom of each ladder — so the free pick is never
also a paid destination.

**Blocked by:** 18, 19, 02

**Status:** resolved

- [x] Twelve weapon kinds exist, four per family, each with an icon and a hit volume
- [x] The rifle pierces, tracking which bodies a shot has already hit
- [x] The lightning staff resolves instantly along its line rather than travelling
- [x] Run Start offers exactly one weapon per family, the first of its ladder
- [x] One family-to-weapons list has one reader; the Shop ladder and Run Start agree
- [x] The number-key weapon hotkey is retired

## Comments

**Implemented.** Seven commits, each independently green: the pierce machinery
and the ladder cleanup landed before any new kind existed, so each was
reviewable against the roster of eight rather than tangled with content.

**The hotkey in the last box is the arrow-key one, not a number-key one.**
There has never been a number-key weapon hotkey in this codebase. The dev
hotkey was `cycle_weapon_kind` on LEFT/RIGHT (`weapon.odin`, `main.odin`),
which is what issue 09 and the shop map both name. It is gone, along with the
comment claiming `weapon_family_kinds` was "only a cycle order for that debug
tool". Net capability change is zero: F8's Add 500 Gold plus TAB's Shop reaches
every non-tier-0 weapon of the equipped family in a running game (the whole
Ranged ladder is 774 Gold, two clicks), and crossing *families* still needs a
fresh Run - which was true of the arrow cycle too, since it never crossed one.

**One list, one reading.** `weapon_family_kinds` keeps being the single table,
but `weapon_tier_index`/`weapon_next_tier` moved out of `shop.odin` to sit
beside it, and a named `weapon_family_starter` replaced every
`weapon_family_kinds[family][0]` at a call site - that expression appearing
anywhere *is* the ladder being read as a menu. weapon.odin now owns what the
ladder is, shop.odin owns what it costs. `draw_shop_weapon_ladder` needed no
change at all, so "the Shop and Run Start agree" is structural rather than
coincidental.

`weapon_family_kinds` is the one per-kind table Odin will not catch you leaving
incomplete - it is keyed by `Weapon_Family`, not `Weapon_Kind`, so a new kind
missing from it compiles clean, is unreachable, and quietly falls back to tier
0 in `weapon_tier_index`. Three tests stand in for that missing compile error.

**Pierce is tracked by shot identity.** A monotonic `Bullet.id` against
`Enemy.last_hit_bullet_id`, one u32 compare placed *ahead* of the rect test
because a shot overlaps a 24px body for three or four frames. Its own id space,
not one shared with swings (ADR-0026). The sharp edge is that 0 is the "no shot
has hit me" value every fresh Enemy carries, so an unstamped Bullet would find
the whole world already stamped and pass through it touching nothing - fixed
structurally by making `spawn_bullet` the one place a Bullet enters the world,
rather than by vigilance. `fire_pellets` claims an id *inside* its pellet loop,
so a volley's pellets pierce independently for free. Walls still stop a shot: a
pierce buys bodies, not terrain.

**The bolt.** Reuses `Magic.range` rather than adding a field - `range` already
means "px this spell reaches from the caster" for the Flamethrower, so
`apply_magic_range_upgrade` folds the two into one arm rather than gaining a
second that could drift. Walls clip the line *before* bodies are ranked;
ranking first would let a bolt pick a target through terrain and merely draw
itself short of it. Nothing persists past the cast - the whole visual is a
chain of ~0.07s streak particles laid along the segment in one call. The one
concession: a `Particle_Streak` takes its orientation from its own velocity, so
a perfectly stationary segment would draw horizontal whatever direction the
shot went, hence a sub-pixel drift speed.

**ADR-0026's "a near-zero arc is a thrust" is true of the hit-check and false
of the animation.** `melee_swing_angle_offset(0, p)` is 0 for every `p`, and
`draw_weapon` displaces the pivot along `aim_dir` for Gun and Magic only, so a
0-degree Spear would sit perfectly still for its whole Follow-through. Authored
at 18 degrees instead, which moves the head ~27px and reads as a jab. If it
still reads flat in motion the fix is a melee thrust displacement in
`draw_weapon`/`weapon_pose_frame` - real new machinery, and not this ticket's.

**Two glyphs were wrong in ways no assertion could see**, caught by rendering
the authored unit-space geometry out to look at. The Lightning Staff's facets
pointed backwards - both triangles widest at 0.86, converging on the rod - so
the one glyph whose whole job is to say "this one is not throwing an area" read
as an arrow pointing away from the aim. And the Greatsword at 0.48 across was a
wedge filling its own frame rather than a blade, with a second crossguard made
invisible by sitting under the blade it was meant to be countable against. Both
fixed; the Hit volume followed the blade.

**Numbers, and what pins them.** Every new tier is deliberately *worse* than
something below it at one thing: the Rifle is the worst gun in its family
against a single body (64 DPS against the Pistol's 75) and unmatched against a
line of four (256); the Greatsword has the lowest single-target DPS on the
roster (49.5) and the widest sweep; the Spear out-reaches and out-DPSes the
Greatsword on one body and is the worst weapon in the family against a crowd.
Two numbers are not free:

- The Rifle's `clip_size = 5` is the floor
  `test_every_clip_size_stack_grows_every_gun_s_clip` allows. At 4 the second
  Clip_Size stack rounds back to 5 and the player pays for nothing - exactly
  the guardrail issue 19 left behind for this weapon.
- The Greatsword's 140 degrees / 0.26s is picked against ADR-0026's chord
  bound, not rounded: at 150/0.24 the opening frame turns 66.8 degrees,
  under-covering the arc's outside by 13.2px against a 12px body radius.

The Lightning Staff's 78 DPS is ~4.2 casts and ~2.9s of *perfect* uptime
against a 220-health boss. The arithmetic is recorded on the preset for issue
21, which should author the Warden's health and phase thresholds against the
whole roster rather than against this one weapon - at 10 Damage stacks nothing
in the catalog leaves a 220-health boss alive for three phases.

**Two deviations from the design ticket's letter, both deliberate.**

- **The Greatsword's countable axis is a second crossguard, not "blade count".**
  Issue 08 named Melee's new axes as "haft length and blade count - the Spear a
  long haft with a short head, the Greatsword a **double-width blade**". The
  Spear's haft is as specified. The Greatsword's width alone is precisely the
  proportional distinction ADR-0018 forbids ("a 20px rod and a 24px rod are
  indistinguishable with nothing alongside them"), so the countable mark is two
  crossguards against the Sword's one, with the blade at 0.34 against 0.24 as
  the thing that reads at a glance. Double width was tried first and produced a
  wedge filling its own frame, not a blade.
- **Magic's `range` tuning bound widened from 150 to 300 for both spells**, not
  just the bolt - the registry's rule is one range per *field*, not per
  field-per-kind, so the Flamethrower's slider got coarser. It is the only
  change in the branch that reaches an untouched weapon.

**Found in review.** `segment_first_wall_hit` marched `travelled <= length` and
never sampled the segment's far end. The half-tile stride already covers any
wall the line passes *through*; what escaped was a wall the line merely ends
*inside* - the last sample can sit ~11px short of a tile edge with the endpoint
1px past it, and a Range stack moves the bolt's length off every step multiple,
so it was reachable the moment a player bought one. The far end is now tested
separately, pinned by a test that fails against the old loop.

Also corrected in review: CONTEXT.md's **Windup** entry enumerates the weapons
that track aim live "(Gun, Melee_Weapon, Fireball, Flamethrower)", and
`Lightning_Bolt` belongs in that list - leaving it out read as ADR-0005
lock-at-Trigger behaviour, which is not what `cast_lightning_bolt` does. That
is a correction to a now-false existing entry rather than one of the new
entries ruled out below. ADR-0020's "two constants cannot be Tunables" is
likewise now three.

**Left standing, flagged not fixed:** ADR-0026's claim that a near-zero arc
needs no machinery of its own, and its 50-90px Greatsword tunnelling figure
which the preset's own chord arithmetic supersedes. The branch's precedent is
to amend (ADR-0008 carries one), so this is the obvious follow-up.

**Out of scope by decision:** CONTEXT.md glossary entries for Pierce and Bolt,
and an ADR-0026 amendment recording the second id space. ADR-0008's amendment
and CONTEXT.md's Weapon tier ladder entry already carried the tier-0-only rule,
so neither needed touching.
