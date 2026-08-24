Type: task
Status: resolved
Blocked by: 01

## Question

Extend the `Enemy_Behaviour_Save` persistence pattern to whatever shape the data-structure ticket settles on for `Enemy` holding Movement Style + Attack Style.

Today (`enemy.odin:67-106`): `Enemy_Behaviour_Kind` enum discriminant + `Enemy_Behaviour_Save` struct with one `Maybe(T)` field per variant + explicit `enemy_behaviour_to_save`/`enemy_behaviour_from_save` switches both ways, specifically to avoid `core:encoding/json`'s union-decoding hazard (it tries each variant in declaration order and keeps the first that parses, so an empty `{}` would silently decode as the wrong variant). Call sites are `main.odin:105` (load) and `main.odin:138` (save), inside the per-spawner loop.

This same discriminant-plus-explicit-switch pattern needs replicating for whatever the new shape is — likely two DTOs (one per axis) or one combined DTO with more `Maybe` fields, each with its own kind enum and explicit to/from-save switches. Follow the existing pattern exactly; don't introduce a new persistence idiom for this one case.

This is manual implementation work gated on the data-structure ticket's decision, not a decision itself — work it directly once unblocked, no research/prototype/grilling skill call needed unless a genuine ambiguity turns up.

## Answer

Kept as a handoff checklist rather than executed now, for the same reason as the Editor and debug overlay rework ticket: the map's Destination defers implementation to a separate follow-on, and ticket 01's `Enemy.movement`/`Enemy.attack` split hasn't been applied to `enemy.odin` yet, so there's no real struct to persist against. Same user decision applies here (keep this map decision-only).

**Checklist for the implementation follow-on**, following the existing `Enemy_Behaviour_Save` pattern exactly (one DTO per axis, not a new idiom):

```odin
Movement_Style_Kind :: enum { Grounded, Floater, Swarmer, Inert }
Movement_Style_Save :: struct {
	kind:     Movement_Style_Kind,
	grounded: Maybe(Grounded) `json:"grounded,omitempty"`,
	floater:  Maybe(Floater) `json:"floater,omitempty"`,
	swarmer:  Maybe(Swarmer) `json:"swarmer,omitempty"`,
}

Attack_Style_Kind :: enum { Melee, Ranged, Inert }
Attack_Style_Save :: struct {
	kind:   Attack_Style_Kind,
	melee:  Maybe(Melee) `json:"melee,omitempty"`,
	ranged: Maybe(Ranged) `json:"ranged,omitempty"`,
}
```

Each gets its own `_to_save`/`_from_save` explicit-switch pair, mirroring `enemy_behaviour_to_save`/`enemy_behaviour_from_save` (enemy.odin:83-106) exactly — never let `json.unmarshal` see the live union directly, same hazard as today (declaration-order variant guessing on an all-optional-fields struct).

`Spawner` (enemy.odin:48-65) needs two template fields instead of one, each following the existing `json:"-"` + parallel `_save` field convention:
```odin
Spawner :: struct {
	position:  Vec2,
	interval:  f32,
	timer:     f32,
	animation: Animation_Name,

	movement_template:      Movement_Style `json:"-"`,
	movement_template_save: Movement_Style_Save,

	attack_template:      Attack_Style `json:"-"`,
	attack_template_save: Attack_Style_Save,
}
```

`main.odin:105` (load) and `main.odin:138` (save) — the per-spawner loop converts both axes now instead of one; otherwise unchanged in structure.

Reference for the target shape: [Enemy data-structure shape](issues/01-enemy-data-structure-shape.md)'s Answer section has the exact field list this DTO pair needs to round-trip.
