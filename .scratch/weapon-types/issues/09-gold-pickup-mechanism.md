Type: grilling
Blocked by: none
Status: resolved

## Question

How does Gold enter the world and reach the player, now that it replaces the cancelled weapon-swap pickup as the third `Pickup_Kind` alongside Health/Ammo: does it reuse existing pickup infrastructure, and does it need its own drop odds?

## Answer

Locked via grilling (2026-08-23), as part of the same session that redrew the map's destination (see [ADR-0002](../../../docs/adr/0002-class-locked-weapon-acquisition.md)):

**New `.Gold` `Pickup_Kind`, reusing all existing pickup machinery.** `pickup.odin`'s `Pickup` struct (`position`, `velocity`, `kind`, `homing`) needs no new fields — Gold has no payload beyond `kind`, same as Health/Ammo today. It gets a `pickup_texture_names[.Gold]` icon entry like the other two.

**Same uniform 3-way roll, same odds.** `maybe_spawn_pickup` keeps its existing shape: roll `PICKUP_DROP_CHANCE` (0.25), then on a hit pick uniformly via `rand.choice_enum(Pickup_Kind)` — now a 3-way Health/Ammo/Gold split instead of 2-way. Gold takes over the slot the cancelled Weapon pickup would have used; no new constant needed. This was chosen over special-cased rarer odds (which the now-cancelled Weapon pickup was going to need, being a much bigger power swing) because Gold is a currency meant to accumulate steadily over many kills — per-drop rarity doesn't need to be tuned specially for that to work.

**`collect_pickup` on `.Gold`:** increments a new running total on `Player` (e.g. `Player.gold: int`), persisted the same way `xp`/`level` already are — not `json:"-"`, since it's run progression that should survive save/load exactly like everything else Class/weapon-related now does.
