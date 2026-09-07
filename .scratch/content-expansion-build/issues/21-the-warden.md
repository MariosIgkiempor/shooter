# 21: The Warden

**What to build:** A final fight that ends a Run rather than another wave. The
Warden is one body with far more health than anything else, occupying a reserved
slot so the wave cap cannot crowd it out; it cycles a rotation of telegraphed
attacks and changes that rotation as its health falls, so the fight has three
recognisable stretches. Its health is shown, its bulk pushes the field out
around it so smaller enemies path around rather than through it, and killing it
always drops.

**Blocked by:** 09, 11, 04

**Status:** ready-for-agent

- [ ] A boss Kind with three phases entered at authored health thresholds
- [ ] Each phase is a rotation of Tell-carrying attacks; the rotation lives inside the Tell variant rather than a parallel system
- [ ] Its health reads at a glance while fighting
- [ ] It holds a reserved slot against the concurrency cap
- [ ] The field treats it as an obstacle at its own radius
- [ ] Its drop is guaranteed, authored as a preset field rather than a special case
