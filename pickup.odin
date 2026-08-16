package shooter

import "core:math/linalg"
import "core:math/rand"

PICKUP_DROP_CHANCE :: 0.25 // chance an enemy death drops any pickup at all
PICKUP_MAGNET_RADIUS :: 40.0
PICKUP_PICKUP_RADIUS :: 6.0
PICKUP_HOMING_ACCEL :: 800.0 // px/s^2 once inside magnet radius
PICKUP_MAX_SPEED :: 260.0
PICKUP_HEAL_AMOUNT :: 50.0 // health pickup heal amount

Pickup_Kind :: enum {
	Health,
	Ammo,
}

pickup_texture_names: [Pickup_Kind]Texture_Name = {
	.Health = .Pickup_Heart,
	.Ammo   = .Pickup_Ammo,
}

Pickup :: struct {
	position: Vec2,
	velocity: Vec2,
	kind:     Pickup_Kind,
	homing:   bool, // sticky once true, so a fast player can't outrun it once it's triggered
}

reset_pickups :: proc() {
	clear(&game.pickups)
}

// rolls PICKUP_DROP_CHANCE; on a hit, picks Health or Ammo 50/50 and spawns one
maybe_spawn_pickup :: proc(position: Vec2) {
	if rand.float32() >= PICKUP_DROP_CHANCE {
		return
	}
	append(&game.pickups, Pickup{position = position, kind = rand.choice_enum(Pickup_Kind)})
}

update_pickups :: proc(dt: f32) {
	player_pos := Vec2{game.player.x, game.player.y}

	#reverse for &pickup, i in game.pickups {
		to_player := player_pos - pickup.position
		dist := linalg.length(to_player)

		if dist <= PICKUP_PICKUP_RADIUS {
			collect_pickup(pickup)
			unordered_remove(&game.pickups, i)
			continue
		}

		if dist <= PICKUP_MAGNET_RADIUS {
			pickup.homing = true
		}

		if pickup.homing {
			dir := to_player / dist
			pickup.velocity += dir * PICKUP_HOMING_ACCEL * dt
			if speed := linalg.length(pickup.velocity); speed > PICKUP_MAX_SPEED {
				pickup.velocity = pickup.velocity / speed * PICKUP_MAX_SPEED
			}
		}

		pickup.position += pickup.velocity * dt
	}
}

collect_pickup :: proc(pickup: Pickup) {
	switch pickup.kind {
	case .Health:
		heal_player(PICKUP_HEAL_AMOUNT)
	case .Ammo:
		refill_weapon_reserve(&game.player.weapon)
	}
}

draw_pickups :: proc(pickups: []Pickup) {
	for pickup in pickups {
		tex := atlas_textures[pickup_texture_names[pickup.kind]]
		dest := Rect{pickup.position.x, pickup.position.y, tex.rect.width, tex.rect.height}
		origin := Vec2{tex.rect.width / 2, tex.rect.height / 2}
		draw_atlas_tile(tex.rect, dest, origin)
	}
}
