package shooter

import "core:math/rand"

// trauma decays to 0 over roughly 1/SCREEN_SHAKE_DECAY seconds; shake offset
// is scaled by trauma^2 so a hit kicks in hard and then eases out smoothly
SCREEN_SHAKE_DECAY :: 2.5
SCREEN_SHAKE_MAX_OFFSET :: 120.0 // screen-space pixels at trauma = 1

reset_screen_shake :: proc() {
	game.screen_shake_trauma = 0
}

// adds trauma from a hit, clamped so repeated hits can't shake harder than max
trigger_screen_shake :: proc(amount: f32) {
	game.screen_shake_trauma = min(game.screen_shake_trauma + amount, 1)
}

// decays trauma and returns this frame's random screen-space shake offset
update_screen_shake :: proc(dt: f32) -> Vec2 {
	game.screen_shake_trauma = exp_approach(game.screen_shake_trauma, 0, SCREEN_SHAKE_DECAY, dt)

	shake := game.screen_shake_trauma * game.screen_shake_trauma
	offset := Vec2{rand.float32_range(-1, 1), rand.float32_range(-1, 1)}
	return offset * shake * SCREEN_SHAKE_MAX_OFFSET
}
