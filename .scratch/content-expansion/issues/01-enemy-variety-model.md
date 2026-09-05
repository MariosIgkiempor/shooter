# Enemy variety model

Type: grilling
Status: resolved

## Question

What *is* an enemy type in this codebase?

Today `Enemy_Kind` is a single-member enum (`Basic`, [enemy.odin:18](../../../enemy.odin)) whose only jobs are indexing `enemy_gold_presets` and the per-kind kill tally. All actual variety comes from composing `Movement_Style` x `Attack_Style`, authored as two loose templates per `Spawn_Composition_Entry`; `spawn_enemy_at` hardcodes `kind = .Basic` for everything it makes, and every enemy in the game shares one global `ENEMY_MAX_HEALTH :: 50`.

Adding enemies forces a choice this map cannot route around:

- **`Enemy_Kind` becomes the authored unit** — a real preset table bundling movement, attack, health, gold, size and colour, the way `weapon_presets` does for `Weapon_Kind`. `Spawn_Composition_Entry` would author an `Enemy_Kind` instead of two templates, and per-type health would replace the global constant.
- **The axes expand instead** — new `Movement_Style` and `Attack_Style` variants, with `Enemy_Kind` left as a thin payout tag. Note that [Enemy behaviours](../../enemy-behaviours/map.md) explicitly ruled Attack Style expansion **out of scope** for that effort; taking this branch redraws that boundary.
- **Both**, with a rule for which axis a given piece of variety belongs on.

Sub-questions the answer has to settle:

- Does a preset table displace what the Spawn Trigger timeline authors, or sit alongside it? A Map's composition entries are the only place enemies are ever placed.
- What happens to per-type visual identity? Actor shapes are fixed per Movement Style today (Grounded = rectangle, Floater = circle, Swarmer = triangle, [Art revamp](../../art-revamp/map.md) ticket 01) — a preset-driven roster wants colour and size to distinguish kinds sharing a shape.
- Where does `ENEMY_MAX_HEALTH` go, and does health scale per ladder rung as well as per kind (see [Map ladder shape](03-map-ladder-shape.md))?

Weigh this against [ADR-0001](../../../docs/adr/0001-weapon-wrapper-struct.md) (bare union vs. wrapper struct) and [enemy-behaviours ticket 01](../../enemy-behaviours/issues/01-enemy-data-structure-shape.md), which extended that rule to two sibling axes. The `weapon_presets` table is the counter-precedent: a flat enum keyed into a preset table, which is exactly what option one proposes for `Enemy_Kind`.

If this redraws enemy-behaviours' Attack-Style scope boundary, **append an amendment pointer** into that map rather than silently overriding it.

## Answer

**`Enemy_Kind` becomes the authored unit, backed by a preset table, and the axes stay open too** — the ticket's third branch ("both"), with a clear rule for which axis a piece of variety belongs on: *behaviour* goes on the `Movement_Style`/`Attack_Style` axes, *identity* (health, colour, payout, and which axis values it composes) goes on the kind.

Two premises the ticket carried were checked against the code first and both were stale or half-built:

- **The three-shape constraint no longer holds.** Commit `665ad38` — landed *after* the art revamp — unified every enemy into a square sized by `enemy_body_size(max_health)` and tinted by `Movement_Style_Kind`, faded by remaining health, and deleted `Actor_Shape_Kind` outright ([main.odin:1093](../../../main.odin)). [Art revamp](../../art-revamp/map.md) ticket 01's rectangle/circle/triangle vocabulary is superseded for enemies. The live identity vocabulary is **colour, size, and opacity** — there is no shape budget to run out of, and this map's Notes and [Enemy catalog](04-enemy-catalog.md) have been corrected.
- **Per-kind size is already wired.** `enemy_body_size` takes a `max_health` argument and is called with the global constant; its own comment names this effort as the trigger ([main.odin:832](../../../main.odin)). Only the field was missing.

### Requirements settled (round 1)

- **Per-enemy `max_health`.** The cheapest source of variety in the game, and the size coupling is the feature: "big means tanky" reads without any new art vocabulary, which is exactly what a square-only roster needs.
- **Attack Style is reopened**, redrawing [Enemy behaviours](../../enemy-behaviours/map.md)'s "attack logic stays frozen" boundary (amendment pointer appended there). Melee/Ranged alone means every enemy either touches you or shoots you, leaving the ladder nowhere to escalate but numbers. The bar is high — each variant costs a `*_Save` mirror, an editor row, and a discriminant, so it must buy a new *player response*, not a stat. One or two at most, chosen by [Enemy catalog](04-enemy-catalog.md).
- **Movement Style stays open**, with `Charger` (windup, then a committed dash along a locked line) the named candidate — the one absent player-response in the movement space, asking the player to *dodge* where nothing does today, and it rhymes with the Windup vocabulary [Boss model](05-boss-model.md) will lean on ([ADR-0004](../../../docs/adr/0004-windup-fraction-not-duration.md)). Note `Turret` needs nothing new: `movement = nil` (`.Inert`) + `attack = Ranged` already works.
- **Kinds are real, not payout tags.** A named entity with its own colour, health, size and behaviour, the way `weapon_presets` authors `Weapon_Kind`. The anonymous-composition alternative cannot carry a difficulty ladder: [Map ladder shape](03-map-ladder-shape.md) needs "harder kinds appear later" to name something, `enemy_gold_presets` needs a payout that tracks pressure, and [Enemy catalog](04-enemy-catalog.md)'s question — "which ones exist, and why each earns its place" — cannot be asked of an anonymous composition at all.

### Shape settled (round 2)

- **The preset displaces the composition templates.** `Spawn_Composition_Entry` becomes `{kind: Enemy_Kind, count: int}`; a Map picks kinds and counts and nothing else.

  This deletes the map's "persistence is a trap" hazard *at its only site*. `Spawn_Composition_Entry` is the sole place enemy unions are ever persisted ([map.odin:59-76](../../../map.odin)), so with a plain enum there: `Movement_Style_Save`/`Attack_Style_Save` and their four conversion procs are no longer needed for persistence, `map.odin`'s save/load hooks for them go, and `vendor/map-builder` loses its duplicated DTOs and both `write_*_literal` procs ([map_builder.odin:326](../../../vendor/map-builder/map_builder.odin)). The live unions survive on `Enemy` as pure runtime state, never marshalled. It also stops `desert_dungeon.json` persisting runtime fields (`attack_timer`, `wobble_phase` are baked into it today).

  Migration is six composition entries in one file, every one a clean mapping onto a named kind — not a migration.

  Cost accepted: a Map can no longer tune a one-off enemy. A variation worth authoring is worth naming, which is [Enemy catalog](04-enemy-catalog.md)'s job.

- **`Enemy_Preset` is its own type, not `[Enemy_Kind]Enemy`.** The `weapon_presets: [Weapon_Kind]Weapon` precedent breaks here on a concrete hazard: `Enemy` carries `path: [dynamic]Vec2i` ([enemy.odin:892](../../../enemy.odin)), so a table of `Enemy` values holds a live dynamic-array header per entry — the same slice-aliasing class [Maps](../../level-maps/map.md) had to guard with `clone_map` — and it would invite `enemy := enemy_presets[kind]` as a spawn path that silently shares state. It also carries `rect`, a world *position*, which is meaningless in a table.

  `Enemy_Preset` holds exactly the authored facts: `movement`, `attack`, `max_health`, `color`, and the Gold payout. **`enemy_gold_presets` folds into it** rather than remaining a second table keyed by the same enum. `spawn_enemy_at` builds an `Enemy` from a preset plus a position.

- **Colour becomes a per-kind preset field**, with hue-tracks-Movement-Style as an *authoring convention* rather than a code rule. `enemy_body_color` takes a colour instead of a `Movement_Style_Kind` ([main.odin:853](../../../main.odin)); the catalog authors palettes so wall-ignorers stay in the violet family and chargers in the red. Encoding that in the type system would mean deriving hue from movement and shade from kind — machinery to enforce a rule content can simply follow, and it would block the one case that most wants to break it: a boss or elite whose point is looking unlike the roster.

- **No per-rung health scaling, and `ENEMY_MAX_HEALTH` is deleted.** A scalar would make the same named kind differently durable per rung, contradicting the premise that the player learns kinds — and because size derives from health, a rung-5 Wasp would be visibly *bigger*, reading as a different enemy rather than a harder one. Escalation belongs to composition (harder kinds later, denser triggers, tighter `time_limit`), which is [Map ladder shape](03-map-ladder-shape.md)'s job and has richer levers. With every kind authoring health, the global constant is a claim false for all but one kind; `Enemy` gains `max_health` and the two draw-time reads use it.

### Consequences settled (round 3)

- **Tuning is code-only.** `enemy_presets` is a table in `enemy.odin`; tuning means editing it and rebuilding, exactly like `weapon_presets` — eight weapons with far more numeric surface than an enemy were dialled in that way. A `data/enemies.json` was rejected: it reintroduces a persisted file with union-shaped content, the exact hazard the displacement just deleted. A debug-panel live-tuning overlay is attractive but has no existing idiom to extend (`debug.odin` is toggles and buttons only) and is not a decision this map needs — it belongs to [Content-scale integration sweep](09-content-scale-integration-sweep.md) or to fog.

  The editor's composition UI therefore **collapses** to a kind selector plus a count, rather than growing. This reverses ticket 09's stated expectation that `editor.odin` goes stale by growing more rows.

- **`Enemy` keeps `movement`/`attack` as unions**, stamped as copies from the preset at spawn. Three fields are genuinely per-enemy and mutable — `Floater.wobble_phase` (randomised at spawn so floaters don't wobble in lockstep), `Melee.attack_timer`, `Ranged.fire_timer` — so the values cannot be shared. Splitting each variant into an authored half and a runtime half was rejected: it doubles the type count and the `*_Kind` bookkeeping, and puts a table lookup plus a switch in front of every read of what is a field access today, to save a few floats across at most 24 enemies. ADR-0001's two-sibling-bare-union shape and every existing read site stay untouched; the change is confined to how an `Enemy` is *built*.

- **[ADR-0020](../../../docs/adr/0020-enemy-kind-is-the-authored-unit.md) written.** Clears all three criteria: hard to reverse (ripples through `map.odin`, `map-builder`, the editor, and every authored map), surprising without context (a reader finding `Movement_Style_Save` deleted has nowhere to look), and a real trade-off (per-map tuning traded away deliberately). Unlike [enemy-behaviours ticket 01](../../enemy-behaviours/issues/01-enemy-data-structure-shape.md), which skipped its ADR by explicit call, this is the decision that makes ADR-0001's bare-union reasoning *stop applying to persistence* — that reversal is what a future reader trips over.

### Follow-on

- `CONTEXT.md` gains **Enemy Kind** and **Enemy Preset**; **Movement Style**, **Attack Style** and **Spawn Trigger** revised.
- Amendment pointer appended to [Enemy behaviours](../../enemy-behaviours/map.md)'s Decisions-so-far for the reopened Attack Style boundary.
- Stale three-shape premise corrected on this map's Notes and on [Enemy catalog](04-enemy-catalog.md).
- Fog graduated: the elite/affix question is now sharp, ticketed as [Elite and affix tier](10-elite-and-affix-tier.md), which blocks [Enemy catalog](04-enemy-catalog.md).
