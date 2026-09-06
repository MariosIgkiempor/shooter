# Weapon catalog expansion

Type: grilling
Status: open

## Question

Which weapons get added, and to which ladders?

Eight `Weapon_Kind`s exist across three families — Ranged (Pistol, SMG, Shotgun), Melee (Dagger, Sword), Magic (Fire_Wand, Flame_Staff, Poison_Staff). Melee is the acknowledged gap: its two entries carry an in-code comment calling them "placeholder melee content... real tier-ladder naming/stats for Melee are still content-authoring for a later ticket", and [Shop and upgrades](../../shop-and-upgrades/map.md) still lists "Concrete named Melee tier-ladder content and Magic tier-ladder numeric stats" as open fog. This ticket graduates that.

To settle, per weapon:

- **Which family and which rung of its tier ladder**, remembering the ladder is strictly sequential and destructive — buying a tier equips it and discards the previous weapon outright, with no owned set and no switching back.
- **The niche it fills** against the enemy roster from [Enemy catalog](04-enemy-catalog.md). A weapon is an answer to something; a tier that is strictly better than its predecessor at everything is a stat bump wearing a name.
- **`fire_mode`**, which is not a free choice: it alone decides whether the weapon gets a **Windup** (`Semi_Automatic`) or a **Follow-through** (`Automatic`) — never both ([ADR-0003](../../../docs/adr/0003-windup-and-follow-through-are-weapon-level.md)).
- **`damage`, `action_rate`, `windup_fraction` / `follow_through_time`**, plus family-specific state (clip/reserve/reload for Gun, range and arc for Melee_Weapon, `Spell_Kind` for Magic — a new Magic tier means a new spell, since each Magic tier is a distinct spell rather than a numeric upgrade).
- **Silhouette geometry.** [ADR-0018](../../../docs/adr/0018-weapon-visual-identity-is-per-kind-not-per-family.md) requires per-kind geometry, authored once in unit space and adapted to both the icon slot and the world, derived from `kind` at draw time and **never stored on `Weapon`** (it serializes into the save file). Distinctions must be **countable** — one barrel vs. two, one orb vs. three — never proportional, because a 20px rod and a 24px rod are indistinguishable with nothing alongside them.
- **Whether a fourth family is warranted at all**, or whether the three existing ladders simply get deeper.

Note what stays fixed: Shop prices and per-Upgrade curves are already standing fog on the shop map and are balance work, not a decision here.

Blocked by [Enemy catalog](04-enemy-catalog.md).

Unblocked: [Enemy catalog](04-enemy-catalog.md) is resolved, and it hands this ticket the target spread the weapons are judged against.

- **The roster spans 20 to ~220 health**, from the 16px Mite to the Warden. The eight current weapons were tuned against a single 50-health enemy, so nothing in `weapon_presets` has ever had to distinguish crowd-clearing from single-target damage — and now both ends exist at once. Rung 4 is authored at **150-250 concurrent bodies**, which is where a weapon that hits one thing at a time stops being a choice and starts being a losing one.
- **Two weapons are labelled placeholders in their own source comment**, and that is this map's Destination calling them out. The Magic tier ladder's numeric stats and concrete named Melee tier-ladder content are the foreign fog item this ticket graduates from [Shop and upgrades](../../shop-and-upgrades/map.md).
- **[ADR-0018](../../../docs/adr/0018-weapon-visual-identity-is-per-kind-not-per-family.md) governs any new weapon**: per-kind geometry authored once in unit space, derived from `kind` at draw time, never stored on `Weapon`, with distinctions that are countable rather than proportional.
- **The enemy roster deliberately did not reserve a weapon answer for itself.** No kind is authored as "the one only AoE beats" — the Mite swarm is a crowd because it is cheap and numerous, not because it is armoured against single-target fire. Whether the weapon ladder should have a hard crowd-clear/single-target split, or stay a smooth ramp, is open here rather than pre-decided by the catalog.
