# Enemy catalog

Type: grilling
Status: resolved

## Question

Given the model settled by [Enemy variety model](01-enemy-variety-model.md), what is the actual roster?

Not "how are enemies represented" but "which ones exist, and why each earns its place". For each entry:

- **What it does to the player** — the pressure it applies that no existing enemy applies. A roster where three entries all mean "walk at you and touch you" is one enemy with three colours.
- **Its axis composition or preset values** — movement, attack, health, speed, size, colour, in whatever shape ticket 01 decided.
- **Its Gold payout.** This graduates [Account progression](../../account-progression/map.md)'s standing fog item: `enemy_gold_presets` holds a single `.Basic = {base_gold = 30, gold_multiplier = 1.0}` marked "placeholder, content-authoring". Payout should track the pressure the enemy applies, and note that Fortune scales Gold gain on top.
- **Where it enters the ladder** — which rung it first appears on. [Map ladder shape](03-map-ladder-shape.md) has settled the ladder and written a per-rung brief stating the **pressure** each rung's mix must exert in Movement × Attack terms, deliberately without naming kinds. This ticket fills those slots, so the briefs are the specification the roster is written against, not a downstream consumer of it: rung 1 slow grounded melee with a light ranged accent, rung 2 melee arriving from unseen bearings, rung 3 sustained ranged chip with a melee escort, rung 4 swarm density (many cheap fast bodies), rung 5 the boss plus adds thin enough to leave it slots.

Constraints to design against:

- **Every enemy is a square** — commit `665ad38` superseded [Art revamp](../../art-revamp/map.md) ticket 01's rectangle/circle/triangle vocabulary and deleted `Actor_Shape_Kind`. Identity is carried by **colour** (a per-kind `Enemy_Preset` field, by [Enemy variety model](01-enemy-variety-model.md)), **size** (derived from `max_health` via `enemy_body_size`, clamped to 10..48px) and **opacity** (fades as health drops). There is no shape budget, but colour and size are not free either: size is *not* independently authorable, so a chunky enemy is a high-health enemy by construction. The authoring convention is that hue tracks Movement Style — wall-ignorers in the violet family, and so on — kept in the catalog rather than enforced in code, so a boss or elite can break it deliberately.
- **One `Attack_Style` slot is already spent.** [Boss model](05-boss-model.md) put a **Tell**-carrying variant on the axis — an attack that commits visibly before it lands ([ADR-0023](../../../docs/adr/0023-enemy-tells-are-absolute-durations.md)) — shared with ordinary kinds rather than reserved for the boss. Against [Enemy variety model](01-enemy-variety-model.md)'s budget of one or two variants, that leaves at most one more, and it means the ladder should teach the Tell read below rung 5 rather than debuting it there. [Boss telegraph and phase feel](06-boss-telegraph-and-phase-feel.md) has since narrowed what the slot covers and handed this ticket its numbers:
  - The variant is for **committed area attacks only** — an attack that claims a patch of ground. Ordinary `Ranged` fire stays untelegraphed, so a "telegraphed shooter" is not a roster entry this axis can express.
  - **0.55s is the reference Tell**, and durations are authored **per attack**, so each entry using this variant carries a rotation of *(attack, tell seconds)* pairs rather than one number. The budget is escape distance: at 100 px/s, 0.55s is 55px, so an attack's area and its Tell have to be authored together or the pair is unfair in one direction or the other.
  - **A telegraphed enemy is a slow one.** It plants for the whole Tell, so its threat is the ground it claims rather than its pressure while moving — which is a different pressure from anything on the roster today, and the reason it earns the slot.
- **The boss is a roster entry, authored here.** Its `Enemy_Preset` values are this ticket's: health, colour, Gold, and the new `ENEMY_SIZE_MAX` ceiling that its health has to reach for it to read as a boss. Its machinery is settled — three health-threshold phases, fixed `Movement_Style`, no self-spawned adds — so what is open is which movement it composes with and what its attack rotation contains.
- `MAX_ENEMIES :: 24` caps the field. A roster designed around swarms of twenty competes with itself for slots.
- Existing coverage: today the only authored composition is Grounded/Floater/Swarmer crossed with Melee/Ranged/none. The catalog should say which of those nine cells are actually worth shipping, not assume all of them are.

This also graduates [Enemy behaviours](../../enemy-behaviours/map.md)'s fog item "Spawner content authoring — which levels/spawners actually place Floater and Swarmer enemies, and in what mix". Clear it from that map when this resolves.

Unblocked: [Enemy variety model](01-enemy-variety-model.md), [Map ladder shape](03-map-ladder-shape.md) and [Elite and affix tier](10-elite-and-affix-tier.md) are all resolved.

[Elite and affix tier](10-elite-and-affix-tier.md) settled that there is **no elite tier and no affix layer** — a heavy enemy is an ordinary roster entry authored here — and hands this ticket four constraints:

- **Heavy kinds cap at roughly 136 health (~48px)**, about 2.7x a 50-health basic. Not taste: `update_enemies` builds one shared `build_inflated_collision_map(tilemap, 1)` for every enemy ([enemy.odin:708](../../../enemy.odin)), and a body past that one-tile envelope needs its own collision map — affordable for exactly one boss, not for a kind that appears several at a time. `ENEMY_SIZE_MAX` rises for the boss, so this ceiling is an authoring rule rather than something the clamp enforces.
- **No kind below the boss breaks the hue convention.** [Enemy variety model](01-enemy-variety-model.md) left it breakable for "a boss or elite"; that licence is the boss's alone, since a heavy appears in crowds where hue is how the player reads what a body does. Relatedness between a heavy and its light cousin comes free — same hue, bigger square.
- **Price a heavy at roughly the bodies it replaces**, and give it no guaranteed drop. `maybe_spawn_pickup` pays Gold about one kill in twelve ([pickup.odin:60](../../../pickup.odin)), so a heavy quadruples payout variance for flat expected income — accepted, because Gold is Account-scoped.
- **Nothing scales an enemy after the stamp.** No per-rung health, no aura, no Run-wide multiplier. A harder enemy is a different named kind, and the rung briefs are filled with kinds and counts only.

Heavy kinds are also what rung 4 needs: `fire_spawn_composition` returns outright at `MAX_ENEMIES :: 24` ([enemy.odin:601](../../../enemy.odin)), and rung 4 is authored at peak concurrency, so past that point pressure comes from heavier bodies rather than more of them. A Tell-carrier is the other case — it plants for its whole Tell, which needs a body that survives standing still.

## Answer

**Nine `Enemy_Kind`s across six of fifteen (movement x attack) cells, one new Movement Style (`Charger`), the second `Attack_Style` slot banked, and a five-family repalette.** Two things the roster ran into are bigger than the roster: `Swarmer` is broken, and `MAX_ENEMIES :: 24` is not the ceiling anyone thought it was.

### The roster

| # | Kind | Movement | Attack | HP -> px | Hue | Debuts | Gold | The pressure |
|---|---|---|---|---|---|---|---|---|
| 1 | Grunt | Grounded 40 | Melee | 50 -> 24 | green | 1 | 30 | the baseline; kiting works |
| 2 | Spitter | Grounded 35 | Ranged | 35 -> 20 | pale green | 1 | 20 | the light ranged accent |
| 3 | Wraith | Floater 45 | Melee | 55 -> 25 | violet | 2 | 35 | you cannot put a wall between you and it |
| 4 | Lancer | Charger 55 / dash | Melee | 60 -> 27 | red | 2 | 50 | punishes kiting in a straight line |
| 5 | Sentry | Inert (nil) | Ranged | 70 -> 30 | cyan | 3 | 35 | chip from fixed ground; you must cross to it |
| 6 | Breaker | Grounded 30 | Tell-area | 130 -> 46 | deep green | 3 | 80 | claims ground; survives standing still |
| 7 | Mite | Swarmer 65 | Melee | 20 -> 16 | yellow | 4 | 3 | count, not quality |
| 8 | Gazer | Floater 25 | Ranged | 30 -> 18 | pale violet | 4 | 20 | shoots from inside the geometry |
| 9 | Warden | Grounded, fixed | Tell-area rotation, 3 phases | ~220 -> ~72 | near-white | 5 | 250 | the boss |

Health and Gold are placeholder content-authoring, the same deferral every prior ticket on this map made, **except** where a number crosses a threshold: Breaker's 130 sits under [Elite and affix tier](10-elite-and-affix-tier.md)'s ~136 ceiling, the Warden's ~220 is what raises `ENEMY_SIZE_MAX` to ~72, Mite's 3 is load-bearing on the economy (below), and the Warden's 250 is guaranteed rather than rolled.

Not shipping, and named so nobody re-proposes them by accident: Grounded/nil, Floater/Tell, Swarmer/Ranged, Swarmer/Tell, Charger/Ranged, Charger/Tell, Inert/Melee (incoherent), Inert/Tell.

### Settled

- **Nothing on the roster could catch the player, and that was the whole problem.** `PLAYER_BASE_MOVE_SPEED :: 100` against authored enemies at Grounded 40, Floater 30, Swarmer 50, with `Melee.attack_range` of 10px meaning literal contact ([enemy.odin:750](../../../enemy.odin)). A player who keeps moving is untouchable by melee, so every point of pressure in the game today comes from projectiles or from geometry taking ground away. Rung 1's "teaches that kiting works" was accidentally the whole game on all five rungs. **The rule now: sustained speed caps around 70; the only thing that exceeds 100 does it on a locked line for a fixed duration.**
- **`Charger` is built, and it is the only Movement Style added.** Windup, then a committed dash along a locked line — [Enemy variety model](01-enemy-variety-model.md)'s named candidate, and the one absent player *response*: the roster asks you to kite, to close, and to hold position, but nothing asks you to dodge. It is the mechanism the speed rule needs, and five styles is already five hue families to keep apart.
- **The dash reuses the Tell's vocabulary with different geometry.** It draws its **lane** where a Tell draws its patch, flashes the body the same way, and times in absolute seconds per [ADR-0023](../../../docs/adr/0023-enemy-tells-are-absolute-durations.md). [Boss telegraph and phase feel](06-boss-telegraph-and-phase-feel.md)'s rule — the ground says *where*, the body says *when* — is exactly what a locked-line dash needs, and one telegraph language means one read to learn. This spends **no `Attack_Style` slot**: `Charger` is a Movement Style borrowing the rendering.
- **The second `Attack_Style` slot is banked.** Three attack styles against five movement styles is fifteen cells for a nine-entry roster; the roster is nowhere near exhausting what the axes already express, and a variant no rung brief demands is a stat wearing a discriminant. The slot stays open for whatever playtesting proves missing.
- **The palette is repaletted to five evenly-spaced hues**: Grounded green, Swarmer yellow, Floater violet (keeps — it is the established wall-ignorer), Charger red, Inert cyan. The existing three sat at RED / VIOLET / ORANGE ([main.odin:828](../../../main.odin)), and red-to-orange is 30 degrees — already the weakest pair before two more families arrive. The semantics also land right way round: the loudest hue belongs to the thing that dashes at you, not to the baseline walker. Five constants, and this ticket authors the whole roster anyway.
- **The Boss's licence to break the hue convention is a licence on *value*, not hue.** Five evenly-spaced families leave no hue free, so the Warden goes near-white — which no family occupies, and which no floor palette from [Per-map theming](07-per-map-theming-and-ambient-effects.md) should either. [Enemy variety model](01-enemy-variety-model.md) granted the licence without noticing there would be nothing left to spend it on.
- **`Melee.attack_range` is authored per kind, not inherited.** It is measured centre-to-centre ([enemy.odin:751](../../../enemy.odin)), so a 46px body with today's `attack_range = 10` **cannot reach the player at all** — a 24px player standing against its edge is 23px+ from its centre. The authoring rule is `attack_range >= body_size/2 + 12`. This is why Breaker carries a Tell-area attack rather than Melee, and it is a live hazard for any future heavy melee kind.
- **Payout anchors at 0.6 x `max_health`, with named deviations.** Health is what the player spends *time* on, it satisfies [Elite and affix tier](10-elite-and-affix-tier.md)'s "price a heavy at the bodies it replaces" by construction (health is additive), and it reproduces today's `.Basic = 30` at 50hp exactly. Three kinds deviate deliberately: **Sentry** pays below anchor (35 vs 42) because a stationary enemy is the safest kill on the roster; **Lancer** pays above (50 vs 36) as the highest threat per body; **Mite** pays far below (3 vs 12) for the economy reason below.
- **`base_gold` x `gold_multiplier` collapses to one `gold: int`.** Only the product is ever read ([account_progression.odin:27](../../../account_progression.odin)), so the two fields are indistinguishable in effect and invite `{base_gold = 15, gold_multiplier = 2.0}` with nobody able to say later which half meant something. The pair's own comment justified it as avoiding a data-shape migration for "a future enemy-variety effort" — this is that effort, and [ADR-0020](../../../docs/adr/0020-enemy-kind-is-the-authored-unit.md) folds the table into `Enemy_Preset` regardless, so the migration happens either way.
- **Kinds carry forward up the ladder, but thin.** A debuting kind takes slots from the ones below it. Retiring kinds outright makes the ladder read as five separate games rather than one that accumulates; holding density constant makes the top rung a wall of everything at once. Rung 5's adds exist to deny the player a static firing position, not to compete with the Tell for attention.
- **`Kills_Reached` stays a rung-3-and-below tool.** It reads `total_kills` across all kinds, and today's authored gate is `count: 15` — which a swarm rung satisfies in seconds, silently converting the pacing lever into a time lever. No code change: the condition does what it says, and the fix is that a swarm rung gates on `Time_Elapsed` instead. Recorded here so nobody authors a kills gate on rung 4 and wonders why the timeline collapsed.

### The rung mixes

Filling [Map ladder shape](03-map-ladder-shape.md)'s briefs, which were written deliberately without naming kinds:

- **Rung 1 — Desert Dungeon.** Grunt, Spitter. Sparse and sequential. *Slow grounded melee with a light ranged accent.*
- **Rung 2 — Warren.** + Wraith, Lancer. Grunt stays dense, Spitter thins. *Melee from an unseen bearing* — the Wraith takes a literally unseen bearing through a wall, and the Lancer punishes the straight-line kiting the warren already denies. Enemy and map teach the same lesson from two sides.
- **Rung 3 — Hall.** + Sentry, Breaker. Lancer stays, Wraith thins. *Sustained ranged chip with a melee escort.* A hall with long sightlines and open crossings is the right classroom for both: the Sentry teaches closing distance, and the Breaker teaches the Tell read two rungs before the boss needs it. Both want the legible geometry rung 3 has and rung 4 deliberately does not.
- **Rung 4 — Ring.** + Mite, Gazer. Mite dominates the count; everything else drops to accents; Breaker supplies pressure that is not more bodies. *Swarm density.* The Gazer is what makes a tight loop hostile — rung 4's dense interior is cover against everything on the roster except a wall-ignoring shooter, which turns that interior into a firing position.
- **Rung 5 — Boss keep.** Warden, plus thin Mite and Grunt only.

This graduates [Enemy behaviours](../../enemy-behaviours/map.md)'s fog item "Spawner content authoring — which levels/spawners actually place Floater and Swarmer enemies, and in what mix", and the enemy half of [Account progression](../../account-progression/map.md)'s "exact numeric values" item.

### `Swarmer` is broken, and the fix is scoped here

Raised by the human while resolving this ticket, confirmed in code, and load-bearing on the roster: rung 4 is "one tight loop, dense interior, no safe corner" and the Mite is its workhorse.

- **`Swarmer` is the only Movement Style that both collides and does not path.** [enemy.odin:740](../../../enemy.odin) is `seek_dir := normalize0(target - pos)` — a straight-line seek — and the delta then goes through `move_actor`, which resolves against the tilemap. `Grounded` paths via `chase_to`/BFS; `Floater` skips collision entirely so it cannot get stuck. `Swarmer` gets the worst half of each and wedges on any wall between it and its slot.
- **Pathing alone would not fix it.** `assign_swarmer_slots` ([enemy.odin:466](../../../enemy.odin)) places ring slots by pure trigonometry around the player with **no wall check**, so a slot routinely lands inside a wall. BFS to an unreachable cell fails, `chase_to` sets `enemy.path = {}` and falls back to straight-line at the goal — the same stuck enemy, now paying for a BFS as well.
- **Both halves are fixed.** A Swarmer routes to its slot the way `Grounded` routes to the player, *and* a slot landing in a wall slides around the ring to the nearest open bearing before assignment. The ring is the mechanic — enemies taking distinct approach angles instead of converging on one point — and a ring with a third of its slots inside geometry is not surrounding the player, it is queuing.

### `MAX_ENEMIES` is not the ceiling; per-enemy pathfinding is

The human raised that the cap can be far higher — 4096 rather than 24. That is right, and it changes what the roster is authored against, but the cap was never what bound.

- **Rung 4 peaks around 150-250 concurrent**, roughly 10x today. The gameplay view is 320x180px ([Per-map theming](07-per-map-theming-and-ambient-effects.md) measured it), so a 16px Mite is 256px^2 against 57,600 — about 225 Mites would tile the screen solid. 150-250 is roughly 20% coverage in the player's immediate area: a crowd you route around rather than shoot through, which is what "the threat is the count" has to mean to be a distinct skill.
- **`MAX_ENEMIES` rises to 4096 and stops being a design input.** It becomes a safety rail against a runaway `Repeating` trigger, not a budget the ladder is authored against. This makes rung 4's brief literally true for the first time — at 24 you cannot author a swarm, only a squad, and [Map ladder shape](03-map-ladder-shape.md) wrote "many cheap fast bodies" against a ceiling that could not deliver it. [Boss model](05-boss-model.md)'s reserved boss slot becomes moot, and [Elite and affix tier](10-elite-and-affix-tier.md)'s "at the cap, more pressure can only mean heavier bodies" loses its cap argument — the Breaker keeps its place on the Tell-carrier argument, which never depended on the ceiling.
- **What actually binds is per-enemy BFS.** `chase_to` calls `find_path` unconditionally every frame per Grounded enemy ([enemy.odin:826](../../../enemy.odin)); each call heap-allocates a `map[Vec2i]Vec2i` plus a queue, floods up to `MAX_SEARCH_NODES :: 1024` cells, then frees them, and separately `delete`s and reallocates that enemy's `Path`. At 4096 that is roughly 4M node visits and 8192 alloc/free pairs per frame. `assign_swarmer_slots` is O(n^2) — n Swarmers make n slots, each scanned for each Swarmer — which is 8.4M distance checks at 4096. And `compute_separation_direction` is grid-bucketed but degrades toward O(n^2) when hundreds of bodies share one 3x3 neighbourhood, which is precisely the case it exists for.
- **Mite drops to 3 Gold, breaking the anchor deliberately.** Gold rolls per body at `PICKUP_DROP_CHANCE :: 0.25` then 1-in-3 for Gold ([pickup.odin:60](../../../pickup.odin)), so income scales **linearly with body count**. [Map ladder shape](03-map-ladder-shape.md) set `victory_multiplier` shallow (1.5 -> 2.5) explicitly because "gross income already climbs on its own as the roster densifies" — an assumption made against a 24 cap. At 200 Mites paying 10, rung 4 prints ~170 Gold in Mites per wave and the top rung becomes strictly dominant the moment it unlocks, which is the exact failure the shallow multiplier was protecting against. A swarm body is priced as a *fraction* because you kill them by the dozen: the anchor prices a body by the time it costs you, and a Mite in a crowd of 200 costs a fraction of the attention one Grunt does.

### `Enemy_Kind` persists by name, not ordinal

[Enemy variety model](01-enemy-variety-model.md) made `Spawn_Composition_Entry` `{kind: Enemy_Kind, count: int}`, so `Enemy_Kind` now rides through `data/maps/*.json` — which it never did before. An enum marshals as its **ordinal**, so inserting a kind mid-enum silently renumbers every composition entry in every map file and Grunts become Wraiths.

[ADR-0020](../../../docs/adr/0020-enemy-kind-is-the-authored-unit.md) removed a union-guessing persistence hazard and introduced an ordinal one in the same move, with the phrase "with a plain enum there". [Map ladder shape](03-map-ladder-shape.md) hit the identical problem for `Map_Name` and solved it with identity strings, and `active_map_pointer` already stores `map_identity_string(name)` for the same reason. A nine-entry roster that will grow makes mid-enum insertion certain, and the failure is silent — the wrong enemies simply spawn.

**Composition entries persist the kind by name.** The alternative — "always append to the enum" — is a convention with no enforcement. This also frees `Enemy_Kind` to be ordered readably, by rung as the table above, rather than in append-only historical order. [ADR-0020](../../../docs/adr/0020-enemy-kind-is-the-authored-unit.md) is amended.

### Not decided here

- **Exact health, Gold and speed tuning**, beyond the threshold-crossing numbers named above. Playtesting, per this map's standing fog item.
- **How enemies path at swarm scale.** Graduated into [Enemy pathing at swarm scale](11-enemy-pathing-at-swarm-scale.md), which is the roster's precondition.

### Follow-on

- **[Weapon catalog expansion](08-weapon-catalog-expansion.md)** is unblocked, and now has a roster to be judged against — including a 220hp boss and crowds of 20hp bodies, which is a far wider target spread than the eight current weapons were tuned for.
- **[Enemy pathing at swarm scale](11-enemy-pathing-at-swarm-scale.md)** is created, taking the per-enemy BFS cost, the O(n^2) slot assignment, `MAX_SEARCH_NODES`, and both halves of the Swarmer fix.
- **[Content-scale integration sweep](09-content-scale-integration-sweep.md)** takes the `ENEMY_SIZE_MAX` raise to ~72, the `Enemy_Kind`-by-name persistence migration, the five-constant repalette, the `attack_range` authoring rule, and pickup/draw cost at 10x body count.
