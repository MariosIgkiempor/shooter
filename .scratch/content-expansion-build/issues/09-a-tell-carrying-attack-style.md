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

**Status:** ready-for-agent

- [ ] An attack style variant carries a Tell of an authored duration in seconds
- [ ] The zone draws at full extent for the whole Tell, on a ground layer beneath actors
- [ ] The telegraphing enemy stops moving and flashes
- [ ] The bearing is locked at Tell start; walking out of the zone avoids the hit
- [ ] The attack resolves at the end of the Tell regardless of what it hits, with screen shake
- [ ] Tell duration is unchanged by anything that scales other timings
