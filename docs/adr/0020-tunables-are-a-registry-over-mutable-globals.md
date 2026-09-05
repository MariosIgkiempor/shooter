# ADR-0020: Tunables are a hand-registered table over mutable globals

**Status**: Accepted

Builds on [ADR-0007](0007-upgrade-stacks-recomputed-not-mutated.md) (stacks are recomputed, never mutated) and [ADR-0014](0014-menu-ui-flat-rect-and-reveal-dismiss-animation.md) (the six Screens left vendor/ui; the editor and the F8 panel did not).

## Context

Balancing meant editing a constant, rebuilding, and replaying. That is a poor loop for numbers whose only honest test is playing — weapon damage, camera follow, particle bursts, orb radius — and it applied to roughly 275 separate values across fifteen files.

The values split into two forms, and the split decided the shape of the solution:

- **Preset tables** (`weapon_presets`, `upgrade_presets`, `relic_presets`, `account_stat_presets`, `enemy_gold_presets`, `weapon_visuals`) were already *mutable globals* — `name: [Enum]T = {...}` declares a variable, not a constant — so they were writable at runtime with no change at all.
- **Loose feel constants** (~150 `SCREAMING_CASE :: value`) were compile-time constants, inlined by the compiler, with no address to take.

A handful of the highest-leverage feel values were not even constants: camera follow lived as bare proc-local literals inside `update_camera_center_smooth_follow`, and the weapon-animation timings inside `draw_game`.

Three mechanisms were considered:

1. **A slider hand-written per value.** Explicit and readable per section, but ~275 hand-written UI rows, and silently stale the moment anyone adds a constant — the panel has no way to know a value exists.
2. **`core:reflect` walking the Preset structs.** Covers `weapon_presets` and friends generically, but reflection has no way to find a loose `f32` global, and the loose constants are the *majority* of the feel knobs. It would have meant maintaining both mechanisms, and reflection cannot supply a sensible slider range either way.
3. **A hand-registered table**: one `Tunable` entry per value, holding a slug, a group, a pointer, a range and the captured Default.

There was a second, independent question: where the edited values persist. Reusing `data/game_save.json` was the obvious cheap answer, since it already round-trips the whole `game` struct.

## Decision

A **Tunable** is one entry in `tunables`, a `[dynamic]Tunable` built once at startup by `register_tunables()`. Each entry carries a `Tunable_Value` — a bare union of `^f32` / `^int` / `^bool` — pointing at the live variable.

The ~150 loose constants became typed mutable globals (`X :: 6.0` → `X: f32 = 6.0`). The identifier is unchanged, so no call site moved. Values that were anonymous literals were named and hoisted first; naming them changed no behaviour, and it is what makes camera follow tunable at all.

Ranges are hand-authored **per field**, not per field-per-kind: every weapon's `damage` shares one range, so the eight per-kind weapon groups are registered by looping `Weapon_Kind` rather than written out eight times. A range only has to be wide enough to be useful, and per-kind ranges go quietly wrong the moment a rebalance pushes a value past its own ceiling.

**Overrides persist to `data/tuning.json`, tracked in git — not to `game_save.json`.** The save file is untracked per-machine session state that is discarded wholesale whenever it fails to parse; a balance pass belongs in a commit, next to `data/maps/`, and should survive a save wipe. The file is **sparse**: only values differing from their Default are written, so changing a Default in code still shows through everywhere it was not deliberately overridden, and the diff reads as exactly the decisions that were made.

Slugs are **decoupled from the Odin identifiers** (`"weapon.shotgun.damage"`, not `"weapon_presets.Shotgun.damage"`), so renaming a global does not orphan its Override. The cost is that nothing structural enforces slug uniqueness — `tuning_test.odin`'s uniqueness test is what does, and it is load-bearing rather than cosmetic.

The UI is a third `EditorMode` alongside Tiles and Collisions, reached with F1 from a paused Run. Exactly one **Tuning Group** is expanded at a time, and only the expanded group emits nodes.

## Consequences

**A Preset edit reaches the player immediately, for free.** ADR-0007's recompute-not-mutate discipline already re-derives the equipped weapon and the player's stats from `weapon_presets` plus the stacks, and `load_game` already re-runs exactly that pair to self-heal a hand-edited save. `apply_tuning_change` calls the same two procs; there was nothing new to write.

**It does not reach entities already on the field.** An Enemy copies its health from `ENEMY_MAX_HEALTH` and its speed from its spawn template at the moment it spawns; a Bullet copies its speed from the weapon that fired it. Those keep the numbers they were born with — only newly-spawned entities pick a change up. This is accepted rather than solved: enemies turn over fast enough that the next wave shows the change, and re-deriving live entities raises questions (what happens to a partially-damaged enemy when max health moves?) that a tuning panel should not have to answer.

**Two constants cannot be Tunables and are excluded.** `PLAYER_BAR_MAX_PARTICLES` backs `[N]Resource_Bar_Particle`, and `SWORD_ECHO_COUNT` backs `[N]f32`; a fixed-size array bound must stay a compile-time constant. `SWORD_ECHO_COUNT` is only a *capacity* — the per-kind echo count that is actually tunable is `Weapon_Visual.swing_echo_count`, which `draw_game` already clamps against it.

**Registration order is load-bearing.** `register_tunables()` captures every Default from the code and must run before `load_tuning()` applies Overrides, which must in turn run before `load_game()`, since loading a save re-derives the weapon from `weapon_presets` and the player from `PLAYER_BASE_MOVE_SPEED`/`PLAYER_BASE_MAX_HEALTH`.

**Adding a knob is now a two-line job** — convert the constant, add a registry line — but it is a job someone has to remember to do. A value added without a registry entry simply does not appear, silently. That is the accepted price of not using reflection, and it buys hand-authored ranges and labels that reflection could never supply.

**`vendor/ui`'s `MAX_CHILDREN` rose from 32 to 128.** The Tuning Group list is a single column of ~35 buttons. Only the child cap needed raising: node and render-command counts stay far under 1024, and `RenderCommands` is a stack-allocated fixed array, so growing `MAX_RENDER_COMMANDS` too would have put a quarter-megabyte on the stack for no benefit.

**One placeholder is now visibly a placeholder.** `WEAPON_STARTING_RESERVE_CLIPS` is `69420` — "reserve-ammo scarcity is off" wearing an int. Its slider range has to reach its own Default to be usable at all, so the range is `0..70000` and correspondingly coarse. The fix is to pick a real starting reserve, which is a balance decision, not a plumbing one.
