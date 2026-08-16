package shooter

import "core:math/linalg"

XP_ORB_RADIUS :: 3.0
XP_ORB_VALUE :: 5 // flat xp per orb; always < XP_LEVEL_BASE
XP_ORB_MAGNET_RADIUS :: 40.0
XP_ORB_PICKUP_RADIUS :: 6.0
XP_ORB_HOMING_ACCEL :: 800.0 // px/s^2 once inside magnet radius
XP_ORB_MAX_SPEED :: 260.0

Xp_Orb :: struct {
	position: Vec2,
	velocity: Vec2,
	value:    int,
	homing:   bool, // sticky once true, so a fast player can't outrun it once it's triggered
}

reset_xp_orbs :: proc() {
	clear(&game.xp_orbs)
}

spawn_xp_orb :: proc(position: Vec2) {
	append(&game.xp_orbs, Xp_Orb{position = position, value = XP_ORB_VALUE})
}

update_xp_orbs :: proc(dt: f32) {
	player_pos := Vec2{game.player.x, game.player.y}

	#reverse for &orb, i in game.xp_orbs {
		to_player := player_pos - orb.position
		dist := linalg.length(to_player)

		if dist <= XP_ORB_PICKUP_RADIUS {
			collect_xp(orb.value)
			unordered_remove(&game.xp_orbs, i)
			continue
		}

		if dist <= XP_ORB_MAGNET_RADIUS {
			orb.homing = true
		}

		if orb.homing {
			dir := to_player / dist
			orb.velocity += dir * XP_ORB_HOMING_ACCEL * dt
			if speed := linalg.length(orb.velocity); speed > XP_ORB_MAX_SPEED {
				orb.velocity = orb.velocity / speed * XP_ORB_MAX_SPEED
			}
		}

		orb.position += orb.velocity * dt
	}
}
