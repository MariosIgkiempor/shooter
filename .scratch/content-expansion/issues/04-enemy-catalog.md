# Enemy catalog

Type: grilling
Status: open

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
