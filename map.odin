package shooter

import "core:encoding/json"
import "core:os"
import "core:reflect"
import "core:slice"

// A named, reusable level definition - tile layout, spawner definitions, and
// a player start position. The same struct shape serves both the on-disk
// file (via load_map/save_map) and the live runtime copy a session plays on
// (game.current_map while Playing, game.editing_map while Editing) - see
// CONTEXT.md's Map entry.
Map :: struct {
	name:         string,
	player_start: Vec2,
	tilemap:      Tilemap,
	spawners:     [dynamic]Spawner,
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

	for &spawner in map_data.spawners {
		spawner.movement_template = movement_style_from_save(spawner.movement_template_save)
		spawner.attack_template = attack_style_from_save(spawner.attack_template_save)
	}

	log_info("Loaded map from `{}`", path)
	return map_data, true
}

save_map :: proc(path: string, map_data: Map) -> bool {
	log_info("Saving map to `{}`", path)

	for &spawner in map_data.spawners {
		spawner.movement_template_save = movement_style_to_save(spawner.movement_template)
		spawner.attack_template_save = attack_style_to_save(spawner.attack_template)
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
// only copies the [dynamic]Tile/[dynamic]Spawner slice headers, aliasing the
// same backing memory - fine for load_map's result (json.unmarshal always
// allocates fresh backing arrays), but anything copying out of a long-lived
// shared Map value (the baked `maps` table, or game.current_map while
// entering Editing) must go through this instead, or in-run tile/spawner
// mutation would corrupt the shared source.
clone_map :: proc(template: Map) -> Map {
	result := template
	result.tilemap.tiles = slice.clone_to_dynamic(template.tilemap.tiles[:])
	result.spawners = slice.clone_to_dynamic(template.spawners[:])
	return result
}

// frees a Map's own dynamic-array backing memory (as opposed to whatever it
// was cloned from). Call before overwriting a live Map value (e.g.
// game.editing_map, reassigned every time Editing is entered or the map
// switcher picks a new map) so the previous map's tiles/spawners don't leak.
delete_map :: proc(map_data: Map) {
	delete(map_data.tilemap.tiles)
	delete(map_data.spawners)
}

// resolves resume-vs-reset player positioning against game_save.json's
// active-map pointer: called once, at the point the player's map choice is
// finalized (Selecting -> Playing). First-ever launch falls out naturally -
// game.active_map_pointer starts as the zero value (empty string), which
// never matches any real identity, so the reset branch always fires.
apply_chosen_map :: proc(map_data: Map, chosen_identity: string) {
	if chosen_identity != game.active_map_pointer {
		game.player.rect.x = map_data.player_start.x
		game.player.rect.y = map_data.player_start.y
	}
	game.active_map_pointer = chosen_identity
}

// the canonical identity a Map_Name is stored/compared as in
// game_save.json's active_map_pointer - the enum case's name, read directly
// from Odin's static type info (not allocated, safe to store indefinitely)
map_identity_string :: proc(name: Map_Name) -> string {
	str, _ := reflect.enum_name_from_value(name)
	return str
}
