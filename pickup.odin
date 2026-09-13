package shooter

import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

PICKUP_DROP_CHANCE: f32 = 0.25 // chance an enemy death drops any pickup at all
PICKUP_MAGNET_RADIUS: f32 = 40.0
PICKUP_PICKUP_RADIUS: f32 = 6.0
PICKUP_HOMING_ACCEL: f32 = 800.0 // px/s^2 once inside magnet radius
PICKUP_MAX_SPEED: f32 = 260.0
PICKUP_HEAL_AMOUNT: f32 = 50.0 // health pickup heal amount
// Gold granted per Gold pickup is no longer flat - it comes from the dying
// enemy's Enemy_Gold_Preset (account_progression.odin) and rides on the
// Pickup itself, so a tougher Enemy_Kind can be worth more without touching
// the drop machinery.
PICKUP_GOLD_RADIUS: f32 = 5.0 // world-space draw radius

// shape/color per kind (art-revamp ticket 03, colors amended by ticket 05):
// Gold is a plain circle (the fixed anchor Health is chosen not to collide
// with); Health = a plus/cross, warm red/pink
PICKUP_HEALTH_COLOR :: rl.Color{225, 90, 110, 255}
PICKUP_CROSS_SIZE :: 10.0 // overall span of Health's plus/cross
PICKUP_CROSS_THICKNESS :: 3.0

// Two kinds, each of which restores something a Run actually uses: Gold, spent
// entirely in the Shop (CONTEXT.md's Gold entry), and Health. Every kind is an
// equal option in maybe_spawn_pickup's rand.choice_enum roll, so a kind added
// here dilutes every other one - the roster is deliberately held at what a Run
// actually spends, which is why the Ammo kind went when the Gun reserve it
// refilled did (CONTEXT.md's Pickup entry).
Pickup_Kind :: enum {
	Health,
	Gold,
}

Pickup :: struct {
	position: Vec2,
	velocity: Vec2,
	kind:     Pickup_Kind,
	homing:   bool, // sticky once true, so a fast player can't outrun it once it's triggered
	// Gold only: the payout this drop carries, resolved from the dying
	// enemy's kind at spawn time (enemy_gold_value) rather than read back
	// from a global at collection time, so a drop is worth what the enemy
	// that dropped it was worth. Ignored by Health.
	gold:     int,
}

reset_pickups :: proc() {
	clear(&game.pickups)
}

// rolls PICKUP_DROP_CHANCE; on a hit, picks one of the kinds uniformly
// and spawns it. `kind` is the dying enemy's Enemy_Kind, used to price a
// Gold drop (enemy_gold_value) and to read the one preset fact that changes
// the roll: the Boss always drops, and drops Gold - a minute spent killing
// it that paid out one time in eight would read as a bug.
maybe_spawn_pickup :: proc(position: Vec2, kind: Enemy_Kind) {
	if enemy_presets[kind].boss {
		append(&game.pickups, Pickup{position = position, kind = .Gold, gold = enemy_gold_value(kind)})
		return
	}
	if rand.float32() >= PICKUP_DROP_CHANCE {
		return
	}
	append(
		&game.pickups,
		Pickup{position = position, kind = rand.choice_enum(Pickup_Kind), gold = enemy_gold_value(kind)},
	)
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
// entry: "Fortune (Gold-gain rate)") and count toward gold_earned, tracked
// separately from `gold` since spending must not shrink it - the Run End
// receipt needs gross earnings and net take as separate lines (ADR-0016).
collect_pickup :: proc(pickup: Pickup) {
	switch pickup.kind {
	case .Health:
		heal_player(PICKUP_HEAL_AMOUNT)
	case .Gold:
		amount := int(apply_account_stat_effect(f32(pickup.gold), .Fortune, game.player.account_stat_stacks[.Fortune]))
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
