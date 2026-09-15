package shooter

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

DAMAGE_NUMBER_LIFETIME: f32 = 0.6
DAMAGE_NUMBER_RISE_SPEED: f32 = 40.0 // px/s, world-space upward drift
DAMAGE_NUMBER_FONT :: Font.Mini_Square_16

Damage_Number :: struct {
	position:     Vec2,
	amount:       f32,
	color:        rl.Color,
	lifetime:     f32, // seconds remaining; despawns at <= 0
	max_lifetime: f32, // starting lifetime, used to compute fade fraction
}

reset_damage_numbers :: proc() {
	clear(&game.damage_numbers)
}

spawn_damage_number :: proc(position: Vec2, amount: f32, color: rl.Color) {
	append(
		&game.damage_numbers,
		Damage_Number {
			position = position,
			amount = amount,
			color = color,
			lifetime = DAMAGE_NUMBER_LIFETIME,
			max_lifetime = DAMAGE_NUMBER_LIFETIME,
		},
	)
}

update_damage_numbers :: proc(dt: f32) {
	#reverse for &dn, i in game.damage_numbers {
		dn.lifetime -= dt
		if dn.lifetime <= 0 {
			unordered_remove(&game.damage_numbers, i)
			continue
		}
		dn.position.y -= DAMAGE_NUMBER_RISE_SPEED * dt
	}
}

draw_damage_numbers :: proc(damage_numbers: []Damage_Number) {
	for dn in damage_numbers {
		t := dn.lifetime / dn.max_lifetime // 1 -> 0 over life
		text := fmt.tprintf("{}", int(dn.amount))
		size := measure_text(DAMAGE_NUMBER_FONT, text)
		pos := Vec2{dn.position.x - size.x / 2, dn.position.y - size.y / 2}
		draw_text(DAMAGE_NUMBER_FONT, text, pos, 0, rl.Fade(dn.color, t))
	}
}
