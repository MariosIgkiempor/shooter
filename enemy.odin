package shooter

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

MAX_ENEMIES: int = 24
ENEMY_SIZE: i32 = 12
ENEMY_MAX_HEALTH: f32 = 50

// which per-kind Gold payout (enemy_gold_presets, account_progression.odin) an
// Enemy grants on death - a single placeholder member today, but the lookup
// is kept extensible for enemy variety that doesn't exist yet (see the
// Gold payout ticket)
Enemy_Kind :: enum {
	Basic,
}

Enemy :: struct {
	using rect: Rect, // bottom-center "feet" anchor, same convention as Player
	squash:     Vec2, // continuous isotropic squash while moving, eased back to {1,1} at rest (draw_actor)
	movement:   Movement_Style,
	attack:     Attack_Style,
	health:     f32,
	kind:       Enemy_Kind,
}

// an enemy's per-frame steering archetype - orthogonal to Attack_Style; nil
// means the enemy doesn't move. See CONTEXT.md's Movement Style entry.
Movement_Style :: union {
	Grounded,
	Floater,
	Swarmer,
}

// an enemy's combat archetype - orthogonal to Movement_Style; nil means the
// enemy doesn't attack. See CONTEXT.md's Attack Style entry.
Attack_Style :: union {
	Melee,
	Ranged,
}

// grounded chase by the shared flow field, colliding with terrain like the
// player does - so it routes around geometry rather than through it
Grounded :: struct {
	speed: f32,
}

// ghostly drift: ignores tilemap collision, wobbles rather than beelining.
// See the Floater movement design ticket for the wobble/pull formula.
Floater :: struct {
	speed:            f32,
	wobble_amplitude: f32, // px, validated ceiling 80
	wobble_frequency: f32, // Hz, validated 3
	pull_strength:    f32, // 0..1, validated 0.35
	wobble_phase:     f32, // runtime: randomized at spawn so multiple Floaters don't wobble in lockstep, not editor-set
}

// flanks the player by seeking a dynamically-assigned slot on a ring around
// it, instead of converging with other Swarmers on one point. See the
// Swarmer surround mechanic ticket.
Swarmer :: struct {
	speed: f32,
}

Melee :: struct {
	attack_damage:   f32,
	attack_range:    f32, // contact distance to land a hit
	attack_cooldown: f32, // seconds between hits
	attack_timer:    f32, // runtime countdown, not editor-set
}

Ranged :: struct {
	min_range:        f32, // retreats if the player is closer than this
	max_range:        f32, // advances if the player is farther than this
	attack_damage:    f32,
	projectile_speed: f32,
	fire_rate:        f32, // shots/sec while in the min..max band
	bullet_lifetime:  f32,
	fire_timer:       f32, // runtime countdown, not editor-set
}

// one entry in a Map's spawn timeline, replacing the old fixed-position
// Spawner - no position is ever authored, enemies always spawn off-screen
// relative to the camera (pick_offscreen_spawn_point). See CONTEXT.md's
// Spawn Trigger entry and the enemy-spawn-revamp map's ticket 03.
//
// condition/mode are tagged json:"-" for the same reason Weapon.variant and
// Spawn_Composition_Entry's templates are: core:encoding/json's union-decode
// guessing doesn't work reliably here either - confirmed directly (a
// Kills_Reached/Repeating trigger round-tripped through json.marshal/
// json.unmarshal on the bare unions came back as Time_Elapsed(0)/One_Shot,
// silently wrong). condition_save/mode_save are the plain persisted mirror,
// same *_Save + explicit `kind` discriminant pattern as
// Movement_Style_Save/Attack_Style_Save below.
Spawn_Trigger :: struct {
	condition:      Spawn_Condition `json:"-"`,
	condition_save: Spawn_Condition_Save,
	mode:           Spawn_Mode `json:"-"`,
	mode_save:      Spawn_Mode_Save,
	composition:    []Spawn_Composition_Entry,

	// runtime-only - tagged json:"-" unlike Spawner.timer's own precedent,
	// since `fired` is a permanent latch rather than a harmless countdown:
	// pressing F1 mid-Playing clones the live map verbatim (clone_map) into
	// game.editing_map, and saving from there would otherwise bake whatever
	// fired/timer/elapsed happened to be at that moment into the map file,
	// permanently disabling a One_Shot trigger (or desyncing a Repeating
	// one's clock) for every future load of it.
	fired:   bool `json:"-"`, // One_Shot: already spawned. Repeating: already activated.
	timer:   f32 `json:"-"`, // Repeating: counts down to the next interval spawn.
	elapsed: f32 `json:"-"`, // Repeating: seconds since activation, checked against duration.
}

Spawn_Condition :: union {
	Time_Elapsed,
	Kills_Reached,
}
// checked against Player.survival_seconds (the same Run-scoped field the
// live HUD counter and Run End screen both read - see CONTEXT.md's Run
// entry)
Time_Elapsed :: struct {
	seconds: f32,
}
// checked against total_kills(Player.kills) - the Run's cumulative kill
// total, not a separate per-map count
Kills_Reached :: struct {
	count: int,
}

Spawn_Condition_Kind :: enum {
	Time_Elapsed,
	Kills_Reached,
}

// plain (non-union) persisted shape of Spawn_Trigger.condition - see the
// json:"-" comment on Spawn_Trigger.condition above
Spawn_Condition_Save :: struct {
	kind:          Spawn_Condition_Kind,
	time_elapsed:  Maybe(Time_Elapsed) `json:"time_elapsed,omitempty"`,
	kills_reached: Maybe(Kills_Reached) `json:"kills_reached,omitempty"`,
}

spawn_condition_to_save :: proc(condition: Spawn_Condition) -> Spawn_Condition_Save {
	switch v in condition {
	case Time_Elapsed:
		return {kind = .Time_Elapsed, time_elapsed = v}
	case Kills_Reached:
		return {kind = .Kills_Reached, kills_reached = v}
	}
	return {} // unreachable: every Spawn_Trigger always has a condition
}

// explicit switch on the decoded `kind` - never lets json.unmarshal's
// union-variant-guessing loop run, same rationale as movement_style_from_save
spawn_condition_from_save :: proc(s: Spawn_Condition_Save) -> Spawn_Condition {
	switch s.kind {
	case .Time_Elapsed:
		return s.time_elapsed.? or_else Time_Elapsed{}
	case .Kills_Reached:
		return s.kills_reached.? or_else Kills_Reached{}
	}
	return Time_Elapsed{} // unreachable: s.kind is always one of the above
}

Spawn_Mode :: union {
	One_Shot,
	Repeating,
}
One_Shot :: struct {}
Repeating :: struct {
	interval: f32,
	duration: f32, // <= 0 means indefinite: runs until the Run ends
}

Spawn_Mode_Kind :: enum {
	One_Shot,
	Repeating,
}

// plain (non-union) persisted shape of Spawn_Trigger.mode - see the
// json:"-" comment on Spawn_Trigger.mode above
Spawn_Mode_Save :: struct {
	kind:      Spawn_Mode_Kind,
	one_shot:  Maybe(One_Shot) `json:"one_shot,omitempty"`,
	repeating: Maybe(Repeating) `json:"repeating,omitempty"`,
}

spawn_mode_to_save :: proc(mode: Spawn_Mode) -> Spawn_Mode_Save {
	switch v in mode {
	case One_Shot:
		return {kind = .One_Shot, one_shot = v}
	case Repeating:
		return {kind = .Repeating, repeating = v}
	}
	return {} // unreachable: every Spawn_Trigger always has a mode
}

// explicit switch on the decoded `kind` - never lets json.unmarshal's
// union-variant-guessing loop run, same rationale as movement_style_from_save
spawn_mode_from_save :: proc(s: Spawn_Mode_Save) -> Spawn_Mode {
	switch s.kind {
	case .One_Shot:
		return s.one_shot.? or_else One_Shot{}
	case .Repeating:
		return s.repeating.? or_else Repeating{}
	}
	return One_Shot{} // unreachable: s.kind is always one of the above
}

// one (Movement Style, Attack Style, count) entry in a Spawn_Trigger's
// composition - generalizes Spawner's single fixed template into a mix,
// reusing Movement_Style/Attack_Style's existing *_Save mirror pattern
// verbatim (see Movement_Style_Save/Attack_Style_Save below)
Spawn_Composition_Entry :: struct {
	movement_template:      Movement_Style `json:"-"`,
	movement_template_save: Movement_Style_Save,
	attack_template:        Attack_Style `json:"-"`,
	attack_template_save:   Attack_Style_Save,
	count:                  int,
}

// discriminant for Movement_Style_Save; also doubles as the grouping key for
// Separation and per-style debug/tuning tables below, since every Movement
// Style variant needs one anyway
Movement_Style_Kind :: enum {
	Grounded,
	Floater,
	Swarmer,
	Inert,
}

movement_style_kind :: proc(movement: Movement_Style) -> Movement_Style_Kind {
	switch _ in movement {
	case Grounded:
		return .Grounded
	case Floater:
		return .Floater
	case Swarmer:
		return .Swarmer
	}
	return .Inert
}

// plain (non-union) persisted shape of Spawn_Composition_Entry.movement_template
// - see the json:"-" comment on Spawn_Composition_Entry.movement_template above
Movement_Style_Save :: struct {
	kind:     Movement_Style_Kind,
	grounded: Maybe(Grounded) `json:"grounded,omitempty"`,
	floater:  Maybe(Floater) `json:"floater,omitempty"`,
	swarmer:  Maybe(Swarmer) `json:"swarmer,omitempty"`,
}

movement_style_to_save :: proc(movement: Movement_Style) -> Movement_Style_Save {
	switch v in movement {
	case Grounded:
		return {kind = .Grounded, grounded = v}
	case Floater:
		return {kind = .Floater, floater = v}
	case Swarmer:
		return {kind = .Swarmer, swarmer = v}
	}
	return {kind = .Inert}
}

// explicit switch on the decoded `kind` - never lets json.unmarshal's
// union-variant-guessing loop run, since Movement_Style is never the direct
// target of json.unmarshal; only Movement_Style_Save is.
movement_style_from_save :: proc(s: Movement_Style_Save) -> Movement_Style {
	switch s.kind {
	case .Grounded:
		return s.grounded.? or_else Grounded{}
	case .Floater:
		return s.floater.? or_else Floater{}
	case .Swarmer:
		return s.swarmer.? or_else Swarmer{}
	case .Inert:
		return nil
	}
	return nil // unreachable: s.kind is always one of the above
}

// discriminant for Attack_Style_Save; internal to persistence, unrelated to
// any gameplay enum
Attack_Style_Kind :: enum {
	Melee,
	Ranged,
	Inert,
}

// plain (non-union) persisted shape of Spawn_Composition_Entry.attack_template
// - see the json:"-" comment on Spawn_Composition_Entry.attack_template above
Attack_Style_Save :: struct {
	kind:   Attack_Style_Kind,
	melee:  Maybe(Melee) `json:"melee,omitempty"`,
	ranged: Maybe(Ranged) `json:"ranged,omitempty"`,
}

attack_style_to_save :: proc(attack: Attack_Style) -> Attack_Style_Save {
	switch v in attack {
	case Melee:
		return {kind = .Melee, melee = v}
	case Ranged:
		return {kind = .Ranged, ranged = v}
	}
	return {kind = .Inert}
}

// explicit switch on the decoded `kind` - never lets json.unmarshal's
// union-variant-guessing loop run, since Attack_Style is never the direct
// target of json.unmarshal; only Attack_Style_Save is.
attack_style_from_save :: proc(s: Attack_Style_Save) -> Attack_Style {
	switch s.kind {
	case .Melee:
		return s.melee.? or_else Melee{}
	case .Ranged:
		return s.ranged.? or_else Ranged{}
	case .Inert:
		return nil
	}
	return nil // unreachable: s.kind is always one of the above
}

// -- Separation ---------------------------------------------------------
// steering force that pushes same-Movement-Style enemies apart so they don't
// clump on one point/path. Validated in the separation-force prototype:
// radius/strength tuned per Movement Style (Grounded's chase is much
// stronger than Floater/Swarmer's gentle wander/orbit), blended with each
// style's own chase/seek direction before scaling by speed*dt.
SEPARATION_RADIUS := [Movement_Style_Kind]f32 {
	.Grounded = 40,
	.Floater  = 15,
	.Swarmer  = 15,
	.Inert    = 0,
}

SEPARATION_STRENGTH := [Movement_Style_Kind]f32 {
	.Grounded = 3.0,
	.Floater  = 0.5,
	.Swarmer  = 0.5,
	.Inert    = 0,
}

// cell size for the neighbour-lookup spatial grid; sized to the largest
// Separation radius (Grounded's) so a 3x3 cell neighbourhood always covers
// every style's search radius
SEPARATION_GRID_CELL_SIZE: f32 = 40

Separation_Grid :: map[Vec2i][dynamic]int

separation_grid_cell :: proc(pos: Vec2) -> Vec2i {
	return {
		i32(math.floor(pos.x / SEPARATION_GRID_CELL_SIZE)),
		i32(math.floor(pos.y / SEPARATION_GRID_CELL_SIZE)),
	}
}

// buckets every enemy's index by grid cell; allocated on the temp allocator,
// valid for this frame only (freed by main's per-frame free_all)
build_separation_grid :: proc(enemies: []Enemy) -> Separation_Grid {
	grid := make(Separation_Grid, context.temp_allocator)
	for enemy, i in enemies {
		cell := separation_grid_cell(Vec2{enemy.x, enemy.y})
		bucket := grid[cell]
		append(&bucket, i)
		grid[cell] = bucket
	}
	return grid
}

// sum of away-from-neighbour directions (same Movement Style only, within
// that style's Separation radius), weighted by closeness then normalized -
// mirrors the prototype's Steering.separationVector exactly
compute_separation_direction :: proc(enemies: []Enemy, index: int, grid: Separation_Grid) -> Vec2 {
	enemy := enemies[index]
	kind := movement_style_kind(enemy.movement)
	radius := SEPARATION_RADIUS[kind]
	if radius <= 0 {
		return {}
	}

	pos := Vec2{enemy.x, enemy.y}
	cell := separation_grid_cell(pos)

	push: Vec2
	for dx in i32(-1) ..= 1 {
		for dy in i32(-1) ..= 1 {
			bucket, ok := grid[cell + {dx, dy}]
			if !ok {
				continue
			}

			for other_index in bucket {
				if other_index == index {
					continue
				}

				other := enemies[other_index]
				if movement_style_kind(other.movement) != kind {
					continue
				}

				offset := pos - Vec2{other.x, other.y}
				dist := linalg.length(offset)
				if dist <= 0 || dist >= radius {
					continue
				}

				push += linalg.normalize0(offset) * ((radius - dist) / radius)
			}
		}
	}

	return linalg.normalize0(push)
}

// -- Swarmer surround -----------------------------------------------------

SWARMER_FALLBACK_SURROUND_RADIUS: f32 = 60 // used when the Swarmer's Attack Style is nil (no attack_range to read)
SWARMER_RING_ROTATION_SPEED: f32 = 0.3 // radians/sec, matches the swarmer-surround prototype's slow ring drift

// the distance a Swarmer orbits the player at - its own Attack Style's
// engagement range, so orbiting and attacking naturally coincide (validated
// for Melee's attack_range in the swarmer-surround-mechanic ticket; Ranged's
// max_range is the natural equivalent - the outer edge of its firing band -
// extrapolated the same way since the ticket only exercised Melee)
swarmer_surround_radius :: proc(attack: Attack_Style) -> f32 {
	switch a in attack {
	case Melee:
		return a.attack_range
	case Ranged:
		return a.max_range
	}
	return SWARMER_FALLBACK_SURROUND_RADIUS
}

// dynamic nearest-free-slot assignment: builds a ring of slots around the
// player (one per live Swarmer, slowly rotating), then greedily assigns each
// Swarmer to whichever unclaimed slot is nearest to it - mirrors the
// swarmer-surround prototype's Steering.ringSlots/assignNearestSlots.
// Returns enemy index -> world-space slot target, temp-allocated. Mixed
// Attack Styles among live Swarmers would want mixed ring radii too; this
// uses the first Swarmer's radius for the whole ring, which is exact for the
// common case (one spawner template) and a reasonable approximation
// otherwise.
assign_swarmer_slots :: proc(enemies: []Enemy, player_pos: Vec2, t: f32) -> map[int]Vec2 {
	swarmer_indices := make([dynamic]int, 0, len(enemies), context.temp_allocator)
	for enemy, i in enemies {
		if _, ok := enemy.movement.(Swarmer); ok {
			append(&swarmer_indices, i)
		}
	}

	count := len(swarmer_indices)
	if count == 0 {
		return nil
	}

	radius := swarmer_surround_radius(enemies[swarmer_indices[0]].attack)
	rotation := t * SWARMER_RING_ROTATION_SPEED

	slots := make([dynamic]Vec2, count, context.temp_allocator)
	for i in 0 ..< count {
		angle := (f32(i) / f32(count)) * math.TAU + rotation
		slots[i] = player_pos + Vec2{math.cos(angle), math.sin(angle)} * radius
	}

	claimed := make([dynamic]bool, count, context.temp_allocator)
	targets := make(map[int]Vec2, count, context.temp_allocator)
	for swarmer_index in swarmer_indices {
		pos := Vec2{enemies[swarmer_index].x, enemies[swarmer_index].y}

		best := -1
		best_dist := max(f32)
		for s in 0 ..< count {
			if claimed[s] {
				continue
			}
			d := linalg.distance(slots[s], pos)
			if d < best_dist {
				best_dist = d
				best = s
			}
		}

		claimed[best] = true
		targets[swarmer_index] = slots[best]
	}

	return targets
}

// -- Floater drift ---------------------------------------------------------

FLOATER_WOBBLE_SIDE_DAMPING: f32 = 0.4 // matches the floater-movement prototype's (1 - pullStrength*0.4) side-weight falloff
FLOATER_WOBBLE_BOOST_SCALE: f32 = 0.6 // matches the prototype's wobbleBoost formula
FLOATER_WOBBLE_AMPLITUDE_CEILING: f32 = 80 // px, the validated ceiling wobble_amplitude tunes against

// layered-sine pseudo-noise: cheap, deterministic per phase, no lookup
// table - good enough to feel "erratic" without a real noise library.
// Mirrors the floater-movement prototype's Steering.wobbleSignal exactly.
// the two sine weights and the harmonic's frequency/phase multipliers, named
// so they can be Tunables - the numbers themselves are unchanged from the
// floater-movement prototype
FLOATER_WOBBLE_PRIMARY_WEIGHT: f32 = 0.7
FLOATER_WOBBLE_HARMONIC_WEIGHT: f32 = 0.3
FLOATER_WOBBLE_HARMONIC_FREQ: f32 = 2.3
FLOATER_WOBBLE_HARMONIC_PHASE: f32 = 1.7

floater_wobble_signal :: proc(t, phase, freq: f32) -> f32 {
	return(
		math.sin(t * freq + phase) * FLOATER_WOBBLE_PRIMARY_WEIGHT +
		math.sin(t * freq * FLOATER_WOBBLE_HARMONIC_FREQ + phase * FLOATER_WOBBLE_HARMONIC_PHASE) *
			FLOATER_WOBBLE_HARMONIC_WEIGHT \
	)
}

// blends a homing pull toward the target with a perpendicular wobble that's
// strongest when pull is weak. Mirrors the prototype's
// Steering.floaterDirection exactly.
floater_direction :: proc(pos, target: Vec2, t, phase, freq, pull_strength: f32) -> Vec2 {
	to_target := linalg.normalize0(target - pos)
	side := Vec2{-to_target.y, to_target.x}
	wobble := floater_wobble_signal(t, phase, freq)

	return linalg.normalize0(
		to_target * pull_strength + side * wobble * (1 - pull_strength * FLOATER_WOBBLE_SIDE_DAMPING),
	)
}

// enemies are transient (`json:"-"`), so they are empty after every load;
// this must run after load_game so they start clean under whatever Spawn
// Triggers were loaded. Spawn Triggers themselves are level data and persist
// through save/load, so they're left untouched here.
reset_enemies :: proc() {
	clear(&game.enemies)
}

// edge-triggered condition check, then Mode-driven firing - a trigger's
// condition is checked once per frame only until `fired` flips true, and
// never re-checked after (see CONTEXT.md's Spawn Trigger entry and the
// enemy-spawn-revamp map's ticket 03). Multiple triggers (including several
// concurrently-running Repeating ones) may be active at once - no mutual
// exclusion, pressure just layers.
update_spawn_triggers :: proc(dt: f32) {
	for &trigger in game.current_map.spawn_triggers {
		if !trigger.fired {
			condition_met: bool
			switch c in trigger.condition {
			case Time_Elapsed:
				condition_met = game.player.survival_seconds >= c.seconds
			case Kills_Reached:
				condition_met = total_kills(game.player.kills) >= c.count
			}
			if !condition_met {
				continue
			}

			trigger.fired = true
			fire_spawn_composition(trigger.composition)

			// seed timer to a full interval and skip straight to next frame
			// rather than falling through into the tick below: timer's
			// zero-value would otherwise satisfy the <= 0 check on this same
			// frame regardless of the seed (dt could be large enough on its
			// own - e.g. a lag spike right as the trigger activates - to
			// drive a freshly-seeded timer to <= 0 too), double-firing the
			// activation composition immediately. Ticking starts clean next
			// frame instead, so the next fire is a genuine interval away.
			if repeating, is_repeating := trigger.mode.(Repeating); is_repeating {
				trigger.timer = repeating.interval
			}
			continue
		}

		repeating, is_repeating := trigger.mode.(Repeating)
		if !is_repeating {
			continue
		}

		trigger.elapsed += dt
		if repeating.duration > 0 && trigger.elapsed > repeating.duration {
			continue
		}

		trigger.timer -= dt
		if trigger.timer <= 0 {
			trigger.timer = repeating.interval
			fire_spawn_composition(trigger.composition)
		}
	}
}

// spawns every entry's full count, off-screen relative to the current
// camera - a spawn that can't fit under MAX_ENEMIES is silently skipped
// per-enemy (not all-or-nothing), so a batch that partially fits still
// spawns what it can (ticket 03: "One_Shot's batch may come up short")
fire_spawn_composition :: proc(composition: []Spawn_Composition_Entry) {
	visible_rect := camera_visible_world_rect(game.camera)
	player_pos := Vec2{game.player.x, game.player.y}
	// the tilemap doesn't change mid-batch, so this is computed once per
	// fire rather than once per enemy inside pick_offscreen_spawn_point -
	// a full-tile scan repeated per spawned enemy would otherwise redo the
	// same work up to len(composition entries' counts) times per fire
	map_bounds := tilemap_world_bounds(&game.current_map.tilemap)

	for entry in composition {
		for _ in 0 ..< entry.count {
			if len(game.enemies) >= MAX_ENEMIES {
				return
			}
			point := pick_offscreen_spawn_point(player_pos, visible_rect, map_bounds, &game.current_map.tilemap)
			spawn_enemy_at(point, entry.movement_template, entry.attack_template)
		}
	}
}

spawn_enemy_at :: proc(position: Vec2, movement_template: Movement_Style, attack_template: Attack_Style) {
	movement := movement_template
	switch &m in movement {
	case Floater:
		m.wobble_phase = rand.float32_range(0, math.TAU)
	case Grounded, Swarmer:
	}

	enemy := Enemy {
		rect     = {position.x, position.y, 0, 0},
		squash   = {1, 1},
		movement = movement,
		attack   = attack_template,
		health   = ENEMY_MAX_HEALTH,
		kind     = .Basic,
	}

	append(&game.enemies, enemy)
}

// -- off-screen spawn placement (enemy-spawn-revamp map, ticket 02) --------

OFFSCREEN_SPAWN_MARGIN: f32 = 30 // px beyond the visible rect's own half-diagonal
OFFSCREEN_SPAWN_MAX_RETRIES: int = 6

// the tilemap's own world-space extent, spanning every authored tile - used
// to clamp a chosen spawn point back onto the playable map. Computed by
// scanning tiles rather than a stored width/height, since Tilemap only ever
// grows sparse tile-by-tile (tilemap_place_tile) - the same "just scan every
// tile" approach move_actor already uses rather than maintaining a cached
// bound. (The flow field is the one thing that does index cells, and it
// derives its own extent in cell space - see tilemap_cell_bounds.)
tilemap_world_bounds :: proc(tilemap: ^Tilemap) -> World_Bounds {
	if len(tilemap.tiles) == 0 {
		return {}
	}

	bounds := World_Bounds{max(f32), min(f32), max(f32), min(f32)}
	for tile in tilemap.tiles {
		rect := tile_world_rect(tile.world_coords, tilemap.tile_size)
		bounds.min_x = min(bounds.min_x, rect.x)
		bounds.max_x = max(bounds.max_x, rect.x + rect.width)
		bounds.min_y = min(bounds.min_y, rect.y)
		bounds.max_y = max(bounds.max_y, rect.y + rect.height)
	}
	return bounds
}

// true if point falls inside a solid tile - mirrors move_actor's own
// per-tile CheckCollisionRecs loop, just against a point instead of a moving
// actor's box, since a spawn candidate has no size of its own to sweep
tile_blocks_point :: proc(tilemap: ^Tilemap, point: Vec2) -> bool {
	for tile in tilemap.tiles {
		if !tile.collides {
			continue
		}
		if rl.CheckCollisionPointRec(point, tile_world_rect(tile.world_coords, tilemap.tile_size)) {
			return true
		}
	}
	return false
}

// angle-around-player at (visible-rect half-diagonal + margin), retried up
// to a small cap against still-visible/wall-blocked candidates, then
// clamped into the map's bounds (map_bounds is a param, not recomputed here,
// since a caller spawning several enemies in one batch already has it and
// the tilemap doesn't change mid-batch). Validated live in the prototype (branch
// prototype/offscreen-spawn-placement, commit 2bebf71) across camera-
// panning, wall-collision-retry, and map-edge-clamp scenarios - see the
// enemy-spawn-revamp map's ticket 02. On exhausted retries, spawns anyway at
// the last (clamped) candidate rather than dropping the spawn: an enemy
// occasionally appearing early or in a rare double-wall pocket is a smaller
// problem than a trigger silently under-spawning.
pick_offscreen_spawn_point :: proc(
	player_pos: Vec2,
	visible_rect: World_Bounds,
	map_bounds: World_Bounds,
	tilemap: ^Tilemap,
) -> Vec2 {
	half_w := (visible_rect.max_x - visible_rect.min_x) / 2
	half_h := (visible_rect.max_y - visible_rect.min_y) / 2
	dist := math.hypot(half_w, half_h) + OFFSCREEN_SPAWN_MARGIN

	point: Vec2
	for _ in 0 ..< OFFSCREEN_SPAWN_MAX_RETRIES {
		angle := rand.float32_range(0, math.TAU)
		point = player_pos + Vec2{math.cos(angle), math.sin(angle)} * dist
		point.x = clamp(point.x, map_bounds.min_x, map_bounds.max_x)
		point.y = clamp(point.y, map_bounds.min_y, map_bounds.max_y)

		if !point_in_world_bounds(point, visible_rect) && !tile_blocks_point(tilemap, point) {
			break
		}
	}
	return point
}

// the flow field is not ensured here: update_game_state re-floods it once a
// frame, before the Spawn Triggers run, so everything downstream reads one
// field describing this frame's player cell.
update_enemies :: proc(dt: f32) {
	player_pos := Vec2{game.player.x, game.player.y}
	t := f32(rl.GetTime())

	separation_grid := build_separation_grid(game.enemies[:])
	swarmer_slots := assign_swarmer_slots(game.enemies[:], player_pos, t)

	for &enemy, i in game.enemies {
		delta: Vec2
		pos := Vec2{enemy.x, enemy.y}
		kind := movement_style_kind(enemy.movement)
		separation_dir := compute_separation_direction(game.enemies[:], i, separation_grid)

		switch &m in enemy.movement {
		case Grounded:
			intent := movement_intent(pos, player_pos, enemy.attack)
			goal := movement_goal_point(pos, player_pos, intent)
			chase_dir := field_chase_direction(&game.flow_field, pos, intent, goal)
			final_dir := linalg.normalize0(chase_dir + separation_dir * SEPARATION_STRENGTH[kind])
			delta = final_dir * m.speed * dt
		case Floater:
			goal := movement_goal_point(pos, player_pos, movement_intent(pos, player_pos, enemy.attack))
			dir := floater_direction(pos, goal, t, m.wobble_phase, m.wobble_frequency, m.pull_strength)
			final_dir := linalg.normalize0(dir + separation_dir * SEPARATION_STRENGTH[kind])
			wobble_boost :=
				1 + (m.wobble_amplitude / FLOATER_WOBBLE_AMPLITUDE_CEILING) * FLOATER_WOBBLE_BOOST_SCALE
			delta = final_dir * m.speed * wobble_boost * dt
		case Swarmer:
			target := swarmer_slots[i] or_else player_pos
			seek_dir := linalg.normalize0(target - pos)
			final_dir := linalg.normalize0(seek_dir + separation_dir * SEPARATION_STRENGTH[kind])
			delta = final_dir * m.speed * dt
		case:
		// nil: doesn't move
		}

		switch &a in enemy.attack {
		case Melee:
			dist_to_player := linalg.distance(pos, player_pos)
			a.attack_timer -= dt

			if dist_to_player <= a.attack_range {
				delta = {}
				if a.attack_timer <= 0 {
					damage_player(a.attack_damage)
					a.attack_timer = a.attack_cooldown
				}
			}
		case Ranged:
			dist_to_player := linalg.distance(pos, player_pos)
			a.fire_timer -= dt

			if dist_to_player <= a.max_range && dist_to_player >= a.min_range && a.fire_timer <= 0 {
				direction := linalg.normalize0(player_pos - pos)
				fire_enemy_bullet(pos, direction, a)
				a.fire_timer = 1.0 / a.fire_rate
			}
		case:
		// nil: no attack
		}

		update_actor_squash(&enemy.squash, delta.x != 0 || delta.y != 0, dt)

		// Floater ignores tilemap collision entirely (see the Floater
		// movement design ticket), so it skips move_actor's collision
		// resolution and applies its delta directly - the same split that
		// decided whether it read the flow field above
		if movement_style_collides_with_terrain[kind] {
			move_actor(&enemy.rect, &game.current_map.tilemap, delta)
		} else {
			enemy.x += delta.x
			enemy.y += delta.y
		}
	}
}

RANGED_RETREAT_LOOKAHEAD: f32 = 100 // arbitrary distance behind the enemy to aim a euclidean Withdraw at; only direction matters since the goal recomputes every frame. A field-steered enemy ignores it entirely - its Withdraw is a one-cell step (flow_field_retreat_target)

// what an enemy's Attack Style is asking its Movement Style to do this frame.
// Realised two different ways: as a euclidean goal point by Floater, which
// never reads the field, and as a step to a neighbouring cell by every
// field-steered style. Derived per frame and stored nowhere, so a Movement
// Style is free to ignore it (a Charger mid-dash will).
Movement_Intent :: enum {
	Approach,
	Hold,
	Withdraw,
}

// re-plugs today's "advance if too far, retreat if too close, hold if in
// band" logic onto whichever Movement Style is driving - a genuine read of
// Attack Style by Movement Style, same as Swarmer reading attack_range.
// Melee (or no attack) simply closes.
movement_intent :: proc(enemy_pos, player_pos: Vec2, attack: Attack_Style) -> Movement_Intent {
	ranged, is_ranged := attack.(Ranged)
	if !is_ranged {
		return .Approach
	}

	dist := linalg.distance(enemy_pos, player_pos)
	switch {
	case dist > ranged.max_range:
		return .Approach
	case dist < ranged.min_range:
		return .Withdraw
	case:
		return .Hold
	}
}

// the euclidean realisation of an intent: the point a style that steers
// straight at things should aim for. Floater's whole path, and the fallback
// every field-steered style takes when the field has nothing to say.
movement_goal_point :: proc(enemy_pos, player_pos: Vec2, intent: Movement_Intent) -> Vec2 {
	switch intent {
	case .Approach:
		return player_pos
	case .Withdraw:
		return enemy_pos + linalg.normalize0(enemy_pos - player_pos) * RANGED_RETREAT_LOOKAHEAD
	case .Hold:
		return enemy_pos
	}
	return player_pos
}

// unit steering direction for a terrain-colliding enemy: the flow field's own
// step where its cell has one, and otherwise straight at the euclidean goal
// the same intent implies - which covers exactly the cases an empty path used
// to cover (the player's own cell, a cell the flood never reached and whose
// neighbours it never reached either, or no field at all).
field_chase_direction :: proc(
	field: ^Flow_Field,
	pos: Vec2,
	intent: Movement_Intent,
	fallback_goal: Vec2,
) -> Vec2 {
	switch intent {
	case .Hold:
		return {}
	case .Approach:
		if target, ok := flow_field_step_target(field, pos); ok {
			return linalg.normalize0(target - pos)
		}
	case .Withdraw:
		if target, ok := flow_field_retreat_target(field, pos); ok {
			return linalg.normalize0(target - pos)
		}
	}
	return linalg.normalize0(fallback_goal - pos)
}

// takes tile_size explicitly rather than always reading game.current_map -
// shared by Playing's own pathfinding/collision code (current_map) and
// editor.odin's world-cursor math (editing_map), which can be a different
// map with the switcher (see the map-baking ticket's isolation invariant)
world_to_cell_coord :: proc(world_pos: Vec2, tile_size: Vec2) -> Vec2i {
	return {
		i32(math.floor(world_pos.x / tile_size.x)),
		i32(math.floor(world_pos.y / tile_size.y)),
	}
}

cell_center_to_world :: proc(cell: Vec2i, tile_size: Vec2) -> Vec2 {
	return {
		(f32(cell.x) + 0.5) * tile_size.x,
		(f32(cell.y) + 0.5) * tile_size.y,
	}
}

// -- the flow field's collision seam --------------------------------------
// which Movement Styles resolve against terrain, named once rather than
// type-asserted on Floater at the point of use. This is the seam the flow
// field splits on too (ADR-0025): a style that collides is one that can read
// the field, because routing around geometry is only meaningful to a body
// geometry stops. Grounded reads it today; Swarmer collides but still seeks
// its ring slots directly until ticket 05 puts it on the contour.
movement_style_collides_with_terrain := [Movement_Style_Kind]bool {
	.Grounded = true,
	.Floater  = false, // flying through walls is its identity - see CONTEXT.md
	.Swarmer  = true,
	.Inert    = true,
}
