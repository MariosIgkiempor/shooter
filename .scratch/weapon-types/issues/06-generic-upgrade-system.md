Type: grilling
Blocked by: 02
Status: resolved

## Question

How do `upgrade_weapon` and the level-up upgrade-choice UI (hud.odin) work generically across whichever weapon type is currently equipped — applying to the common-header `damage` and `Fire_Mode`/cooldown fields from ticket 02 regardless of variant — while leaving room for type-specific upgrades (fogged on the map for now) to be added later without restructuring this?

## Answer

Locked via grilling (2026-08-23):

**`upgrade_weapon` splits into an unconditional header pass + a type-specific switch.** The generic part always runs regardless of variant — `damage *= WEAPON_UPGRADE_DAMAGE_MULT`, `action_rate *= WEAPON_UPGRADE_ACTION_RATE_MULT` (renamed from `WEAPON_UPGRADE_FIRE_RATE_MULT` to match ticket 02's `fire_rate`→`action_rate` rename). The Gun-only clip bonus moves into a `switch &v in weapon.variant`, with `case Melee_Weapon, Magic:` left as an empty placeholder — exactly matching the no-op idiom ticket 02 already established in `weapon_create`/`update_weapon`:

```odin
upgrade_weapon :: proc(weapon: ^Weapon) {
	weapon.damage *= WEAPON_UPGRADE_DAMAGE_MULT
	weapon.action_rate *= WEAPON_UPGRADE_ACTION_RATE_MULT

	switch &v in weapon.variant {
	case Gun:
		v.clip_size += WEAPON_UPGRADE_CLIP_BONUS
		v.ammo_in_clip += WEAPON_UPGRADE_CLIP_BONUS
	case Melee_Weapon, Magic:
		// no type-specific upgrade yet — placeholder, ticket 06 fog
	}
}
```

This was the forced consequence of ticket 02's header/variant split, not a real design branch — the generic multipliers apply identically to all three types by construction (they live on the header), and the clip bonus was already Gun-only before the refactor.

**Level-up UI conditionally renders based on equipped variant.** `refill_weapon_reserve` only makes sense for Gun (`reserve_ammo` only exists in the `Gun` payload) and Melee/Magic have no ammo-equivalent resource (cooldown-only, no stamina/mana, per the map's already-locked scope). `draw_level_up_ui` switches on `game.player.weapon.variant`: Gun sees all three buttons ("Upgrade Weapon" / "Refill Ammo" / "Skip", unchanged from today); Melee/Magic see only two ("Upgrade Weapon" / "Skip") — no invented placeholder second option. A Melee/Magic-specific second upgrade choice stays exactly the fog the map already tracks ("type-specific upgrade paths beyond the generic..."), not designed here.

`refill_weapon_reserve` narrows from `(weapon: ^Weapon)` to `(gun: ^Gun)`, so it's only callable where it's meaningful — the type system enforces the boundary the UI respects, rather than a runtime check.
