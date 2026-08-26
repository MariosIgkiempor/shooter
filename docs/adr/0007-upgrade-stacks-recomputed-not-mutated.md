# Upgrade stacks are recomputed onto the weapon, not mutated in place

Status: accepted

Shop-purchased Upgrade stacks (`Player.upgrade_stacks: [Upgrade_Kind]int`) are the single source of truth for how many times each Upgrade has been bought; they're never applied by mutating a `Weapon`'s fields directly. Instead, an `apply_upgrades` pass runs over a freshly-created `Weapon` every time one exists — on Class_Select, on a tier purchase's `weapon_create` call, and on load from save — deriving its live stats from the preset baseline plus owned stacks. Each Upgrade kind carries a per-kind tagged effect, `Multiplicative(f32)` or `Additive(f32)` (matching how the retired `upgrade_weapon` already mixed both), rather than forcing every kind into one operation shape.

Chosen over mutating `Weapon`/`Player` fields in place at purchase time because a tier purchase already discards and recreates the `Weapon` outright (ADR-0002) — recomputing from stored stack counts means that recreation doesn't need its own special-cased "replay every purchase" logic, and the Shop UI's "current stack / next price" display reads directly from the same array instead of reverse-deriving a purchase count from mutated stat values.

Gold and Upgrade stacks follow the same persistence precedent as the existing `weapon`/`xp`/`level` fields: plain (non-`json:"-"`) fields on `Player`, round-tripping through `data/game_save.json` like everything else. A Run survives quitting and relaunching the app exactly as left; only clicking Restart clears it (per ADR-0006).
