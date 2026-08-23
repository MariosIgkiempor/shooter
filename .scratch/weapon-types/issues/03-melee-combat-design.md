Type: prototype
Blocked by: 02
Status: resolved

## Question

How exactly does a melee swing resolve:

- Swing duration and the active-frame window during which the hitbox actually threatens enemies.
- The hitbox shape (arc/cone vs. an expanding rect in the player's facing direction) and its size relative to the player.
- How it's checked **once** per swing against enemies (not per-frame, to avoid multi-hit on a single swing) — what "once per swing" means mechanically given the game's per-frame update loop.
- How cleave (hitting every enemy overlapping the arc, not just the first) reuses `bullet.odin`'s existing damage/hit-particle/xp-orb/pickup-drop pipeline instead of duplicating it.

Build a rough prototype (stub code and/or a visual mock of the swing arc) to react to — "how should it behave" is the open question here, not just data layout.

## Answer

Locked via prototype session (2026-08-23): interactive HTML mock at [prototypes/03-melee-swing.html](../prototypes/03-melee-swing.html) (throwaway — a pure JS logic module driving a canvas + guided scenarios, not committed as production code). User reacted and confirmed both recommendations.

**Hit-check timing: Instant.** `try_swing_melee` resolves the hit-check synchronously, once, in the same call — exactly like `try_fire_gun` spawning bullets instantly (per ticket 02's contract, returns `bool` "acted"). The swing's visual duration is purely cosmetic playback afterward; it does not gate or re-trigger anything. This eliminates the "once per swing not per frame" problem structurally rather than needing to solve it: there is no active-frame window to guard, so `Melee_Weapon` needs no extra runtime flag (no `hasResolvedHit`-equivalent state). The prototype's delayed-window alternative (winding → active → recovering, with a guard flag) was built and demonstrated working, but rejected as unnecessary complexity once instant resolution was on the table.

**Hitbox shape: Arc/cone.** `dist(player, enemy) <= melee.range + enemy.radius && angle_between(aim_dir, direction_to_enemy) <= melee.arc_degrees/2`. `aim_dir` is the existing generic `game.player.aim_dir` (mouse-facing, per ticket 02 — no melee-specific input needed). Conceptually mirrors `Gun.spread_angle`'s existing cone-around-`aim_dir` idea, just reused for hit detection instead of pellet fan-out — same mental model, no new pattern introduced to the codebase.

**Cleave mechanism:** a single hit-check pass gathers every alive enemy whose collision box overlaps the arc (not just the nearest), then applies the hit to each. This requires factoring `bullet.odin`'s currently-inlined per-enemy hit pipeline (`update_bullets` lines 58-78: damage, `spawn_hit_spark`, and on death `spawn_xp_orb`/`maybe_spawn_pickup`/removal) out into a shared proc — e.g. `apply_hit_to_enemy(enemy_index: int, damage: f32)` — called once per bullet-enemy collision (as today) and once per enemy caught in a melee swing's arc (new). No duplicated damage/death logic between Gun and Melee.

**`Melee_Weapon` variant fields implied by this:** `range: f32`, `arc_degrees: f32`, `swing_time: f32` (cosmetic-only animation duration — ticket 07 owns the actual animation). `damage`/`action_rate`/`cooldown_timer` stay on the `Weapon` header per ticket 02, not duplicated here. No swing-state/flag fields needed given instant resolution.

**`try_swing_melee` shape** (mirrors `try_fire_gun`'s contract exactly):
```odin
try_swing_melee :: proc(melee: ^Melee_Weapon, origin, aim_dir: Vec2) -> bool {
	for &enemy, i in game.enemies {
		if !enemy_in_melee_arc(melee, origin, aim_dir, enemy) do continue
		apply_hit_to_enemy(i, melee.damage) // melee.damage reads Weapon.damage via caller, or header passed in
	}
	return true // melee always "acts" once triggered — no ammo-style failure case
}
```
(Exact parameter passing of the header's `damage` into this proc is an implementation detail for the build session, not a design branch.)
