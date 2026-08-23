Type: grilling
Blocked by: 01
Status: resolved

## Question

What is the exact `Weapon` union shape:

- The common header fields — `damage`, cooldown state, `Fire_Mode` (now generic across all types per the grilling decision), and whatever discriminant field ticket 01's save-safety mechanism requires.
- The per-variant payload for `Gun` (carries over `clip_size`/`ammo_in_clip`/`reserve_ammo`/`reload_time`/`reload_timer`/`pellet_count`/`spread_angle`/`bullet_lifetime` from today's flat struct), `Melee` (swing state — whatever ticket 03 ends up needing), and `Magic` (cast state — whatever ticket 04 ends up needing).

Also decide: do the existing `weapon_presets`-style `[Enum]T` preset tables extend naturally — e.g. `melee_presets: [Melee_Kind]Melee_Preset`, `magic_presets: [Magic_Kind]Magic_Preset` — and what do `weapon_create`, `update_weapon`, and `try_fire_weapon` look like once dispatch becomes `switch &variant in weapon` (mirroring how `update_enemy` dispatches over `Enemy_Behaviour`)?

This is the foundational ticket for the whole map — every other open ticket depends on its answer.

## Answer

Locked via grilling (2026-08-23), across three rounds:

**Structural pattern — wrapper struct, not a bare union.** `Weapon` stays a plain struct with common fields directly on it: `kind: Weapon_Kind`, `fire_mode: Fire_Mode`, `damage: f32`, `action_rate: f32`, `cooldown_timer: f32`. It carries one additional field, `variant: Weapon_Variant`, holding `union { Gun, Melee_Weapon, Magic }` (variant names fixed by ticket 01's `Weapon_Save` DTO). This was chosen over mirroring `Enemy_Behaviour`'s bare-union shape because Odin unions require a `switch`/type-assertion to read any field — mirroring `Enemy_Behaviour` exactly would force existing direct reads (`main.odin:231` `weapon.fire_mode`, `main.odin:523` `weapon.kind`) into a switch for no benefit. Recorded as [ADR-0001](../../../docs/adr/0001-weapon-wrapper-struct.md); `Weapon`/`Gun`/`Melee_Weapon`/`Magic`/action-rate/fire-mode terminology captured in [CONTEXT.md](../../../CONTEXT.md).

**Header field list and generic Fire_Mode semantics.** Header = `kind`, `fire_mode`, `damage`, `action_rate` (renamed from `fire_rate` — generic actions/sec across firing/swinging/casting), `cooldown_timer` (generic runtime countdown). Everything else Gun-specific today (`projectile_speed`, `clip_size`, `ammo_in_clip`, `reserve_ammo`, `reload_time`, `reload_timer`, `pellet_count`, `spread_angle`, `bullet_lifetime`) moves into the `Gun` variant only. `Fire_Mode.Automatic` = action re-triggers repeatedly while input is held, gated by `cooldown_timer`; `Semi_Automatic` = once per press — applies generically; tickets 03/04 still own the actual swing/cast animation and hit-detection detail.

**`Weapon_Kind` stays a single flat enum** spanning every concrete weapon across all three types (`Pistol, SMG, Shotgun, <melee kinds TBD 03>, <magic kinds TBD 04>`), indexed into one `weapon_presets: [Weapon_Kind]Weapon` table exactly like today, each entry's `variant` pre-populated with the right union case. Rejected a two-level `Weapon_Type` + per-type-kind scheme as unnecessary churn; can be layered on later (a `weapon_kind_type: [Weapon_Kind]Weapon_Type` lookup) if ticket 05 needs type-level bucketing for pickups.

**Proc shapes after the switch to union dispatch:**

```odin
try_use_weapon :: proc(weapon: ^Weapon, origin, aim_dir: Vec2) {
	if weapon.cooldown_timer > 0 do return

	acted: bool
	switch &v in weapon.variant {
	case Gun:          acted = try_fire_gun(weapon, &v, origin, aim_dir)
	case Melee_Weapon: // ticket 03
	case Magic:        // ticket 04
	}

	if acted {
		weapon.cooldown_timer = 1.0 / weapon.action_rate
	}
}
```

Renamed from `try_fire_weapon`: each per-variant action proc (`try_fire_gun` today; future `try_swing_melee`/`try_cast_magic`) owns its own gating (Gun: ammo + reload) and returns whether an action happened, so `cooldown_timer` is set in exactly one place instead of duplicated per variant. `fire_pellets` stays in bullet.odin, called from `try_fire_gun`.

```odin
weapon_create :: proc(kind: Weapon_Kind) -> Weapon {
	w := weapon_presets[kind]
	switch &v in w.variant {
	case Gun:
		v.ammo_in_clip = v.clip_size
		v.reserve_ammo = v.clip_size * WEAPON_STARTING_RESERVE_CLIPS
	case Melee_Weapon, Magic: // no runtime init yet — tickets 03/04
	}
	return w
}

update_weapon :: proc(weapon: ^Weapon, dt: f32) {
	if weapon.cooldown_timer > 0 {
		weapon.cooldown_timer -= dt
	}
	switch &v in weapon.variant {
	case Gun:
		if v.reload_timer > 0 { /* existing reload-completion logic, unchanged */ }
	case Melee_Weapon, Magic: // nothing yet — tickets 03/04
	}
}
```

Empty `Melee_Weapon, Magic` cases are placeholders only, matching the existing `enemy.odin` idiom for a no-op case.

**`upgrade_weapon` scope boundary**: the generic damage upgrade stays a direct header field write (`weapon.damage *= mult`), no switch needed. The Gun-only clip bonus needs a switch now that `Weapon` is a union — but the actual catalog/design of what upgrades exist per type is entirely ticket 06's (**generic-upgrade-system**) job, not decided here.

**Call-site impact flagged, not fixed here** (owned by later tickets): `hud.odin:71-81` reads Gun-only fields directly and will need a type switch once ticket 07 (HUD/visual requirements) redesigns it; `bullet.odin`'s `fire_pellets` takes the flat `Weapon` today and will take `(weapon: Weapon, gun: Gun, origin, aim_dir: Vec2)` once this lands.
