# ADR-0017: A Run is won by clearing a Map's Spawn Trigger timeline

**Status**: Accepted

## Context

Before this, a Run had exactly one ending: death. `damage_player` was the only path to `Run_End`, and a Run was an endless survival attempt with no objective.

[ADR-0016](0016-gold-is-the-single-currency.md) made Gold the single currency and made banking it the route to permanent power. That creates a problem it cannot solve on its own: if a Run has no ending the player can *achieve*, and death costs nothing, then hoarding is unconditionally correct and the Shop is never worth opening.

## Decision

A Run ends in one of three outcomes: `Cleared`, `Killed`, or `Timed_Out`. `Cleared` pays the Map's `victory_multiplier` on the Run's net take; the other two bank at face value. Nothing is ever forfeited.

**Cleared is derived, not authored**: the Map's Spawn Trigger timeline is exhausted (every trigger has fired, and every `Repeating` one has passed its `duration`) *and* no enemies remain alive.

Maps carry the objective directly — `Map.time_limit` and `Map.victory_multiplier` — rather than a parallel `[Map_Name]` preset table, since `maps.odin` is generated from `data/maps/*.json` by the map_builder and the fields must round-trip through that file anyway.

## Consequences

Deriving the win from the timeline rather than from an authored kill quota is the load-bearing choice. `fire_spawn_composition` silently skips spawns once `MAX_ENEMIES` is reached, so a quota can exceed what a Map is ever able to put on the field, making it unwinnable in a way nothing in the data would reveal. The derived condition cannot fail that way.

The cost is a new authoring constraint: a `Repeating` trigger with `duration <= 0` means indefinite, so a Map containing one can never be Cleared. Every trigger on `desert_dungeon` was unbounded and had to be given a finite duration. This is not currently validated by the map_builder, and probably should be.

Because a victory *multiplier* (rather than a flat purse) rewards carrying Gold out, spending is always economically negative. That is deliberate: the pull toward hoarding is meant to be constant, and **Map difficulty is the only thing that makes a player open the Shop**. It follows that a Map must be authored to be unclearable at the base power of the account level it is meant for — and that Maps are a fixed ladder rather than scaled to the player, since a Map outgrown is a signal to move up rather than a treadmill.

The Run End screen becomes a receipt (earned, spent, bonus, banked) with a per-outcome header, reusing the existing `Run_End` `Screen_Kind` so the two new endings need no new wiring through `apply_screen_kind`/`rank_count`. The HUD's elapsed timer becomes a countdown, since running it out now ends the Run.

The Shop still pauses the clock. Making deliberation cost time would push the optimal play toward not opening the Shop at all, which is precisely the behaviour ADR-0016 exists to make interesting.
