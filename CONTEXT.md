# Shooter

A top-down twin-stick shooter (Odin + raylib). Single global `game` struct, free-function updates (`update_x`/`draw_x`), enums + `[Enum]T` preset tables as the standing idiom for per-kind data.

## Language

**Weapon**:
The player's single currently-equipped combat tool. Common state (kind, fire mode, damage, action rate, cooldown) lives directly on it; type-specific state lives in one of `Gun`, `Melee_Weapon`, or `Magic` behind its `variant` field. See [ADR-0001](docs/adr/0001-weapon-wrapper-struct.md) for why this differs in shape from `Enemy_Behaviour`.
_Avoid_: Loadout, armament

**Gun** / **Melee_Weapon** / **Magic**:
The three concrete `Weapon` variants. Gun keeps the clip/reserve/reload ranged-firing mechanic; Melee_Weapon and Magic are cooldown-only (no stamina/mana economy). Which `Weapon_Kind`s belong to which Class is a separate lookup table — see **Class**.

**Action rate**:
The generic "actions per second" cadence shared by all weapon types — firing (Gun), swinging (Melee_Weapon), casting (Magic). Gates how often `cooldown_timer` lets a weapon act again.
_Avoid_: Fire rate (Gun-specific predecessor term, now only correct when talking about Gun specifically)

**Fire mode**:
Whether a weapon's action re-triggers repeatedly while its input is held (`Automatic`) or once per press (`Semi_Automatic`). Applies generically across all three weapon types, not just Gun.

**Enemy_Behaviour**:
An enemy's AI archetype — `Melee` (chases and attacks in melee range) or `Ranged` (holds a distance band, fires enemy bullets). Unrelated to `Weapon`'s `Melee_Weapon`/player Melee — enemies keep their own separate behaviour system by design (see the weapon-types map's Out of scope).

**Class**:
The player's permanent choice — made once, at game start — of which `Weapon` family they can ever equip: `Melee`, `Magic`, or `Ranged`. `Weapon_Kind` stays the single flat enum from [ADR-0001](docs/adr/0001-weapon-wrapper-struct.md); a separate lookup table buckets its members by Class. See [ADR-0002](docs/adr/0002-class-locked-weapon-acquisition.md) for why acquisition is Class-locked rather than a free cross-type swap.
_Avoid_: Loadout, role, archetype

**Gold**:
Currency earned from enemy kills (a `Pickup_Kind.Gold` drop) and spent in the Shop to buy the next tier of the player's Class weapon ladder. A progression axis separate from XP: XP grants free generic stat upgrades on level-up; Gold buys a discrete weapon-kind upgrade via deliberate purchase.
_Avoid_: Currency, coins, cash

**Shop**:
The on-demand UI panel where the player spends Gold to buy the next `Weapon_Kind` in their Class's tier ladder. Opened at the player's discretion, unlike the level-up upgrade-choice UI which only appears on an XP level-up.
_Avoid_: Store, market

**Weapon tier ladder**:
The fixed, sequential order of `Weapon_Kind`s a Class progresses through via Shop purchases (e.g. Ranged: Pistol → SMG → Shotgun). Buying the next tier immediately equips it and discards the previous weapon outright — no unlocking a set of owned kinds, no switching back.
_Avoid_: Rank (Level already names the separate XP-progression concept)
