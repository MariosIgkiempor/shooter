package shooter

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
// patches, content-expansion-build ticket 22, will go at the top of
// draw_ground_layer), then claimed ground, so a claim is never hidden by
// decoration. The Charger's lane (ticket 10) is a second claimed shape and
// extends this proc rather than paralleling it.
//
// Read-only: draw_world_contents runs twice a frame once the blurred
// backdrop is compositing (draw_blurred_world), so nothing here may mutate.

TELL_ZONE_COLOR :: Color{255, 190, 70, 255} // hot amber, the prototype's; a Color cannot be a Tunable
TELL_ZONE_CLAIM_ALPHA: f32 = 0.13 // the full-extent disc, present from the first frame
TELL_ZONE_FILL_ALPHA: f32 = 0.34 // the inner disc that sweeps out to it as the Tell runs
TELL_ZONE_EDGE_ALPHA: f32 = 0.8 // the outline, so the extent reads even over a bright floor

draw_ground_layer :: proc(enemies: []Enemy) {
	for enemy in enemies {
		if a, is_tell := enemy.attack.(Tell_Area); is_tell {
			draw_tell_area_zone(a)
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
