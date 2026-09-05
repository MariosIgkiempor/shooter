Type: grilling
Status: resolved

## Question

What's the data shape for Run-scoped state, and exactly what does Restart do to it?

- New fields needed: `gold: int`, some form of per-Upgrade-kind purchased-stack tracking (an `Upgrade_Kind` enum + `[Upgrade_Kind]int` table, or similar), plus whatever new mutable fields general Upgrades need (e.g. a `Player.move_speed` field to replace today's hardcoded `100` literal at `main.odin:290`, a `Player.max_health` field to replace the `PLAYER_MAX_HEALTH` constant). Where do these live — on `Player`, or on `game` directly?
- How do purchased Upgrade stacks actually take effect? The map's Decisions-so-far already settled that stacks are tracked independently of the equipped `Weapon_Kind` and reapply on top of whichever tier is equipped (surviving a tier purchase). Decide the mechanism: recomputed from base preset + stack count every time the weapon changes (and cached at other times), or reapplied incrementally on every purchase and left mutated on the live `Weapon`/`Player` fields directly? The former avoids drift; the latter is simpler but must replay correctly after a tier purchase resets the `Weapon` to its fresh preset.
- Save/load: `core:encoding/json` marshals the whole `game` struct directly (`main.odin:109-176`); a field round-trips automatically unless tagged `json:"-"`. Since Gold/Upgrade-stacks are Run-scoped (should reset on Restart, not on save/load — a save/load isn't a Restart), should they be plain persisted fields that `restart_game` explicitly zeroes out, mirroring how `Player.health` is reset in `draw_game_over_ui`'s Restart handler today (`hud.odin:316-343`)? Or do they need a different reset hook?
- Confirm exactly what `Restart` zeroes vs leaves alone: Gold → 0, equipped weapon → `class_weapon_kinds[player.class][0]` (Class's tier-1), every Upgrade stack → 0, `Player.move_speed`/`max_health` → their base values. `Player.class`, `class_chosen`, `xp`, `level` are untouched (Account progression, per ADR-0006).

Not blocked by [01-upgrade-catalog-contents](01-upgrade-catalog-contents.md) — the data-model shape (enum + generic stack table + reset hook) can be decided from the three known effect categories (Player stat, weapon-header stat, weapon-variant stat) without the exact item list.

## Answer

Locked via grilling; recorded as [ADR-0007](../../../docs/adr/0007-upgrade-stacks-recomputed-not-mutated.md):

**Recompute-from-base, not mutate-in-place.** `Player.upgrade_stacks: [Upgrade_Kind]int` is the sole source of truth. An `apply_upgrades` pass derives a `Weapon`'s live stats from its preset baseline plus owned stacks, run every time a `Weapon` is (re)created — Class_Select, a tier purchase's `weapon_create`, and load-from-save. `Player` also gains plain `gold: int`, `move_speed: f32`, and `max_health: f32` fields (replacing the hardcoded `100` movement literal at `main.odin:290` and the `PLAYER_MAX_HEALTH` constant respectively).

**Per-kind tagged effect**: each `Upgrade_Kind` carries `Multiplicative(f32)` or `Additive(f32)` — Damage/Action Rate/Move Speed stay percentage-based, Max Health/Clip Size/Arc Width/Range stay flat additions, matching how the retired `upgrade_weapon` already mixed both without issue.

**Persistence mirrors existing precedent**: `gold`/`upgrade_stacks`/`move_speed`/`max_health` are plain (non-`json:"-"`) fields, round-tripping through `data/game_save.json` exactly like `weapon`/`xp`/`level` already do — a Run survives quitting and relaunching the app; only `Restart` clears it.

**Restart resets**: `gold` → 0, `upgrade_stacks` → all zero, `move_speed`/`max_health` → base constants, equipped weapon → `class_weapon_kinds[player.class][0]` freshly created (then `apply_upgrades` over zeroed stacks is a no-op). `Player.class`, `class_chosen`, `xp`, `level` are untouched (Account progression, per ADR-0006).
