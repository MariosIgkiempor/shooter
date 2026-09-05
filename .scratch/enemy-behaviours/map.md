# Enemy behaviours

Label: wayfinder:map

## Destination

A spec for splitting the current `Enemy_Behaviour` (a bare union of `Melee` | `Ranged`, movement and attack bundled per variant) into two orthogonal, composable axes:

- **Movement Style** — grounded chase via the existing BFS path, ghostly Floater drift (no tilemap collision, erratic wander), Swarmer surround (flanks the player instead of converging with other Swarmers on one point).
- **Attack Style** — frozen at today's Melee / Ranged / none logic, just re-plugged onto the new movement axis instead of being bundled with it.

Layered on top: a same-Movement-Style **Separation** steering force so enemies don't clump onto the same point/path. Reaching the end of this map means every architecture, design-feel, and integration decision needed to build this is closed — implementation itself is a separate follow-on.

**Status: all tickets resolved.** Every architecture and design-feel decision is closed, plus precise implementation checklists for the editor/debug/persistence integration work. Nothing left to decide before the implementation follow-on starts (the two "Not yet specified" items below are deliberately deferred, not blockers).

## Notes

- Domain: see `CONTEXT.md`'s `## Language` section for **Movement Style**, **Attack Style**, and **Separation** (already written during this map's charting). `Enemy_Behaviour` is the retiring pre-split name.
- Consult `docs/adr/0001-weapon-wrapper-struct.md` before the data-structure ticket — it's the existing precedent for "bare union vs wrapper struct" polymorphism in this codebase, but Enemy now needs to hold *two* independent axis values at once, which neither existing shape directly covers.
- Prototype/grilling tickets in this map should call the Skill tool per the wayfinder skill's Ticket Types section (prototype → "prototype"; grilling → "grilling" + "domain-modeling").
- Existing Melee/Ranged enemies are not required to keep exact current behavior through this split — some drift (e.g. picking up Separation by default) is acceptable.
- Sprite/animation assets for Floater and Swarmer (formerly listed as fog below) are now specified by the [Art revamp](../art-revamp/map.md) map's [actor shape and movement transform](../art-revamp/issues/01-actor-shape-and-movement-transform.md) ticket: Floater renders as a circle, Swarmer as a triangle, both sharing the same continuous-squash movement transform as every other actor.

## Decisions so far

- [Enemy data-structure shape](issues/01-enemy-data-structure-shape.md): `Enemy` gains two sibling bare-union fields, `movement: Movement_Style` (`Grounded | Floater | Swarmer`) and `attack: Attack_Style` (`Melee | Ranged`), replacing `behaviour: Enemy_Behaviour`. `speed` moves onto each Movement Style variant. No new ADR — treated as a natural two-axis extension of ADR-0001's bare-union rule.
- [Separation force design](issues/02-separation-force-design.md): radius 40px, strength 3.0 (separation:chase = 3:1), blend as `normalize(chase_dir + separation_dir * strength) * speed * dt`, grouped by Movement Style only (confirmed live in the prototype). Build a spatial grid for neighbour lookup, not brute-force, for headroom. Prototype on branch `prototype/separation-force`.
- [Floater movement design](issues/03-floater-movement-design.md): overlaps the player, ignores arena bounds, low Floater-Floater separation (radius ~15px, strength ~0.5, much gentler than Grounded's), wobble amplitude 80px at 3Hz blended with a pull-toward-player of 0.35. Needs its own movement-application path outside the collision-clamped `move_actor` other Movement Styles use. Prototype on branch `prototype/floater-movement`.
- [Swarmer surround mechanic](issues/04-swarmer-surround-mechanic.md): dynamic nearest-free-slot assignment on a ring around the player, with Separation layered on top (not replaced) using Floater-like gentle tuning (radius ~15px, strength ~0.5). Surround radius = the Swarmer's own Attack Style `attack_range` (fallback 60px if nil). Resolves the Separation/Swarmer composition fog item below. Prototype on branch `prototype/swarmer-surround`.
- [Editor and debug overlay rework](issues/05-editor-and-debug-overlay-rework.md): kept decision-only — resolved into a precise implementation checklist (two independent selector rows in `editor.odin`, extended `draw_debug_attack_ranges` plus a new Movement Style debug visualization in `main.odin`) rather than executed now, since it needs ticket 01's struct split actually landed in `enemy.odin` first, which is out of this map's scope.
- [Persistence extension](issues/06-persistence-extension.md): kept decision-only — resolved into a concrete `Movement_Style_Save`/`Attack_Style_Save` DTO pair (mirroring today's `Enemy_Behaviour_Save` pattern exactly) plus the `Spawner` field changes needed to hold two templates instead of one, as a checklist for the implementation follow-on.

## Not yet specified

- Spawner content authoring — which levels/spawners actually place Floater and Swarmer enemies, and in what mix (parallel to how the weapon-types map deferred weapon tier-ladder content authoring).

## Out of scope

- Attack Style expansion (new attack types beyond Melee/Ranged/none) — this effort only generalizes movement; attack logic stays frozen.
- Turret/stationary and Charger/ambusher archetypes — considered during scoping alongside Floater and Swarmer, not selected for this effort.
- Full boids (alignment + cohesion) — only Separation (anti-clumping) is in scope; the rest of the classic flocking triad was not requested.
- Editor/debug-tooling being left stale — explicitly ruled *in* scope instead (see Editor and debug overlay rework ticket), noted here only to record that "leave it broken" was considered and rejected.
