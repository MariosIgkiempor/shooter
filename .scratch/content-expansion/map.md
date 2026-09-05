# Content expansion

Label: wayfinder:map

## Destination

A spec for a content expansion across four axes — **enemy types**, **Maps as an ordered difficulty ladder**, **weapons**, and **bosses** — closing every design decision so that the content model, the named rosters, and the machinery each axis needs are fully specified. Reaching the end of this map means nothing is left to decide before someone goes and authors the content; implementation itself is a separate follow-on.

The game is mechanically dense and content-thin. Every system needed to carry variety already exists and is fully specified — the Movement/Attack axes, the Spawn Trigger timeline, the Weapon tier ladder, the Shop, Account progression, Relics, and `Map` with its objective fields — but almost nothing has been authored into them: one Map, one `Enemy_Kind`, and eight `Weapon_Kind`s of which two are labelled placeholders in their own source comment.

## Notes

- **Decisions only.** Wayfinder's plan-don't-do default stands: tickets close decisions, they do not author content or land code. The pull to just start writing enemy presets is the signal the map has reached its edge.
- Domain: see `CONTEXT.md`'s `## Language` section. Grilling tickets call the Skill tool twice ("grilling" + "domain-modeling"); prototype tickets call "prototype".
- **This effort may redraw another map's scope boundary.** [Enemy behaviours](../enemy-behaviours/map.md) explicitly ruled *Attack Style expansion* out of scope ("this effort only generalizes movement; attack logic stays frozen"). [Enemy variety model](issues/01-enemy-variety-model.md) may reopen it. If it does, **append an amendment pointer** into that map's Decisions-so-far rather than silently overriding it — the precedent is [Art revamp](../art-revamp/map.md), which reopened weapon-action-feel's locked "new art assumed needed" decision exactly this way.
- **Three foreign fog items graduate here.** Clear each from its own map as the corresponding ticket resolves:
  - [Enemy behaviours](../enemy-behaviours/map.md) — "Spawner content authoring — which levels/spawners actually place Floater and Swarmer enemies, and in what mix" → [Enemy catalog](issues/04-enemy-catalog.md).
  - [Shop and upgrades](../shop-and-upgrades/map.md) — "Concrete named Melee tier-ladder content and Magic tier-ladder numeric stats" → [Weapon catalog expansion](issues/08-weapon-catalog-expansion.md).
  - [Account progression](../account-progression/map.md) — per-`Enemy_Kind` Gold values, marked "placeholder, content-authoring" in `enemy_gold_presets` → [Enemy catalog](issues/04-enemy-catalog.md).
- **The three-shape actor vocabulary is superseded — do not design against it.** [Art revamp](../art-revamp/map.md) ticket 01's rectangle/circle/triangle-per-Movement-Style rule was overtaken by commit `665ad38`, which unified every enemy into a square sized by `enemy_body_size(max_health)`, tinted per kind and faded by remaining health, and deleted `Actor_Shape_Kind`. The live identity vocabulary for enemies is **colour, size and opacity**; there is no shape budget to run out of. Corrected here and on [Enemy catalog](issues/04-enemy-catalog.md) after [Enemy variety model](issues/01-enemy-variety-model.md) checked it against the code.
- **Flat-shape tiles are already decided, not open.** [Art revamp](../art-revamp/map.md)'s [tilemap ticket](../art-revamp/issues/04-tilemap-shape-treatment.md) locked flat fill for floor and wall, a darker inset bevel on walls, wall-vs-floor read from `Tile.collides`, and `Map`/persistence untouched. [Per-map theming](issues/07-per-map-theming-and-ambient-effects.md) builds *on* that; it does not reopen it.
- **`map_icon_colors`'s own comment anticipates this effort**: "Presentation only, so it lives here rather than on Map itself... Promote it onto Map if maps ever gain real per-map theming" ([map.odin](../../map.odin)). It also warns what promotion costs — the editor would need a colour picker, and the generated `maps.odin` is rewritten every build.
- **`MAX_ENEMIES :: 24`** silently truncates a composition batch. A deeper roster, denser ladder rungs, and a boss spawning adds all press on this ceiling from different directions — and it is the reason [ADR-0017](../../docs/adr/0017-run-outcome-and-map-objective.md) derives Cleared from the timeline rather than a kill quota.
- **Persistence is a trap, not a formality.** Any new `Movement_Style`/`Attack_Style` union variant needs its `*_Save` mirror with an explicit `kind` discriminant. `core:encoding/json`'s union-variant guessing is confirmed broken here — a `Kills_Reached`/`Repeating` trigger round-tripped back as `Time_Elapsed(0)`/`One_Shot`, silently wrong ([enemy.odin](../../enemy.odin)).
- **[ADR-0018](../../docs/adr/0018-weapon-visual-identity-is-per-kind-not-per-family.md)** governs any new weapon: per-kind geometry authored once in unit space, derived from `kind` at draw time and never stored on `Weapon` (it serializes into the save file), with distinctions that are **countable** rather than proportional.
- **[ADR-0017](../../docs/adr/0017-run-outcome-and-map-objective.md)** governs any boss: Cleared is the timeline exhausting *and* no enemies alive. A boss must be expressible in that frame, or the frame changes deliberately.
- Existing precedent worth reading before ticket 01: [ADR-0001](../../docs/adr/0001-weapon-wrapper-struct.md) (bare union vs. wrapper struct), [enemy-behaviours ticket 01](../enemy-behaviours/issues/01-enemy-data-structure-shape.md) (its two-axis extension), and `weapon_presets` (the flat-enum-into-preset-table counter-precedent).

## Decisions so far

- [Enemy variety model](issues/01-enemy-variety-model.md): `Enemy_Kind` becomes the authored unit, keying an `Enemy_Preset` table (movement, attack, `max_health`, colour, Gold — absorbing `enemy_gold_presets`), and a Map's composition entry collapses to `(kind, count)`. The behavioural axes stay open too, with an explicit rule: *behaviour* on the axes, *identity* on the kind. Attack Style is reopened (amending [Enemy behaviours](../enemy-behaviours/map.md)); `Charger` is the named Movement Style candidate. Deleting the templates from the composition entry removes enemy unions from persistence entirely, taking `Movement_Style_Save`/`Attack_Style_Save` and `map-builder`'s literal writers with them. `ENEMY_MAX_HEALTH` is deleted; no per-rung health scaling. Tuning is code-only, so the editor's composition UI collapses rather than grows. [ADR-0020](../../docs/adr/0020-enemy-kind-is-the-authored-unit.md).

## Not yet specified

- **What becomes of the level editor** if generation wins [Map layout authoring model](issues/02-map-layout-authoring-model.md) — retired, kept for spawn-timeline authoring only, or kept whole for hand-made chunks.
- Whether new enemy or map content wants **new pickup kinds** to drop. `Pickup_Kind` is Gold/Health/Ammo today; nothing has asked it to grow yet.
- **Balance numbers across the whole catalog** — playtesting work, not a design branch, matching how every prior map deferred its numerics.
- **Audio** for any new content — untouched here, and already standing fog on two other maps.

## Out of scope

- **New Relics, Upgrades, and `Account_Stat`s** — adjacent content axes, considered during scoping and not among the four selected. They spend the same Gold and would each need their own balance frame.
- **UI/menu chrome redesign** — settled by [Menu UI polish](../menu-ui-polish/map.md). Map Selection's *information* needs are in scope (see [Map ladder shape](issues/03-map-ladder-shape.md)); its visual language is not.
- **Implementation of any of it** — decisions only, per the Destination.
