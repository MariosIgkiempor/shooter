# Art revamp

Label: wayfinder:map

**Status: all tickets resolved.** Every decision needed to build this is closed — the shape vocabulary, the movement transform, weapon effects, bullets/pickups, tilemap, palette consistency, and atlas cleanup. Nothing left to decide before the implementation follow-on starts.

## Destination

A spec for replacing all sprite-based art in the game world — player, enemies, weapon icons, bullets, pickups, and the tilemap — with a unified geometric-shapes rendering system, including a movement-conveying transform (tilt/squish) applied uniformly to player and enemy actors via the shared `draw_actor`. Explicitly reconciles weapon-action-feel's locked "new art assumed needed" decision against this shapes+transform-only direction. UI/menu chrome (9-slice panels, splash background) stays out of scope. Reaching the end of this map means the shape vocabulary, the transform system's mechanics, and each entity category's treatment are fully specified — implementation itself is a separate follow-on.

## Notes

- Domain: CONTEXT.md's `## Language` section; [ADR-0010](../../docs/adr/0010-hand-rolled-menu-ui-no-layout-engine.md) (hand-rolled over generic engine/library — same approach applies here); [ADR-0011](../../docs/adr/0011-in-game-hud-moves-to-world-space-resource-indicators.md) (already-shape precedent, defines "Resource indicator").
- Reopens a locked decision in [weapon-action-feel](../weapon-action-feel/map.md) ("New art... assumed needed", see its Notes and issues 04-06). Resolving that ticket here must append an amendment pointer into weapon-action-feel's Decisions-so-far (and the affected prototype tickets), not silently override it — per domain-modeling's flag-conflicts rule.
- Resolving the actor-shape ticket graduates [enemy-behaviours](../enemy-behaviours/map.md)'s open fog item "Sprite/animation assets for Floater and Swarmer" — update that map's Not-yet-specified once landed.
- Existing transform precedent to build on: `draw_weapon`'s pivot/angle/scale pattern (main.odin:872-976), `exp_approach` (editor.odin:147-149) as the easing primitive, `shake.odin`'s trauma-decay pattern.
- `draw_actor` (main.odin:779-799) is the single shared call site for Player and Enemy body rendering — the transform system hooks in here.
- Tilemap-as-shapes only changes how tile IDs render; it does not touch the `Map` struct/persistence from level-maps.
- Grilling tickets call the Skill tool twice ("grilling" + "domain-modeling"); the actor-shape and tilemap tickets call "prototype" too (HITL, visual questions).

## Decisions so far

- [Actor shape and movement transform](issues/01-actor-shape-and-movement-transform.md): Variant A wins — continuous isotropic squash (`scale_x`→1.15, `scale_y`→0.85 while moving, eased via `exp_approach`, no rotation/tilt at all). Shapes by entity type: Player/Grounded = rectangle, Floater = circle, Swarmer = triangle. Sets the vocabulary and transform mechanics every other in-scope ticket builds on. Prototype on branch `prototype/actor-shape-transform`.
- [Weapon shape and reconcile weapon-action-feel](issues/02-weapon-shape-and-reconcile-weapon-action-feel.md): distinct silhouette per weapon family (Gun=rod, Melee=wedge, Magic=rod+orb). Enhanced shape-based particle effects (a new streak kind, a new one-shot flash kind, non-linear fades) confirmed to supply the "punch" weapon-action-feel found plain icon-transform lacking — today's existing dot-only particles remain insufficient, confirming the gap was in the particle *vocabulary*, not shapes as a category. Amends weapon-action-feel's locked "new art assumed needed" decision. Prototype: [Weapon Effects Bench](https://claude.ai/code/artifact/3acfe471-59f9-4fe7-a171-dbd7bd97f6f9).
- [Bullets and pickups shape treatment](issues/03-bullets-and-pickups-shape-treatment.md): bullets reuse ticket 02's streak shape (player=gold/yellow, enemy=red, unchanged tints); Fireball bullets get a distinct thicker "comet" shape, not just its existing orange color. Gold pickup stays an unchanged circle; Health = a plus/cross, Ammo = stacked short bars — both chosen to avoid colliding with the already-claimed rect/circle/triangle vocabulary.
- [Tilemap shape treatment](issues/04-tilemap-shape-treatment.md): flat fill for both floor and wall, walls get a darker inset bevel border for thickness (no grid lines, no per-tile color noise). Wall/floor comes from the existing `Tile.collides` bool, untouched by `Map`/persistence. Warm sand/stone palette, judged live at play scale in the real shipped level. Prototype on branch `prototype/tilemap-shapes`.
- [Shape-vocabulary consistency pass](issues/05-shape-vocabulary-consistency-pass.md): only spawner markers change — recolored from Grounded-enemy-clashing RED to a muted gray-blue (they're visible during real gameplay, not just the editor). Gold, poison cloud, particles, and the Resource-indicator palette are all confirmed consistent as-is. Also closed a loose end from ticket 03: Health = warm red/pink, Ammo = light gray/silver (colors were left unspecified there).
- [Atlas pipeline cleanup](issues/06-atlas-pipeline-cleanup.md): 24 now-dead `Texture_Name` entries and their source files deleted outright (including `Particle_Poison_Gas0-3` — brought into scope and decided directly: replaced with square particles that fade over time). The level editor's tile picker keeps real Kenney thumbnails (editor tooling, not world-facing art), so `tileset_normal`'s backing texture is kept. `vendor/atlas-builder` needs no code change — it re-packs whatever's present generically. `rl.SetShapesTexture` confirmed unaffected by a shrunken atlas.

## Not yet specified

- Whether the movement-transform pattern extends beyond movement-start to other actor states (damage flash, death, firing) — not sharp yet, may still be worth a look during implementation but doesn't block it.
- Per-frame transform-math performance at scale (many enemies, or many weapon-effect particles now that bursts are bigger) — not raised as a real concern, just unmeasured.

## Out of scope

- UI/menu chrome (9-slice panels/buttons) — excluded during scoping; redone with real art via ADR-0010 (commit `34592ce`; `7bb9f07` is a `.scratch`/ADR doc commit, not an art one — corrected here, the original citation was wrong). Splash's background image was also out of scope, but not because any commit already redid it: it was never sprite/atlas art needing this effort's shape treatment to begin with, and stayed untouched. Never ticketed. Now itself in scope for [Flat-Rect Menu UI: Transitions & Animation](../menu-ui-polish/map.md), which additionally supersedes ADR-0010's nine-slice-reuse decision.
