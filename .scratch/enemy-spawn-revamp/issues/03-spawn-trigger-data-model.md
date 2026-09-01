Type: grilling
Status: resolved

## Question

Design the `Spawn_Trigger` shape that replaces today's `Spawner`
(`enemy.odin:88-101`) entirely — no fixed position, no single fixed
template, no per-spawner `interval` ticking forever. A `Map` will hold a
timeline of these instead of `spawners: [dynamic]Spawner`
(`map.odin:17`).

Needs to settle:

- **Condition.** A bare union or tagged variant with (at least)
  `Time_Elapsed(seconds: f32)` and `Kills_Reached(count: int)`, read
  against the existing Run-scoped `Player` fields — `survival_seconds`
  and `total_kills(kills)` (`account_progression.odin:48`) — per
  [ticket 01](01-level-kill-and-time-counters.md)'s resolution: there is
  no separate per-map/per-level counter state, a Run and its one Map are
  the same lifetime today.
- **Mode.** `One_Shot` (a fixed composition-count batch fired once when
  the condition is crossed) vs. `Repeating` (an ongoing interval-based
  spawn, mirroring today's `Spawner.interval`/`timer` mechanism) — the
  level format needs to support both, so this is a variant, not a global
  switch. For `Repeating`, settle whether/how it ever stops (a duration,
  an enemy-count cap, or "runs until the level ends").
- **Composition.** A list of entries, each an existing `Movement_Style` +
  `Attack_Style` pair plus a count — generalizing today's single fixed
  template per spawner into a mix of several compositions per trigger.
  Confirm this reuses the exact `Movement_Style`/`Attack_Style` bare
  unions from the [Enemy behaviours map](../../enemy-behaviours/map.md)
  unchanged.
- **Concurrency and firing semantics.** Can multiple triggers be active
  at once (e.g. a `Repeating` trigger still running when a later
  `One_Shot` trigger's condition crosses)? Does each trigger fire at most
  once when its condition is first crossed (edge-triggered), or does it
  keep re-checking? Does the existing global `MAX_ENEMIES` cap
  (`enemy.odin:10`) remain a single shared ceiling across all active
  triggers, silently dropping/delaying spawns past it?

## Answer

Settled via grilling — new vocabulary recorded in
[CONTEXT.md](../../../CONTEXT.md) as **Spawn Trigger**. Final shape:

```odin
Spawn_Trigger :: struct {
	condition:   Spawn_Condition,
	mode:        Spawn_Mode,
	composition: []Spawn_Composition_Entry,

	// Runtime-only, never persisted — mirrors how today's `Spawner`
	// already mixes blueprint fields with a runtime `timer` on one
	// struct (see the Maps map's precedent for this).
	fired:   bool, // One_Shot: already spawned. Repeating: already activated.
	timer:   f32,  // Repeating: counts down to the next interval spawn.
	elapsed: f32,  // Repeating: seconds since activation, checked against duration.
}

Spawn_Condition :: union { Time_Elapsed, Kills_Reached }
Time_Elapsed  :: struct { seconds: f32 }
Kills_Reached :: struct { count: int } // absolute cumulative Run kill total — same value the HUD counter (ticket 01) shows, not a separate count

Spawn_Mode :: union { One_Shot, Repeating }
One_Shot :: struct {}
Repeating :: struct {
	interval: f32,
	duration: f32, // <= 0 means indefinite: runs until the Run ends
}

Spawn_Composition_Entry :: struct {
	movement_template:      Movement_Style `json:"-"`,
	movement_template_save: Movement_Style_Save,
	attack_template:        Attack_Style `json:"-"`,
	attack_template_save:   Attack_Style_Save,
	count: int,
}
```

`Map.spawners: [dynamic]Spawner` becomes `Map.spawn_triggers:
[dynamic]Spawn_Trigger`.

**Key decisions:**
- **Condition** reads the existing Run-scoped `Player` fields directly —
  `survival_seconds` for `Time_Elapsed`, `total_kills(kills)` for
  `Kills_Reached` — per [ticket 01](01-level-kill-and-time-counters.md).
  No new counter state.
- **Mode**'s `composition` means the same thing in both variants: "spawn
  this whole batch, all entries, all their counts, at once." `Repeating`
  just does that once per `interval` instead of once total.
- **`Repeating` stopping**: optional `duration` (seconds since
  activation); `<= 0` (the zero-value) means indefinite, matching this
  codebase's general zero-sentinel style rather than reaching for a
  `Maybe` wrapper.
- **Firing is edge-triggered and permanent**: a trigger's `condition` is
  checked once per frame only until `fired` flips true; a `Repeating`
  trigger's own interval/duration ticking afterward is independent of
  whatever made the original condition become true. A trigger never
  re-fires.
- **Concurrency**: multiple triggers (including several concurrently
  running `Repeating` ones) may be active at once — no mutual exclusion.
- **`MAX_ENEMIES`**: stays a single shared global ceiling
  (`enemy.odin:10`); a spawn attempt that can't fit is silently skipped,
  no queueing — `Repeating` just tries again next interval, `One_Shot`'s
  batch may come up short.

**Ripple effects on this map**: unblocks
[Editor spawn-trigger authoring](04-editor-spawn-trigger-authoring.md)
and [Map format migration and baking tool](05-map-format-migration-and-baking-tool.md),
both already scoped against this shape. `Spawn_Composition_Entry`
reuses `Movement_Style`/`Attack_Style`'s existing `*_Save` mirror
pattern from `Spawner` unchanged — ticket 05 has an exact precedent to
follow, not a new persistence shape to invent.
