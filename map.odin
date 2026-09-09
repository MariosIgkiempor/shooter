package shooter

import "core:encoding/json"
import "core:os"
import "core:slice"

// A named, reusable level definition - tile layout, a Spawn Trigger
// timeline, and a player start position. The same struct shape serves both
// the on-disk file (via load_map/save_map) and the live runtime copy a
// session plays on (game.current_map while Playing, game.editing_map while
// Editing) - see CONTEXT.md's Map entry.
Map :: struct {
	name:               string,
	player_start:       Vec2,
	tilemap:            Tilemap,
	spawn_triggers:     [dynamic]Spawn_Trigger,
	// -- objective (ADR-0017) ---------------------------------------------
	// seconds the player has to clear the Map before the Run ends in
	// Timed_Out. <= 0 means untimed, which only makes sense for a Map whose
	// Spawn Trigger timeline is itself finite.
	time_limit:         f32,
	// multiplier applied to a cleared Run's net Gold take (bank_run_gold).
	// Authored per Map so a later, harder rung of the ladder can pay more
	// for the risk it asks the player to carry.
	victory_multiplier: f32,
}

// the swatch color the Map Selection screen's icon draws in (icon.odin's
// icon_map_swatch). Presentation only, so it lives here rather than on Map
// itself: Map round-trips through data/maps/*.json and the map_builder, and
// a color baked into that format would need the level editor to grow a
// color picker to author it. Promote it onto Map if maps ever gain real
// per-map theming. Kept out of the generated maps.odin - build.sh re-runs
// the map_builder every build and would wipe it.
map_icon_colors: [Map_Name]Color = {
	.Desert_Dungeon = {214, 178, 108, 255}, // warm sand, matching the tilemap palette
}

load_map :: proc(path: string) -> (map_data: Map, ok: bool) {
	log_info("Loading map from `{}`", path)

	file_contents, file_error := os.read_entire_file(path, context.temp_allocator)
	if file_error != nil {
		log_error("Couldn't read map file at `{}`: {}", path, file_error)
		return {}, false
	}

	json_error := json.unmarshal(file_contents, &map_data)
	if json_error != nil {
		log_error("Couldn't unmarshal map file at `{}`: {}", path, json_error)
		return {}, false
	}

	// a name no case carries is a load failure, not something to guess at
	// (ADR-0028). The *_from_save procs name the offending identity and its
	// enum; these lines name the file and the record it sits in, so between
	// them the log says exactly which edit is needed. json.unmarshal has
	// already allocated by this point, hence the delete_map before bailing.
	for &trigger, trigger_index in map_data.spawn_triggers {
		condition, condition_ok := spawn_condition_from_save(trigger.condition_save)
		mode, mode_ok := spawn_mode_from_save(trigger.mode_save)
		if !condition_ok || !mode_ok {
			log_error("Spawn trigger {} in `{}` names something this build doesn't have", trigger_index, path)
			delete_map(map_data)
			return {}, false
		}
		trigger.condition = condition
		trigger.mode = mode
		// the identity strings have done their job. Unlike the ones
		// *_to_save writes (which point into static type info), these were
		// allocated by json.unmarshal out of the file, and nothing reads
		// them again - save_map rebuilds all four from the live unions
		// before it marshals. Freeing them here keeps a map switch from
		// leaking one string per trigger and per composition entry.
		delete_identity_string(&trigger.condition_save.kind)
		delete_identity_string(&trigger.mode_save.kind)

		for &entry, entry_index in trigger.composition {
			movement, movement_ok := movement_style_from_save(entry.movement_template_save)
			attack, attack_ok := attack_style_from_save(entry.attack_template_save)
			if !movement_ok || !attack_ok {
				log_error(
					"Composition entry {} of spawn trigger {} in `{}` names something this build doesn't have",
					entry_index,
					trigger_index,
					path,
				)
				delete_map(map_data)
				return {}, false
			}
			entry.movement_template = movement
			entry.attack_template = attack
			delete_identity_string(&entry.movement_template_save.kind)
			delete_identity_string(&entry.attack_template_save.kind)
		}
	}

	log_info("Loaded map from `{}`", path)
	return map_data, true
}

save_map :: proc(path: string, map_data: Map) -> bool {
	log_info("Saving map to `{}`", path)

	for &trigger in map_data.spawn_triggers {
		trigger.condition_save = spawn_condition_to_save(trigger.condition)
		trigger.mode_save = spawn_mode_to_save(trigger.mode)
		for &entry in trigger.composition {
			entry.movement_template_save = movement_style_to_save(entry.movement_template)
			entry.attack_template_save = attack_style_to_save(entry.attack_template)
		}
	}

	json_data, json_error := json.marshal(map_data, allocator = context.temp_allocator)
	if json_error != nil {
		log_error("Couldn't marshal map `{}`", path)
		return false
	}

	file_error := os.write_entire_file(path, json_data)
	if file_error != nil {
		log_error("Couldn't write map file at `{}`", path)
		return false
	}

	log_info("Saved map to `{}`", path)
	return true
}

// deep-copies a Map's dynamic-array fields. A plain value copy (`a := b`)
// only copies the [dynamic]Tile/[dynamic]Spawn_Trigger slice headers,
// aliasing the same backing memory - fine for load_map's result
// (json.unmarshal always allocates fresh backing arrays), but anything
// copying out of a long-lived shared Map value (the baked `maps` table, or
// game.current_map while entering Editing) must go through this instead, or
// in-run tile/trigger mutation would corrupt the shared source.
// Spawn_Trigger.composition is itself a slice field, so cloning the outer
// array alone would leave every clone's composition aliasing the same
// backing array - each trigger needs its own nested clone too.
clone_map :: proc(template: Map) -> Map {
	result := template
	result.tilemap.tiles = slice.clone_to_dynamic(template.tilemap.tiles[:])
	result.spawn_triggers = slice.clone_to_dynamic(template.spawn_triggers[:])
	for &trigger in result.spawn_triggers {
		trigger.composition = slice.clone(trigger.composition)
	}
	return result
}

// frees a Map's own dynamic-array backing memory (as opposed to whatever it
// was cloned from). Call before overwriting a live Map value (e.g.
// game.editing_map, reassigned every time Editing is entered or the map
// switcher picks a new map) so the previous map's tiles/triggers don't leak
// - each trigger's composition is freed before the outer array, mirroring
// clone_map's nested clone above.
delete_map :: proc(map_data: Map) {
	delete(map_data.tilemap.tiles)
	for trigger in map_data.spawn_triggers {
		delete(trigger.composition)
	}
	delete(map_data.spawn_triggers)
}

// resolves resume-vs-reset player positioning against game_save.json's
// active-map pointer: called once, at the point the player's map choice is
// finalized (Selecting -> Playing). First-ever launch falls out naturally -
// game.active_map_pointer starts as the zero value (empty string), which
// never matches any real identity, so the reset branch always fires.
apply_chosen_map :: proc(map_data: Map, chosen_identity: string) {
	// the live tilemap has just been replaced, so every cell the flow field
	// holds describes the previous Map. Invalidate rather than destroy: the
	// allocation is reused by the next flood.
	flow_field_invalidate(&game.flow_field)

	if chosen_identity != game.active_map_pointer {
		game.player.rect.x = map_data.player_start.x
		game.player.rect.y = map_data.player_start.y
	}
	game.active_map_pointer = chosen_identity
}
