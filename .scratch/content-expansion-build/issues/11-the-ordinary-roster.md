# 11: The ordinary roster

**What to build:** Eight distinct enemies the player learns to tell apart on
sight and answer differently — a body that crowds, one that shoots, one that
ignores walls, one that charges, one that holds a line, one that claims ground,
a swarm, and one that punishes standing still. Each is authored as a preset, and
each reaches only as far as its own body plus its own reach rather than a single
shared attack range.

**Blocked by:** 08, 09, 10, 05

**Status:** ready-for-agent

- [ ] Eight Kinds are authored, each visually distinct by family hue and size
- [ ] Attack range is per Kind and measured surface to surface
- [ ] The concurrency cap and the body-size clamp rise to what the roster needs
- [ ] The single shared health ceiling is deleted; body size derives from the Kind's own health
- [ ] A test asserts every preset is well-formed: hue matches its movement family, size within the clamp and inflation envelope, sustained speed under the player's unless it is a Charger, payout near the anchor or a named deviation, and every Kind appears in at least one authored composition
