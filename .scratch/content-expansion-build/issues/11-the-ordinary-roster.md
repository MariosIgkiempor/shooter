# 11: The ordinary roster

**What to build:** Eight distinct enemies the player learns to tell apart on
sight and answer differently — a body that crowds, one that shoots, one that
ignores walls, one that charges, one that holds a line, one that claims ground,
a swarm, and one that punishes standing still. Each is authored as a preset, and
each reaches only as far as its own body plus its own reach rather than a single
shared attack range.

**Blocked by:** 08, 09, 10, 05

**Status:** resolved

- [x] Eight Kinds are authored, each visually distinct by family hue and size
- [x] Attack range is per Kind and measured surface to surface
- [x] The concurrency cap and the body-size clamp rise to what the roster needs
- [x] The single shared health ceiling is deleted; body size derives from the Kind's own health
- [x] A test asserts every preset is well-formed: hue matches its movement family, size within the clamp and inflation envelope, sustained speed under the player's unless it is a Charger, payout near the anchor or a named deviation, and every Kind appears in at least one authored composition

## Comments

Most of this ticket had already landed under 08/09/10: seven of the eight
Kinds, the five family hue constants, and `ENEMY_MAX_HEALTH`'s deletion
(commit `c87074c`, with ticket 08 - body size has derived from the Kind's own
`max_health` since). What this ticket adds:

**Sentry** is the eighth Kind - Inert (nil movement) / Ranged, 70 health
(30px), `ENEMY_INERT_COLOR`, 35 Gold. The one answer on the roster that is
neither kiting nor dodging: it holds a line, so the player crosses open
ground to clear it. Its band has no floor (`min_range = 0`, since an Inert
body cannot retreat) and a 200px ceiling so a player approaching from the
edge of view is already under fire - playtest numbers. It sits in the enum
between Lancer and Breaker, in rung order; persistence is by name so the
insertion renumbers nothing. Provisionally on Cold Hall's kill-gated wave
beside the Breaker and Lancer, the placement 09/10 set, until ticket 17
re-authors the timelines.

**Reach is per body.** `update_enemies`' Melee case subtracted a flat
`ACTOR_SIZE.x` - both bodies assumed 24px - so a 46px Breaker's reach
landed short of its own drawn edge and a 16px Mite's landed from a gap.
`melee_contact_distance` is now the one arithmetic: half the player's body,
half the enemy's own drawn body, then the Kind's authored `attack_range`
past that surface. `charger_lane_half_width`, `swarmer_surround_radius`
(now handed the `Enemy`) and the F8 attack-range ring all read it, so the
lane, the ring and the overlay agree with the hit. `attack_range` is
authored per Kind for the first time - Grunt 10, Wraith 12, Lancer 14,
Mite 8 - as playtest starting points. Collision stays `ACTOR_SIZE`; the
reach is measured from what the player sees.

**Spitter and Gazer are pale.** Two new constants
(`ENEMY_GROUNDED_PALE_COLOR`, `ENEMY_FLOATER_PALE_COLOR`) keep their family
hue inside the test's tolerance and lift the value, so the light cousin
reads as lighter rather than as a sixth family.

**Cap and clamp.** `MAX_ENEMIES` 24 -> 4096 and its Tunable slider to match:
a safety rail, not a budget (CONTEXT.md's Run outcome entry and ADR-0020's
amendment say so). `ENEMY_SIZE_MAX` 48 -> 72 for the Warden; the 48px
one-tile envelope is now enforced on ordinary Kinds by the test below rather
than by the clamp. The stale unused `ENEMY_SIZE: i32 = 12` is deleted.

**The rulebook.** Five tests in `enemy_preset_test.odin`, each mutation-
verified to fail on exactly its own rule: body size unclamped and within
the inflation envelope (derived from `FLOW_FIELD_INFLATION_RADIUS` and the
smallest baked tile size); sustained speed under `PLAYER_BASE_MOVE_SPEED`
for every Kind including the Charger's approach; payout within 3 Gold of
0.6 x max health unless named (Sentry below, Lancer above, Mite far below -
and a named Kind must actually deviate, so the list cannot rot); every Kind
in at least one baked composition with a positive count; and at least one
Inert Kind. Hue-per-family, the Charger speed rule and Tell rotations were
already pinned. Full suite: 302 passing.

**Review.** Both axes of `/code-review` ran against the diff. Acted on: a
stale F8 overlay comment; the payout test was direction-blind (a named
"below" Kind retuned above the anchor still passed - it now checks the
direction); a tautological lower half of the clamp check; the sustained-
speed clause is pinned to the catalog's 70 ceiling rather than merely
under the player's 100, with the ceiling itself pinned under the player;
`movement_sustained_speed` and `ENEMY_GOLD_PER_MAX_HEALTH` moved into
`enemy.odin` so the rule presets are authored against lives beside them
(ticket 12's Presets mode will want both); the Charger test no longer
duplicates the roster-wide sustained clause; ADR-0020's amendment names the
flow field as the envelope's mechanism. Noted, not changed: a Melee
Lancer's lane widens from 34 to ~40px half-width under the new arithmetic
(the lane cannot be narrower than what it delivers), which trims the dodge
window by ~0.05s - a `tell_seconds` retune is a playtest call.

Not verified at the keyboard: Cold Hall at 12 kills spawns a cyan Sentry;
the F8 Movement Styles overlay should show the Mite ring at contact
distance rather than hugging the player.
