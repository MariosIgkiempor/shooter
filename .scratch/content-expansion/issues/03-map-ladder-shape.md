# Map ladder shape

Type: grilling
Status: resolved

## Question

Maps become an ordered difficulty ladder rather than a flat set of options. What is the ladder's shape?

`Map` already carries the two fields a ladder needs — `time_limit` and `victory_multiplier`, the latter with an in-code comment that anticipates exactly this ("Authored per Map so a later, harder rung of the ladder can pay more for the risk it asks the player to carry", [map.odin](../../../map.odin)). Nothing consumes them as an ordering yet.

To settle:

- **How many rungs**, and what distinguishes each one as an experience rather than as a number.
- **What escalates.** Candidates: enemy mix (harder kinds appearing later), Spawn Trigger density and overlap, `time_limit` tightening, layout hostility, boss presence. Which of these carry the curve, and which stay flat?
- **What it pays.** `victory_multiplier` per rung, against the fact that Gold is the single currency and a Run's *net* take is what banks ([ADR-0016](../../../docs/adr/0016-gold-is-the-single-currency.md)) — a harder rung paying more has to be worth the higher chance of dying with an unbanked wallet.
- **Gating.** Are later rungs locked until an Account Level, cleared-predecessor, or nothing at all? `Account_Stat` already establishes `unlock_level` as this codebase's gating idiom; reusing it for Maps is available but not obviously right, since Level measures banked Gold rather than skill.
- **Presentation.** [hud.odin](../../../hud.odin)'s `draw_map_selection_ui` draws one button per `Map_Name` in a single column, with a swatch icon per map. That does not scale past a handful, and it has no vocabulary for "locked", "cleared", or "harder". Decide what the screen becomes — the layout work itself belongs to the implementation follow-on, but the information it must convey is decided here.
- **Does clearing a rung persist?** Nothing on the Account records which Maps have been cleared today. A ladder may or may not want that.

[Map layout authoring model](02-map-layout-authoring-model.md) has settled what a rung is made of, and hands this ticket two constraints and one extra job:

- A rung is a **hand-drawn file**, so the rung count is bounded by what a person will actually draw — decide it as a number someone commits to, not an aspiration.
- **Footprint is flat** across rungs (~54×48, capped by `MAX_SEARCH_NODES`), so "layout hostility" as an escalation axis means denser and meaner geometry, never a bigger arena.
- This ticket **produces the per-rung authoring briefs** — size, chokepoints, sightlines, enemy mix, spawn timeline, `time_limit`, `victory_multiplier` — since drawing them is authoring and belongs to the implementation follow-on.

## Answer

**Five rungs, ordered by an authored `rung` field, gated by clearing the rung below, escalating by roster and timeline density.** [ADR-0022](../../../docs/adr/0022-map-rungs-are-gated-by-clears.md) records the gate, the persistence, and the one-Run-one-rung frame.

### The risk premise this ticket was built on was wrong

The ticket asked how "a harder rung paying more has to be worth the higher chance of dying with an unbanked wallet". There is no unbanked wallet. `bank_run_gold` banks a Run's net take at face value on Killed and Timed_Out (`RUN_LOSS_MULTIPLIER :: 1.0`) and explicitly refuses to run the Level cascade backwards. Failing a rung costs the time and the forgone multiplier, nothing else.

That was left as-is rather than fixed. A loss penalty would make rung choice a genuine wager, but Gold *is* Account progression under [ADR-0016](../../../docs/adr/0016-gold-is-the-single-currency.md), so penalising a loss means running permanent progress backwards — something the codebase already decided not to do. What keeps a lower rung worth playing instead is **reliability**: a rung cleared every time at ×2 beats a rung cleared one try in four at ×2.5. That is what fixes the multiplier curve's shape below.

### Settled

- **Five rungs.** Rung 1 is the existing Desert Dungeon, re-tuned rather than redrawn. Rung 5 is the boss rung and the only one — [Boss model](05-boss-model.md) authors one boss, not five.
- **A Run is one rung attempt.** The flow stays as it is: `Run_Start` → weapon → `Map_Selection` → `Playing` → `Run_End`. The gauntlet reading (clearing rung N carries you into rung N+1) was rejected — it needs mid-Run map transition, timeline/position/`survival_seconds` reset and a chain-banking rule, none of which exists, and it duplicates escalation the Account layer already provides.
- **The curve is carried by roster and timeline** — which `Enemy_Kind`s appear, and how densely and overlappingly their Spawn Triggers fire. **Layout hostility escalates secondarily**: tighter chokepoints, shorter sightlines, less open ground.
- **Flat across all five**: footprint (settled by [ADR-0021](../../../docs/adr/0021-map-layouts-are-hand-authored-places.md)), Run length (~4–6 min, so rungs are comparable — escalate intensity within the window, never duration), and enemy health, which [ADR-0020](../../../docs/adr/0020-enemy-kind-is-the-authored-unit.md) fixed per-kind with no per-rung scaling.
- **`time_limit` is mop-up slack, not a difficulty axis.** Cleared requires the timeline to exhaust, so a limit below the timeline's natural end makes a rung unwinnable rather than hard. It is derived as `timeline_end + slack`; only the slack tightens up the ladder (~90s → ~30s). Rung 1 today already sits at timeline-end ~270 against `time_limit = 330`.
- **Gating is cleared-predecessor**, rung 1 always open. `unlock_level` was rejected: Level measures banked Gold, so it asks "have you saved enough?" rather than "can you do this?", and Fortune compounds Gold gain directly into ladder access.
- **The Account gains a cleared set** — one bool per Map, Account-scoped, surviving `start_new_run` alongside the wallet, Level, `account_stat_stacks` and `relic_stacks`. Nothing richer: no clear counts, no best times. **Persisted by identity string, not enum ordinal** — `map_builder` generates `Map_Name` from a filename-sorted listing, so a new map file renumbers every case after it; `active_map_pointer` already stores `map_identity_string(name)` for the same reason.
- **Ordering lives on `Map` as an authored `rung: int`**, 1..N with no gaps or duplicates — beside `time_limit` and `victory_multiplier`, in the editor's new map-level panel. Not the enum's order (alphabetical by filename), not a side table in code. Map Selection sorts by it; the map-validity test from [Map layout authoring model](02-map-layout-authoring-model.md) gains the gap/duplicate check.
- **`victory_multiplier` rises shallowly**, roughly 1.5 / 1.75 / 2.0 / 2.25 / 2.5. Shallow because gross income already climbs on its own as the roster densifies; a steep multiplier makes the top rung strictly dominant the moment it unlocks. Exact numbers stay placeholder content-authoring, matching `upgrade_presets` and `account_stat_presets` — only the shape is locked.
- **A rung pays through `victory_multiplier` alone.** A kill pays what its kind pays, on every rung. No per-rung Gold factor.
- **Map Selection conveys six things**: rung order (sorted ascending), name, swatch, locked/unlocked, cleared/not, and the two authored stakes (`time_limit`, `victory_multiplier`). Not: roster previews, best times, star ratings. **Locked rungs are drawn locked, not hidden**, following `account_stat_unlocked`'s precedent. At five rows the existing single column still fits, so no layout redesign is forced — the ticket's "doesn't scale past a handful" worry doesn't bite at five.
- **Nothing follows clearing all five.** Rungs stay replayable, the cleared record stays a bool, and the reason to keep playing is Account progression, which is unbounded. Endless/prestige/ascension is a fresh effort with its own balance frame — recorded Out of scope.

### The five rungs

Each brief fixes geometry, timeline shape, slack and multiplier, and states the **pressure** the mix must exert in Movement × Attack terms. It deliberately does **not** name `Enemy_Kind`s: that would front-run [Enemy variety model](01-enemy-variety-model.md) and [Elite and affix tier](10-elite-and-affix-tier.md), and authoring the roster is [Enemy catalog](04-enemy-catalog.md)'s job.

**Rung 1 — Desert Dungeon** *(exists, re-tuned)*. Open ground, few chokepoints, long clean sightlines. Timeline sparse and sequential, minimal overlap. Pressure: slow grounded melee with a light ranged accent. Teaches that kiting works. Slack ~90s, multiplier 1.5.

**Rung 2 — Warren**. Broken sightlines, many short chokepoints, no long lanes. Two triggers overlapping. Pressure: melee that arrives from an unseen bearing — the map does the ambushing, not the enemy. Teaches that you can't kite in a straight line. Slack ~75s, multiplier 1.75.

**Rung 3 — Hall**. Long sightlines, sparse cover, wide crossings the player must make in the open. Three overlapping triggers, the first `Kills_Reached` gate. Pressure: sustained ranged chip with a melee escort that punishes standing still behind cover. Teaches holding position under fire. Slack ~60s, multiplier 2.0.

**Rung 4 — Ring**. One tight loop, dense interior, no safe corner. Four triggers, heavy overlap, peak concurrency. Pressure: swarm density — many cheap fast bodies, so the threat is the count rather than any one enemy. Teaches crowd management. Slack ~45s, multiplier 2.25. **This is the hardest rung as terrain**, and the one that will press `MAX_ENEMIES :: 24`.

**Rung 5 — Boss keep**. Deliberately **legible**: open, simple, few obstructions. Geometry stops escalating here. A boss whose telegraphs must be read needs room to read them, so hostile terrain would fight the encounter rather than serve it. Pressure: the boss, plus adds thin enough to leave slots for it. Slack ~30s, multiplier 2.5.

### Follow-on

- **[Enemy catalog](04-enemy-catalog.md) gains this ticket as a blocker** — it fills the mix slots these briefs define.
- **[Boss telegraph and phase feel](06-boss-telegraph-and-phase-feel.md)** gets a legible stage to prototype against, decided here rather than by that ticket.
- **[Content-scale integration sweep](09-content-scale-integration-sweep.md)** takes the rung-4 density case against `MAX_ENEMIES`, plus the new persisted cleared set, the `rung` field through the JSON/bake/editor path, and the Map Selection information rework.
