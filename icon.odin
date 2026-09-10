package shooter

import "core:math"
import rl "vendor:raylib"

// -- Icons: shape-drawn glyphs ----------------------------------------------
//
// Every icon in the game is drawn from code, never from the atlas. This is
// the art-revamp direction (all world art is shapes) carried into the UI -
// and, for weapons, back out into the world again: a Shop row's Shotgun and
// the Shotgun in your hands are the *same* geometry, drawn through two
// different frames. See ADR-0018.
//
// Authoring convention: every glyph is laid out in a **unit square** -
// coordinates and sizes in 0..1, origin top-left, pointing right - and
// mapped onto the screen by an Icon_Frame. Nothing in a glyph body knows
// how big it will be, or whether it is upright in a menu or rotated to
// follow the player's aim.
//
// Two rules make that survive small sizes:
//   - stroke widths go through icon_stroke, which floors at one pixel in
//     *target* space. A glyph that reads as a solid blob at 9px still reads;
//     a glyph whose strokes scaled linearly to 0.4px would vanish.
//   - distinctions between sibling glyphs are *countable* (one barrel vs
//     two, one orb vs three), never proportional. You can't compare a 20px
//     rod to a 24px rod with no reference alongside it, but you can count.
//
// Color: a glyph draws in its own world colors by default, so a Shop icon
// and the thing it depicts match. Pass a `tint` to override every part of
// the glyph with one flat color - that's how a maxed/unaffordable/locked
// row grays out, and how the melee swing's motion-trail echoes fade. Tint
// *replaces* rather than multiplies deliberately: gray multiplied over the
// magic rod's purple is still recognisably purple, and a disabled row that
// still reads as live is the bug this prevents. `alpha` is separate from
// tint and always applies on top - it carries Reveal/Dismiss motion, which
// is animation, not state.

// smallest stroke a glyph is allowed to draw, in destination pixels
ICON_STROKE_MIN :: 1.0

// the signature every glyph shares, so they can live in [Enum]Icon_Proc
// dispatch tables (CONTEXT.md's standing enum-table idiom) and be called
// without a switch at any site that already has the enum value in hand
Icon_Proc :: proc(frame: Icon_Frame, tint: Maybe(Color), alpha: f32)

// -- Icon_Frame: where a unit square lands ----------------------------------
//
// An affine map from the glyph's unit square onto the screen. Two
// constructors exist and there will never be more: icon_frame_rect for a
// menu/HUD slot (upright, axis-aligned) and icon_frame_pivot for the world
// (anchored at the weapon's grip, rotated to the player's aim). This is the
// "one definition, two adapters" ADR-0018 settles on - authoring a weapon's
// icon and its world silhouette separately would let them drift apart on
// the first tweak, which is the problem per-kind identity exists to solve.
Icon_Frame :: struct {
	origin: Vec2, // where unit (0, 0) lands
	x_axis: Vec2, // screen delta for u += 1
	y_axis: Vec2, // screen delta for v += 1
	size:   f32, // the frame's nominal side in pixels - what stroke widths scale against
	// mirrors the glyph across its own long axis. The world frame sets this
	// when aiming leftward so an asymmetric silhouette (a pistol's grip hangs
	// *below* its barrel) flips rather than rotating past vertical and
	// hanging its grip in the air. Absorbed into the unit coordinate rather
	// than into y_axis, so y_axis stays a true 90-degree rotation of x_axis
	// and the frame is never sheared.
	flip_v: bool,
}

// the largest centered square inside `bounds`. Glyphs are authored square,
// so a non-square slot letterboxes rather than stretching - a stretched
// circle stops reading as Gold's circle, which is the whole point of it.
icon_square :: proc(bounds: Rect) -> Rect {
	size := min(bounds.width, bounds.height)
	return {bounds.x + (bounds.width - size) / 2, bounds.y + (bounds.height - size) / 2, size, size}
}

// an upright, axis-aligned frame filling `bounds`'s centered square - every
// menu row, button and Resource indicator slot
icon_frame_rect :: proc(bounds: Rect) -> Icon_Frame {
	sq := icon_square(bounds)
	return {origin = {sq.x, sq.y}, x_axis = {sq.width, 0}, y_axis = {0, sq.height}, size = sq.width}
}

// a frame anchored at a weapon's grip and rotated to its aim: unit (0, 0.5)
// lands exactly on `pivot`, and the glyph extends `size` px along
// `angle_deg`. Mirrored across the aim axis when pointing leftward.
icon_frame_pivot :: proc(pivot: Vec2, angle_deg, size: f32) -> Icon_Frame {
	rad := math.to_radians(angle_deg)
	c := math.cos(rad)
	s := math.sin(rad)
	x_axis := Vec2{c, s} * size
	y_axis := Vec2{-s, c} * size

	// normalized to (-180, 180] first, so the leftward test is a single
	// comparison rather than depending on how atan2's range reached here
	normalized := angle_deg
	for normalized > 180 do normalized -= 360
	for normalized <= -180 do normalized += 360

	return {
		origin = pivot - y_axis * 0.5,
		x_axis = x_axis,
		y_axis = y_axis,
		size = size,
		flip_v = abs(normalized) > 90,
	}
}

// maps a unit-space point through the frame
icon_at :: proc(f: Icon_Frame, u, v: f32) -> Vec2 {
	vv := f.flip_v ? 1 - v : v
	return f.origin + f.x_axis * u + f.y_axis * vv
}

// a unit-space length converted to destination pixels, floored at
// ICON_STROKE_MIN so thin geometry survives the 9px Resource indicator slot
icon_stroke :: proc(f: Icon_Frame, unit_length: f32) -> f32 {
	return max(unit_length * f.size, ICON_STROKE_MIN)
}

// resolves a glyph part's final color: its own color, or the flat `tint`
// replacing it, with `alpha` folded in either way
icon_color :: proc(own: Color, tint: Maybe(Color), alpha: f32) -> Color {
	c := own
	if t, tinted := tint.?; tinted {
		c = t
	}
	return menu_with_alpha(c, alpha)
}

// -- primitives --------------------------------------------------------------
//
// All of these take unit-space coordinates and map through the frame, so
// they work identically upright in a menu and rotated in the world.

// raylib culls back-facing triangles, and a rotated or mirrored frame can
// reverse a triangle's winding - so the winding is chosen from the *mapped*
// points rather than assumed from the authored order.
//
// The sign was established empirically, not from raylib's "vertices in
// counter-clockwise order" docs, which are ambiguous about y-down screen
// space: rl.DrawTriangle renders the **negative** cross product and culls
// the positive one. The retired draw_wedge got this backwards, which is why
// the melee blade it drew never actually appeared.
// true when (a, b, c) is already in the order rl.DrawTriangle will render
// rather than cull. Extracted from the drawing so the empirically-found sign
// is pinned by a test - it is the kind of thing a later tidy-up would
// "correct" back to matching raylib's docs and silently blank every glyph.
icon_triangle_front_facing :: proc(a, b, c: Vec2) -> bool {
	return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) <= 0
}

@(private = "file")
icon_tri_pts :: proc(a, b, c: Vec2, color: Color) {
	if icon_triangle_front_facing(a, b, c) {
		rl.DrawTriangle(a, b, c, color)
	} else {
		rl.DrawTriangle(a, c, b, color)
	}
}

// a unit-space quad, given its four corners in order
@(private = "file")
icon_quad :: proc(f: Icon_Frame, ax, ay, bx, by, cx, cy, dx, dy: f32, color: Color) {
	a := icon_at(f, ax, ay)
	b := icon_at(f, bx, by)
	c := icon_at(f, cx, cy)
	d := icon_at(f, dx, dy)
	icon_tri_pts(a, b, c, color)
	icon_tri_pts(a, c, d, color)
}

// a bar along the glyph's long axis, `thickness` across, centered on `cy`.
// Thickness resolves to pixels through icon_stroke and converts back into
// unit space, so the ICON_STROKE_MIN floor applies to what's actually drawn.
icon_bar_h :: proc(f: Icon_Frame, x, cy, length, thickness: f32, color: Color) {
	if f.size <= 0 {
		return // a zero-sized slot draws nothing rather than dividing by it
	}
	t := icon_stroke(f, thickness) / f.size
	icon_quad(f, x, cy - t / 2, x + length, cy - t / 2, x + length, cy + t / 2, x, cy + t / 2, color)
}

// a bar across the glyph's long axis, `thickness` wide, centered on `cx`
icon_bar_v :: proc(f: Icon_Frame, cx, y, length, thickness: f32, color: Color) {
	if f.size <= 0 {
		return
	}
	t := icon_stroke(f, thickness) / f.size
	icon_quad(f, cx - t / 2, y, cx + t / 2, y, cx + t / 2, y + length, cx - t / 2, y + length, color)
}

icon_disc :: proc(f: Icon_Frame, cx, cy, radius: f32, color: Color) {
	rl.DrawCircleV(icon_at(f, cx, cy), icon_stroke(f, radius), color)
}

icon_tri :: proc(f: Icon_Frame, ax, ay, bx, by, cx, cy: f32, color: Color) {
	icon_tri_pts(icon_at(f, ax, ay), icon_at(f, bx, by), icon_at(f, cx, cy), color)
}

icon_line :: proc(f: Icon_Frame, ax, ay, bx, by, thickness: f32, color: Color) {
	rl.DrawLineEx(icon_at(f, ax, ay), icon_at(f, bx, by), icon_stroke(f, thickness), color)
}

// a chevron (">") - the shared "movement/progress" mark, used by Move_Speed
// and Account Level
icon_chevron :: proc(f: Icon_Frame, x, cy, w, h, thickness: f32, color: Color) {
	icon_line(f, x, cy - h / 2, x + w, cy, thickness, color)
	icon_line(f, x + w, cy, x, cy + h / 2, thickness, color)
}

// the frame's own rotation in degrees - circle sectors are the one primitive
// raylib takes angles for rather than points, so they need it explicitly
@(private = "file")
icon_frame_angle :: proc(f: Icon_Frame) -> f32 {
	return math.to_degrees(math.atan2(f.x_axis.y, f.x_axis.x))
}

icon_sector :: proc(f: Icon_Frame, cx, cy, radius, start_deg, end_deg: f32, color: Color) {
	base := icon_frame_angle(f)
	rl.DrawCircleSector(icon_at(f, cx, cy), icon_stroke(f, radius), base + start_deg, base + end_deg, 16, color)
}

// -- weapon glyphs -----------------------------------------------------------
//
// All eight point along +u and share one vocabulary: a rod down the middle,
// a grip hanging below its back, and per-kind countable additions. These are
// the glyphs draw_weapon renders in the world (through icon_frame_pivot) as
// well as the ones the Shop and Run Start screens render in a box.

// where each kind's business end sits along +u, so the world frame can be
// sized to put a melee weapon's tip at its actual `range` rather than short
// of it - see weapon_world_frame_size (weapon.odin)
weapon_icon_reach: [Weapon_Kind]f32 = {
	.Pistol       = 0.76,
	.SMG          = 0.80,
	.Shotgun      = 0.88,
	.Dagger       = 0.80,
	.Sword        = 0.92,
	.Fire_Wand    = 0.87,
	.Flame_Staff  = 0.86,
	.Poison_Staff = 0.82,
}

@(private = "file")
icon_gun_base :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32, rod_x, rod_len, rod_thick: f32) {
	c := icon_color(WEAPON_GUN_COLOR, tint, alpha)
	icon_bar_h(f, rod_x, 0.42, rod_len, rod_thick, c) // barrel
	icon_bar_v(f, rod_x + 0.08, 0.42, 0.28, 0.15, c) // grip
}

icon_pistol :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	icon_gun_base(f, tint, alpha, 0.24, 0.52, 0.14)
}

// two verticals under the barrel (grip + magazine) - the countable
// difference from Pistol's single grip
icon_smg :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	c := icon_color(WEAPON_GUN_COLOR, tint, alpha)
	icon_gun_base(f, tint, alpha, 0.18, 0.62, 0.14)
	icon_bar_v(f, 0.42, 0.42, 0.34, 0.13, c) // magazine
}

// two stacked barrels - countable against SMG's two verticals, and the
// widest silhouette of the three
icon_shotgun :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	c := icon_color(WEAPON_GUN_COLOR, tint, alpha)
	icon_bar_h(f, 0.14, 0.34, 0.74, 0.12, c)
	icon_bar_h(f, 0.14, 0.50, 0.74, 0.12, c)
	icon_bar_v(f, 0.22, 0.42, 0.30, 0.15, c) // grip
}

// Melee is the one family whose frame is sized by gameplay (`range`, 40-60px)
// rather than by the visual table, so it is much larger than a gun's 30-38px
// frame - and every cross-axis proportion scales with it. Authored at the
// same 0.30-0.70 spread the other glyphs use, a Sword's blade would draw
// ~26px across against the old wedge's 8px: a chunky triangle, not a blade.
// The blade is kept narrow here so it reads as a blade at world scale while
// staying legible in a 15-20px menu box. This is the proportion most likely
// to want tuning once seen in motion.
@(private = "file")
icon_blade :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32, tip_x, guard_x, guard_h, blade_h: f32, pommel: bool) {
	c := icon_color(WEAPON_MELEE_COLOR, tint, alpha)
	icon_tri(f, guard_x, 0.5 - blade_h / 2, tip_x, 0.5, guard_x, 0.5 + blade_h / 2, c) // blade
	icon_bar_v(f, guard_x, 0.5 - guard_h / 2, guard_h, 0.09, c) // crossguard
	icon_bar_h(f, guard_x - 0.16, 0.5, 0.16, 0.10, c) // hilt
	if pommel {
		icon_disc(f, guard_x - 0.18, 0.5, 0.07, c)
	}
}

// short blade, narrow guard, no pommel
icon_dagger :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	icon_blade(f, tint, alpha, 0.80, 0.44, 0.20, 0.22, false)
}

// long blade, wide guard, plus a pommel - three countable differences from
// Dagger, none of them "it's bigger"
icon_sword :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	icon_blade(f, tint, alpha, 0.92, 0.28, 0.32, 0.24, true)
}

@(private = "file")
icon_staff :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32, rod_x, rod_len: f32) -> (tip_x: f32) {
	icon_bar_h(f, rod_x, 0.5, rod_len, 0.12, icon_color(WEAPON_MAGIC_ROD_COLOR, tint, alpha))
	return rod_x + rod_len
}

// one orb
icon_fire_wand :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	tip := icon_staff(f, tint, alpha, 0.10, 0.62)
	icon_disc(f, tip, 0.5, 0.15, icon_color(WEAPON_MAGIC_ORB_COLOR, tint, alpha))
}

// orb plus two smaller flame ticks - a countable two, not a bigger one
icon_flame_staff :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	orb := icon_color(WEAPON_MAGIC_ORB_COLOR, tint, alpha)
	tip := icon_staff(f, tint, alpha, 0.06, 0.60)
	icon_disc(f, tip, 0.5, 0.14, orb)
	icon_disc(f, tip + 0.20, 0.32, 0.07, orb)
	icon_disc(f, tip + 0.20, 0.68, 0.07, orb)
}

// orb plus a three-dot cloud, echoing the poison cloud it leaves behind
icon_poison_staff :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	orb := icon_color(ICON_POISON_COLOR, tint, alpha)
	tip := icon_staff(f, tint, alpha, 0.06, 0.54)
	icon_disc(f, tip, 0.5, 0.13, orb)
	icon_disc(f, tip + 0.16, 0.26, 0.09, orb)
	icon_disc(f, tip + 0.22, 0.62, 0.10, orb)
}

weapon_icons: [Weapon_Kind]Icon_Proc = {
	.Pistol       = icon_pistol,
	.SMG          = icon_smg,
	.Shotgun      = icon_shotgun,
	.Dagger       = icon_dagger,
	.Sword        = icon_sword,
	.Fire_Wand    = icon_fire_wand,
	.Flame_Staff  = icon_flame_staff,
	.Poison_Staff = icon_poison_staff,
}

// -- resource / pickup glyphs ------------------------------------------------
//
// These deliberately reuse the world's own pickup shapes (pickup.odin's
// circle / cross / stacked bars) so the icon beside a bar and the thing you
// pick up off the floor are the same mark.

// the shared accent for glyphs with no world color of their own to borrow -
// the abstract stat marks, Account Level, the clock, the map swatch
ICON_NEUTRAL_COLOR :: Color{170, 185, 215, 255}
ICON_KILLS_COLOR :: Color{205, 120, 120, 255}
// the poison cloud's own green, opaque - poison_cloud.odin draws the cloud
// itself at alpha 90, far too faint to read as a glyph
ICON_POISON_COLOR :: Color{50, 180, 60, 255}

icon_gold :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	icon_disc(f, 0.5, 0.5, 0.36, icon_color(rl.GOLD, tint, alpha))
}

icon_health :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	c := icon_color(PICKUP_HEALTH_COLOR, tint, alpha)
	icon_bar_h(f, 0.16, 0.5, 0.68, 0.24, c)
	icon_bar_v(f, 0.5, 0.16, 0.68, 0.24, c)
}

// three stacked cartridges. Every other pickup glyph borrows its world
// object's color; this one has no world object left to borrow from once the
// Ammo pickup retired with the Gun reserve, so it falls back to the Ammo
// indicator's own bar color - a fallback its only caller never reaches, since
// the indicator always passes a tint.
icon_ammo :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	c := icon_color(RESOURCE_AMMO_COLOR, tint, alpha)
	for i in 0 ..< 3 {
		icon_bar_v(f, 0.22 + f32(i) * 0.28, 0.18, 0.64, 0.16, c)
	}
}

// a clock face: an outline with a swept wedge. Shared by the two things in
// the game that mean "time": the Melee/Magic Cooldown indicator (which had
// no dedicated art at all before this, just a placeholder circle) and the
// HUD's Run timer. The Cooldown use tints it with its bar's live color, so
// the neutral own-color below is what the HUD readout shows.
icon_clock :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	c := icon_color(ICON_NEUTRAL_COLOR, tint, alpha)
	rl.DrawCircleLinesV(icon_at(f, 0.5, 0.5), icon_stroke(f, 0.38), c)
	icon_sector(f, 0.5, 0.5, 0.38, -90, 40, c)
}

// two crossed strokes - deliberately not any enemy's own shape (rect /
// circle / triangle are all claimed), so it reads as the event, not the actor
icon_kills :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	c := icon_color(ICON_KILLS_COLOR, tint, alpha)
	icon_line(f, 0.2, 0.2, 0.8, 0.8, 0.16, c)
	icon_line(f, 0.8, 0.2, 0.2, 0.8, 0.16, c)
}

// stacked upward chevrons - the Account Level mark, sharing Move_Speed's
// chevron primitive turned to point up, since both mean "more"
icon_level :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	c := icon_color(ICON_NEUTRAL_COLOR, tint, alpha)
	for i in 0 ..< 2 {
		y := 0.56 + f32(i) * 0.24
		icon_line(f, 0.18, y, 0.5, y - 0.28, 0.14, c)
		icon_line(f, 0.5, y - 0.28, 0.82, y, 0.14, c)
	}
}

// a flat filled square. The Map Selection screen's swatch: unlike every
// other glyph its color *is* its content, so callers pass the color through
// the tint channel (draw_menu_button's icon_tint) rather than it having a
// world color of its own. The color a caller passes is the Map's own wall
// colour - see map_swatch_color in map.odin.
icon_swatch :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	icon_bar_h(f, 0.12, 0.5, 0.76, 0.76, icon_color(ICON_NEUTRAL_COLOR, tint, alpha))
}

// -- upgrade glyphs ----------------------------------------------------------
//
// The only glyphs with no world shape to borrow, so they're invented - but
// invented from the shared primitives above rather than as seven unrelated
// drawings, and each distinguished by something countable.

// two chevrons - "faster"
icon_upgrade_move_speed :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	c := icon_color(ICON_NEUTRAL_COLOR, tint, alpha)
	icon_chevron(f, 0.18, 0.5, 0.30, 0.56, 0.14, c)
	icon_chevron(f, 0.48, 0.5, 0.30, 0.56, 0.14, c)
}

// the health cross - the same mark the Health pickup and Vigor use
icon_upgrade_max_health :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	icon_health(f, tint, alpha)
}

// an upward spike - "bigger hit"
icon_upgrade_damage :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	icon_tri(f, 0.5, 0.12, 0.86, 0.84, 0.14, 0.84, icon_color(ICON_NEUTRAL_COLOR, tint, alpha))
}

// three rapid ticks of rising height - countable, and distinct from the Ammo
// indicator's three equal bars by the ramp
icon_upgrade_action_rate :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	c := icon_color(ICON_NEUTRAL_COLOR, tint, alpha)
	for i in 0 ..< 3 {
		h := 0.28 + f32(i) * 0.24
		icon_bar_v(f, 0.24 + f32(i) * 0.26, 0.84 - h, h, 0.15, c)
	}
}

// a magazine: the Ammo indicator's stacked bars inside an outline box
icon_upgrade_clip_size :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	c := icon_color(ICON_NEUTRAL_COLOR, tint, alpha)
	t: f32 = 0.09
	icon_bar_h(f, 0.20, 0.14, 0.60, t, c)
	icon_bar_h(f, 0.20, 0.86, 0.60, t, c)
	icon_bar_v(f, 0.20, 0.14, 0.72, t, c)
	icon_bar_v(f, 0.80, 0.14, 0.72, t, c)
	for i in 0 ..< 3 {
		icon_bar_v(f, 0.32 + f32(i) * 0.18, 0.30, 0.40, 0.10, c)
	}
}

// a blade with the shared "further" chevron off its tip - Reach lengthens the
// weapon itself (and its Hit volume with it, ADR-0026), so the glyph is a
// blade going further rather than icon_upgrade_range's bare measuring rule
icon_upgrade_reach :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	c := icon_color(ICON_NEUTRAL_COLOR, tint, alpha)
	icon_bar_h(f, 0.06, 0.5, 0.13, 0.10, c) // hilt
	icon_bar_v(f, 0.21, 0.39, 0.22, 0.09, c) // crossguard
	icon_tri(f, 0.21, 0.39, 0.60, 0.5, 0.21, 0.61, c) // blade
	icon_chevron(f, 0.70, 0.5, 0.20, 0.44, 0.12, c)
}

// a measuring rule with an arrowhead - how far a spell carries, distinct from
// Reach's blade because Range extends a cast, not the weapon
icon_upgrade_range :: proc(f: Icon_Frame, tint: Maybe(Color), alpha: f32) {
	c := icon_color(ICON_NEUTRAL_COLOR, tint, alpha)
	icon_bar_h(f, 0.12, 0.5, 0.58, 0.13, c)
	icon_bar_v(f, 0.14, 0.26, 0.48, 0.13, c)
	icon_tri(f, 0.92, 0.5, 0.62, 0.26, 0.62, 0.74, c)
}

upgrade_icons: [Upgrade_Kind]Icon_Proc = {
	.Move_Speed  = icon_upgrade_move_speed,
	.Max_Health  = icon_upgrade_max_health,
	.Damage      = icon_upgrade_damage,
	.Action_Rate = icon_upgrade_action_rate,
	.Clip_Size   = icon_upgrade_clip_size,
	.Reach       = icon_upgrade_reach,
	.Range       = icon_upgrade_range,
}

// Vigor/Might/Swiftness are the Account-scoped versions of the Max_Health/
// Damage/Move_Speed Upgrades, so they share those glyphs outright rather
// than getting lookalikes - the repetition is the point, it's what says
// "this is the same stat, bought on the other axis". Fortune raises Gold
// yield, so it takes Gold's own circle.
account_stat_icons: [Account_Stat]Icon_Proc = {
	.Vigor     = icon_upgrade_max_health,
	.Might     = icon_upgrade_damage,
	.Swiftness = icon_upgrade_move_speed,
	.Fortune   = icon_gold,
}
