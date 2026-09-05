# ADR-0016: Gold is the single currency

**Status**: Accepted

Supersedes [ADR-0006](0006-gold-shop-run-progression-xp-account-progression.md) (Gold and XP as two currencies on two axes) and [ADR-0009](0009-xp-is-a-run-end-grant.md) (XP as a Run-end grant).

## Context

ADR-0006 put Gold and XP on separate axes: Gold was Run-scoped and spent in the Shop, XP was Account-scoped and spent on `Account_Stat`. ADR-0009 then made XP a Run-end grant, minted by `compute_run_xp` from a formula over kills, survival time, and Gold earned.

That combination meant the two economies could never touch. XP was *minted*, not earned, so nothing the player did with Gold could affect it, and nothing they did with XP could affect a Run. Shop spending was therefore free: it cost the player nothing they could otherwise have had. There was no decision anywhere in the system — only two independent ratchets, each of which the player wanted to maximise separately.

## Decision

Gold is the only currency. It is Account-scoped: `start_new_run` no longer resets it, and it is spent both in the Shop (weapon tiers, `Upgrade` stacks — Run-scoped power) and on the Main Menu (`Account_Stat` — permanent power).

A Run settles once, when it ends (`bank_run_gold`). What banks toward the next Account Level is the Run's **net take** — the wallet's delta against `Player.run_start_gold`, i.e. everything picked up minus everything spent in the Shop — not the whole wallet. Measuring the delta is what stops savings carried in from being re-banked, and re-levelled, every Run.

Account Level is fed by that banked total and **gates** which `Account_Stat`s are purchasable, via a per-stat `unlock_level`. `Account_Stat` also gains a `max_stack` and a growth factor comparable to `Upgrade`'s.

## Consequences

A Shop purchase is now visibly paid for out of Account progression: two Runs with identical kills end at different Account Levels if one of them spent. That is the decision the two-currency model could not express.

Because Level gates access, banking buys something a Shop purchase cannot — the ladder itself — so the two sinks are not merely priced against each other but qualitatively different.

Levelling had to be recalibrated wholesale. XP was minted tens-per-Run by a formula; Gold is picked up hundreds-per-Run, so the level base moved from 10 to 500. `Account_Stat` growth moved from an uncapped 1.08 to a capped 1.15: competing for the same coin as a Shop Upgrade, it cannot also be the cheaper, unbounded ladder.

Fortune is a special case. It raises Gold gain, and Gold is now Account progression itself, so it compounds into its own purchase price. It is given the lowest `max_stack` and the highest `unlock_level` so that "bank into Fortune until it stops paying, then play" is not the strictly correct opening.

Gold income, `Account_Stat` prices, and Map difficulty are now a single coupled balance problem rather than independent knobs. Every figure involved is placeholder content-authoring and expected to need a tuning pass against the running game.

`gold_earned` survives the merge but changes purpose: it no longer feeds a formula, and exists solely so the Run End receipt can show gross earnings and net take as separate lines. The debug "Add Gold" cheat correspondingly bumps `run_start_gold` alongside `gold`, so a granted windfall settles as exactly zero rather than inflating real progression.
