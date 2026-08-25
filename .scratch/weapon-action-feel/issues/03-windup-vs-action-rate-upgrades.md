Type: grilling
Status: resolved

## Question

`upgrade_weapon` multiplies `action_rate` by `WEAPON_UPGRADE_ACTION_RATE_MULT` (1.10) on every pick, stacking across a run — so a weapon's cycle length `1/action_rate` shrinks over time with no ceiling. This map's destination locks Windup as nested *within* that cycle (`windup_time` doesn't extend it), but `windup_time` itself is a fixed per-`Weapon_Kind` preset value with no described relationship to `action_rate`.

Left alone, enough action-rate upgrades on a Windup-gated weapon (Pistol, Shotgun, Sword, Fire_Wand, Poison_Staff) will eventually shrink `1/action_rate` below `windup_time`, breaking the "Windup happens within the cooldown window" invariant this whole map is built on. Decide how that's prevented — candidates to weigh, not a prescribed answer:

- `windup_time` scales down proportionally as `action_rate` increases via upgrades, keeping Windup a constant *fraction* of the cycle rather than a constant duration.
- `action_rate` upgrades get an effective floor on cycle length (`1/action_rate >= windup_time`) for weapons with a Windup, capping how fast a Windup-gated weapon can ultimately act.
- Something else — e.g. late-game upgrades convert a weapon's Windup into a shorter Follow-through instead, changing its feel deliberately as it grows.

Follow-through has no equivalent problem (it's cosmetic-only and can just get visually truncated by the next Trigger without breaking anything), so this ticket is about Windup-gated weapons specifically.

## Answer

**Windup scales as a fraction of the cycle**, not a fixed duration. The field renames from the originally-anticipated `windup_time` to **`windup_fraction: f32`** (0..1) — the proportion of the weapon's *current* cycle Windup occupies. The actual `windup_timer` countdown is derived fresh at Trigger time as `windup_fraction / action_rate`, using whatever `action_rate` is at that moment (post-upgrades). Because Windup is defined relative to the cycle rather than as an absolute duration, "Windup nested within cooldown" holds automatically for any number of stacked `action_rate` upgrades — no clamping, no ceiling on upgrades, no synchronization step to remember anywhere.

`follow_through_time`/`follow_through_timer` are unaffected — they stay fixed durations in seconds, since Follow-through has no equivalent invariant to protect (purely cosmetic, safely truncated by the next Trigger if a cycle ever shrinks past it).

Full reasoning, including the two rejected alternatives (a floor on action_rate upgrades; converting Windup into Follow-through past a threshold), is in [ADR-0004](../../../docs/adr/0004-windup-fraction-not-duration.md). Vocabulary updated in [CONTEXT.md](../../../CONTEXT.md) (Windup, Action rate, Resolve entries) and [ADR-0003](../../../docs/adr/0003-windup-and-follow-through-are-weapon-level.md) (field name corrected from `windup_time` to `windup_fraction`).

Implementation note: this also fixes the exact shape of content-authoring's future job — tuning `windup_fraction` per `Weapon_Kind` means picking a 0..1 proportion, not a seconds value, for each of Pistol/Shotgun/Sword/Fire_Wand/Poison_Staff. Worth flagging to whoever authors those in the prototype tickets.
