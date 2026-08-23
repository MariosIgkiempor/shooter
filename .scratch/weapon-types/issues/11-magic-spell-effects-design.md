Type: grilling
Blocked by: 04, 10
Status: resolved

## Question

What are the concrete Magic spell effects — the "actual list" ticket 04 deliberately left as fog. First cut: three spells — Fireball (simple projectile), Flamethrower (continuous cone while mouse held), Poison Cloud (lingering ground AoE that damages enemies walking through it) — covering how they map onto the `Weapon_Kind`/tier-ladder system, their targeting/cast model, damage model, and fire mode.

## Answer

Locked via grilling (2026-08-24):

**Spell-to-`Weapon_Kind` mapping: three separate `Weapon_Kind`s on the Magic tier ladder**, not one wand with a runtime spell-switch. Fire Wand → Flame Staff → Poison Staff, mirroring the existing Ranged ladder (Pistol → SMG → Shotgun: each tier is already a qualitatively different weapon, bought via Shop, fully replacing the previous — see ticket 10). No in-combat spell-select UI/input is needed as a result: spell choice happens at Shop-purchase time, browsable via the existing weapon-cycle debug tool same as any other `Weapon_Kind`.

`Magic` gains a `Spell_Kind :: enum { Fireball, Flamethrower, Poison_Cloud }` field; each of the three new `weapon_presets` entries sets it fixed. `try_cast_magic` switches on `magic.spell_kind` — the exact shape ticket 04 anticipated ("a future ticket is expected to add a `Spell_Kind` enum + switch inside `try_cast_magic`").

Still cooldown-only, no mana — extends the map's existing "no resource economy" lock to all three spells, no exception.

**Fireball** — `Fire_Mode.Semi_Automatic`. Travels along `aim_dir`, reusing the `Bullet` pattern/pipeline as-is. On hitting an enemy, explodes: damages every enemy within a small AoE radius of the impact point (via the shared `apply_hit_to_enemy`), not just the one it directly collided with. Reaching max range/lifetime without a hit fizzles with no effect — a miss is not rewarded with free AoE.

**Flamethrower** — `Fire_Mode.Automatic`, reusing the existing held-input pattern (SMG/Dagger: re-triggers every frame, gated by `cooldown_timer`/`action_rate`). Each tick runs an instant cone hit-check — same shape as melee's `enemy_in_melee_arc` (ticket 03), just against the spell's own range/arc/damage fields — hitting every enemy currently in the cone per tick (cleave, no single-target cap). The cone always tracks the live `aim_dir`, so it follows the mouse while held.

**Poison Cloud** — `Fire_Mode.Semi_Automatic` (one click, one cloud — deliberately not holdable, since that would make it a flamethrower-shaped spam tool). Ground-targeted at the mouse's world position rather than a fixed point along `aim_dir` — the one spell that breaks from the aim_dir-targeting model the other two (and melee/gun) share — clamped to a max range from the player if the cursor is farther out, so it stays a positioning spell with real exposure rather than a screen-wide zoning tool. Cast still resolves instantly per ticket 04's lock: the cloud spawns immediately as its own persisted tracked entity (same precedent as `Bullet` — a new array + its own `update`/`draw` pair), no travel or channel phase. Deals repeating tick damage to every enemy currently overlapping it for its duration (via `apply_hit_to_enemy`) — lingering in it stacks up damage, rather than a single hit on entry. No enemy-side DoT/status state is introduced; the damage lives entirely on the cloud entity's own tick, consistent with there being no status-effect system on `Enemy` today.

**Cross-cutting:** none of the three damage the player — enemies only, no friendly-fire check needed. v1 visuals are placeholder primitives (colored projectile/cone/zone), matching how melee weapons started before getting real sprites — real art is a later pass. Concrete numbers (damage, AoE/cone/cloud radius, cloud duration and tick rate, max placement range) are left as content-authoring for the build session, not locked here — matching how the map already treats `Weapon_Kind` stats/prices elsewhere.

**Build order:** implement Fireball first — simplest, and it validates the `Spell_Kind` plumbing end-to-end before the trickier continuous/persistent-entity spells. Flamethrower and Poison Cloud follow in either order; they don't depend on each other.

## Comments

(none)
