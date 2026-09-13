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
	// the decorative layers this Map runs continuously (ambience.odin). Empty
	// is a valid authoring choice and means the Map looks exactly as its
	// tiles do.
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

// the accent that tints a Map theme's ambience - its motes and the top of
// its light wash - pushed off the wall toward white (CONTEXT.md's Map theme
// entry). Derived like the bevel, and for the same reason: an authored third
// colour would be free to belong to no place in particular (ADR-0024). The
// mix is the prototype's, judged in motion on content-expansion ticket 07.
MAP_ACCENT_MIX :: 0.45

map_accent_color :: proc(map_data: Map) -> Color {
	return color_mix(map_data.wall_color, {255, 255, 255, 255}, MAP_ACCENT_MIX)
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

// channel-wise scale toward black, keeping alpha - color_mix's sibling for
// "this colour, dimmed", used where a theme darkens its own floor
color_scale :: proc(c: Color, factor: f32) -> Color {
	return Color {
		u8(clamp(f32(c.r) * factor, 0, 255)),
		u8(clamp(f32(c.g) * factor, 0, 255)),
		u8(clamp(f32(c.b) * factor, 0, 255)),
		c.a,
	}
}

// perceived brightness, Rec. 601 weights - the coarse "is this the darker of
// the two" a floor-against-wall comparison needs, not a colour-managed one.
// Ignores alpha: the colours it ranks are opaque world colours.
color_luma :: proc(c: Color) -> f32 {
	return 0.299 * f32(c.r) + 0.587 * f32(c.g) + 0.114 * f32(c.b)
}

// -- validity (ticket 15) ---------------------------------------------------
// The two answers about an authored Map that the validity sweep in
// map_test.odin needs and nothing at runtime derives for it. Both read only
// what an author wrote, never `game`.

// the cell footprint a Map may not exceed on either axis. Footprint is held
// flat across the ladder - a harder Map is denser, not bigger (ADR-0021) -
// and this is the footprint the shipped Maps have, so a Map that wants more
// changes this on purpose rather than drifting past it.
MAP_MAX_CELL_EXTENT :: Vec2i{54, 48}

// the earliest point a Map's timeline can stop producing enemies, and whether
// it can stop at all. This is what `time_limit` has to clear (ADR-0022). The
// runtime sibling is spawn_timeline_exhausted (main.odin), which asks whether
// a Run's timeline is finished *now* and reads the latches
// update_spawn_triggers writes; this one reads only the authored triggers.
//
// A Time_Elapsed condition names its own activation time. A Kills_Reached one
// does not: the count could be met on the first frame or never, so its
// activation is play-dependent and unknowable here. Zero is the only honest
// answer, and taking it makes this a *lower* bound on the timeline rather
// than a prediction of it - a Map whose limit does not clear even the
// earliest possible finish is broken for certain, which is the claim a
// validity test can actually make. It cannot certify the other direction,
// and does not pretend to.
//
// A trigger's span is its Repeating duration and nothing more:
// update_spawn_triggers stops firing once `elapsed` passes `duration`, so
// activation + duration is the last instant it can still spawn. A One_Shot
// spans nothing. `bounded` is false where some Repeating trigger has
// duration <= 0, which runs until the Run ends: such a Map can never be
// Cleared at all (CONTEXT.md's Run outcome entry), whatever its time limit.
map_timeline_earliest_end :: proc(triggers: []Spawn_Trigger) -> (seconds: f32, bounded: bool) {
	bounded = true
	for trigger in triggers {
		activation: f32
		switch condition in trigger.condition {
		case Time_Elapsed:
			activation = max(condition.seconds, 0)
		case Kills_Reached:
			activation = 0
		}

		span: f32
		if repeating, is_repeating := trigger.mode.(Repeating); is_repeating {
			if repeating.duration <= 0 {
				bounded = false
				continue
			}
			span = repeating.duration
		}

		seconds = max(seconds, activation + span)
	}
	return seconds, bounded
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
		// them again - save_map rebuilds each of them from the live value
		// beside it before it marshals. Freeing them here keeps a map switch from
		// leaking one string per trigger and per composition entry.
		delete_identity_string(&trigger.condition_save.kind)
		delete_identity_string(&trigger.mode_save.kind)

		for &entry, entry_index in trigger.composition {
			kind, kind_ok := enum_from_identity_string(Enemy_Kind, entry.kind_save)
			if !kind_ok {
				log_error(
					"Composition entry {} of spawn trigger {} in `{}` names an Enemy Kind this build doesn't have",
					entry_index,
					trigger_index,
					path,
				)
				delete_map(map_data)
				return {}, false
			}
			entry.kind = kind
			delete_identity_string(&entry.kind_save)
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
			entry.kind_save = enum_identity_string(entry.kind)
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

// finalizes a Map choice, if its rung is open (ADR-0022): the one path from
// Selecting to a live Map. The gate lives here and not only in the screen
// that grays the row, the same way try_buy_account_stat re-checks its own
// unlock. False is a no-op - the live map, the active-map pointer and the
// player's position are all left exactly as they were.
try_choose_map :: proc(name: Map_Name) -> bool {
	if !map_rung_open(name) {
		return false
	}

	// clone_map, never a plain value copy - game.current_map would otherwise
	// alias the shared baked table's backing tile/spawner memory (see
	// clone_map's doc comment)
	game.current_map = clone_map(maps[name])
	apply_chosen_map(game.current_map, enum_identity_string(name))
	return true
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
	flow_field_invalidate(&game.boss_flow_field)
	ambience_invalidate(&game.ambience)

	if chosen_identity != game.active_map_pointer {
		game.player.rect.x = map_data.player_start.x
		game.player.rect.y = map_data.player_start.y
	}
	game.active_map_pointer = chosen_identity
}
