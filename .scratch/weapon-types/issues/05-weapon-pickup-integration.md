Type: grilling
Blocked by: 02
Status: closed (out of scope)

## Question

How does a weapon-swap pickup work end-to-end:

- The new `Pickup_Kind` variant and what data it carries (a specific preset selection across Gun/Melee/Magic — however presets ended up identified in ticket 02).
- How it plugs into the existing enemy-death drop-chance table alongside Health/Ammo.
- What `collect_pickup` does on pickup: replace `Player.weapon` outright, discarding the previous weapon (per the "no drop-back" decision — the old weapon does not re-enter the world as a pickup).

## Closed: out of scope

Never resolved — grilling was in progress this session when the user redirected the whole weapon-acquisition model (2026-08-23). The map's destination was redrawn: weapon type is no longer acquired via a random enemy-dropped pickup at all. Superseded by a Class chosen once at game start (locking weapon type permanently) plus a Gold-funded Shop for in-Class upgrades — see [08-class-selection-mechanics](08-class-selection-mechanics.md), [09-gold-pickup-mechanism](09-gold-pickup-mechanism.md), [10-weapon-shop-and-tier-ladder](10-weapon-shop-and-tier-ladder.md), and [ADR-0002](../../../docs/adr/0002-class-locked-weapon-acquisition.md).
