# Boss model

Type: grilling
Blocked by: 01
Status: resolved

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


## Answer

**The boss is an `Enemy_Kind` in the ordinary enemy pool, with health-threshold phases that change its attack rotation and nothing else, attacking through a new telegraph-carrying `Attack_Style` variant timed in absolute seconds.** [ADR-0023](../../../docs/adr/0023-enemy-tells-are-absolute-durations.md) records the telegraph timing and its name.

### Four facts the ticket was written without

- **Windup is weapon-only.** `windup_fraction`/`windup_timer` live on `Weapon` ([weapon.odin:69](../../../weapon.odin)). Enemies have nothing of the kind: `Melee` deals damage the instant `attack_timer` expires inside `attack_range`, `Ranged` fires the instant `fire_timer` expires inside its band ([enemy.odin:748-772](../../../enemy.odin)). There is no committed action to extend and no telegraph to reuse — the machinery is built from scratch either way, so "reuse Windup or not" was really "which timing rule".
- **Enemies have no health bar.** [ADR-0011](../../../docs/adr/0011-in-game-hud-moves-to-world-space-resource-indicators.md)'s "every entity (Player, Enemy)" is stale: commit `665ad38` deleted the enemy indicator, and `draw_enemy` now fades opacity toward `ENEMY_MIN_OPACITY :: 0.25` in its place ([main.odin:1094](../../../main.odin)). Only `draw_player_resource_indicators` exists. A boss bar is therefore not an exception to a live rule; it is a restoration.
- **A boss cannot be big by being healthy.** `enemy_body_size` clamps at `ENEMY_SIZE_MAX :: 48.0`, which 136 health already reaches ([main.odin:841](../../../main.odin)). Past that, health buys no more square.
- **`fire_spawn_composition` `return`s outright at `MAX_ENEMIES`** ([enemy.odin:601](../../../enemy.odin)), so a boss authored inside a batch can be dropped whole — and a rung whose boss never spawned clears the moment its timeline runs dry, silently.

### Settled

- **The boss is an `Enemy_Kind` preset entry in `game.enemies`**, not its own type and not an `Attack_Style` variant. [ADR-0020](../../../docs/adr/0020-enemy-kind-is-the-authored-unit.md) already made the kind the authored unit, so the boss is the roster's heaviest entry. A parallel type would re-derive collision, pathing, separation, damage, death, the kill tally and pickup drops — and would break [ADR-0017](../../../docs/adr/0017-run-outcome-and-map-objective.md)'s Cleared, since `spawn_timeline_exhausted() && len(game.enemies) == 0` would stop seeing it. In the pool, **killing the boss simply is the last enemy dying**, and the win condition needs no change at all.
- **Phases are health thresholds — two transitions, three phases.** Health is the signal the player can actually read now that the boss carries an indicator. Timed phases make the fight a script that runs identically regardless of performance; positional phases need arena features rung 5 deliberately removed. Thresholds are content-authoring, like every number on this map.
- **A phase changes the attack rotation and its pacing. Nothing else.** `Movement_Style` is fixed for the boss's whole life — no enemy swaps it mid-life today, and doing so would need `path` cleared and `wobble_phase` reseeded on the swap. Combined with adds being off the table, this is deliberately the narrow reading: the fight escalates by demanding faster and more varied reads, not by the boss becoming a different creature.
- **Adds come from the Spawn Trigger timeline, never from the boss.** If the boss spawned its own, the timeline could exhaust while the boss kept producing enemies, making `check_run_objectives` a race against the boss's spawn clock — exactly what [ADR-0017](../../../docs/adr/0017-run-outcome-and-map-objective.md) avoided by refusing a kill quota. The timeline stays the only answer to "can more enemies arrive". This costs the "summons a wave at 50%" beat; that is the price of a derivable win condition.
- **The boss's attacks go through a new `Attack_Style` variant carrying a Tell**, shared with ordinary kinds rather than a boss-only path. It spends one of the one-or-two variant slots [Enemy variety model](01-enemy-variety-model.md) budgeted, and it clears that ticket's bar — a telegraphed committed attack is the first enemy action a player can *react* to rather than only stay out of the range of. Sharing the machinery means `Charger`'s committed dash and the boss's attacks read as one vocabulary, and the ladder can teach the read below rung 5.
- **A Tell is timed in absolute seconds, not as a fraction.** [ADR-0004](../../../docs/adr/0004-windup-fraction-not-duration.md)'s fraction exists to keep Windup nested inside a cycle that `action_rate` upgrades shrink without ceiling. Nothing shrinks an enemy's cycle — an `Enemy` is a pure stamp of its preset — so that invariant has no enemy-side existence. Positively: a learned reaction time must be stable, and a fraction would silently retune the read every time the attack's cooldown was rebalanced. What carries over is the committed-action rule: **a Tell always resolves**, in range or not. [ADR-0023](../../../docs/adr/0023-enemy-tells-are-absolute-durations.md).
- **"Tell" is the canonical term**, chosen because the glossary already forbids the two obvious names: *Windup* is weapon-level by [ADR-0003](../../../docs/adr/0003-windup-and-follow-through-are-weapon-level.md), and the **Windup** entry's own `_Avoid_` rules out *telegraph* as a mechanic name ("telegraph is the effect Windup produces, not the name of the mechanic"). A Tell produces a telegraph the same way a Windup does.
- **The boss keeps a world-space Resource indicator — no screen-space bar.** Same fraction-only icon-and-bar the player carries, same anchor formula, machinery that already exists. [ADR-0011](../../../docs/adr/0011-in-game-hud-moves-to-world-space-resource-indicators.md)'s load-bearing rule is "no screen-space bars anywhere", and this leaves it exactly intact; the exception granted is to *which entities carry an indicator*, which enemies lost after that ADR was written anyway. Justified because opacity cannot resolve a fraction on an entity the player spends a minute killing — 60% and 40% look nearly identical. Rung 5's arena is open by [Map ladder shape](03-map-ladder-shape.md), so the boss is on screen when it matters. The opacity fade stays, now redundant rather than wrong.
- **`ENEMY_SIZE_MAX` rises; the derivation is untouched.** Size stays `10 + 0.28 x max_health`, so it still *means* health and nothing becomes independently authorable — preserving [ADR-0020](../../../docs/adr/0020-enemy-kind-is-the-authored-unit.md)'s "a chunky enemy is a high-health enemy by construction". No ordinary roster entry will be authored near even today's clamp, so raising it changes exactly one entity, and the boss's size is earned rather than declared. A per-preset size override was rejected for breaking that derivation. The new ceiling is a number for [Enemy catalog](04-enemy-catalog.md) to land with the boss's health.
- **The boss spawns from its own `One_Shot` trigger at `Time_Elapsed{0}`, with a reserved slot.** Present from the first second: rung 5 is a boss fight with adds layered over it, not a wave-clear with a boss stapled on — which also means its ~30s of slack is mop-up for the adds rather than the boss's whole health bar. The reservation stops an add trigger consuming the slot `fire_spawn_composition` would otherwise refuse the boss. The off-screen entrance (`pick_offscreen_spawn_point`) is accepted as-is: no doors, no cutscene, the boss walks in, and the open arena makes that legible.
- **Boss death drops a guaranteed Gold pickup**, bypassing `PICKUP_DROP_CHANCE :: 0.25`. Rolled through the ordinary path the boss would pay out Gold roughly one kill in twelve (a 25% drop, then uniform among three kinds); a boss that drops nothing reads as a bug. The payout number stays [Enemy catalog](04-enemy-catalog.md)'s.
- **Path inflation is derived from body size**, and the boss gets its own collision map. `update_enemies` paths every enemy against `build_inflated_collision_map(tilemap, 1)` — a hardcoded one-tile inflation against 16x16 tiles, clearing roughly the 3-tile body today's 48px clamp allows ([enemy.odin:878](../../../enemy.odin)). A larger boss would be handed BFS paths through gaps its body cannot enter, then jam against `move_actor` while the path kept insisting. With exactly one boss a second collision map per frame is cheap, and deriving the radius stops it being a constant tuned for one body size. The residual — a boss too wide for a corridor cannot enter it — is accepted as something the arena is entitled to say.

### Deliberately not decided here

- **How a phase transition reads**, and how long a Tell should be in practice, belong to [Boss telegraph and phase feel](06-boss-telegraph-and-phase-feel.md): both can only be judged in motion.
- **Every number** — the boss's health, its Tell durations, its phase thresholds, the new size ceiling, its Gold — is content-authoring, matching how `weapon_presets` and `account_stat_presets` hold theirs.

### Follow-on

- **[Enemy catalog](04-enemy-catalog.md)** inherits a spent `Attack_Style` slot as a constraint, plus the boss's own preset values and the new size ceiling. It does not gain this ticket as a blocker: the roster it writes is specified by the rung briefs, and the Tell variant is a constraint on its remaining choices rather than an input it waits on.
- **[Boss telegraph and phase feel](06-boss-telegraph-and-phase-feel.md)** now knows exactly what it is prototyping: a Tell in seconds on a fixed-movement boss with three health-threshold phases.
- **[Content-scale integration sweep](09-content-scale-integration-sweep.md)** takes four new seams: the reserved `MAX_ENEMIES` slot, the size-derived path inflation and the boss's own collision map, `ENEMY_SIZE_MAX` rising, the restored Resource indicator for one entity, and the guaranteed drop path around `maybe_spawn_pickup`.
- **[ADR-0011](../../../docs/adr/0011-in-game-hud-moves-to-world-space-resource-indicators.md) is stale on the enemy side** and was found so here, not changed here — commit `665ad38` removed the enemy indicator without amending it. The **Resource indicator** glossary entry has been corrected to describe what is actually true.
