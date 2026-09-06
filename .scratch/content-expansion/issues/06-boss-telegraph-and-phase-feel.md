# Boss telegraph and phase feel

Type: prototype
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

The stage is already decided: [Map ladder shape](03-map-ladder-shape.md) made rung 5's arena deliberately legible — open, simple, few obstructions — precisely so telegraphs can be read. Prototype against that, not against a cluttered arena; if a telegraph only works in open ground, that is the answer working as intended rather than a limitation to design around.

[Boss model](05-boss-model.md) has settled what is being prototyped, and narrowed this ticket considerably:

- **The mechanic is a Tell**, not a Windup — timed in **absolute seconds** ([ADR-0023](../../../docs/adr/0023-enemy-tells-are-absolute-durations.md)), so the duration judged here is the duration authored, not a fraction to be recomputed against a cycle. Comparing against the player's own Windup is still useful as a feel reference, but the two are not the same quantity.
- **A Tell always resolves**, in range or not. A prototype that lets a Tell be cancelled when the player leaves range is testing a different mechanic.
- **Three phases on health thresholds**, and a phase changes **only** the attack rotation and its pacing. `Movement_Style` is fixed for the boss's life and the boss never spawns adds, so those are not available as transition cues — which makes phase legibility a harder and more interesting question here, not an easier one. Colour, pause, burst, and a rotation the player can hear change are what is left.
- **The boss carries a world-space Resource indicator**, so a threshold crossing is visible on the bar. Whether that alone counts as a legible transition is exactly what this prototype answers.
- **The boss is bigger than any enemy today** (`ENEMY_SIZE_MAX` rises), which changes how much screen a telegraph has to cover to read as belonging to it.

Unblocked: [Boss model](05-boss-model.md) is resolved.
