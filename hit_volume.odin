package shooter

import "core:math"
import "core:math/linalg"

// -- Hit volumes: a weapon hits only what it touches -------------------------
//
// A melee weapon's hit volume is the weapon itself (CONTEXT.md's Hit volume
// entry, ADR-0026). The shapes are authored in the *same unit space as the
// glyph* and ride the *same pivot frame*, so the thing that damages and the
// thing the player is watching are one object and can never be somewhere else.
//
// This replaces enemy_in_melee_arc: a cone measured from the player's feet,
// resolved in a single instant at Resolve. Under that test a Sword killed
// everything within 110 degrees of its feet on the exact frame its blade was
// drawn back at -55 degrees, pointing away from most of what it had just
// killed - the sweep the player watched was entirely after the fact, and
// measured from a point 12px below where the blade was drawn.
//
// The cone itself was never wrong in general, only wrong for *blades*, which
// are thin things pretending to be wedges. It survives as the flamethrower's
// own (enemy_in_magic_cone, weapon.odin), because an emitted flame really is
// a spreading wedge.

// one convex polygon of a weapon's hit volume, in the glyph's unit space -
// the same (u, v) coordinates icon.odin's glyph primitives are authored in,
// mapped to the world through icon_at.
Hit_Poly :: []Vec2

// the set of shapes a weapon's action damages with, per Weapon_Kind. A *set*
// rather than one shape: a weapon may carry several (a head and a haft), or
// one, and nothing here assumes a count. The guard, hilt and pommel carry
// none - they are the part in the player's hand, and a volume there means
// hitting things behind you at the start of a sweep.
//
// Empty for everything whose hit-check is not its own silhouette: a Gun's
// reach is its bullet, and Magic's is its cone or its cast.
//
// A parallel per-kind table beside weapon_icons/weapon_icon_reach rather than
// something the glyph procs emit, kept honest by hit_volume_test.odin's
// silhouette assertions instead. Having the procs emit their own colliders is
// the pure answer and would cost rewriting every glyph into data to buy a
// guarantee an assertion already gives (ADR-0026).
//
// Each blade below is the exact triangle icon_blade draws (icon.odin):
// {guard_x, 0.5 - blade_h/2}, {tip_x, 0.5}, {guard_x, 0.5 + blade_h/2}.
weapon_hit_volumes: [Weapon_Kind][]Hit_Poly = {
	.Dagger       = {{{0.44, 0.39}, {0.80, 0.50}, {0.44, 0.61}}},
	.Sword        = {{{0.28, 0.38}, {0.92, 0.50}, {0.28, 0.62}}},
	// the head only, and one polygon. A spear kills with its point: the haft
	// is what you hold, and a volume along it would let a thrust cut down
	// whatever it passed. This is also what makes it a different weapon from
	// the Greatsword rather than a longer one - a ~14x16px head at 85px reach
	// takes about one body per thrust. ADR-0026's "a head and a haft" is
	// permission to author several shapes, not a requirement to.
	.Spear        = {{{0.80, 0.41}, {0.96, 0.50}, {0.80, 0.59}}},
	// exactly the triangle icon_blade draws at tip 0.94, guard 0.22, blade_h
	// 0.34 - the widest blade in the catalog, which is the whole of what its
	// tier buys over the Spear's single-body head
	.Greatsword   = {{{0.22, 0.33}, {0.94, 0.50}, {0.22, 0.67}}},

	// a Gun's reach is its bullet and Magic's is its cone or its cast, so
	// neither family's silhouette is a hit-check. Spelled out rather than
	// left to the enumerated array's default so adding a Weapon_Kind is a
	// compile error here, the way it already is for weapon_icons.
	.Pistol       = {},
	.SMG          = {},
	.Shotgun      = {},
	.Rifle        = {},
	.Fire_Wand    = {},
	.Flame_Staff  = {},
	.Poison_Staff = {},
	.Lightning_Staff = {},
}

// scratch space a pose is mapped into before it's tested, sized for the
// largest polygon any kind can author. Volumes are read-only tables, so the
// only per-frame allocation the hit-check would otherwise need is this.
MAX_HIT_POLY_POINTS :: 8

// -- swing motion ------------------------------------------------------------
//
// One curve, shared by the drawn blade and the volume that rides it. It was
// two: Sword's eased two-phase sweep lived in draw_weapon and was reconstructed
// from cooldown arithmetic, while Dagger's Follow-through was a separate linear
// sweep. Both now read follow_through_timer, and both read this.

// where the swing reaches its extreme, as a fraction of the Follow-through
// window - the rest is the return to neutral. Expressed as a fraction rather
// than the absolute seconds it used to be (SWORD_SWING_OUT_TIME/
// SWORD_SWING_RETURN_TIME, 0.07/0.11 of a 0.18s window) so a weapon's swing
// and its active window are the same length by construction, whatever
// follow_through_time a kind is authored with.
SWING_OUT_FRACTION: f32 = 0.39

// degrees the swing adds to the aim angle at `progress` (0..1) through the
// Follow-through window. Starts drawn back at -arc/2, snaps out to +arc/2,
// eases home - a spring was prototyped for this and rejected as feeling wrong.
melee_swing_angle_offset :: proc(arc_degrees, progress: f32) -> f32 {
	draw_back := -(arc_degrees / 2)
	extreme := arc_degrees / 2

	p := clamp(progress, 0, 1)
	if p < SWING_OUT_FRACTION {
		t := ease_out_cubic(p / SWING_OUT_FRACTION)
		return draw_back + (extreme - draw_back) * t
	}

	t := ease_out_cubic((p - SWING_OUT_FRACTION) / (1 - SWING_OUT_FRACTION))
	return extreme - extreme * t
}

// the frame a weapon's glyph is drawn on and its hit volume rides. The one
// place weapon_world_frame_size meets icon_frame_pivot, so the silhouette and
// the volume can only ever be posed together.
weapon_pose_frame :: proc(weapon: Weapon, pivot: Vec2, angle_deg, scale: f32) -> Icon_Frame {
	return icon_frame_pivot(pivot, angle_deg, weapon_world_frame_size(weapon) * scale)
}

// the aim direction as a frame angle, in degrees
aim_angle_degrees :: proc(aim_dir: Vec2) -> f32 {
	return math.to_degrees(math.atan2(aim_dir.y, aim_dir.x))
}

// -- geometry ----------------------------------------------------------------
//
// A body is a circle: the centre of its actor_collision_rect and half its
// side. Deliberately the *centre*, not the feet anchor the retired cone
// measured from - a weapon hangs off weapon_pivot_position, which is the same
// ACTOR_SIZE.y/2 above the player's anchor that a body's centre is above its
// own, so testing chest to chest is what keeps reach unchanged by the move.

enemy_body_circle :: proc(enemy: Enemy) -> (center: Vec2, radius: f32) {
	box := actor_collision_rect(enemy.rect)
	return {box.x + box.width / 2, box.y + box.height / 2}, min(box.width, box.height) / 2
}

// closest-point-on-segment against the circle, the standard form - also what
// the polygon test falls back on for every edge
segment_circle_overlap :: proc(a, b, center: Vec2, radius: f32) -> bool {
	ab := b - a
	len_sq := linalg.dot(ab, ab)
	t: f32 = 0
	if len_sq > 0 {
		t = clamp(linalg.dot(center - a, ab) / len_sq, 0, 1)
	}
	closest := a + ab * t
	offset := center - closest
	return linalg.dot(offset, offset) <= radius * radius
}

// even-odd crossing count. Works for any simple polygon, which matters: the
// swept quads below are built from two poses and can be non-convex when a
// frame's rotation is large.
point_in_polygon :: proc(poly: []Vec2, p: Vec2) -> bool {
	inside := false
	j := len(poly) - 1
	for i in 0 ..< len(poly) {
		a := poly[i]
		b := poly[j]
		if (a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
			inside = !inside
		}
		j = i
	}
	return inside
}

// the circle overlaps the polygon if its centre is inside, or if any edge
// comes within radius of it. Covers both a body swallowed by a wide blade and
// a body clipped by its edge.
polygon_circle_overlap :: proc(poly: []Vec2, center: Vec2, radius: f32) -> bool {
	if len(poly) < 3 {
		return false
	}
	if point_in_polygon(poly, center) {
		return true
	}
	j := len(poly) - 1
	for i in 0 ..< len(poly) {
		if segment_circle_overlap(poly[j], poly[i], center, radius) {
			return true
		}
		j = i
	}
	return false
}

// the polygon anywhere between two consecutive poses, not only at each pose.
// This is what stops a swing tunnelling: a Sword crosses its arc in a handful
// of frames, front-loaded by ease_out_cubic, moving its tip far enough on the
// opening frame for a small body to sit between two samples and be touched by
// nothing at all.
//
// The swept region is `cur`, plus one quad per edge spanning that edge's
// previous and current positions. That union *is* the region: a point inside
// it that touches neither end pose was entered and left as the pose advanced,
// so it lies on some edge's swept surface. `prev` itself needs no test - the
// previous frame already tested it as its own `cur`.
//
// Per-edge quads rather than one convex hull of both poses. A hull
// over-covers near the pivot, damaging ground the blade never crossed, which
// is the bug this whole mechanism exists to fix, told in a smaller voice.
// Sub-stepping the swing fixes the same bug by doing the same work several
// times; this costs one quad per edge per frame.
//
// Known bound: interpolating vertices linearly chords the rotation arc, so the
// sweep under-covers the outside of a fast turn by about r*(1-cos(angle/2)) -
// single-digit pixels at the worst frame of the widest swing, against the
// 50-90px gap it closes.
polygon_swept_circle_overlap :: proc(prev, cur: []Vec2, center: Vec2, radius: f32) -> bool {
	if len(prev) != len(cur) || len(cur) < 3 {
		return false
	}
	if polygon_circle_overlap(cur, center, radius) {
		return true
	}

	quad: [4]Vec2
	j := len(cur) - 1
	for i in 0 ..< len(cur) {
		quad = {prev[j], prev[i], cur[i], cur[j]}
		if polygon_circle_overlap(quad[:], center, radius) {
			return true
		}
		j = i
	}
	return false
}

// -- the swing ---------------------------------------------------------------

// A swing's identity, so one swing damages a given body at most once however
// long its shapes overlap and however many of them touched it. Per-collider
// damage would make "author a second collider" silently mean "double this
// weapon's damage against small bodies".
//
// Monotonic and global rather than per-Weapon: a counter living on the Weapon
// would restart at 1 when the player buys a tier and weapon_create overwrites
// the struct, and an Enemy that outlived the switch would carry a stale id
// that suddenly matched again. Deliberately its own id space rather than one
// shared with bullets - a piercing shot and a swing have no reason to be
// coupled, and coupling them gives two lifetimes one counter.
@(private = "file")
next_swing_id: u32 = 1

next_swing_identity :: proc() -> u32 {
	id := next_swing_id
	next_swing_id += 1
	return id
}

// maps one authored polygon onto the world through a posed frame
hit_poly_to_world :: proc(frame: Icon_Frame, poly: Hit_Poly, out: []Vec2) -> []Vec2 {
	n := min(len(poly), len(out))
	for i in 0 ..< n {
		out[i] = icon_at(frame, poly[i].x, poly[i].y)
	}
	return out[:n]
}

// tests the equipped weapon's hit volume between its previous and current pose
// and damages whatever it touched, once per swing per body. Called every frame
// of the Follow-through window from update_weapon - a swing is a temporal
// event with an active window now, not an instant, so a body entering the arc
// after Resolve is still hit and a body leaving before the blade arrives is
// not.
//
// `elapsed_prev`/`elapsed_now` are seconds into that window. Both poses use
// this frame's origin: the player moves a couple of px against a blade tip
// moving tens, so a stored previous origin would buy nothing and be one more
// piece of state to keep honest.
swing_hit_check :: proc(weapon: ^Weapon, origin, aim_dir: Vec2, elapsed_prev, elapsed_now: f32, enemies: []Enemy) {
	volume := weapon_hit_volumes[weapon.kind]
	if len(volume) == 0 || weapon.follow_through_time <= 0 {
		return
	}

	arc := weapon_visuals[weapon.kind].swing_arc_degrees
	pivot := weapon_pivot_position(origin)
	base := aim_angle_degrees(aim_dir)

	angle_at :: proc(base, arc, elapsed, window: f32) -> f32 {
		return base + melee_swing_angle_offset(arc, clamp(elapsed / window, 0, 1))
	}

	frame_prev := weapon_pose_frame(
		weapon^,
		pivot,
		angle_at(base, arc, elapsed_prev, weapon.follow_through_time),
		1,
	)
	frame_now := weapon_pose_frame(weapon^, pivot, angle_at(base, arc, elapsed_now, weapon.follow_through_time), 1)

	prev_points: [MAX_HIT_POLY_POINTS]Vec2
	now_points: [MAX_HIT_POLY_POINTS]Vec2

	// walked backwards because apply_hit_to_enemy removes by index
	// (unordered_remove), same as every other hit source: the element swapped
	// into the freed slot is one this pass has already visited
	for i := len(enemies) - 1; i >= 0; i -= 1 {
		if enemies[i].last_hit_swing_id == weapon.swing_id {
			continue
		}

		center, radius := enemy_body_circle(enemies[i])

		for poly in volume {
			prev := hit_poly_to_world(frame_prev, poly, prev_points[:])
			now := hit_poly_to_world(frame_now, poly, now_points[:])
			if !polygon_swept_circle_overlap(prev, now, center, radius) {
				continue
			}

			enemies[i].last_hit_swing_id = weapon.swing_id
			apply_hit_to_enemy(i, weapon.damage, Vec2{enemies[i].x, enemies[i].y})
			break
		}
	}
}
