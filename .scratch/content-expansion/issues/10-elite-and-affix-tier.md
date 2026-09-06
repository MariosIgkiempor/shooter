# Elite and affix tier

Type: grilling
Status: resolved

## Question

Does an **elite** tier belong between ordinary enemies and bosses — and if so, is an elite its own `Enemy_Kind`, or a modifier layered onto one?

Graduated from this map's fog once [Enemy variety model](01-enemy-variety-model.md) settled what a kind is. The fog item's stated blocker was exactly that: "can't be phrased sharply until Enemy variety model says what a kind is". A kind is now an `Enemy_Preset` entry in a flat `[Enemy_Kind]` table — `movement`, `attack`, `max_health`, `color`, Gold payout — stamped onto an `Enemy` at spawn, and a Map's composition authors `(kind, count)` and nothing else.

That makes the question sharp, and gives it three branches:

- **Elites are ordinary kinds.** An "Armoured Wasp" is simply another `Enemy_Kind` entry with more health and a different colour. Costs nothing new; the enum and the catalog absorb it. But every base × affix combination is a separate authored entry, and the player has no cue that two entries are related.
- **Elites are a modifier applied at spawn.** `Enemy` gains an affix (or a small set), applied on top of a preset — scaling health, tinting the body, adding a behaviour. This is the one thing in the model that would make an `Enemy` no longer a pure stamp of its preset, which [ADR-0020](../../../docs/adr/0020-enemy-kind-is-the-authored-unit.md) deliberately made it. It also reopens the per-rung-scaling question that [Enemy variety model](01-enemy-variety-model.md) closed, from a different direction.
- **No elite tier.** Pressure between ordinary enemies and a boss comes from composition — denser triggers, harder kinds later — which is what [Map ladder shape](03-map-ladder-shape.md) already owns.

To settle:

- **Where an elite is authored.** A Map's composition authors `(kind, count)`; an affix has no place to be authored there without widening the entry that [ADR-0020](../../../docs/adr/0020-enemy-kind-is-the-authored-unit.md) just narrowed. Does the affix come from the kind, from the rung, or from a widened composition entry — and if the last, is that ADR-0020's first amendment?
- **What an elite *does* to the player.** The same bar every roster entry faces: a new pressure, not a stat bump wearing a colour.
- **How it reads.** Colour is now a per-kind preset field with hue-tracks-Movement-Style as an authoring convention. An elite either takes a colour of its own (breaking the convention deliberately, the way a boss may) or is marked some other way — outline, size, particle — with size already spoken for by `max_health`.
- **Its payout.** `Enemy_Preset` carries the Gold payout, so an affixed enemy either pays its base kind's Gold or needs a rule that scales it.
- **Whether the boss shares this machinery.** [Boss model](05-boss-model.md) asks where phases and telegraphs live and lists "a flag or tier on `Enemy_Kind`" as one branch. If elites are a modifier, a boss may be the extreme end of the same mechanism rather than its own type — decide here whether that is a live option for ticket 05, or explicitly not.

## Answer

**No elite tier and no affix layer. A heavy enemy is an ordinary `Enemy_Kind` with more health, and nothing modifies an enemy after it is stamped from its preset.** [ADR-0020](../../../docs/adr/0020-enemy-kind-is-the-authored-unit.md) is amended with the finding rather than reversed.

### Settled

- **The affix branch is dead, and not on the grounds the ticket expected.** The ticket framed the cost as breaking [ADR-0020](../../../docs/adr/0020-enemy-kind-is-the-authored-unit.md)'s pure-stamp rule. The harder problem is that an affix has **nowhere to show itself**: colour is a per-kind preset field ([Enemy variety model](01-enemy-variety-model.md)), size is *derived* from `max_health` in `enemy_body_size` ([main.odin:841](../../../main.odin)) and deliberately not authorable, and opacity is the remaining-health fade ([main.odin:1094](../../../main.odin)). All three identity channels are spent. Borrowing size is the worst case rather than a workaround — a health affix makes the body physically grow, so its cue *contradicts* the base kind's silhouette. It is not unmarked, it is mismarked.
- **There is no authoring site either.** A `(kind, count)` composition entry has no room for one, and widening it is precisely the narrowing [ADR-0020](../../../docs/adr/0020-enemy-kind-is-the-authored-unit.md) is. So the affix is not ADR-0020's first amendment; it is the thing ADR-0020 decided against, arriving from the other side.
- **The rule generalises and is now written down.** Nothing modifies an enemy after the stamp — no affix, no per-rung scaling, no champion aura, no Run-wide difficulty multiplier. [Enemy variety model](01-enemy-variety-model.md) closed per-rung health scaling for one case; this closes the class. It lives in `CONTEXT.md`'s **Enemy Kind** entry, so the next proposal has to argue against a stated rule rather than rediscover the argument.
- **Heavy kinds do exist, and the ladder needs them.** `fire_spawn_composition` returns outright at `MAX_ENEMIES :: 24` ([enemy.odin:601](../../../enemy.odin)) and [Map ladder shape](03-map-ladder-shape.md) authored rung 4 at peak concurrency against that ceiling, with a rung still above it. At the cap, more pressure can only mean heavier bodies. Separately, [Boss telegraph and phase feel](06-boss-telegraph-and-phase-feel.md) wants the Tell read taught below rung 5, and a Tell-carrier **plants for its whole Tell** — which is only survivable on a body that does not die to incidental fire. Both needs are met by roster entries, not by a mechanism.
- **A heavy kind stays at or below ~48px / ~136 health.** This is a code constraint, not taste. `update_enemies` builds **one shared** `build_inflated_collision_map(tilemap, 1)` for every enemy ([enemy.odin:708](../../../enemy.odin)), and [Boss model](05-boss-model.md) justified the boss's own second map as cheap *because there is exactly one boss*. A heavy past the one-tile envelope needs its own map, and that cost is per distinct heavy size, several at a time. Raising `ENEMY_SIZE_MAX` for the boss hands the whole roster headroom silently, so the ceiling is an authoring rule in [Enemy catalog](04-enemy-catalog.md) rather than a second clamp. `10 + 0.28 x max_health` puts it at roughly **136 health — about 2.7x a 50-health basic** — which is the number the catalog tunes against.
- **Relatedness needs no new convention.** The affix branch's one genuine advantage was the player seeing that an elite is a *version of* something. It comes free: hue already tracks Movement Style, and a heavy is bigger by construction, so a heavy grounded melee is the same hue as its light cousin in a bigger square without anyone authoring the relationship.
- **A heavy may not break the hue convention.** [Enemy variety model](01-enemy-variety-model.md) left the convention breakable for "a boss or elite whose point is looking unlike the roster"; that licence is the boss's alone. The boss earns it by being one entity, on one rung, carrying a Resource indicator, in an arena [Map ladder shape](03-map-ladder-shape.md) built for reading it. A heavy appears in crowds, where hue is how the player knows what a body does.
- **A heavy pays its base rate and rolls the ordinary drop.** `maybe_spawn_pickup` rolls `PICKUP_DROP_CHANCE :: 0.25` and *then* picks uniformly among three pickup kinds ([pickup.odin:60](../../../pickup.odin)), so any kill pays Gold roughly one time in twelve. Trading four bodies for one heavy holds expected Gold flat and **quadruples its variance** — accepted, because Gold is Account-scoped ([ADR-0016](../../../docs/adr/0016-gold-is-the-single-currency.md)) and smooths at the level that matters. No guaranteed drop below the boss: the boss's exception is justified by being once per Run at the climax, and a second exception would make it the rule.
- **"Elite" does not become a word this project uses.** No glossary entry — a term for something with no mechanism, no marker and no authoring site is how the affix returns under a new name. `CONTEXT.md`'s **Boss** entry warned off Elite as "a separate, unrelated tier", which presumed the tier existed; corrected to record it as considered and rejected.

### Answering the ticket's last bullet

The ticket asked whether the boss might be the extreme end of an elite mechanism, and whether that was a live option for [Boss model](05-boss-model.md). It is not, and [Boss model](05-boss-model.md) resolved first and independently: the boss is an `Enemy_Kind` in the ordinary pool. Elites being kinds means there is **one mechanism**, not two — which is the outcome that bullet was hoping for, reached without a tier. Of the boss's kind-level extras, only the Tell-carrying `Attack_Style` is shared with ordinary kinds (already settled by [Boss model](05-boss-model.md)); phases, the reserved `MAX_ENEMIES` slot, the guaranteed drop, the Resource indicator and the raised size ceiling stay the boss's.

### Not decided here

- **Which heavy kinds exist, and their numbers.** [Enemy catalog](04-enemy-catalog.md)'s, like every other roster entry.

### Follow-on

- **[Enemy catalog](04-enemy-catalog.md)** is unblocked, and inherits four constraints: the ~136-health heavy ceiling, no hue-convention break below the boss, payout priced at the bodies a heavy replaces, and no guaranteed drop.
- **[Content-scale integration sweep](09-content-scale-integration-sweep.md)** takes the global `ENEMY_SIZE_MAX` raise and the single shared inflated collision map.
