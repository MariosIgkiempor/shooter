Type: grilling
Blocked by: 02, 08, 09
Status: resolved

## Question

How does spending Gold to "buy a better weapon" actually work: what UI it needs, how the purchasable set is structured within a Class, what a purchase does to the currently-equipped weapon, and how this relates to the pre-existing XP-level-up generic upgrade system (ticket 06's scope).

## Answer

Locked via grilling (2026-08-23), as part of the same session that redrew the map's destination (see [ADR-0002](../../../docs/adr/0002-class-locked-weapon-acquisition.md)):

**Dedicated on-demand Shop panel, not folded into the level-up modal.** A new UI panel, opened at the player's discretion (e.g. a keybind, mirroring how `F1` toggles `ProgramMode.Editing`) rather than gated behind XP level-ups. Gold accrues on a separate, continuous timeline from XP/level — tying spending to level-up moments would make a steadily-accruing currency only usable at irregular, XP-gated intervals. Reuses the same `ui` library panel/button idiom as `draw_level_up_ui`/`draw_game_over_ui`; no new UI infrastructure, just a new open-trigger.

**Fixed sequential tier ladder per Class**, not a browsable priced catalog. Within a Class, the Shop only ever offers "the next tier up" (e.g. Ranged: Pistol → SMG → Shotgun) — one purchase advances exactly one step. Chosen over a browsable set-of-all-kinds-with-prices because it needs no non-linear price list or explanation of why one kind is "better" than another out of order, and it gives purchases a clear, legible sense of progression.

**Purchase = immediate equip, discard old, no unlocking.** Buying the next tier calls the same replace-outright mechanism the cancelled weapon-swap pickup was going to use: `game.player.weapon = weapon_create(next_kind)`, discarding the previous weapon entirely. There is no set of "owned" kinds to freely switch between and no sell-back/downgrade path — this was chosen specifically to avoid reopening the map's already-closed "no inventory" decision.

**`Weapon_Kind` stays a flat enum; Class-bucketing is a new lookup table.** A new `weapon_kind_class: [Weapon_Kind]Class` (or equivalent) table buckets the existing flat `Weapon_Kind` enum by Class — anticipated back in ticket 02's answer as the natural extension point ("can be layered on later ... if ticket 05 needs type-level bucketing for pickups"). `Weapon_Kind`'s shape from ticket 02 is untouched.

**Coexists with, does not replace, ticket 06's XP-level-up upgrade system.** Two independent progression axes: XP level-ups still grant free generic stat upgrades (`WEAPON_UPGRADE_DAMAGE_MULT` etc.) to whatever weapon is currently equipped, unchanged from ticket 06's original scope; Gold purchases separately swap in a stronger discrete `Weapon_Kind` within the locked Class. A purchase discards the old weapon's header entirely, so any XP-driven upgrade multipliers accumulated on it are lost on swap and start fresh on the new tier's preset baseline — direct consequence of "discard outright," not a new rule.

**Starting weapon:** on `Class_Select` confirming a Class, `weapon_create` is called once with that Class's tier-1 `Weapon_Kind` (per [08-class-selection-mechanics](08-class-selection-mechanics.md)) — the Shop's ladder always starts from the bottom.
