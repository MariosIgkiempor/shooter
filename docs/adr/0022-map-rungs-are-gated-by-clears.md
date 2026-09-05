# Map rungs are gated by clears, not by Account Level

Status: accepted

Maps become an ordered difficulty ladder: each Map carries a `rung` (1..N, no gaps, no duplicates), and a rung is playable only once the rung below it has been Cleared at least once. Rung 1 is always open. Gating them on Account Level instead was considered and rejected.

`unlock_level` is this codebase's established gating idiom — every `Account_Stat` and every Relic uses it — so reusing it for Maps was the obvious move. It is the wrong one. Level advances on **banked** Gold ([ADR-0016](0016-gold-is-the-single-currency.md)), so a Level gate asks "have you saved enough?" where the ladder means to ask "can you do this?". A patient player would bank their way onto the top rung having never beaten the second, and Fortune makes it worse: it raises Gold gain, so it would compound directly into ladder access. A clear is the only evidence the game has that a player can actually handle a rung, and it is evidence the game was already computing and then throwing away — before this, Cleared paid a multiplier and was immediately forgotten.

So the Account gains a **cleared set**: one bool per Map, Account-scoped, surviving `start_new_run` alongside the wallet, Level, `account_stat_stacks` and `relic_stacks`. Nothing richer — no clear counts, no best times, no per-rung statistics. The set is also what gives the Map Selection screen a vocabulary it does not have today, where every Map is an identical unconditional button.

**It is persisted by identity string, not by enum ordinal.** `account_stat_stacks` persists as an enum-keyed array and that is fine, because `Account_Stat` is hand-written and stable. `Map_Name` is neither: `map_builder` generates it from a filename-sorted directory listing, so adding `boss_keep.json` renumbers every case that sorts after it. An ordinal-keyed cleared set would then silently credit the player with clears they never earned, and silently lock rungs they had. `active_map_pointer` already stores `map_identity_string(name)` for exactly this reason; the cleared set reuses that mechanism.

## One Run is one rung

A Run remains exactly one Map attempt — pick a weapon, pick a rung, play it, settle. Clearing rung 3 does not carry the player into rung 4 with their wallet and Upgrades intact.

The gauntlet reading is the more fashionable one, and it needs machinery none of which exists: a mid-Run map transition, a reset of `survival_seconds` and the spawn timeline and the player's position, and a banking rule for a chain of Maps rather than one. It would also re-litigate ADR-0016's settled "a Run banks its net take" and ADR-0017's three outcomes. And it would duplicate something the game already has one layer up: Gold, Level, `Account_Stat`s and Relics are all Account-scoped, so escalation across attempts is already the shape of the game. The ladder is a difficulty *selection*, and keeping a Run to one rung is what keeps the top rung reachable in a single sitting.

## Consequences

**Failing a rung still costs nothing but the bonus.** `bank_run_gold` banks a Run's net take at face value on Killed and Timed_Out, and refuses to run the Level cascade backwards. A per-rung loss penalty was considered as the thing that would make rung choice a wager, and rejected: Gold *is* Account progression, so penalising a loss would run permanent progress backwards. What keeps a lower rung worth playing is reliability — a rung cleared every time at a smaller multiplier beats a rung cleared one try in four at a larger one — and `victory_multiplier` therefore rises only shallowly across the ladder, because gross income already rises on its own as the roster densifies. A steep multiplier would make the top rung strictly dominant the moment it unlocked and collapse the ladder into one Map.

**A rung pays through `victory_multiplier` alone.** Kills pay what their `Enemy_Kind` pays, on every rung ([ADR-0020](0020-enemy-kind-is-the-authored-unit.md)). No per-rung factor on Gold payouts: two Gold-scaling knobs in different files would make any payout impossible to reason about, and would put a second authority on a number ADR-0020 just centralised onto the kind.

**Ordering lives on the Map, not in the enum or a side table.** `Map_Name`'s order is alphabetical-by-filename and so was never an ordering anyone chose; a hand-written ladder table in code would be a second place to keep in sync with the map files. `rung` rides through `data/maps/*.json` and the bake for free, sits beside `time_limit` and `victory_multiplier` in the editor's new map-level panel ([ADR-0021](0021-map-layouts-are-hand-authored-places.md)), and joins the map-validity test as "rungs are 1..N, no gaps, no duplicates".

**`time_limit` is mop-up slack, not a difficulty axis.** Cleared requires the Spawn Trigger timeline to exhaust ([ADR-0017](0017-run-outcome-and-map-objective.md)), so a `time_limit` below the timeline's natural end does not make a rung harder — it makes it unwinnable by construction. It is therefore derived per rung as `timeline_end + slack`, and only the slack tightens as the ladder climbs, pressuring how fast the last stragglers die rather than how long the player survives.

**Locked rungs are drawn, not hidden**, following `account_stat_unlocked`'s precedent, so the ladder ahead stays visible as something a clear buys.
