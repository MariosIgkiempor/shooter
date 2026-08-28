# Account Progression Rework

Label: wayfinder:map

## Destination

An implementation-ready design spec for retiring the permanent Class lock. Any weapon can be chosen as a fresh starter each Run, upgraded in-Run via the existing per-family Weapon tier ladder plus Run-scoped `Upgrade_Kind` stats, funded by Gold — exactly as today, minus the permanent account-level lock. At Run end (death), kills (per-Enemy-kind weighted, built extensibly even though only one `Enemy` kind exists today) plus survival time plus Gold earned convert to XP, spent between Runs on a new, permanent `Account_Stat` taxonomy — Vigor (Max Health), Might (Damage), Swiftness (Move Speed), Fortune (Gold-gain rate) — layered under the existing recompute-not-mutate Upgrade model ([ADR-0007](../../docs/adr/0007-upgrade-stacks-recomputed-not-mutated.md)) rather than replacing it. The real-time XP-orb pickup and the mid-run "Level Up → Continue" stub are removed entirely, replaced by a new end-of-Run summary + `Account_Stat`-spend screen. "Done" means a build session could implement this directly with no open design questions left — this map produces the spec (CONTEXT.md updates, a superseding/amending ADR pair, a fully resolved ticket list), not code.

## Notes

- Vocabulary is settled in [CONTEXT.md](../../CONTEXT.md): **Weapon family** (renamed from Class), **Weapon tier ladder**, **Gold**, **Shop**, **Upgrade**, **Run**, **Account progression**, **Account_Stat**. Read it before resolving any ticket.
- [ADR-0002](../../docs/adr/0002-class-locked-weapon-acquisition.md) (class-locked-weapon-acquisition) is superseded by [ADR-0008](../../docs/adr/0008-weapon-family-is-run-scoped.md). [ADR-0006](../../docs/adr/0006-gold-shop-run-progression-xp-account-progression.md) (gold-shop-run-progression / xp-account-progression) is amended by [ADR-0009](../../docs/adr/0009-xp-is-a-run-end-grant.md) for the XP mechanism change — its Run-vs-Account split itself stands unchanged.
- This map builds on, and does not reopen, mechanism already locked by the `.scratch/shop-and-upgrades/` map: the Shop is an on-demand pausing panel; the Weapon tier ladder is a fixed sequential per-family order; buying the next tier discards the old weapon outright and reapplies Upgrade stacks via `apply_upgrades`; Gold is a `Pickup_Kind.Gold` drop via the existing pickup-roll machinery. Only the *permanent* Class lock (ADR-0002) is being reopened — the tier-ladder and Shop mechanics themselves are not.
- This map is a **spec to hand off**, not execution — tickets decide, they don't implement. Default wayfinder behavior applies, not overridden.
- Grilling tickets: call the Skill tool twice, for "grilling" and "domain-modeling" (new vocabulary — `Account_Stat`, Vigor/Might/Swiftness/Fortune — should land in CONTEXT.md as it's coined or refined). Ticket 01 (prototype): call the Skill tool for "prototype".

## Decisions so far

- [Run-start and run-end screens](issues/01-run-start-and-run-end-screens.md): Variant A wins both new screens — the weapon picker is three columns by family (Ranged/Melee/Magic), the end-of-Run screen is two-column (Run summary + Account Level/XP bar left, `Account_Stat` spend list right). Picking a starter weapon proceeds to the existing map-selection screen, not straight into the Run. Spending earned XP on `Account_Stat`s is optional — Continue is never blocked on unspent XP, which banks indefinitely.
- [XP formula and Account_Stat pricing](issues/02-xp-formula-and-account-stat-pricing.md): end-of-Run XP is a weighted sum of kills (via a per-`Enemy_Kind` `{ base_xp, xp_multiplier }` lookup) + survival time + Gold earned (discounted weight, since Gold partly derives from kills already). `Account_Stat` purchases use the same geometric pricing mechanism as `Upgrade_Preset` but with gentler growth and no `max_stack` cap; all four stats are `Multiplicative`.
- [Save-data and program-mode flow](issues/03-save-data-and-program-mode-flow.md): Class retires as a domain term, replaced by Run-scoped **Weapon family** ([ADR-0008](../../docs/adr/0008-weapon-family-is-run-scoped.md)); family-specific Upgrade slots re-gate on the equipped weapon instead of a persistent field. The old Game Over screen is fully retired in favor of the Run End screen. `ProgramMode.Choosing_Class` is replaced by `Run_Start`, entered uniformly at first launch and after every death, followed by `Selecting` (map) then `Playing`. Save data gets a clean reset, no migration path ([ADR-0009](../../docs/adr/0009-xp-is-a-run-end-grant.md)).

**Last open ticket — the map's route is clear.** [ADR-0008](../../docs/adr/0008-weapon-family-is-run-scoped.md) (supersedes ADR-0002) and [ADR-0009](../../docs/adr/0009-xp-is-a-run-end-grant.md) (amends ADR-0006) are written; [CONTEXT.md](../../CONTEXT.md)'s Weapon family (renamed from Class), Gold, Shop, Weapon tier ladder, Upgrade, Run, and Account progression entries are all updated to match.

## Not yet specified

- Exact numeric values — `base_xp`/`xp_multiplier` for the one `Enemy_Kind` today, the relative weights of the three XP-formula terms, and `Account_Stat` `base_price`/`price_growth` — balance/content-authoring, not a design branch. Left for the implementation session, same as the equivalent gap in `.scratch/shop-and-upgrades/`.

## Out of scope

- New `Enemy_Kind` content/variety — ruled out explicitly during grilling; only the extensible per-kind XP data model is in scope this effort.
- "Insight" (a permanent XP-gain-rate `Account_Stat`) — declined for balance risk (a stat that accelerates its own currency).
- Wave/depth-reached as an XP-formula factor — declined for now; kills, survival time, and Gold earned are the formula's only inputs.
