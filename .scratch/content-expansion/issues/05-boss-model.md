# Boss model

Type: grilling
Blocked by: 01
Status: open

## Question

Bosses get real machinery — phases and telegraphed attacks — not just a big-statted ordinary enemy. Where does that machinery live?

The type-system question first:

- A **new `Attack_Style` variant** (phases as internal state of the attack)?
- A **flag or tier on `Enemy_Kind`**, if ticket 01 made that a real preset table?
- **Its own type** alongside `Enemy`, given a boss is singular where `game.enemies` is a pool?

Then the mechanics:

- **Phases.** Health-threshold transitions, timed, or positional? What changes across a phase — attack pattern, movement style, spawned adds? Note that swapping `Movement_Style` mid-life is something no enemy does today.
- **Telegraphs.** The codebase already has a telegraph vocabulary in **Windup** — a proportional slice of the action cycle, aim tracked live through it, resolving into a hit whether or not it still lands ([ADR-0004](../../../docs/adr/0004-windup-fraction-not-duration.md), [ADR-0005](../../../docs/adr/0005-ground-targeted-casts-lock-at-trigger.md) for the ground-targeted exception). Do boss telegraphs reuse that machinery, or is a boss attack a different enough animal to need its own?
- **Adds.** If a boss summons, does it go through the Spawn Trigger timeline or spawn directly? `MAX_ENEMIES :: 24` truncates silently, so a boss plus adds can starve itself of slots.

And the two integration questions:

- **Run outcome.** [ADR-0017](../../../docs/adr/0017-run-outcome-and-map-objective.md) derives Cleared from the Spawn Trigger timeline being exhausted *and* no enemies alive — deliberately not from an authored kill quota, because `MAX_ENEMIES` truncation makes quotas unreachable. A boss must be expressible in that frame, or the frame has to change.
- **Health readout.** [ADR-0011](../../../docs/adr/0011-in-game-hud-moves-to-world-space-resource-indicators.md) put every entity's health in a world-space, fraction-only Resource indicator above it, with no screen-space bars anywhere. A boss health bar is the classic exception to that rule. Decide whether to grant it, and if so, why this case is special rather than the start of the bars coming back.

[Map ladder shape](03-map-ladder-shape.md) has placed the boss: **rung 5 of five, and the only boss on the ladder** — so this ticket authors one, not a family. It also fixed that rung's arena as deliberately **legible** (open, simple, few obstructions), geometry escalation stopping short of the boss so telegraphs have room to read. The `time_limit` frame is unchanged and tight there: ~30s of mop-up slack past the timeline's natural end, so a boss that lingers after its adds are dead eats that slack directly.

Blocked by [Enemy variety model](01-enemy-variety-model.md).
