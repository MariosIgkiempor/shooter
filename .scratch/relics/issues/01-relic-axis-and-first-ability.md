Type: grilling
Status: resolved

## Question

Some Account-level purchases should be passive abilities rather than stat coefficients. Proposed: a rotating damage orb (Vampire Survivors' King Bible), a shield covering one direction (possibly chasing the mouse), and a "pet" that deals damage passively.

Settle, before any code:

- **What the concept is called.** "Powerup" is not a term this repo uses, and the glossary avoids "perk" and "meta progression" for the neighbouring concepts.
- **Where it lives in the data model.** `Account_Stat_Preset.effect` is a bare `Multiplicative` ([account_progression.odin](../../../account_progression.odin)) and `apply_account_stat_effect` is one `math.pow` over an `f32` base — is an ability a new `Account_Stat` member, a widening of that field, or its own axis?
- **The purchase shape.** One-off unlock, or a stacking ladder like `Account_Stat`'s (`max_stack` + geometric `price_growth` + `unlock_level`)? If stacking, what does a second stack buy?
- **Scope.** All three abilities, or a subset — and if a subset, which, and what blocks the rest?
- **The shield specifically.** There is no damage mitigation anywhere in the codebase: `damage_player(amount)` takes an amount and nothing else, so it cannot tell which direction a hit came from. And a shield that tracks the mouse sits between the player and everything they are aiming at.

## Answer

Locked via grilling:

**Name: Relic.** Recorded in [CONTEXT.md](../../../CONTEXT.md) as the permanent *behavioural* taxonomy Account progression's Gold buys into — the sibling of `Account_Stat`'s permanent *numeric* one. `_Avoid_: Powerup, Passive, Ability, Perk, Artifact, Item`. "Ability" is avoided specifically because it implies something the player triggers, and a Relic never is.

**Its own axis, not a widened `Account_Stat`.** `Relic_Kind` + `relic_presets` + `Player.relic_stacks`, in [relic.odin](../../../relic.odin). `Relic_Preset` is `Account_Stat_Preset` minus `effect`: the whole purchase mechanism is reused (geometric price, hard `max_stack`, Account-Level `unlock_level`, same wallet, same Main Menu panel, same three row states), and only the field that cannot express an ability is dropped. Rationale and the two rejected alternatives — widening `effect` into a union, and a `proc` field on the preset — are in [ADR-0019](../../../docs/adr/0019-relics-are-a-parallel-account-axis.md).

**Stacking ladder, low cap, where a stack buys a whole further instance.** The Orbiting Orb caps at 4 and grows at 1.35 per stack, against every `Account_Stat`'s 10 and 1.15: a stack adds a second orb rather than five percent of a stat, so matching `Account_Stat`'s growth would make a Relic strictly the best Gold sink in the game.

**No recompute step.** A Relic's live effect is derived from `relic_stacks` every frame rather than applied onto a mutable copy, so unlike `try_buy_account_stat` there is nothing to re-derive after a purchase. This reaches [ADR-0007](../../../docs/adr/0007-upgrade-stacks-recomputed-not-mutated.md)'s discipline by having nothing that could drift. Only transient runtime (orbit phase, tick timer) is stored, in `game.relic_state`, tagged `json:"-"`.

**Scope: the axis plus the Orbiting Orb.** A ring of orbs circling the player's mid-body, damaging every enemy an orb overlaps on a repeating tick — the same repeating-tick shape as a `Poison_Cloud`'s DoT, not a single hit on entry, so an enemy caught by two orbs on one tick takes two hits. Scaled by **Might** (Account progression's Damage stat) but not by the Run-scoped Damage `Upgrade`, which is bought against the equipped `Weapon`.

**Shield and Pet deferred**, with their blockers recorded in [map.md](../map.md). The Shield's cost is almost entirely the mitigation seam — widening `damage_player` to `damage_player(amount, source_pos)`, which i-frames and flat damage reduction would also want, and which is worth landing on its own terms rather than as a side effect of one Relic. Its motion is already decided: **independent rotation, not mouse-tracking**. The player aims at what they are fighting, so a shield welded to the crosshair blocks nearly everything incoming — that is not a shield, it is near-invulnerability. A shield the player has to position by turning away from a threat is a real decision.
