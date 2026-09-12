package shooter

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

// Ambient effects: the purely decorative layers a Map theme runs continuously
// (CONTEXT.md) - drifting motes in the air above the actors, large off-grid
// patches on the floor beneath them, and a wash of coloured light over the
// place. Which of the three a Map runs is authored on the Map (Map.ambient,
// ADR-0024); this file is what runs them.
//
// They carry no information and may never occlude any. That rule is what
// decides each layer's slot in draw_world_contents: patches go at the top of
// the Ground layer (under the actors and under any claimed ground), the wash
// goes between the tilemap and the Ground layer so it lights the place and
// nothing drawn on top of it is tinted, and motes go above the bodies but
// under damage numbers and resource indicators. The wash is a world-space
// quad rather than a screen overlay so a menu's blurred backdrop blurs it
// with everything else instead of leaving an unblurred tint over the blur.
//
// Their budget is their own: two fixed arrays on `game`, never
// game.particles, which is unbounded, event-driven and cleared at a Run
// boundary. Ambience is steady-state and cannot starve hit feedback of
// anything, nor be starved by it.
//
// Draw procs are read-only: draw_world_contents runs twice a frame under the
// blurred backdrop, so every mote moves and every patch is placed in
// update_ambience, never in draw.

AMBIENT_MOTE_MAX :: 96 // the mote budget: every mote there will ever be
AMBIENT_PATCH_MAX :: 40 // the floor-patch budget, seeded once per Map

Mote :: struct {
	position: Vec2,
	drift:    Vec2, // px/s, this mote's own
	radius:   f32,
	phase:    f32, // offsets the shared shimmer so the field does not pulse in unison
}

Floor_Patch :: struct {
	position: Vec2,
	radius:   f32,
	darker:   bool, // a shadowed blotch, or one lifted toward the wall
}

// runtime state derived from the live Map: on `game` rather than on Map, for
// the flow field's reason - a Map is serialised and deep-cloned, and this is
// nothing an author decides
Ambience :: struct {
	motes:        [AMBIENT_MOTE_MAX]Mote,
	motes_seeded: bool,
	patches:      [AMBIENT_PATCH_MAX]Floor_Patch,
	patch_count:  int,
	// what the patches were placed on, so ambience_ensure re-places them
	// only once the tilemap underneath is no longer the one they describe -
	// flow_field_ensure's idiom, and the same two facts it watches
	patches_placed:    bool,
	patches_placed_on: Ambient_Set,
	patch_tile_count:  int,
	patch_tile_size:   Vec2,
	time:              f32, // drives the mote shimmer
}

AMBIENT_MOTE_DRIFT_MAX: f32 = 6 // px/s, each axis
AMBIENT_MOTE_RADIUS_MIN: f32 = 0.6
AMBIENT_MOTE_RADIUS_MAX: f32 = 1.9

// -- motes -------------------------------------------------------------------

seed_mote :: proc(m: ^Mote, bounds: World_Bounds) {
	m.position = {
		rand.float32_range(bounds.min_x, bounds.max_x),
		rand.float32_range(bounds.min_y, bounds.max_y),
	}
	m.drift = {
		rand.float32_range(-AMBIENT_MOTE_DRIFT_MAX, AMBIENT_MOTE_DRIFT_MAX),
		rand.float32_range(-AMBIENT_MOTE_DRIFT_MAX, AMBIENT_MOTE_DRIFT_MAX),
	}
	m.radius = rand.float32_range(AMBIENT_MOTE_RADIUS_MIN, AMBIENT_MOTE_RADIUS_MAX)
	m.phase = rand.float32_range(0, math.TAU)
}

// drifts every mote, and reseeds any that has left `bounds` back inside it -
// the field is a fixed budget, so a mote is never lost off-screen, only moved
update_motes :: proc(motes: []Mote, bounds: World_Bounds, dt: f32) {
	for &m in motes {
		m.position += m.drift * dt
		if !point_in_world_bounds(m.position, bounds) {
			seed_mote(&m, bounds)
		}
	}
}

// -- floor patches -----------------------------------------------------------

AMBIENT_PATCH_RADIUS_MIN: f32 = 18
AMBIENT_PATCH_RADIUS_MAX: f32 = 62
AMBIENT_PATCH_DARKER_SHARE: f32 = 0.6 // the rest lift toward the wall colour
// candidates tried per patch before giving up on it: a map that is mostly
// wall or void simply gets fewer patches rather than looping forever
AMBIENT_PATCH_PLACEMENT_TRIES :: 8
// a fixed seed, so a place's blotches are its blotches: the same on every
// visit, which is what lets them read as part of the layout the player
// learns rather than as something that happened this Run
AMBIENT_PATCH_SEED :: 0x5EED

// places up to len(patches) blotches, each centred on a floor tile, and
// returns how many it placed. Off-grid on purpose - a decal layer with no
// relationship to the tile grid is what keeps this clear of the locked
// no-per-tile-colour-noise rule (ADR-0024) - but centred on floor, because a
// blotch on a wall or in an untiled gap is the world misreporting where the
// floor is.
seed_floor_patches :: proc(patches: []Floor_Patch, tilemap: ^Tilemap) -> (count: int) {
	if len(tilemap.tiles) == 0 {
		return 0
	}

	// a local generator, so the seed reaches nothing else and nothing else's
	// draws disturb the placement
	generator := rand.create(AMBIENT_PATCH_SEED)
	context.random_generator = rand.default_random_generator(&generator)

	// packed from the front - a patch whose every candidate missed the floor
	// leaves no hole, so patches[:count] is exactly what to draw
	bounds := tilemap_world_bounds(tilemap)
	for _ in 0 ..< len(patches) {
		for _ in 0 ..< AMBIENT_PATCH_PLACEMENT_TRIES {
			candidate := Vec2 {
				rand.float32_range(bounds.min_x, bounds.max_x),
				rand.float32_range(bounds.min_y, bounds.max_y),
			}
			if !tile_is_floor_at(tilemap, candidate) {
				continue
			}
			patches[count] = {
				position = candidate,
				radius   = rand.float32_range(AMBIENT_PATCH_RADIUS_MIN, AMBIENT_PATCH_RADIUS_MAX),
				darker   = rand.float32() < AMBIENT_PATCH_DARKER_SHARE,
			}
			count += 1
			break
		}
	}
	return count
}

// true if point lies on a tile that exists and does not collide - the
// complement of tile_blocks_point is not this, since an untiled gap blocks
// nothing but is not floor either
tile_is_floor_at :: proc(tilemap: ^Tilemap, point: Vec2) -> bool {
	for tile in tilemap.tiles {
		if rl.CheckCollisionPointRec(point, tile_world_rect(tile.world_coords, tilemap.tile_size)) {
			return !tile.collides
		}
	}
	return false
}

// -- per frame ---------------------------------------------------------------

// the patch half of the per-frame entry point: places the patches on the
// first frame a Map is live and again whenever the tiles underneath change -
// a Map chosen from Selecting, a tile painted in the editor - and otherwise
// leaves them alone. Returns whether it re-placed them, which is what makes
// "once per Map" assertable. A Map that does not run Floor_Patches gets
// none, so an empty ambient set leaves the whole struct untouched.
ambience_ensure :: proc(a: ^Ambience, map_data: ^Map) -> (replaced: bool) {
	tilemap := &map_data.tilemap
	if a.patches_placed &&
	   a.patches_placed_on == map_data.ambient &&
	   a.patch_tile_count == len(tilemap.tiles) &&
	   a.patch_tile_size == tilemap.tile_size {
		return false
	}

	a.patch_count = 0
	if .Floor_Patches in map_data.ambient {
		a.patch_count = seed_floor_patches(a.patches[:], tilemap)
	}
	a.patches_placed = true
	a.patches_placed_on = map_data.ambient
	a.patch_tile_count = len(tilemap.tiles)
	a.patch_tile_size = tilemap.tile_size
	return true
}

// how far past the visible rect motes live, so one drifts into view rather
// than popping at the edge - and how far past it the wash reaches, since
// camera_visible_world_rect is the unshaken rect and shake moves the lens
AMBIENT_VIEW_MARGIN: f32 = 24

// the per-frame entry point, called outside the Shop / Run End pause:
// ambience is steady-state and keeps drifting behind a blurred backdrop, and
// runs in Editing so the editor's Ambient toggles preview live. Reads the
// same Map draw_tilemap does - the one being edited while Editing, else the
// one being played.
update_ambience :: proc(dt: f32) {
	a := &game.ambience
	map_data := game.program_mode == .Editing ? &game.editing_map : &game.current_map
	ambience_ensure(a, map_data)

	if .Motes not_in map_data.ambient {
		return
	}
	a.time += dt
	bounds := ambient_view_bounds(game.camera)
	if !a.motes_seeded {
		for &m in a.motes {
			seed_mote(&m, bounds)
		}
		a.motes_seeded = true
	}
	update_motes(a.motes[:], bounds, dt)
}

ambient_view_bounds :: proc(camera: Camera) -> World_Bounds {
	bounds := camera_visible_world_rect(camera)
	bounds.min_x -= AMBIENT_VIEW_MARGIN
	bounds.max_x += AMBIENT_VIEW_MARGIN
	bounds.min_y -= AMBIENT_VIEW_MARGIN
	bounds.max_y += AMBIENT_VIEW_MARGIN
	return bounds
}

// -- draw (read-only) --------------------------------------------------------

AMBIENT_PATCH_ALPHA: f32 = 0.45
AMBIENT_PATCH_DARKER_SCALE: f32 = 0.7 // a shadowed blotch: the floor, dimmed
AMBIENT_PATCH_LIFT_MIX: f32 = 0.3 // a lifted blotch: the floor, mixed toward the wall
AMBIENT_WASH_TOP_ALPHA: f32 = 0.10 // the accent, at the top of the view
AMBIENT_WASH_BOTTOM_ALPHA: f32 = 0.16 // the floor darkened, at the bottom
AMBIENT_WASH_BOTTOM_SCALE: f32 = 0.5
AMBIENT_MOTE_ALPHA_BASE: f32 = 0.35
AMBIENT_MOTE_ALPHA_SHIMMER: f32 = 0.25
AMBIENT_MOTE_SHIMMER_RATE: f32 = 1.6 // rad/s

// the top of the Ground layer: under the actors and under any claimed ground
draw_ambient_floor_patches :: proc(map_data: ^Map, patches: []Floor_Patch) {
	if .Floor_Patches not_in map_data.ambient {
		return
	}
	shadow := color_scale(map_data.floor_color, AMBIENT_PATCH_DARKER_SCALE)
	lift := color_mix(map_data.floor_color, map_data.wall_color, AMBIENT_PATCH_LIFT_MIX)
	for patch in patches {
		rl.DrawCircleV(patch.position, patch.radius, rl.Fade(patch.darker ? shadow : lift, AMBIENT_PATCH_ALPHA))
	}
}

// between the tilemap and the Ground layer: lights the place, tints nothing
// drawn on top of it. A world-space quad over the view (plus the shake
// margin) rather than a screen overlay, so it blurs with the world under a
// menu's backdrop instead of sitting unblurred over the blur.
draw_ambient_light_wash :: proc(map_data: ^Map, camera: Camera) {
	if .Light_Wash not_in map_data.ambient {
		return
	}
	bounds := camera_visible_world_rect(camera)
	margin := AMBIENT_VIEW_MARGIN + SCREEN_SHAKE_MAX_OFFSET
	quad := Rect {
		bounds.min_x - margin,
		bounds.min_y - margin,
		bounds.max_x - bounds.min_x + margin * 2,
		bounds.max_y - bounds.min_y + margin * 2,
	}
	top := rl.Fade(map_accent_color(map_data^), AMBIENT_WASH_TOP_ALPHA)
	bottom := rl.Fade(color_scale(map_data.floor_color, AMBIENT_WASH_BOTTOM_SCALE), AMBIENT_WASH_BOTTOM_ALPHA)
	rl.DrawRectangleGradientEx(quad, top, bottom, top, bottom)
}

// above the bodies, below damage numbers and resource indicators: dust hangs
// in the air, and information stays on top of it
draw_ambient_motes :: proc(map_data: ^Map, motes: []Mote, time: f32) {
	if .Motes not_in map_data.ambient {
		return
	}
	accent := map_accent_color(map_data^)
	for m in motes {
		shimmer := AMBIENT_MOTE_ALPHA_BASE + AMBIENT_MOTE_ALPHA_SHIMMER * math.sin(time * AMBIENT_MOTE_SHIMMER_RATE + m.phase)
		rl.DrawCircleV(m.position, m.radius, rl.Fade(accent, shimmer))
	}
}
