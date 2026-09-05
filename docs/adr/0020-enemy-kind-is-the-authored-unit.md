# Enemy_Kind is the authored unit; Maps compose kinds, not behaviours

Status: accepted

`Enemy` holds two sibling bare unions, `movement: Movement_Style` and `attack: Attack_Style` (see ADR-0001 and the enemy-behaviours map). Until now those unions were also the *authored* unit: a Map's `Spawn_Composition_Entry` carried a `movement_template` and an `attack_template`, so every Map hand-tuned its own enemies field by field in the level editor, and `Enemy_Kind` was a single-member enum whose only jobs were pricing the Gold drop and keying the kill tally.

That shape does not survive a real roster. It makes an enemy anonymous — variety exists but has no name, so nothing can say "harder kinds appear on later rungs", and a per-kind Gold payout that tracks the pressure an enemy applies has nothing to hang on. It also means the same enemy authored in two Maps is two independent piles of numbers that drift apart.

`Enemy_Kind` is now the authored unit. It keys `enemy_presets: [Enemy_Kind]Enemy_Preset` — `movement`, `attack`, `max_health`, `color`, and the Gold payout, absorbing the old `enemy_gold_presets` table — and `Spawn_Composition_Entry` becomes `{kind, count}`. A Map picks kinds and counts; it cannot tune an enemy. The behavioural axes stay open and keep growing, but the rule for which axis a piece of variety belongs on is now explicit: *behaviour* goes on `Movement_Style`/`Attack_Style`, *identity* goes on the kind.

`Enemy_Preset` is its own type rather than a table of full `Enemy` values, which is where the obvious mirror of `weapon_presets: [Weapon_Kind]Weapon` was rejected. `Enemy` carries `path: [dynamic]Vec2i`, so a table of `Enemy` values would hold a live dynamic-array header per entry — the same slice-header aliasing hazard `clone_map` exists to guard — and it would invite `enemy := enemy_presets[kind]` as a spawn path that silently shares state. It also carries `rect`, a world position, meaningless in a table. A preset holds only authored facts; `spawn_enemy_at` builds an `Enemy` from one plus a position.

An `Enemy` is a **pure stamp of its preset**: the union values are copied onto it at spawn rather than looked up per read, because `Floater.wobble_phase`, `Melee.attack_timer` and `Ranged.fire_timer` are per-enemy mutable state that cannot be shared. Splitting each variant into authored and runtime halves would double the type count and put a table lookup and a switch in front of what is a field access today, to save a few floats across at most `MAX_ENEMIES` enemies. Nothing scales an enemy after the stamp — in particular there is no per-Map health multiplier, because the player is meant to learn that a given kind dies to a given amount of fire, and body size derives from `max_health`, so a scaled enemy would read as a *different* kind rather than a harder one.

## What this reverses

ADR-0001 established when to reach for a bare union rather than a wrapper struct, and the enemy-behaviours map extended it to two sibling axes. That reasoning still governs the unions' *shape*, but it **no longer applies to persistence**, because those unions are no longer persisted at all.

`Spawn_Composition_Entry` was the only place `Movement_Style`/`Attack_Style` were ever marshalled. With a plain enum there, `Movement_Style_Save`/`Attack_Style_Save`, their four conversion procs, `map.odin`'s save/load hooks for them, and `vendor/map-builder`'s duplicated DTOs and `write_*_literal` procs all stop being needed. The union-variant-guessing hazard that those mirrors exist to defend against — `core:encoding/json` decoding a `Kills_Reached`/`Repeating` trigger back as `Time_Elapsed(0)`/`One_Shot`, confirmed directly in this codebase — is simply absent from the enemy path afterwards. It still governs `Spawn_Trigger`'s own condition/mode unions, which are unaffected.

A reader finding those mirrors gone should look here rather than assume they were lost.

## What it costs

A Map can no longer author a one-off tuned enemy, and numeric tuning moves out of the level editor into source: `enemy_presets` is a table in `enemy.odin`, tuned by editing it and rebuilding, exactly as `weapon_presets` has always been. The editor's composition UI collapses to a kind selector and a count.

Both were accepted deliberately. A variation worth authoring is worth naming, and a `data/enemies.json` would reintroduce a persisted file of union-shaped content — the precise hazard this decision removes.
