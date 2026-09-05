# ADR-0019: Relics are a parallel Account axis, not a widened Account_Stat

**Status**: Accepted

Builds on [ADR-0016](0016-gold-is-the-single-currency.md) (Gold is the single currency, `Account_Stat` gains `max_stack` and `unlock_level`) and [ADR-0007](0007-upgrade-stacks-recomputed-not-mutated.md) (stacks are recomputed, never mutated).

## Context

Account progression could express exactly one kind of permanent purchase: a number folded into an existing stat. `Account_Stat_Preset.effect` is a bare `Multiplicative`, and `apply_account_stat_effect` is one line of `math.pow`. Every one of Vigor, Might, Swiftness and Fortune is that same shape.

The permanent purchases we now want are not numbers. An orb circling the player, a shield covering one arc, a companion that fights on its own — each is a thing that exists in the world and acts every frame. None of them is a coefficient on a stat that already exists, and no widening of a single `f32` field reaches them.

Nothing owned-by-the-player existed at all before this. The nearest precedents were `Poison_Cloud` (a player-spawned, autonomously-ticking, damage-dealing entity, but stationary, expiring, and owned by a `Weapon`) and `assign_swarmer_slots` (the only orbit maths in the repo, used hostilely).

Three shapes were considered:

1. **Widen `Account_Stat_Preset.effect` into a union**, adding a behavioural variant alongside `Multiplicative`. Every existing consumer — `apply_account_stat_effect`, `recompute_player_stats`, `apply_upgrades` — takes a base `f32` and returns an `f32`. A behavioural variant has no `f32` to return, so all of them would grow a branch that answers "not applicable", and `Account_Stat`'s one clear job (scale a stat) would become two.
2. **A `proc` field on the preset**, invoked per frame. This repo has no callback or hook anywhere; every per-kind behaviour is a `switch` over an enum against an `[Enum]T` preset table. A function pointer in a persisted preset table would be a new idiom introduced for one feature.
3. **A parallel axis**: its own enum, preset table and stacks array.

## Decision

A **Relic** is its own axis: `Relic_Kind`, `relic_presets`, and `Player.relic_stacks`, alongside — not inside — `Account_Stat`.

It reuses `Account_Stat`'s entire *purchase* mechanism verbatim: geometric `base_price`/`price_growth`, a hard `max_stack`, an Account-Level `unlock_level`, the same Gold wallet, the same Main Menu panel, the same three row states (locked / MAXED / buyable). What it does not reuse is the `effect` field, because that field is the thing that cannot express it.

`Relic_Preset` is therefore `Account_Stat_Preset` minus `effect`. What a stack *does* lives with the ability's own runtime instead of in the table.

A Relic's live effect is **derived from `relic_stacks` every frame**, never applied onto anything. `relic_orb_count()` reads the stack count directly; the orbs' positions are recomputed from it and a single shared phase. Only transient runtime — the orbit phase and the damage tick timer — is stored, in `game.relic_state`, tagged `json:"-"`.

Might scales Relic damage; the Run-scoped Damage `Upgrade` does not.

## Consequences

Adding a Relic is a table row plus an `update_`/`draw_` pair, with no change to any existing stat-derivation code. `apply_account_stat_effect` and `recompute_player_stats` are untouched by this ADR, and stay as narrow as they were.

The Main Menu now carries three panels rather than two: Progression, Relics, and the navigation panel. The two ladders share a wallet but are different kinds of purchase, and one panel holding both stands 482px tall against the 540px default window — overflowing outright the moment a second Relic exists.

`try_buy_relic` has no post-purchase step at all, unlike `try_buy_account_stat`'s Vigor/Swiftness `recompute_player_stats` branches and its heal-on-cap-raise. Deriving every frame is a stronger form of ADR-0007's recompute-not-mutate: there is no mutable copy that could drift, so there is nothing to keep in sync.

The price ladder is deliberately steeper and shorter than any `Account_Stat`'s — 1.35 growth over 4 stacks against 1.15 over 10. A stack buys a whole extra orb rather than five percent of a stat, so matching `Account_Stat`'s growth would make a Relic strictly the best Gold sink in the game. Every figure is placeholder content-authoring, as with `upgrade_presets` and `account_stat_presets`, and expects a tuning pass against the running game.

Might scaling Relic damage couples Relics to one `Account_Stat`, which means a Might build and a Relic build reinforce each other rather than competing. That is intentional — Might is Account progression's Damage stat and a Relic is Account-scoped — but it is a real balance coupling, not a neutral choice.

Two further Relics are designed but not built, and both were deferred because of what they cost rather than what they add. A **Chasing Shield** needs mitigation, which does not exist anywhere: `damage_player(amount)` has no idea where a hit came from, so blocking one direction requires widening it to `damage_player(amount, source_pos)` — the right seam for i-frames and damage reduction too, and worth landing on its own terms rather than as a side effect. It is also not to be welded to the mouse: the player aims at what they are fighting, so a shield tracking the crosshair would block nearly everything, and it will instead rotate independently. A **Pet** needs targeting and steering that no player-owned entity has yet.
