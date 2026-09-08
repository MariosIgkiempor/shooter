package shooter

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

// -- Resource indicator: world-space icon+bar shown above every entity ------
//
// Replaces the old bottom-of-screen HUD (draw_hud) and the old flat-color
// draw_health_bar - see ADR-0011 and CONTEXT.md's Resource indicator entry.
// Every entity (Player, Enemy) shows a Health indicator, always visible.
// The player additionally shows exactly one secondary indicator at a time,
// keyed by the equipped Weapon's family: an Ammo indicator for Gun, or a
// Cooldown indicator for Melee_Weapon/Magic. Every indicator is
// fraction-only (no numeric readout): an icon beside a flat rect bar (no
// nine-slice - see the map's Out of scope) whose translucent fill is
// populated by particles bouncing inside it, particle *count* tracking the
// resource fraction directly. Validated in
// prototype/hud-resource-indicator-bars (ticket 02, commit bd6b359): Simmer
// motion (random-direction jitter, bouncing off the fill bounds) won over a
// rightward-flowing alternative.
//
// Reuses the world-space anchor formula already established for enemies
// (entity.y - document_size.y - gap) - see the map's Notes.

RESOURCE_BAR_WIDTH :: 30
RESOURCE_BAR_HEIGHT :: 6
RESOURCE_BAR_ICON_SIZE :: 9
RESOURCE_BAR_ELEMENT_GAP :: 3
RESOURCE_BAR_GAP_ABOVE_SPRITE :: 6
RESOURCE_BAR_ROW_HEIGHT :: 10
RESOURCE_BAR_ROW_SPACING :: 1 // gap between the Health row and the secondary row

RESOURCE_BAR_BG :: Color{30, 32, 38, 255}
RESOURCE_BAR_FILL_ALPHA :: 70.0 / 255.0 // rl.Fade takes a 0..1 fraction, not a 0..255 byte

RESOURCE_HEALTHY_COLOR :: Color{100, 200, 120, 255}
RESOURCE_CRITICAL_COLOR :: Color{210, 60, 60, 255}
RESOURCE_AMMO_COLOR :: Color{215, 215, 225, 255}
RESOURCE_RELOADING_COLOR :: Color{230, 150, 40, 255}
RESOURCE_COOLDOWN_COLOR :: Color{150, 170, 230, 255}

PLAYER_BAR_MAX_PARTICLES :: 20 // sustained particle count at frac = 1

RESOURCE_PARTICLE_MIN_LIFETIME :: 0.4
RESOURCE_PARTICLE_MAX_LIFETIME :: 0.9
RESOURCE_PARTICLE_MAX_ALPHA :: 0.55 // translucent even at full lifetime, not just while fading out
RESOURCE_PARTICLE_RADIUS :: 1.2

RESOURCE_PARTICLE_SIMMER_MIN_SPEED :: 2.0
RESOURCE_PARTICLE_SIMMER_MAX_SPEED :: 5.0
RESOURCE_PARTICLE_CHAOTIC_MIN_SPEED :: 16.0 // Gun reload: faster, fully chaotic - reads as distinct from plain depletion
RESOURCE_PARTICLE_CHAOTIC_MAX_SPEED :: 26.0
RESOURCE_PARTICLE_RELOAD_COUNT :: 6 // shown regardless of clip frac - reloading from an empty clip (frac 0) is the common case, and a frac-scaled count would make the reload cue invisible exactly then

// one particle inside a Resource indicator's fill region. Position/velocity
// are stored as an offset from the bar's top-left corner, not world-space -
// the bar itself is recomputed fresh from the entity's position every
// frame, so a world-space particle would get dragged/clamped against the
// shifted fill rect on every frame the entity moved, reading as if the
// particle were being dragged by that motion (found during ticket 02's
// prototyping). Local coordinates decouple particle motion from entity
// motion entirely; converted to world-space only at draw time.
//
// lifetime <= 0 doubles as "not currently shown" - a slot past the current
// target_count is retired by zeroing lifetime rather than via a separate
// active flag, so there's exactly one piece of state to keep in sync
// instead of two that could disagree
Resource_Bar_Particle :: struct {
	local_pos:    Vec2,
	vel:          Vec2,
	lifetime:     f32,
	max_lifetime: f32,
}

// the player has exactly one Health indicator and, at most, one secondary
// indicator (Ammo or Cooldown, never both - only one Weapon is ever
// equipped) - a global pair of particle sets mirrors game.player itself
// being a single global value, not a collection
player_health_bar_particles:    [PLAYER_BAR_MAX_PARTICLES]Resource_Bar_Particle
player_secondary_bar_particles: [PLAYER_BAR_MAX_PARTICLES]Resource_Bar_Particle

// keeps `particles` topped up to a count proportional to `frac` (index < that
// count stays eligible to be shown, the rest are retired), each one bouncing
// inside a bounding width so they visibly live inside the level being
// shown, not the bar's full extent - except while `chaotic` (Gun reload):
// reload roams the bar's *full* width at a fixed count regardless of frac,
// since the common case is reloading from an empty clip (frac == 0), where
// a frac-scaled bound/count would make the reload cue invisible right when
// it matters most
update_resource_bar_particles :: proc(
	particles: []Resource_Bar_Particle,
	bar: Rect,
	frac: f32,
	chaotic: bool,
	dt: f32,
) {
	bounds_width := chaotic ? bar.width : bar.width * clamp(frac, 0, 1)

	target_count: int
	if chaotic {
		target_count = min(RESOURCE_PARTICLE_RELOAD_COUNT, len(particles))
	} else {
		target_count = frac <= 0 ? 0 : max(1, int(math.round(clamp(frac, 0, 1) * f32(len(particles)))))
	}

	speed_min: f32 = chaotic ? RESOURCE_PARTICLE_CHAOTIC_MIN_SPEED : RESOURCE_PARTICLE_SIMMER_MIN_SPEED
	speed_max: f32 = chaotic ? RESOURCE_PARTICLE_CHAOTIC_MAX_SPEED : RESOURCE_PARTICLE_SIMMER_MAX_SPEED

	for &p, i in particles {
		if i >= target_count {
			p.lifetime = 0
			continue
		}

		p.lifetime -= dt
		if p.lifetime <= 0 {
			spawn_resource_bar_particle(&p, bounds_width, bar.height, speed_min, speed_max)
			continue
		}

		p.local_pos += p.vel * dt

		if p.local_pos.x < 0 {
			p.local_pos.x = 0
			p.vel.x = abs(p.vel.x)
		}
		if p.local_pos.x > bounds_width {
			p.local_pos.x = bounds_width
			p.vel.x = -abs(p.vel.x)
		}
		if p.local_pos.y < 0 {
			p.local_pos.y = 0
			p.vel.y = abs(p.vel.y)
		}
		if p.local_pos.y > bar.height {
			p.local_pos.y = bar.height
			p.vel.y = -abs(p.vel.y)
		}
	}
}

spawn_resource_bar_particle :: proc(p: ^Resource_Bar_Particle, bounds_width, bar_height, speed_min, speed_max: f32) {
	angle := rand.float32_range(0, math.TAU)
	lifetime := rand.float32_range(RESOURCE_PARTICLE_MIN_LIFETIME, RESOURCE_PARTICLE_MAX_LIFETIME)

	p.local_pos = Vec2{rand.float32_range(0, bounds_width), rand.float32_range(0, bar_height)}
	p.vel = Vec2{math.cos(angle), math.sin(angle)} * rand.float32_range(speed_min, speed_max)
	p.lifetime = lifetime
	p.max_lifetime = lifetime
}

// row 0 sits immediately above the sprite (the Health indicator); each
// further row stacks upward, i.e. further from the sprite - matching ticket
// 01's "Health indicator closer to the sprite, secondary indicator further
// out" layout. Every row reserves the same total width (icon + gap + bar) so
// stacked rows stay left-aligned regardless of has_icon; a row without an
// icon (the Health indicator - no icon, per the user) gives that freed space
// to the bar instead of leaving a blank gutter, so it reads as a
// deliberately wider bar, not a shifted one
resource_indicator_row_rects :: proc(feet, doc_size: Vec2, row: int, has_icon: bool) -> (icon_pos: Vec2, bar: Rect) {
	row_width := f32(RESOURCE_BAR_ICON_SIZE) + RESOURCE_BAR_ELEMENT_GAP + RESOURCE_BAR_WIDTH
	x := feet.x - row_width / 2

	row_top := feet.y - doc_size.y - RESOURCE_BAR_GAP_ABOVE_SPRITE - RESOURCE_BAR_ROW_HEIGHT
	row_top -= f32(row) * (RESOURCE_BAR_ROW_HEIGHT + RESOURCE_BAR_ROW_SPACING)

	if has_icon {
		icon_pos = Vec2{x, row_top + (RESOURCE_BAR_ROW_HEIGHT - RESOURCE_BAR_ICON_SIZE) / 2}
		bar_x := x + RESOURCE_BAR_ICON_SIZE + RESOURCE_BAR_ELEMENT_GAP
		bar = Rect{bar_x, row_top + (RESOURCE_BAR_ROW_HEIGHT - RESOURCE_BAR_HEIGHT) / 2, RESOURCE_BAR_WIDTH, RESOURCE_BAR_HEIGHT}
	} else {
		bar = Rect{x, row_top + (RESOURCE_BAR_ROW_HEIGHT - RESOURCE_BAR_HEIGHT) / 2, row_width, RESOURCE_BAR_HEIGHT}
	}
	return
}

draw_resource_bar :: proc(bar: Rect, frac: f32, fill_color: Color, particles: []Resource_Bar_Particle) {
	draw_rectangle(bar, RESOURCE_BAR_BG)

	fill_width := bar.width * clamp(frac, 0, 1)
	if fill_width > 0 {
		draw_rectangle({bar.x, bar.y, fill_width, bar.height}, rl.Fade(fill_color, RESOURCE_BAR_FILL_ALPHA))
	}

	for p in particles {
		if p.lifetime <= 0 {
			continue
		}
		t := p.lifetime / p.max_lifetime // 1 -> 0 over life, same fade convention as particle.odin's draw_particles
		world_pos := Vec2{bar.x + p.local_pos.x, bar.y + p.local_pos.y}
		rl.DrawCircleV(world_pos, RESOURCE_PARTICLE_RADIUS, rl.Fade(fill_color, RESOURCE_PARTICLE_MAX_ALPHA * t))
	}
}

// the indicator's glyph is a shape-drawn icon (icon.odin), not an atlas
// tile - there is no icon art in the atlas any more, and a code-drawn glyph
// scales into this 9px slot from the same unit-space definition the ~20px
// menu rows use. Tinted with the bar's own live color rather than its world
// color: this row already goes orange while reloading, and the icon has to
// follow its bar or the two contradict each other.
draw_resource_indicator_icon :: proc(pos: Vec2, icon: Icon_Proc, color: Color) {
	icon(icon_frame_rect({pos.x, pos.y, RESOURCE_BAR_ICON_SIZE, RESOURCE_BAR_ICON_SIZE}), color, 1)
}

// the player's secondary indicator (Ammo for Gun, Cooldown for Melee_Weapon/
// Magic - ticket 01), computed once and shared by both
// update_player_resource_indicators (drives the particle sim) and
// draw_player_resource_indicators (draws the bar/icon), so the two can't
// drift apart the way two independent re-derivations could. `ok` is false
// only for a still-nil Weapon.variant (pre-Run, before start_new_run has
// ever run weapon_create) - callers skip drawing/updating entirely then,
// same as the old per-site switch with no matching case did
Player_Secondary_Resource :: struct {
	frac:    f32,
	chaotic: bool, // Gun reload: distinct fast/chaotic particle treatment
	color:   Color,
	icon:    Icon_Proc, // the Ammo indicator's stacked bars for Gun, a clock face for Melee_Weapon/Magic
}

player_secondary_resource :: proc(weapon: Weapon) -> (r: Player_Secondary_Resource, ok: bool) {
	switch v in weapon.variant {
	case Gun:
		ammo_frac: f32 = 0
		if v.clip_size > 0 {
			ammo_frac = clamp(f32(v.ammo_in_clip) / f32(v.clip_size), 0, 1)
		}

		// only two states, because only two are reachable: a Gun with an
		// empty clip always starts a reload on the spot (try_fire_gun ->
		// start_reload, which has no reserve left to refuse on), so there is
		// no "out of ammo entirely" for the bar to show
		color := RESOURCE_AMMO_COLOR
		if v.reload_timer > 0 {
			color = RESOURCE_RELOADING_COLOR
		}

		return Player_Secondary_Resource{frac = ammo_frac, chaotic = v.reload_timer > 0, color = color, icon = icon_ammo}, true
	case Melee_Weapon, Magic:
		return Player_Secondary_Resource {
				frac = weapon_ready_fraction(weapon),
				color = RESOURCE_COOLDOWN_COLOR,
				icon = icon_clock,
			},
			true
	}
	return {}, false
}

update_player_resource_indicators :: proc(dt: f32) {
	doc := ACTOR_SIZE
	feet := Vec2{game.player.x, game.player.y}

	health_frac := clamp(game.player.health / game.player.max_health, 0, 1)
	_, health_bar := resource_indicator_row_rects(feet, doc, 0, false)
	update_resource_bar_particles(player_health_bar_particles[:], health_bar, health_frac, false, dt)

	if secondary, ok := player_secondary_resource(game.player.weapon); ok {
		_, secondary_bar := resource_indicator_row_rects(feet, doc, 1, true)
		update_resource_bar_particles(player_secondary_bar_particles[:], secondary_bar, secondary.frac, secondary.chaotic, dt)
	}
}

draw_player_resource_indicators :: proc(player: Player) {
	doc := ACTOR_SIZE
	feet := Vec2{player.x, player.y}

	health_frac := clamp(player.health / player.max_health, 0, 1)
	health_color := rl.ColorLerp(RESOURCE_CRITICAL_COLOR, RESOURCE_HEALTHY_COLOR, health_frac)
	_, health_bar := resource_indicator_row_rects(feet, doc, 0, false)
	draw_resource_bar(health_bar, health_frac, health_color, player_health_bar_particles[:])

	if secondary, ok := player_secondary_resource(player.weapon); ok {
		secondary_icon_pos, secondary_bar := resource_indicator_row_rects(feet, doc, 1, true)

		draw_resource_indicator_icon(secondary_icon_pos, secondary.icon, secondary.color)
		draw_resource_bar(secondary_bar, secondary.frac, secondary.color, player_secondary_bar_particles[:])
	}
}

