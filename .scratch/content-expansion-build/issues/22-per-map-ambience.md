# 22: Per-Map ambience

**What to build:** Standing still in a Map tells you which Map you are in.
Drifting motes, patches on the floor, and a wash of coloured light give each
place a mood, drawn as part of the world so they sit under the action rather
than over it.

**Blocked by:** 13, 09

**Status:** ready-for-agent

- [ ] Motes, floor patches and a light wash are authored per Map
- [ ] They draw inside the world pass, in their own layers relative to actors
- [ ] They draw from their own budget and cannot starve gameplay effects
- [ ] A Map that authors none of them looks exactly as it does today
