Type: task
Blocked by: 03
Status: resolved

## Question

Specify the `Map.spawners: [dynamic]Spawner` → `Map.spawn_triggers:
[dynamic]Spawn_Trigger` migration across persistence and the map-baking
tool, plus how the existing authored content gets carried over.

Needs to settle:

- **`map.odin` changes.** Update `load_map`/`save_map`/`clone_map`
  (`map.odin:20-66`) for the new field and [ticket 03](03-spawn-trigger-data-model.md)'s
  `Spawn_Trigger` shape, including any `*_Save` plain-struct mirror
  needed for its `Movement_Style`/`Attack_Style` composition entries
  (matching today's `movement_template_save`/`attack_template_save`
  pattern on `Spawner`).
- **`vendor/map-builder` changes.** The baking tool mirrors `Map`'s shape
  into a composite-literal table in generated `maps.odin` (see the
  [Map baking tool](../../level-maps/issues/04-map-baking-tool.md) ticket
  for the exact pattern it follows for `Spawner` today) — confirm the
  equivalent mirroring for `Spawn_Trigger`, and that nothing else in the
  build pipeline still references the old `Spawner` shape once this
  lands.
- **`data/maps/desert_dungeon.json` migration.** The existing map's
  authored spawners need re-authoring into the new trigger format by
  hand — confirm this is a one-off manual edit (same precedent as the
  original desert-dungeon extraction in the
  [Maps map](../../level-maps/map.md)), not a reusable converter, and
  note it depends on [ticket 04](04-editor-spawn-trigger-authoring.md)'s
  authoring UX existing to actually do the re-authoring (though this
  ticket only needs to specify the migration, not perform it).

## Answer

**`map.odin` changes.** `Map.spawners: [dynamic]Spawner` (map.odin:17)
becomes `Map.spawn_triggers: [dynamic]Spawn_Trigger`. The per-element
Save-mirror conversion loops in `load_map`/`save_map` (map.odin:35-38,
47-50) go one level deeper than today's flat per-spawner loop, since the
template conversion now lives on each trigger's *composition entries*,
not on the trigger itself:

```odin
// load_map, after json.unmarshal:
for &trigger in map_data.spawn_triggers {
	for &entry in trigger.composition {
		entry.movement_template = movement_style_from_save(entry.movement_template_save)
		entry.attack_template = attack_style_from_save(entry.attack_template_save)
	}
}

// save_map, before json.marshal: the mirror image, entry.*_save = *_to_save(entry.*_template)
```

`clone_map` (map.odin:75-80) surfaces a **new aliasing hazard** beyond
what it already documents for `tilemap.tiles`/`spawners`: `Spawn_Trigger.composition`
is itself a slice field, so cloning the outer `[dynamic]Spawn_Trigger`
with `slice.clone_to_dynamic` only copies each trigger struct by value —
every clone's `composition` would alias the same backing array. Needs an
extra nested clone pass:

```odin
clone_map :: proc(template: Map) -> Map {
	result := template
	result.tilemap.tiles = slice.clone_to_dynamic(template.tilemap.tiles[:])
	result.spawn_triggers = slice.clone_to_dynamic(template.spawn_triggers[:])
	for &trigger in result.spawn_triggers {
		trigger.composition = slice.clone(trigger.composition)
	}
	return result
}
```

`delete_map` (map.odin:86-89) mirrors this: free each trigger's
`composition` before freeing the outer `spawn_triggers` array.

No changes needed to `apply_chosen_map`, `save_game`/`load_game`, or
`game_save.json` — per the Maps map's own decision, those never
referenced `spawners` in the first place.

**`vendor/map-builder` changes.** The tool keeps its own mirrored struct
definitions (`map_builder.odin:96` today defines its own `Spawner`, not
an import of the real type) — this needs a mirrored `Spawn_Trigger`/
`Spawn_Condition`/`Spawn_Mode`/`Spawn_Composition_Entry` set matching
[ticket 03](03-spawn-trigger-data-model.md)'s shape exactly. `write_spawners_literal`
(map_builder.odin:244-256) is replaced by a `write_spawn_triggers_literal`
that emits one `Spawn_Trigger{...}` composite literal per trigger,
delegating to new `write_spawn_condition_literal`/`write_spawn_mode_literal`
helpers for the union fields — following the exact same pattern
`write_movement_style_literal`/`write_attack_style_literal` already use
for `Spawner`'s two union fields today, since `Spawn_Condition`/`Spawn_Mode`
are the same "bare union of plain structs" shape. The composition list
itself needs its own literal-writer (a slice of `Spawn_Composition_Entry`,
each with a nested `write_movement_style_literal`/`write_attack_style_literal`
call per entry, same as today's per-spawner call but now looped once per
composition entry instead of once per spawner).

**`data/maps/desert_dungeon.json` migration.** One-off manual edit,
confirmed — no reusable converter, same precedent as the original
desert-dungeon extraction ([Maps map](../../level-maps/map.md)'s Notes).
Can be done as a direct hand-edit of the JSON file (the new shape is a
plain nested object, no different in kind from editing any other JSON
by hand) — it does **not** need to wait for [ticket 04](04-editor-spawn-trigger-authoring.md)'s
editor UI to actually exist; that UI is for ongoing authoring convenience,
not a hard requirement for this one-time migration.

**Ripple effects on this map**: none — this was the last data-shape/UX
ticket. The graduated [Spawn Trigger content authoring](06-spawn-trigger-content-authoring.md)
ticket (see map Notes) is pure content, not a further spec decision.
