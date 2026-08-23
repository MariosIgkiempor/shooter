# Weapon acquisition is Class-locked, not free-swap via random pickup

Status: accepted

The weapon-types map originally locked weapon acquisition as a random enemy-dropped pickup: any `Weapon_Kind` across all three types could drop and would replace the current weapon outright. That design was fully speced (arc/cone selection excluding the current kind, its own rarer drop roll, a world-sprite icon) but never implemented — it was superseded mid-session, before any code landed, by a Class-based model.

Instead, the player picks a Class (`Melee`, `Magic`, or `Ranged`) once, at game start, permanently fixing which `Weapon` family they can ever equip — there is no free cross-type swap. Progression within that Class runs on a separate axis: enemy kills drop Gold, spent in an on-demand Shop to buy the next `Weapon_Kind` in a fixed tier ladder, immediately equipping it and discarding the old one.

This trades the randomness of an any-type pickup for a build the player commits to and deliberately grows. Everything else from the original weapon-types design carries over unchanged — the `Weapon` wrapper struct, `Weapon_Kind` as one flat enum ([ADR-0001](0001-weapon-wrapper-struct.md)), "discard the old weapon on acquiring a new one" — only the acquisition trigger changes, from random/any-type to deliberate/same-Class-only.

Consequences: the weapon-pickup-integration ticket (scoped to the random-pickup mechanism) closed out of scope. `Weapon_Kind` gains a Class-bucketing lookup table but keeps its existing flat shape. Magic is offered as a selectable Class despite having no implemented spell effects yet, so it needs at least one placeholder `Weapon_Kind` with real header stats before that path is playable.
