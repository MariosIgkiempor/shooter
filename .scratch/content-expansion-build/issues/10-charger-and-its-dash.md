# 10: Charger and its dash

**What to build:** The first enemy that can catch a running player. A Charger
telegraphs a straight lane, then crosses it faster than the player can run,
travelling a bounded distance and stopping — so the counter is to move out of
the lane during the Tell, not to outrun it.

**Blocked by:** 09, 04

**Status:** resolved

- [x] A movement style that telegraphs a lane, then dashes along it
- [x] The lane is locked when the Tell starts and the dash covers a bounded distance
- [x] The dash speed exceeds the player's run speed; sustained speed between dashes does not
- [x] The lane telegraph uses the same Tell vocabulary as the area attack

## Comments

Implemented as the `Charger` Movement Style variant (`enemy.odin`): authored
`speed` / `dash_speed` / `dash_distance` / `tell_seconds` /
`recovery_seconds` / `cooldown_seconds`, runtime `phase` (Approaching,
Telling, Dashing, Recovering) plus the LOCKed `lane_origin` / `lane_dir`.
`update_charger` is the pure seam (`enemy_charger_test.odin`): it is handed
the approach direction - Grounded's field chase plus Separation - and never
reads `game` or the field itself, so the dash ignores both by construction.
A Tell starts when the player is within `dash_distance`; between the LOCK
and the dash's end nothing reads the player.

**The dash carries no damage.** The Kind's Attack Style lands when the dash
brings it into contact, so the variant spends no Attack Style slot, as the
catalog decided. That needed one change in `update_enemies`: Melee's "hold
your ground with the player in reach" no longer zeroes a committed
Charger's delta, or the dash would have stopped on the frame it arrived.

**A wall ends the dash.** `move_actor` now returns `blocked`
(`move_actor_test.odin`); `update_enemies` reads it only for a Dashing
Charger and sends it straight to recovery (`charger_end_dash`). A slide
along a wall counts as blocked, so a shallow-angle dash that grazes a wall
also stops - accepted, since a wall is meant to be baitable.

**The lane's width is derived, not authored.** `charger_lane_half_width` is
`ACTOR_SIZE.x + Melee.attack_range` - the perpendicular offset at which a
passing body's contact test lands, the same arithmetic `update_enemies`'
Melee case runs - so the ground shows the danger rather than the body. A
Charger with no contact attack claims its own body width. The lane is drawn
in `ground_layer.odin` with the disc's `TELL_ZONE_*` colour and alphas;
`draw_enemy` reads either Tell through one `enemy_tell_progress`, so the
body flash is shared verbatim.

**Lancer** is the first Kind to carry it (Charger 55 / dash 260 over 140px,
0.5s Tell; Melee; 60 health; red; 50 Gold), provisionally on Cold Hall's
kill-gated composition beside the Breaker until ticket 11 re-authors the
roster. `enemy_preset_test.odin` pins the speed rule: every Charger's
`speed` is below `PLAYER_BASE_MOVE_SPEED` and its `dash_speed` above it.
`ENEMY_CHARGER_COLOR` is the red the palette had reserved; the
hue-separation test now walks every pair of the five families.

Not verified at the keyboard: the lane's look in motion. Cold Hall at 12
kills spawns a Lancer; F8's Movement Styles overlay draws its
`dash_distance` ring.
