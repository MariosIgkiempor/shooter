/*
This map builder looks into a 'data/maps' folder for map JSON files (the
shape written by the shooter package's save_map) and generates `maps.odin`:
a Map_Name enum (one case per file) indexing a fully-baked [Map_Name]Map
table, plus a map_path_for_name proc mapping each case back to its source
file. Playing mode consumes the baked table directly (no runtime file I/O);
Editing mode stays entirely file-based via load_map/save_map and never reads
this generated table - see the Maps map's map-baking-tool ticket.

Mirrors vendor/atlas-builder's shape and conventions exactly, including its
strings.to_ada_case naming convention for deriving enum case names.
*/
package map_builder

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"
import "core:path/slashpath"
import "core:slice"
import "core:strings"

MAPS_DIR :: "data/maps"
MAPS_ODIN_OUTPUT_PATH :: "maps.odin"

// -- local mirrors of the shooter package's persistence-facing types --------
//
// This program never imports the shooter package (maps.odin doesn't exist
// yet on a clean checkout, and shooter's own code already assumes it does -
// same bootstrapping constraint atlas_builder.odin's Atlas_Texture mirror
// documents). These types exist only to unmarshal a map JSON file; the
// generated output below re-emits the data as literal Odin source using the
// shooter package's real type names, which this program never needs to
// resolve or type-check itself.

Vec2 :: [2]f32
Vec2i :: [2]i32

// raylib's Color, mirrored rather than imported like everything else here -
// an RGBA array, which is the shape it marshals to and out of
Color :: [4]u8

Tile :: struct {
	world_coords: Vec2i,
	collides:     bool,
}

Tilemap :: struct {
	tile_size: Vec2,
	tiles:     [dynamic]Tile,
}

Grounded_Save :: struct {
	speed: f32,
}

Floater_Save :: struct {
	speed:            f32,
	wobble_amplitude: f32,
	wobble_frequency: f32,
	pull_strength:    f32,
	wobble_phase:     f32,
}

Swarmer_Save :: struct {
	speed: f32,
}

Movement_Style_Save :: struct {
	kind:     string,
	grounded: Maybe(Grounded_Save) `json:"grounded,omitempty"`,
	floater:  Maybe(Floater_Save) `json:"floater,omitempty"`,
	swarmer:  Maybe(Swarmer_Save) `json:"swarmer,omitempty"`,
}

Melee_Save :: struct {
	attack_damage:   f32,
	attack_range:    f32,
	attack_cooldown: f32,
	attack_timer:    f32,
}

Ranged_Save :: struct {
	min_range:        f32,
	max_range:        f32,
	attack_damage:    f32,
	projectile_speed: f32,
	fire_rate:        f32,
	bullet_lifetime:  f32,
	fire_timer:       f32,
}

Attack_Style_Save :: struct {
	kind:   string,
	melee:  Maybe(Melee_Save) `json:"melee,omitempty"`,
	ranged: Maybe(Ranged_Save) `json:"ranged,omitempty"`,
}

Spawn_Composition_Entry :: struct {
	movement_template_save: Movement_Style_Save,
	attack_template_save:   Attack_Style_Save,
	count:                  int,
}

Time_Elapsed :: struct {
	seconds: f32,
}

Kills_Reached :: struct {
	count: int,
}

Spawn_Condition_Save :: struct {
	kind:          string,
	time_elapsed:  Maybe(Time_Elapsed) `json:"time_elapsed,omitempty"`,
	kills_reached: Maybe(Kills_Reached) `json:"kills_reached,omitempty"`,
}

One_Shot :: struct {}

Repeating :: struct {
	interval: f32,
	duration: f32,
}

Spawn_Mode_Save :: struct {
	kind:      string,
	one_shot:  Maybe(One_Shot) `json:"one_shot,omitempty"`,
	repeating: Maybe(Repeating) `json:"repeating,omitempty"`,
}

Spawn_Trigger :: struct {
	condition_save: Spawn_Condition_Save,
	mode_save:      Spawn_Mode_Save,
	composition:    [dynamic]Spawn_Composition_Entry,
}

Map :: struct {
	name:               string,
	player_start:       Vec2,
	tilemap:            Tilemap,
	spawn_triggers:     [dynamic]Spawn_Trigger,
	time_limit:         f32,
	victory_multiplier: f32,
	rung:               int,
	floor_color:        Color,
	wall_color:         Color,
	// only the on-disk form is mirrored: the generated literal emits the
	// shooter package's live `ambient` bit_set from these names, the same way
	// each Spawn_Trigger's *_save fields become live unions below
	ambient_save:       []string,
}

Map_Source :: struct {
	enum_name: string,
	file_name: string,
	path:      string,
	data:      Map,
}

main :: proc() {
	context.logger = log.create_console_logger()

	d, derr := os.open(MAPS_DIR, os.O_RDONLY)
	if derr != nil {
		log.panicf("No %s folder found", MAPS_DIR)
	}
	defer os.close(d)

	file_infos, read_err := os.read_dir(d, -1, context.allocator)
	if read_err != nil {
		log.panicf("Couldn't read `%s`: %v", MAPS_DIR, read_err)
	}

	slice.sort_by(file_infos, proc(i, j: os.File_Info) -> bool {
		return i.name < j.name
	})

	sources: [dynamic]Map_Source

	for fi in file_infos {
		if !strings.has_suffix(fi.name, ".json") {
			continue
		}

		path := fmt.tprintf("%s/%s", MAPS_DIR, fi.name)

		file_contents, file_err := os.read_entire_file(path, context.allocator)
		if file_err != nil {
			log.panicf("Couldn't read map file `%s`: %v", path, file_err)
		}

		data: Map
		json_err := json.unmarshal(file_contents, &data)
		if json_err != nil {
			log.panicf("Couldn't unmarshal map file `%s`: %v", path, json_err)
		}

		append(&sources, Map_Source{
			enum_name = strings.to_ada_case(slashpath.name(slashpath.base(path))),
			file_name = fi.name,
			path      = path,
			data      = data,
		})
	}

	if len(sources) == 0 {
		log.panicf("No map files found in `%s` - at least one map is required", MAPS_DIR)
	}

	f, open_err := os.open(
		MAPS_ODIN_OUTPUT_PATH,
		os.O_WRONLY | os.O_CREATE | os.O_TRUNC,
		{.Read_User, .Write_User, .Read_Group, .Read_Other},
	)
	if open_err != nil {
		log.panicf("Couldn't open `%s` for writing: %v", MAPS_ODIN_OUTPUT_PATH, open_err)
	}
	defer os.close(f)

	fmt.fprintln(f, "// This file is generated by running the map_builder.")
	// Map.tilemap.tiles/spawners are [dynamic]T fields, and the baked table
	// below constructs them via inline composite literals ({Tile{...}, ...})
	// rather than append calls - Odin disables that by default (it silently
	// allocates using the current context.allocator), so it must be opted
	// into explicitly for this file.
	fmt.fprintln(f, "#+feature dynamic-literals")
	fmt.fprintln(f, "package shooter")
	fmt.fprintln(f, "")

	fmt.fprintln(f, "Map_Name :: enum {")
	for source in sources {
		fmt.fprintf(f, "\t%s,\n", source.enum_name)
	}
	fmt.fprintln(f, "}")
	fmt.fprintln(f, "")

	fmt.fprintln(f, "maps: [Map_Name]Map = {")
	for source in sources {
		fmt.fprintf(f, "\t.%s = ", source.enum_name)
		write_map_literal(f, source.data)
		fmt.fprintln(f, ",")
	}
	fmt.fprintln(f, "}")
	fmt.fprintln(f, "")

	fmt.fprintln(f, "// data/maps/<Map_Name-derived-slug>.json, for callers that need the live")
	fmt.fprintln(f, "// file path rather than the baked table (the editor's switcher)")
	fmt.fprintln(f, "map_path_for_name :: proc(name: Map_Name) -> string {")
	fmt.fprintln(f, "\tswitch name {")
	for source in sources {
		fmt.fprintf(f, "\tcase .%s: return \"%s\"\n", source.enum_name, source.path)
	}
	fmt.fprintln(f, "\t}")
	fmt.fprintln(f, "\treturn \"\" // unreachable: name is always one of the above")
	fmt.fprintln(f, "}")
}

write_map_literal :: proc(f: ^os.File, m: Map) {
	fmt.fprintf(f, "Map{{name = %q, player_start = {{%v, %v}}, tilemap = ", m.name, m.player_start.x, m.player_start.y)
	write_tilemap_literal(f, m.tilemap)
	fmt.fprint(f, ", spawn_triggers = ")
	write_spawn_triggers_literal(f, m.spawn_triggers)
	fmt.fprintf(f, ", time_limit = %v, victory_multiplier = %v", m.time_limit, m.victory_multiplier)
	fmt.fprintf(f, ", rung = %v", m.rung)
	fmt.fprint(f, ", floor_color = ")
	write_color_literal(f, m.floor_color)
	fmt.fprint(f, ", wall_color = ")
	write_color_literal(f, m.wall_color)
	fmt.fprint(f, ", ambient = ")
	write_ambient_literal(f, m.ambient_save)
	fmt.fprint(f, "}")
}

write_color_literal :: proc(f: ^os.File, c: Color) {
	fmt.fprintf(f, "Color{{%v, %v, %v, %v}}", c[0], c[1], c[2], c[3])
}

// the identity strings become a bit_set literal, so an effect this build
// doesn't have fails the bake the way an unknown Spawn_Condition_Kind does
// rather than emitting source that won't compile with nothing to say why
write_ambient_literal :: proc(f: ^os.File, effects: []string) {
	fmt.fprint(f, "{")
	for effect, i in effects {
		switch effect {
		case "Motes", "Floor_Patches", "Light_Wash":
		case:
			log.panicf("`%s` is not an Ambient_Effect - the map file is stale, or the enum was renamed", effect)
		}
		if i > 0 {
			fmt.fprint(f, ", ")
		}
		fmt.fprintf(f, ".%s", effect)
	}
	fmt.fprint(f, "}")
}

// one Tile literal per line (rather than one giant single-line array, as an
// earlier version of this generator emitted) - a map's tile count runs into
// the thousands, and the Odin compiler's per-line bookkeeping scales badly
// with extreme line length, to the point of exhausting many GB of memory on
// a single multi-hundred-KB line. Matches atlas_builder.odin's own
// one-entry-per-line convention for its (much shorter) atlas_textures table.
write_tilemap_literal :: proc(f: ^os.File, t: Tilemap) {
	fmt.fprintf(f, "Tilemap{{tile_size = {{%v, %v}}, tiles = {{\n", t.tile_size.x, t.tile_size.y)
	for tile in t.tiles {
		fmt.fprintf(
			f,
			"\t\tTile{{world_coords = {{%v, %v}}, collides = %v}},\n",
			tile.world_coords.x, tile.world_coords.y,
			tile.collides,
		)
	}
	fmt.fprint(f, "\t}}")
}

write_spawn_triggers_literal :: proc(f: ^os.File, triggers: [dynamic]Spawn_Trigger) {
	fmt.fprint(f, "{\n")
	for trigger in triggers {
		fmt.fprint(f, "\t\tSpawn_Trigger{condition = ")
		write_spawn_condition_literal(f, trigger.condition_save)
		fmt.fprint(f, ", mode = ")
		write_spawn_mode_literal(f, trigger.mode_save)
		fmt.fprint(f, ", composition = {")
		for entry, i in trigger.composition {
			if i > 0 {
				fmt.fprint(f, ", ")
			}
			fmt.fprintf(f, "Spawn_Composition_Entry{{count = %v, movement_template = ", entry.count)
			write_movement_style_literal(f, entry.movement_template_save)
			fmt.fprint(f, ", attack_template = ")
			write_attack_style_literal(f, entry.attack_template_save)
			fmt.fprint(f, "}")
		}
		fmt.fprint(f, "}},\n")
	}
	fmt.fprint(f, "\t}")
}

write_spawn_condition_literal :: proc(f: ^os.File, s: Spawn_Condition_Save) {
	switch s.kind {
	case "Time_Elapsed":
		v := s.time_elapsed.? or_else Time_Elapsed{}
		fmt.fprintf(f, "Time_Elapsed{{seconds = %v}}", v.seconds)
	case "Kills_Reached":
		v := s.kills_reached.? or_else Kills_Reached{}
		fmt.fprintf(f, "Kills_Reached{{count = %v}}", v.count)
	case:
		log.panicf("`%s` is not a Spawn_Condition_Kind - the map file is stale, or the enum was renamed", s.kind)
	}
}

write_spawn_mode_literal :: proc(f: ^os.File, s: Spawn_Mode_Save) {
	switch s.kind {
	case "One_Shot":
		fmt.fprint(f, "One_Shot{}")
	case "Repeating":
		v := s.repeating.? or_else Repeating{}
		fmt.fprintf(f, "Repeating{{interval = %v, duration = %v}}", v.interval, v.duration)
	case:
		log.panicf("`%s` is not a Spawn_Mode_Kind - the map file is stale, or the enum was renamed", s.kind)
	}
}

write_movement_style_literal :: proc(f: ^os.File, s: Movement_Style_Save) {
	switch s.kind {
	case "Grounded":
		v := s.grounded.? or_else Grounded_Save{}
		fmt.fprintf(f, "Grounded{{speed = %v}}", v.speed)
	case "Floater":
		v := s.floater.? or_else Floater_Save{}
		fmt.fprintf(
			f,
			"Floater{{speed = %v, wobble_amplitude = %v, wobble_frequency = %v, pull_strength = %v}}",
			v.speed, v.wobble_amplitude, v.wobble_frequency, v.pull_strength,
		)
	case "Swarmer":
		v := s.swarmer.? or_else Swarmer_Save{}
		fmt.fprintf(f, "Swarmer{{speed = %v}}", v.speed)
	case "Inert":
		fmt.fprint(f, "nil")
	case:
		log.panicf("`%s` is not a Movement_Style_Kind - the map file is stale, or the enum was renamed", s.kind)
	}
}

write_attack_style_literal :: proc(f: ^os.File, s: Attack_Style_Save) {
	switch s.kind {
	case "Melee":
		v := s.melee.? or_else Melee_Save{}
		fmt.fprintf(
			f,
			"Melee{{attack_damage = %v, attack_range = %v, attack_cooldown = %v}}",
			v.attack_damage, v.attack_range, v.attack_cooldown,
		)
	case "Ranged":
		v := s.ranged.? or_else Ranged_Save{}
		fmt.fprintf(
			f,
			"Ranged{{min_range = %v, max_range = %v, attack_damage = %v, projectile_speed = %v, fire_rate = %v, bullet_lifetime = %v}}",
			v.min_range, v.max_range, v.attack_damage, v.projectile_speed, v.fire_rate, v.bullet_lifetime,
		)
	case "Inert":
		fmt.fprint(f, "nil")
	case:
		log.panicf("`%s` is not an Attack_Style_Kind - the map file is stale, or the enum was renamed", s.kind)
	}
}
