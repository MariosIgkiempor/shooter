# Enemy spawn revamp

Label: wayfinder:map

## Destination

A spec for revamping enemy spawning and level HUD counters: (1) enemies always
spawn off-screen relative to the camera — no more fixed on-map `Spawner`
positions; (2) each `Map` defines a timeline of Spawn Triggers, keyed on
elapsed level time or level kill-count, each producing either a one-shot
batch or a continuous/repeating spawn of a composition (a mix of Movement
Style + Attack Style pairs, with counts); (3) the top-right HUD shows a live
Run-scoped kill counter and elapsed-time counter (reusing the existing
`Player.kills`/`survival_seconds`, reset at Run start — see ticket 01's
resolution for why this isn't "per-level"). Reaching the end of this map
means the exact data shapes
(`Spawn_Trigger`, the off-screen placement algorithm, the level-counter
state), the editor authoring UX, and the map-format/baking-tool migration are
all decided — implementation itself is a separate follow-on.

**Status: all tickets resolved.** Every data-shape, algorithm, editor UX,
persistence-migration, and content-authoring decision needed to build this
is closed. Nothing left to decide before the implementation follow-on
starts.

## Notes

- Odin + raylib. Key files: `enemy.odin` (`Spawner`, `update_spawners`,
  `spawn_enemy`, `MAX_ENEMIES`), `map.odin` (`Map` struct, `load_map`/
  `save_map`/`clone_map`/`apply_chosen_map`), `editor.odin` (spawner
  placement, `.Spawners` mode, property buttons), `main.odin`
  (`update_game_state`, `draw_game`, `game.camera` vs `game.ui_camera`,
  `GAMEPLAY_ZOOM`), `renderer.odin` (`draw_text`), `platform.odin`
  (`get_screen_width`/`get_screen_height`), `vendor/map-builder/`
  (mirrors `Map`/`Spawner` shape into baked `maps.odin`), `bullet.odin`
  (`apply_hit_to_enemy`, where kills currently increment).
- Domain: see `CONTEXT.md`'s `## Language` for **Movement Style**, **Attack
  Style**, and **Map**. This map should add a **Spawn Trigger** entry to
  `CONTEXT.md` once its shape is decided (ticket 03).
- Precedent maps to consult: [Maps](../level-maps/map.md) for the `Map`
  struct/persistence/baking-tool pattern any `Map` field change must mirror;
  [Enemy behaviours](../enemy-behaviours/map.md) for the `Movement_Style`/
  `Attack_Style` union shape a trigger's composition reuses, and its
  deferred "Spawner content authoring" fog item (now folded into this
  effort); [In-game HUD redesign](../hud-redesign/map.md) / ADR-0011 for why
  the new counters are screen-space (`game.ui_camera`), *not* world-space
  Resource indicators — they're level meta-stats, not an entity's own
  resource.
- No existing camera-viewport/world-bounds utility exists (`platform.odin`
  only exposes raw screen pixel dimensions) — the off-screen placement
  ticket has to build one from `camera.target`/`zoom`/screen size.
- The font atlas is missing a `/` glyph (`LETTERS_IN_FONT`, `atlas.odin:26`)
  — `hud.odin` already works around this for "X of Y" style text; reuse
  that convention for any counter format needing a separator.
- Grilling tickets in this map should call the Skill tool per wayfinder's
  Ticket Types section ("grilling" + "domain-modeling"); prototype tickets
  call it for "prototype".

## Decisions so far

- [Level kill and time counters](issues/01-level-kill-and-time-counters.md): no new state — "Level" is reserved for Account XP progression, and the thing that actually resets is a **Run** (pick Weapon, pick Map, play to death), which today always maps 1:1 to one Map pick. The counter reuses the existing Run-scoped `Player.kills`/`Player.survival_seconds` directly (no new fields, no new reset/increment hooks); the only new work is a top-right `draw_text` in the currently-no-op `.Playing` case of the `game.ui_camera` block (main.odin:786-790), format `"Kills: {}   Time: {}"` (MM:SS), visible under both the shop and run-end overlays since neither covers the top-right corner. Unblocks [Spawn Trigger data model](issues/03-spawn-trigger-data-model.md), whose Condition now reads these same existing fields.
- [Off-screen spawn placement](issues/02-offscreen-spawn-placement.md): angle-around-player at `hypot(visible_rect_half_w, visible_rect_half_h) + margin(~30px)`, computed from a new camera visible-world-rect helper (no rotation handling needed). Retry loop (cap 6) skips candidates still visible or blocked by tilemap collision, then clamps into map bounds; on exhausted retries, spawn anyway rather than dropping the spawn. `MAX_ENEMIES` gating is untouched. Prototyped on branch `prototype/offscreen-spawn-placement` (commit `2bebf71`).
- [Spawn trigger data model](issues/03-spawn-trigger-data-model.md): `Spawn_Trigger` holds three sibling fields — `condition` (`Time_Elapsed`/`Kills_Reached`, reading the existing Run-scoped `Player` fields), `mode` (`One_Shot`/`Repeating`, both sharing the same "spawn the whole composition batch" meaning), `composition` (a list of Movement Style + Attack Style + count entries) — plus non-persisted runtime fields (`fired`/`timer`/`elapsed`) mirroring how `Spawner` already mixes blueprint and runtime. Edge-triggered, fires at most once; multiple triggers may run concurrently; `MAX_ENEMIES` stays a shared global cap with silent-skip on overflow. New vocabulary recorded in [CONTEXT.md](../../CONTEXT.md) as **Spawn Trigger**. Unblocks [Editor spawn-trigger authoring](issues/04-editor-spawn-trigger-authoring.md) and [Map format migration and baking tool](issues/05-map-format-migration-and-baking-tool.md).
- [Editor spawn-trigger authoring](issues/04-editor-spawn-trigger-authoring.md): a vertical list of trigger rows with inline expand (click a row to reveal its condition/mode/composition editor beneath it, `+ Add Spawn Trigger` at the bottom) — won over a tile-grid-plus-side-panel and a property-button-cycling layout. No dedicated `Editor_Mode` case needed; the list is an always-visible panel while Editing, closer to the Maps map's always-visible map-switcher row than to today's `.Spawners` mode. Prototyped on branch `prototype/editor-spawn-trigger-authoring` (commit `2775c04`).
- [Map format migration and baking tool](issues/05-map-format-migration-and-baking-tool.md): `Map.spawners` → `Map.spawn_triggers`; `load_map`/`save_map`'s Save-mirror conversion loop moves one level deeper (per composition entry, not per trigger). `clone_map`/`delete_map` need a new nested clone/free pass for `Spawn_Trigger.composition` — a slice-typed field the outer array clone alone would otherwise alias. `vendor/map-builder` gets mirrored `Spawn_Trigger`/`Spawn_Condition`/`Spawn_Mode`/`Spawn_Composition_Entry` types and a `write_spawn_triggers_literal`, following the existing `write_movement_style_literal` pattern. `data/maps/desert_dungeon.json` migrates via a one-off manual JSON edit, not gated on the editor UI existing.
- [Spawn trigger content authoring](issues/06-spawn-trigger-content-authoring.md): three `Repeating`, indefinite-duration triggers that layer rather than replace — Phase 1 a `Time_Elapsed(0)` Grounded trickle, Phase 2 a `Kills_Reached(15)` Floater mix-in, Phase 3 a `Time_Elapsed(150)` Swarmer escalation — reusing the existing 6 spawners' exact stats verbatim, no rebalancing. No general cross-map authoring guideline; each map's phase/threshold/mix design is left as an open creative call. This was the map's last ticket.

## Not yet specified

## Out of scope

- New `Enemy_Kind` variety or new Movement/Attack Style variants — this
  effort only changes *when/where/how* existing enemy compositions spawn,
  not what compositions exist.
- Per-room or multi-zone spawn areas within a single map — triggers apply
  to the whole map's single timeline, not sub-regions.
- Adaptive/performance-based difficulty scaling — trigger thresholds are
  fixed, authored values; nothing adjusts them based on how the player is
  doing.
