# Boss telegraph and phase feel

Type: prototype
Blocked by: 05
Status: open

## Question

Given the machinery decided by [Boss model](05-boss-model.md), what does a boss attack actually *feel* like?

A HITL prototype question, not an architecture one — how long a telegraph reads for and what it looks like can only be judged in motion.

To answer:

- **Telegraph duration.** Long enough to react to, short enough not to be boring on the tenth repetition. Compare directly against the player's own Windup, which is a fraction of the weapon's cycle rather than a fixed duration.
- **Telegraph form.** The existing vocabulary is pull-back along `aim_dir` for Gun/Magic and an arc pull-back for Melee. A boss telegraphing a ground slam or a sweep has no equivalent yet. Flat shapes and particles are the whole toolkit ([Art revamp](../../art-revamp/map.md)) — no sprites.
- **Phase transition legibility.** How does the player know a phase changed? A colour shift, a pause, a burst, a change in movement? A transition nobody notices is not a phase.
- **Screen feedback.** `shake.odin`'s trauma-decay is available. Whether a boss earns screen shake where ordinary enemies do not is part of this.

Build it cheap and throwaway on a `prototype/` branch, link it from this ticket, and judge it at real gameplay zoom in motion — the standard [Art revamp](../../art-revamp/map.md) set for every visual decision in this codebase.

Blocked by [Boss model](05-boss-model.md).
