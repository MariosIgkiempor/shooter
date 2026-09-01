package shooter

import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

PICKUP_DROP_CHANCE :: 0.25 // chance an enemy death drops any pickup at all
PICKUP_MAGNET_RADIUS :: 40.0
PICKUP_PICKUP_RADIUS :: 6.0
PICKUP_HOMING_ACCEL :: 800.0 // px/s^2 once inside magnet radius
PICKUP_MAX_SPEED :: 260.0
PICKUP_HEAL_AMOUNT :: 50.0 // health pickup heal amount
PICKUP_GOLD_AMOUNT :: 10 // gold granted per Gold pickup, spent in the Shop
PICKUP_GOLD_RADIUS :: 5.0 // world-space draw radius

// shape/color per kind (art-revamp ticket 03, colors amended by ticket 05):
// Gold is a plain circle (the fixed anchor the other two are chosen not to
// collide with); Health = a plus/cross, warm red/pink; Ammo = stacked short
// bars, light gray/silver (echoing the weapon-metal tone)
PICKUP_HEALTH_COLOR :: rl.Color{225, 90, 110, 255}
PICKUP_AMMO_COLOR :: rl.Color{200, 200, 205, 255}
PICKUP_CROSS_SIZE :: 10.0 // overall span of Health's plus/cross
PICKUP_CROSS_THICKNESS :: 3.0
PICKUP_AMMO_BAR_COUNT :: 3
PICKUP_AMMO_BAR_WIDTH :: 2.5
PICKUP_AMMO_BAR_HEIGHT :: 8.0
PICKUP_AMMO_BAR_GAP :: 1.5

// Gold reuses all existing pickup machinery (roll odds, homing, collection) -
// it's a third uniform option in maybe_spawn_pickup's rand.choice_enum roll,
// same as Health/Ammo, spent entirely in the Shop (CONTEXT.md's Gold entry)
Pickup_Kind :: enum {
	Health,
	Ammo,
	Gold,
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

// Gold pickups scale with Account_Stat's Fortune (CONTEXT.md's Account_Stat
// entry: "Fortune (Gold-gain rate)") and count toward gold_earned - one of
// compute_run_xp's three Run-end inputs, tracked separately from `gold`
// since spending in the Shop must not shrink it (account_progression.odin).
collect_pickup :: proc(pickup: Pickup) {
	switch pickup.kind {
	case .Health:
		heal_player(PICKUP_HEAL_AMOUNT)
	case .Ammo:
		refill_weapon_reserve(&game.player.weapon)
	case .Gold:
		amount := int(apply_account_stat_effect(f32(PICKUP_GOLD_AMOUNT), .Fortune, game.player.account_stat_stacks[.Fortune]))
		game.player.gold += amount
		game.player.gold_earned += amount
	}
}

draw_pickups :: proc(pickups: []Pickup) {
	for pickup in pickups {
		switch pickup.kind {
		case .Gold:
			rl.DrawCircleV(pickup.position, PICKUP_GOLD_RADIUS, rl.GOLD)
		case .Health:
			draw_health_pickup_cross(pickup.position)
		case .Ammo:
			draw_ammo_pickup_bars(pickup.position)
		}
	}
}

// a plus/cross built from two overlapping rects - a standard, unambiguous
// health glyph (art-revamp ticket 03)
draw_health_pickup_cross :: proc(position: Vec2) {
	half: f32 = PICKUP_CROSS_SIZE / 2
	rl.DrawRectangleV(
		position - Vec2{half, PICKUP_CROSS_THICKNESS / 2},
		Vec2{PICKUP_CROSS_SIZE, PICKUP_CROSS_THICKNESS},
		PICKUP_HEALTH_COLOR,
	)
	rl.DrawRectangleV(
		position - Vec2{PICKUP_CROSS_THICKNESS / 2, half},
		Vec2{PICKUP_CROSS_THICKNESS, PICKUP_CROSS_SIZE},
		PICKUP_HEALTH_COLOR,
	)
}

// a small cluster of parallel bars ("stacked cartridges") - distinct from
// the cross, Gold's circle, and a single bullet streak (art-revamp ticket 03)
draw_ammo_pickup_bars :: proc(position: Vec2) {
	total_width := f32(PICKUP_AMMO_BAR_COUNT) * PICKUP_AMMO_BAR_WIDTH + f32(PICKUP_AMMO_BAR_COUNT - 1) * PICKUP_AMMO_BAR_GAP
	left := position.x - total_width / 2

	for i in 0 ..< PICKUP_AMMO_BAR_COUNT {
		x := left + f32(i) * (PICKUP_AMMO_BAR_WIDTH + PICKUP_AMMO_BAR_GAP)
		rl.DrawRectangleV(
			Vec2{x, position.y - PICKUP_AMMO_BAR_HEIGHT / 2},
			Vec2{PICKUP_AMMO_BAR_WIDTH, PICKUP_AMMO_BAR_HEIGHT},
			PICKUP_AMMO_COLOR,
		)
	}
}
