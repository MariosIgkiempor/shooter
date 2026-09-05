# Relics

Label: wayfinder:map

## Destination

A permanent Account-scoped progression axis whose purchases are *abilities* rather than stat coefficients — things that exist in the world and act on their own, every frame, without the player triggering them. Three were proposed: an orbiting damage orb, a directional shield, and a companion that deals damage passively. "Done" means the axis exists end-to-end (data model, purchase UI, persistence, tests) with at least one ability shipped on it.

**Shipped**: the axis plus the Orbiting Orb. The Shield and the Pet are deferred with their blocking work named below.

## Notes

- Vocabulary is settled in [CONTEXT.md](../../CONTEXT.md): **Relic**, and the existing **Account progression** / **Account_Stat** / **Gold** entries it sits alongside. Read it before resolving any ticket. [ADR-0019](../../docs/adr/0019-relics-are-a-parallel-account-axis.md) records why a Relic is its own axis rather than a widened `Account_Stat`.
- "Powerup" was the word this effort started from and is **not** the term: `CONTEXT.md`'s `_Avoid_` lines are enforceable (see `docs/agents/domain.md`), and the glossary already avoids "perk" and "meta progression" for the neighbouring concepts.
- A Relic reuses `Account_Stat`'s whole purchase mechanism (geometric price, hard `max_stack`, Account-Level `unlock_level`, same wallet, same Main Menu panel). Only the `effect` field is not reused — that field is the thing that could not express an ability. This is not reopened as a ticket.
- Two existing precedents carried the implementation: `Poison_Cloud` ([poison_cloud.odin](../../poison_cloud.odin)) for a player-owned, autonomously-ticking, repeating-tick damage source, and `assign_swarmer_slots` ([enemy.odin](../../enemy.odin)) for the only ring/orbit maths in the repo.
- All prices, radii, speeds and damage figures are placeholder content-authoring, exactly as with `upgrade_presets` and `account_stat_presets`.

## Decisions so far

- [Relic axis and the first ability](issues/01-relic-axis-and-first-ability.md): the concept is a **Relic**, not a powerup; it is a parallel axis (`Relic_Kind` + `relic_presets` + `Player.relic_stacks`) rather than a widened `Account_Stat`, because `Account_Stat_Preset.effect` is a bare `Multiplicative` and an ability is not a number; purchases are a **stacking ladder with a low cap**, where a stack buys a whole further instance of the ability (a second orb) rather than scaling the one; scope was cut to **the axis plus the Orbiting Orb**; the Shield is to rotate **independently of the mouse**, and needs `damage_player(amount, source_pos)` first. See [ADR-0019](../../docs/adr/0019-relics-are-a-parallel-account-axis.md).

## Not yet specified

- **Chasing Shield.** Blocked on a mitigation seam that does not exist: `damage_player(amount)` ([main.odin](../../main.odin)) has no idea where a hit came from, so a directional block requires widening it to carry the source position. Both callers ([bullet.odin](../../bullet.odin)'s enemy-bullet hit and [enemy.odin](../../enemy.odin)'s Melee contact) already have one to pass. That seam is also what i-frames and flat damage reduction would want, so it is worth landing on its own terms. Decided already: the shield rotates independently rather than tracking the mouse — a shield welded to the crosshair sits between the player and everything they are shooting at, which is not a shield but near-invulnerability.
- **Pet.** Needs target selection and steering, neither of which any player-owned entity has yet; the closest existing behaviour is `Enemy`'s `Movement_Style`, which is built to chase the player rather than to follow them.
- Balance for the Orbiting Orb: price ladder, orbit radius and angular speed, tick rate, and base damage are all first-pass figures that want a tuning pass against the running game.
- Whether a Relic should be visible anywhere other than the Main Menu — a Run End receipt line, or a Shop readout — is unaddressed.

## Out of scope

- Making Relics Run-scoped, purchasable mid-Run, or droppable. They are Account progression, bought between Runs on the Main Menu, and survive `start_new_run` exactly as Gold/Level/`Account_Stat` stacks do.
- Player-triggered abilities with cooldowns or a resource cost. A Relic is always-on by definition; an activated ability would be a different concept needing its own name and its own input handling.
- A second currency, or any mana/stamina economy — standing out-of-scope calls from the shop-and-upgrades map, unaffected by this effort.
