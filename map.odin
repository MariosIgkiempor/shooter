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
	// -- ladder position (ADR-0022) ---------------------------------------
	// where this Map sits on the Map ladder, 1..N with no gaps and no
	// duplicates. Authored here rather than taken from Map_Name's order,
	// which the map_builder derives from a filename-sorted directory listing
	// and is therefore nobody's chosen ordering.
	rung:               int,
	// -- theme (ADR-0024) -------------------------------------------------
	// the two authored colours of the place. Everything else derives:
	// map_bevel_color mixes between them and map_swatch_color is the wall
	// itself, so the Map Selection screen cannot advertise a colour the
	// world does not have.
	floor_color:        Color,
	wall_color:         Color,
	// the decorative layers this Map runs continuously. Empty is a valid
	// authoring choice and means the Map looks exactly as its tiles do.
	ambient:            Ambient_Set `json:"-"`,
	// the on-disk form of `ambient`: one identity string per effect
	// (ADR-0028), resolved by load_map and rebuilt by save_map. Nil at
	// runtime, so clone_map and delete_map have nothing to do with it.
	ambient_save:       []string,
}

// the decorative layers a Map theme can run - drifting motes above the
// actors, off-grid patches on the floor beneath them, a directional wash of
// light across the screen. No vignette: the screen edges are where enemies
// enter, and an ambient effect may never occlude information (ADR-0024).
// Authored per Map rather than fixed, because five Maps differing only in
// hue read as five palettes rather than five places.
Ambient_Effect :: enum {
	Motes,
	Floor_Patches,
	Light_Wash,
}

Ambient_Set :: bit_set[Ambient_Effect]

// the wall bevel and the Map Selection swatch, derived from the two colours
// a Map authors rather than authored alongside them - a separately authored
// third colour would be free to disagree with the world it sits in or
// advertises, and deriving makes that disagreement unrepresentable
// (ADR-0024).
//
// The mix is weighted toward the floor so a wall reads as thicker than it is:
// on the Desert Dungeon palette it lands on {74, 64, 53}, within one 8-bit
// step of the TILEMAP_WALL_BEVEL_COLOR constant it replaces. That weighting
// is also what keeps the inset darker than the wall it insets - true for as
// long as a Map authors a floor darker than its wall, which is what a floor
// is, and which is the validity question ticket 15 asks of the pair.
MAP_BEVEL_MIX :: 0.27

map_bevel_color :: proc(map_data: Map) -> Color {
	return color_mix(map_data.floor_color, map_data.wall_color, MAP_BEVEL_MIX)
}

map_swatch_color :: proc(map_data: Map) -> Color {
	return map_data.wall_color
}

// channel-wise lerp, keeping a's alpha - the colours it mixes are opaque
// world colours, and an interpolated transparency has no meaning for any of
// them
color_mix :: proc(a, b: Color, t: f32) -> Color {
	return Color {
		u8(f32(a.r) + (f32(b.r) - f32(a.r)) * t),
		u8(f32(a.g) + (f32(b.g) - f32(a.g)) * t),
		u8(f32(a.b) + (f32(b.b) - f32(a.b)) * t),
		a.a,
	}
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

	// the theme's ambient set arrives as identity strings too (ADR-0028), and
	// resolves before the triggers below so its own allocations are gone
	// before any of that loop's failure paths can bail past them. An effect
	// this build doesn't have fails the load rather than quietly leaving the
	// Map one layer short of the place it was authored to be.
	for identity, effect_index in map_data.ambient_save {
		effect, effect_ok := enum_from_identity_string(Ambient_Effect, identity)
		if !effect_ok {
			log_error("Ambient effect {} in `{}` names something this build doesn't have", effect_index, path)
			delete_ambient_save(&map_data)
			delete_map(map_data)
			return {}, false
		}
		map_data.ambient += {effect}
	}
	delete_ambient_save(&map_data)

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

	// the live bit_set is what's authored; its identity-string list is
	// rebuilt from it here, the same way each trigger's *_save fields are
	// above. A local copy because an Odin parameter is immutable - and the
	// shallow copy is safe, since marshalling is the only thing that reads
	// it. The strings themselves point into static type info, so the temp
	// slice holding them is all there is to free.
	to_write := map_data
	ambient_save := make([dynamic]string, 0, len(Ambient_Effect), context.temp_allocator)
	for effect in Ambient_Effect {
		if effect in map_data.ambient {
			append(&ambient_save, enum_identity_string(effect))
		}
	}
	to_write.ambient_save = ambient_save[:]

	json_data, json_error := json.marshal(to_write, allocator = context.temp_allocator)
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

// frees the identity strings json.unmarshal allocated for a Map's ambient
// set, and the slice holding them, once they've been resolved into the live
// bit_set. Blanks the field so nothing downstream (clone_map, delete_map, a
// later save) can read or re-free what it points at - save_map rebuilds the
// list from the set rather than reusing this one.
delete_ambient_save :: proc(map_data: ^Map) {
	for &identity in map_data.ambient_save {
		delete_identity_string(&identity)
	}
	delete(map_data.ambient_save)
	map_data.ambient_save = nil
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
