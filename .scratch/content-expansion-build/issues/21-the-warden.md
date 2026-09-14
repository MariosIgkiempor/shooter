# 21: The Warden

**What to build:** A final fight that ends a Run rather than another wave. The
Warden is one body with far more health than anything else, occupying a reserved
slot so the wave cap cannot crowd it out; it cycles a rotation of telegraphed
attacks and changes that rotation as its health falls, so the fight has three
recognisable stretches. Its health is shown, its bulk pushes the field out
around it so smaller enemies path around rather than through it, and killing it
always drops.

**Blocked by:** 09, 11, 04

**Status:** ready-for-human

- [x] A boss Kind with three phases entered at authored health thresholds
- [x] Each phase is a rotation of Tell-carrying attacks; the rotation lives inside the Tell variant rather than a parallel system
- [x] Its health reads at a glance while fighting
- [x] It holds a reserved slot against the concurrency cap
- [x] The field treats it as an obstacle at its own radius
- [x] Its drop is guaranteed, authored as a preset field rather than a special case

## Comments

Ticket 17 authored rung 5 as `data/maps/pale_keep.json` without a Warden to
place. Its second Spawn Trigger — Breaker ×2, `Time_Elapsed` 15 s, repeating
every 30 s for 150 s — is the stand-in for the boss and is the line this
ticket replaces (a `One_Shot` Warden, most likely). The thin Grunt/Mite adds
on the first trigger are the "adds thin enough to leave slots for it" the
ladder brief asks for, and are the whole of the rest of the timeline. The
Keep's wall (`[160, 156, 148]`) was kept off near-white so the Warden's own
value stays unclaimed. The `time_limit` (210 s) was set as 30 s past that
stand-in timeline's end; re-derive it once the Warden's own timeline exists.


Implemented on `claude/warden-content-expansion-4f557c`.

**The shape.** `Tell_Area` is now `phases: [3]Tell_Phase` + `phase_count`,
each phase an entry threshold (`enter_below`, ignored on phase 0), a
rotation and its own `cooldown_seconds`; the ordinary roster authors one
phase. A phase advance happens in `update_tell_area` only while no Tell is
running (the committed Tell resolves first, ADR-0023), walks every
threshold the body has fallen below in one tick, never goes back, restarts
the new rotation from its head and keeps the recovery still owed. The health
fraction is a parameter, so the machine stays pure and its tests stay
unpinned.

**One flag.** `Enemy_Preset.boss` drives the reserved slot
(`fire_spawn_composition` caps an ordinary Kind at `MAX_ENEMIES -
ENEMY_BOSS_RESERVED_SLOTS`, per entry, so a Boss behind a full batch still
spawns), the Health indicator, the guaranteed Gold drop, the obstacle stamp
and the Boss's own field. Radii stay derived from `max_health`.

**Two fields.** The shared field takes `[]Flow_Obstacle` and stamps each as
`inflated` ground (never `collides` - move_actor must not stop the Boss on
its own body) grown by the field's radius, re-flooding only when the body
crosses a cell. Since the Boss cannot read a field it is stamped into,
`game.boss_flow_field` is ensured while one is alive at
`flow_field_radius_for_body` (2 for 72px on 16px tiles - the inverse of the
preset test's envelope formula). This is the keying ticket 04 deferred here
and what ADR-0025 already described.

**Pale Keep.** The Breaker stand-in is replaced by a `One_Shot` Warden at
`Time_Elapsed 0`, placed first so it fires ahead of the adds on the same
frame. The timeline's earliest end was always the adds trigger (0 + 180 s),
so `time_limit` re-derives to 210 unchanged.

**Flash on a near-white body.** `tell_flash_color` lerped toward white,
which left the Warden's body unchanged through its Tells; a body above
`TELL_FLASH_LIGHT_BODY_LUMA` now swings toward dark instead.

**Review findings left open.** (1) The stamp is `inflated`, not solid, so when
the player stands inside the Warden's disc (any melee exchange, the 30px-
reach slam) the flood walks out through it and adds on the far side route
through the Boss for those frames - the price of the source-under-obstacle
rule the field needs to keep flooding at all. (2) The Warden's spawn point
is tested against the shared radius-1 field, since its own does not exist
until it does; on an open court that never matters. (3) The phase notches
on the bar and the `LITERAL` colour swatch in Presets mode were not asked
for - both are one line to remove. (4) `Player.kills` is indexed by
`Enemy_Kind` and persisted positionally, an ordinal contract ADR-0028
rejects; the Warden is appended last and the hazard is now named on the
enum rather than fixed.

**Balance caveat, not fixed here.** 220 health is pinned by size derivation
(`ENEMY_SIZE_MAX` = 72 allows ≤ 221), and a bare Pistol is 75 DPS - the
Warden dies in ~3 s of sustained fire. Phase legibility therefore depends on
the adds forcing the player off it. Raising health means raising
`ENEMY_SIZE_MAX` (and re-deriving the boss field radius), which is a content
decision for play, not this ticket.
