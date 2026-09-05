# Enemy catalog

Type: grilling
Blocked by: 01, 10
Status: open

## Question

Given the model settled by [Enemy variety model](01-enemy-variety-model.md), what is the actual roster?

Not "how are enemies represented" but "which ones exist, and why each earns its place". For each entry:

- **What it does to the player** — the pressure it applies that no existing enemy applies. A roster where three entries all mean "walk at you and touch you" is one enemy with three colours.
- **Its axis composition or preset values** — movement, attack, health, speed, size, colour, in whatever shape ticket 01 decided.
- **Its Gold payout.** This graduates [Account progression](../../account-progression/map.md)'s standing fog item: `enemy_gold_presets` holds a single `.Basic = {base_gold = 30, gold_multiplier = 1.0}` marked "placeholder, content-authoring". Payout should track the pressure the enemy applies, and note that Fortune scales Gold gain on top.
- **Where it enters the ladder** — which rung it first appears on, feeding [Map ladder shape](03-map-ladder-shape.md)'s escalation curve.

Constraints to design against:

- **Every enemy is a square** — commit `665ad38` superseded [Art revamp](../../art-revamp/map.md) ticket 01's rectangle/circle/triangle vocabulary and deleted `Actor_Shape_Kind`. Identity is carried by **colour** (a per-kind `Enemy_Preset` field, by [Enemy variety model](01-enemy-variety-model.md)), **size** (derived from `max_health` via `enemy_body_size`, clamped to 10..48px) and **opacity** (fades as health drops). There is no shape budget, but colour and size are not free either: size is *not* independently authorable, so a chunky enemy is a high-health enemy by construction. The authoring convention is that hue tracks Movement Style — wall-ignorers in the violet family, and so on — kept in the catalog rather than enforced in code, so a boss or elite can break it deliberately.
- `MAX_ENEMIES :: 24` caps the field. A roster designed around swarms of twenty competes with itself for slots.
- Existing coverage: today the only authored composition is Grounded/Floater/Swarmer crossed with Melee/Ranged/none. The catalog should say which of those nine cells are actually worth shipping, not assume all of them are.

This also graduates [Enemy behaviours](../../enemy-behaviours/map.md)'s fog item "Spawner content authoring — which levels/spawners actually place Floater and Swarmer enemies, and in what mix". Clear it from that map when this resolves.
