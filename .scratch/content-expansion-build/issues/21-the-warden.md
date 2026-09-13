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

