Type: grilling
Blocked by: 02
Status: resolved

## Question

What is the generic Magic "cast" plumbing:

- The cooldown/activation model, reusing the common-header `Fire_Mode`/cooldown from ticket 02.
- The shape of the "cast" hook that a future spell-effect ticket will implement against — e.g. a proc pointer, a nested tagged sub-union keyed by an (initially empty or single-placeholder) `Spell_Kind`, or a dispatch table.

Lock only the interface here. No specific spell effects (projectile, homing, AoE, DoT, etc.) are designed in this ticket — the exact list is intentionally left as fog on the map, to graduate into its own tickets later once this plumbing exists.

## Answer

Locked via grilling (2026-08-23):

**Cast resolution: instant/synchronous.** `try_cast_magic` resolves in one call, exactly matching `try_swing_melee`/`try_fire_gun`'s contract — no active-cast/channel window, no extra runtime flag. Any future spell effect that needs to persist beyond the triggering frame (a flying projectile, a lingering AoE, a DoT) spawns its own tracked entity, the same way `fire_pellets` spawns `Bullet`s that `update_bullets` then owns — it is not represented by state on `Weapon` or `Magic`. This extends ticket 03's precedent (instant hit-check, cosmetic playback only) to casting.

**`Magic` variant: empty struct for now.** `Magic :: struct {}`. No `Spell_Kind` enum and no switch skeleton yet — inventing an enum with a single placeholder case isn't locking an interface, it's speculative design for a case that doesn't exist. The future spell-effect ticket adds `Spell_Kind` (plus a `switch` inside `try_cast_magic`) once it has an actual list of effects to enumerate; that's a mechanical, low-risk addition against an already-fixed proc signature, not a design decision being deferred.

**`try_cast_magic` signature** (mirrors `try_swing_melee` exactly):
```odin
try_cast_magic :: proc(magic: ^Magic, origin, aim_dir: Vec2) -> bool {
	// no-op today: consumes the trigger, does nothing observable yet.
	// future spell-effect ticket fills this in.
	return true
}
```
Dispatched from `try_use_weapon`'s existing `switch &v in weapon.variant` (ticket 02); `cooldown_timer` is set once by the caller after `acted == true`, same as every other variant — Magic introduces no new dispatch pattern.

**Preset/table impact:** `Magic{}` slots into `weapon_presets` the same placeholder way `Melee_Weapon{}` does per ticket 02's `weapon_create`/`update_weapon` — both cases stay no-ops in the `switch &v in w.variant` until their respective follow-on tickets give them runtime init logic.
