# 09: A Tell-carrying attack style

**What to build:** An enemy can claim an area of ground before it strikes, and
the player can read it and step out. The zone appears at full extent from the
first frame of the Tell — it does not grow — the enemy's body flashes for the
duration, the enemy plants while telegraphing, and the bearing is fixed when
the Tell starts rather than when it resolves, so sidestepping works. The attack
resolves whether or not anything is still standing there, and lands with a
screen shake.

This introduces the ground layer the zone draws into, beneath every actor.

**Blocked by:** 08

**Status:** resolved

- [x] An attack style variant carries a Tell of an authored duration in seconds
- [x] The zone draws at full extent for the whole Tell, on a ground layer beneath actors
- [x] The telegraphing enemy stops moving and flashes
- [x] The bearing is locked at Tell start; walking out of the zone avoids the hit
- [x] The attack resolves at the end of the Tell regardless of what it hits, with screen shake
- [x] Tell duration is unchanged by anything that scales other timings

## Comments

Implemented as the `Tell_Area` Attack Style variant (`enemy.odin`): a rotation
of `Area_Attack`s (`radius`, `reach`, `damage`, `tell_seconds`), cycled on
resolve, per ADR-0023's amendment - so ticket 21 stacks phases on this shape
rather than reshaping it. `update_tell_area` is the pure seam
(`enemy_tell_test.odin`); `update_enemies` applies its tick: plant, shake on
resolve hit or miss, `damage_player` only when the locked disc still covers
the player. The Ground layer is `ground_layer.odin`, called first after
`draw_tilemap`; the body flash is `tell_flash_color` (value only, toward
white - hue stays family, alpha stays health). One Kind carries it now:
**Breaker**, provisionally added to Cold Hall's kill-gated composition so it
is playable before ticket 11 re-authors the roster.
