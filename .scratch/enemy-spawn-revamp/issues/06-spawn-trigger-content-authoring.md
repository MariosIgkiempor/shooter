Type: grilling
Status: resolved

## Question

Now that the `Spawn_Trigger` shape ([ticket 03](03-spawn-trigger-data-model.md))
and its editor authoring UX ([ticket 04](04-editor-spawn-trigger-authoring.md))
are both decided, author the actual Spawn Trigger timeline content: which
time/kill thresholds, modes, and enemy compositions get placed on the
existing desert dungeon map (`data/maps/desert_dungeon.json`), replacing
its current fixed `Spawner`s entirely — and whether any guidance is needed
for future maps' timelines, or whether this is purely a per-map authoring
exercise with no general rule.

This is a content/pacing design question (how hard, how fast, what mix),
not a data-shape or UX question — those are both already closed. Parallel
to how the enemy-behaviours map deferred its own "which spawners actually
place Floater and Swarmer enemies, and in what mix" question as pure
content authoring.

## Answer

**Existing content, confirmed via a fresh read of `data/maps/desert_dungeon.json`**:
6 spawners, all `interval: 3.0`, covering all three Movement Styles ×
both Attack Styles (already implemented and tuned, not just specified on
paper):

1. Grounded + Melee (speed 40, damage 10, range 10, cooldown 1)
2. Grounded + Ranged (speed 40, min/max range 60/120, damage 8, projectile speed 200, fire_rate 1)
3. Floater + Melee (speed 30, wobble amplitude 80 @ 3Hz, pull 0.35)
4. Floater + Ranged (same Floater tuning + same Ranged stats as #2)
5. Swarmer + Melee (speed 50, same Melee stats as #1)
6. Swarmer + Ranged (speed 50, same Ranged stats as #2)

**New timeline — 3 Spawn Triggers, reusing these exact 6 compositions'
stats redistributed across phases, no rebalancing**:

```odin
spawn_triggers = {
	// Phase 1 - baseline trickle, from the start of the Run
	Spawn_Trigger{
		condition = Time_Elapsed{seconds = 0},
		mode = Repeating{interval = 3, duration = 0}, // indefinite
		composition = {
			{movement = Grounded{speed = 40}, attack = Melee{damage = 10, range = 10, cooldown = 1}, count = 1},
			{movement = Grounded{speed = 40}, attack = Ranged{min_range = 60, max_range = 120, damage = 8, projectile_speed = 200, fire_rate = 1}, count = 1},
		},
	},
	// Phase 2 - mix-in, gated on player aggression rather than the clock
	Spawn_Trigger{
		condition = Kills_Reached{count = 15},
		mode = Repeating{interval = 4, duration = 0}, // indefinite
		composition = {
			{movement = Floater{speed = 30, wobble_amplitude = 80, wobble_frequency = 3, pull_strength = 0.35}, attack = Melee{damage = 10, range = 10, cooldown = 1}, count = 1},
			{movement = Floater{speed = 30, wobble_amplitude = 80, wobble_frequency = 3, pull_strength = 0.35}, attack = Ranged{min_range = 60, max_range = 120, damage = 8, projectile_speed = 200, fire_rate = 1}, count = 1},
		},
	},
	// Phase 3 - late escalation, layers on top of the still-running Phase 1/2 triggers
	Spawn_Trigger{
		condition = Time_Elapsed{seconds = 150}, // 2.5 min
		mode = Repeating{interval = 3, duration = 0}, // indefinite
		composition = {
			{movement = Swarmer{speed = 50}, attack = Melee{damage = 10, range = 10, cooldown = 1}, count = 2},
			{movement = Swarmer{speed = 50}, attack = Ranged{min_range = 60, max_range = 120, damage = 8, projectile_speed = 200, fire_rate = 1}, count = 2},
		},
	},
}
```

**Why this shape:**
- **Three phases** (Q1): an always-on Grounded trickle from second 0, a
  Floater mix-in gated on kills rather than the clock (so an aggressive
  player sees variety sooner), and a heavier Swarmer wave at 2.5 minutes
  — each phase's trigger is `Repeating` with no `duration`, so once a
  phase turns on it stays on, layering with the ones before it rather
  than replacing them (per [ticket 03](03-spawn-trigger-data-model.md)'s
  "multiple triggers may run concurrently" decision) — pressure genuinely
  compounds over a Run instead of just relocating.
- **Mixed condition types** (Q2): `Time_Elapsed` anchors the guaranteed
  start and late-game floor (a passive player still eventually faces the
  Phase 3 wave); `Kills_Reached` on Phase 2 makes the mid-game escalate
  faster specifically for a player who's racking up kills, a genuinely
  different feel from a pure clock.
- **Reused compositions, unchanged stats** (Q3): all six
  movement/attack stat blocks above are copied verbatim from the
  existing spawners — this ticket only re-times and re-groups them, it
  doesn't rebalance them (rebalancing individual enemy stats is out of
  this map's scope regardless).
- **No general authoring guideline for future maps** (Q4): explicitly
  decided against — which phases, thresholds, and enemy mix a map uses
  is left as an open creative/game-design call for whoever authors that
  map next, not something this map should template or constrain.

**Migration note**: this content is exactly what
[ticket 05](05-map-format-migration-and-baking-tool.md)'s one-off manual
`data/maps/desert_dungeon.json` edit should produce — this ticket
specifies the target content, ticket 05 specifies the mechanical file
format it lands in; performing the actual edit is implementation, not
part of this map.

**This closes the map.** All three destination points (off-screen
placement, the Spawn Trigger timeline mechanism, the Run-scoped HUD
counters) plus their editor UX and persistence migration are now fully
specified, and this ticket supplies real authored content to prove the
shape works end-to-end. Nothing remains to decide before implementation.
