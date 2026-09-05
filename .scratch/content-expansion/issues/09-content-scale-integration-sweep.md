# Content-scale integration sweep

Type: grilling
Blocked by: 01, 03, 05, 08
Status: open

## Question

What breaks once the catalogs are real rather than placeholders?

Every system in this game was built and tested against one enemy kind, one map, and eight weapons. This ticket walks the seams and decides what each needs, producing an implementation checklist rather than leaving the follow-on session to discover them — the same shape [Enemy behaviours](../../enemy-behaviours/map.md) used for its editor/persistence tickets.

Known seams:

- **`ENEMY_MAX_HEALTH` is deleted.** `Enemy` gains `max_health` from its preset; the two draw-time reads ([main.odin:1095-1096](../../../main.odin)) and `enemy_body_size`'s caller switch to it. Worth checking what else assumed a uniform 50 — `enemy_spawn_test.odin` and the debug overlays are the likely sites.
- **`MAX_ENEMIES :: 24`.** A composition batch is silently truncated at the cap, which is precisely why [ADR-0017](../../../docs/adr/0017-run-outcome-and-map-objective.md) derives Cleared from the timeline rather than a kill quota. A deeper roster, denser ladder rungs, and a boss spawning adds all press on this ceiling from different directions. Raise it, budget it per rung, or prioritise which enemies survive truncation?
- **Map Selection.** `draw_map_selection_ui` ([hud.odin](../../../hud.odin)) draws one button per `Map_Name` in a single column. A ladder needs order, and possibly locked and cleared states, per [Map ladder shape](03-map-ladder-shape.md).
- **Persistence — now a deletion, not an extension.** [Enemy variety model](01-enemy-variety-model.md) found `Spawn_Composition_Entry` to be the only place enemy unions are ever marshalled, so authoring an `Enemy_Kind` there removes them from persistence entirely: `Movement_Style_Save`/`Attack_Style_Save`, their four conversion procs, `map.odin`'s hooks ([map.odin:59-76](../../../map.odin)), and `vendor/map-builder`'s duplicated DTOs and both `write_*_literal` procs ([map_builder.odin:326](../../../vendor/map-builder/map_builder.odin)) all become dead. `desert_dungeon.json`'s six composition entries need rewriting as `(kind, count)` — which also stops it baking runtime fields (`attack_timer`, `wobble_phase`) into the file. New axis variants therefore need **no** `*_Save` mirror. `Spawn_Trigger`'s own condition/mode unions are untouched and still need theirs — the `core:encoding/json` union-guessing hazard is real and confirmed here ([enemy.odin](../../../enemy.odin)), just no longer on the enemy path.
- **The level editor.** Settled by [Enemy variety model](01-enemy-variety-model.md), and in the opposite direction to what this ticket first assumed: `draw_spawn_composition_entry_ui` **collapses** to a kind selector plus a count, losing every per-field slider ([editor.odin:694](../../../editor.odin)). Since presets are a code table, numeric tuning now means editing `enemy.odin` and rebuilding — the `weapon_presets` model. Open here: whether a debug-panel live-tuning overlay is worth building to replace what the sliders gave (`debug.odin` is toggles and buttons only today, so there is no idiom to extend), or whether rebuild-to-tune is genuinely fine.
- **`enemy_gold_presets` is dissolved, not filled.** [Enemy variety model](01-enemy-variety-model.md) folded the Gold payout into `Enemy_Preset`, so there is one table keyed by `Enemy_Kind` rather than two. `enemy_gold_value` reads through it; `total_kills` and the `[Enemy_Kind]int` kill tally are unaffected but now iterate a real roster.
- **The dev weapon-cycle hotkey.** `cycle_weapon_kind` walks `weapon_family_kinds` with the arrow keys, and [Shop and upgrades](../../shop-and-upgrades/map.md) already carries "whether the dev-only LEFT/RIGHT hotkey is retired now a real Shop exists" as open fog. A longer ladder makes it either more useful or more misleading.
- **Debug overlays.** `draw_debug_attack_ranges` and the Movement Style visualisation assume today's small vocabulary.

Blocked by [Enemy variety model](01-enemy-variety-model.md), [Map ladder shape](03-map-ladder-shape.md), [Boss model](05-boss-model.md) and [Weapon catalog expansion](08-weapon-catalog-expansion.md) — it can only sweep seams once it knows what is coming through them.
