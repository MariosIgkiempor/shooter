package shooter

import "core:math"
import rl "vendor:raylib"

// The Ground layer: the world-space draw slot immediately above the tilemap
// and beneath every actor (CONTEXT.md). What belongs here is the world
// telling the player something - scenery, or ground an enemy has claimed -
// so nothing on it may be hidden by a crowd standing on it, because a crowd
// standing on it is exactly the case that matters. The player's own output
// (a poison cloud) stays above the actors in draw_world_contents; that is
// feedback on a shot already fired, not the world speaking.
//
// Drawn in order of who is speaking: scenery first (a Map theme's floor
// patches, ambience.odin), then claimed ground, so a claim is never hidden by
// decoration. Two shapes claim ground - a Tell_Area's disc and a Charger's
// lane - in one colour and one alpha vocabulary, because they are one read
// for the player to learn.
//
// Read-only: draw_world_contents runs twice a frame once the blurred
// backdrop is compositing (draw_blurred_world), so nothing here may mutate.

TELL_ZONE_COLOR :: Color{255, 190, 70, 255} // hot amber, the prototype's; a Color cannot be a Tunable
TELL_ZONE_CLAIM_ALPHA: f32 = 0.13 // the full-extent disc, present from the first frame
TELL_ZONE_FILL_ALPHA: f32 = 0.34 // the inner disc that sweeps out to it as the Tell runs
TELL_ZONE_EDGE_ALPHA: f32 = 0.8 // the outline, so the extent reads even over a bright floor

draw_ground_layer :: proc(map_data: ^Map, patches: []Floor_Patch, enemies: []Enemy) {
	draw_ambient_floor_patches(map_data, patches)
	for enemy in enemies {
		if a, is_tell := enemy.attack.(Tell_Area); is_tell {
			draw_tell_area_zone(a)
		}
		if c, is_charger := enemy.movement.(Charger); is_charger {
			draw_charger_lane(enemy, c)
		}
	}
}

// the claimed disc, at full extent from the first frame - the outer disc and
// its edge never grow, so a zone is never mistaken for a smaller attack - with
// an inner disc sweeping out to it. The ground says *where*; the fill and the
// body flash (tell_flash_color) say *when*.
draw_tell_area_zone :: proc(a: Tell_Area) {
	progress, telling := tell_area_progress(a)
	if !telling {
		return
	}
	attack, ok := tell_area_current_attack(a)
	if !ok {
		return
	}
	rl.DrawCircleV(a.tell_centre, attack.radius, rl.Fade(TELL_ZONE_COLOR, TELL_ZONE_CLAIM_ALPHA))
	rl.DrawCircleV(a.tell_centre, attack.radius * progress, rl.Fade(TELL_ZONE_COLOR, TELL_ZONE_FILL_ALPHA))
	rl.DrawCircleLinesV(a.tell_centre, attack.radius, rl.Fade(TELL_ZONE_COLOR, TELL_ZONE_EDGE_ALPHA))
}

// the claimed lane, at full extent from the first frame - from the body's
// feet along the locked bearing for the whole dash, as wide as what the dash
// delivers (charger_lane_half_width) - with an inner strip sweeping down it
// as the Tell runs. The same three layers as the disc, in the disc's colour:
// the ground says *where*, the sweep and the body flash say *when*.
draw_charger_lane :: proc(enemy: Enemy, c: Charger) {
	progress, telling := charger_tell_progress(c)
	if !telling {
		return
	}
	half_width := charger_lane_half_width(enemy)
	length := c.dash_distance + half_width // to the far edge of what the body's stop still reaches
	angle := math.atan2(c.lane_dir.y, c.lane_dir.x) * math.DEG_PER_RAD
	// DrawRectanglePro rotates about `origin` in the rect's own space: the
	// lane's near edge midpoint sits on the feet, so the strip runs from the
	// body forward rather than hanging past it
	claim := Rect{c.lane_origin.x, c.lane_origin.y, length, half_width * 2}
	rl.DrawRectanglePro(claim, {0, half_width}, angle, rl.Fade(TELL_ZONE_COLOR, TELL_ZONE_CLAIM_ALPHA))
	fill := Rect{c.lane_origin.x, c.lane_origin.y, length * progress, half_width * 2}
	rl.DrawRectanglePro(fill, {0, half_width}, angle, rl.Fade(TELL_ZONE_COLOR, TELL_ZONE_FILL_ALPHA))

	side := Vec2{-c.lane_dir.y, c.lane_dir.x} * half_width
	near_left := c.lane_origin - side
	near_right := c.lane_origin + side
	far_left := near_left + c.lane_dir * length
	far_right := near_right + c.lane_dir * length
	edge := rl.Fade(TELL_ZONE_COLOR, TELL_ZONE_EDGE_ALPHA)
	rl.DrawLineV(near_left, far_left, edge)
	rl.DrawLineV(far_left, far_right, edge)
	rl.DrawLineV(far_right, near_right, edge)
	rl.DrawLineV(near_right, near_left, edge)
}
