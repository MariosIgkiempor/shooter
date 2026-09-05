package shooter

import "core:math"
import rl "vendor:raylib"

// -- Relic (see CONTEXT.md's Relic entry, ADR-0019) -------------------------
//
// The permanent *behavioural* axis Account progression's Gold buys into, the
// sibling of Account_Stat's permanent *numeric* one. An Account_Stat's whole
// effect is a number folded into an existing stat (Account_Stat_Preset.effect
// is a bare Multiplicative); a Relic's effect is a thing that exists in the
// world and acts on its own, which no amount of widening that field expresses
// - hence a parallel enum + preset table + stacks array rather than a new
// Account_Stat member (ADR-0019).
//
// Relic_Kind is the ladder: one member per ability. Today's only member is
// Orbiting_Orb; the Chasing Shield and the Pet are both deliberately deferred
// (see .scratch/relics/map.md), the Shield behind a damage_player mitigation
// seam that does not exist yet.

Relic_Kind :: enum {
	Orbiting_Orb,
}

// deliberately the same shape as Account_Stat_Preset minus `effect`: a Relic
// has no single number to fold anywhere, so what a stack *does* lives with
// the ability's own runtime below rather than in this table. Everything else
// - geometric pricing, a hard max_stack, an Account-Level unlock gate - is
// the identical mechanism, reused rather than reinvented.
Relic_Preset :: struct {
	display_name: string,
	base_price:   int,
	price_growth: f32,
	max_stack:    int,
	unlock_level: int,
}

// exact prices/growth/caps are placeholder content-authoring, same as
// upgrade_presets and account_stat_presets - only the shape is locked.
//
// Priced above every Account_Stat and grown faster (1.35 vs 1.15) on a much
// shorter ladder (4 vs 10): a stack here adds a whole second orb rather than
// 5% of a stat, so the same growth factor would make it strictly the best
// Gold sink in the game. The unlock_level sits above Vigor's but below
// Might's, so the first Relic is the first thing banking buys that is not
// simply a bigger number.
relic_presets: [Relic_Kind]Relic_Preset = {
	.Orbiting_Orb = {
		display_name = "Orbiting Orb",
		base_price = 700,
		price_growth = 1.35,
		max_stack = 4,
		unlock_level = 2,
	},
}

// gold cost of the next purchase of `kind`, given how many stacks are already
// owned - the same geometric mechanism as account_stat_price/upgrade_price
relic_price :: proc(kind: Relic_Kind, current_stack: int) -> int {
	preset := relic_presets[kind]
	return int(f32(preset.base_price) * math.pow(preset.price_growth, f32(current_stack)))
}

// whether the Account has reached `kind`'s unlock_level - the Main Menu still
// draws a locked row rather than hiding it, mirroring account_stat_unlocked,
// so the ladder ahead stays visible as something banking buys
relic_unlocked :: proc(kind: Relic_Kind) -> bool {
	return game.player.level >= relic_presets[kind].unlock_level
}

relic_maxed :: proc(kind: Relic_Kind) -> bool {
	return game.player.relic_stacks[kind] >= relic_presets[kind].max_stack
}

// buys one stack of `kind`, if unlocked, not maxed, and affordable - the same
// guard order and same wallet (ADR-0016) as try_buy_account_stat, enforced
// here rather than only in the UI that filters these rows.
//
// Unlike try_buy_account_stat there is nothing to recompute afterwards: a
// Relic's live effect is derived from relic_stacks every frame (see
// relic_orb_count), never applied onto a stat that could then drift out of
// sync with it - the same recompute-not-mutate discipline as ADR-0007,
// arrived at by having no mutable copy at all.
try_buy_relic :: proc(kind: Relic_Kind) -> bool {
	if !relic_unlocked(kind) {
		return false
	}

	if relic_maxed(kind) {
		return false
	}

	price := relic_price(kind, game.player.relic_stacks[kind])
	if game.player.gold < price {
		return false
	}

	game.player.gold -= price
	game.player.relic_stacks[kind] += 1
	return true
}

// -- Orbiting Orb -----------------------------------------------------------

RELIC_ORB_ORBIT_RADIUS :: 46.0 // distance from the player's mid-body to an orb's center
RELIC_ORB_SIZE :: 7.0 // an orb's own radius, both drawn and hit-tested
RELIC_ORB_ANGULAR_SPEED :: 2.2 // radians/sec the whole ring rotates at
RELIC_ORB_BASE_DAMAGE :: 14.0 // per tick, before Might
RELIC_ORB_TICK_RATE :: 3.0 // damage ticks/sec while an enemy overlaps

RELIC_ORB_COLOR :: rl.Color{120, 200, 255, 200}
RELIC_ORB_CORE_COLOR :: rl.Color{235, 250, 255, 255}

// transient runtime state for every Relic, kept off Player deliberately:
// Player is the persisted record (relic_stacks lives there), and a saved
// orbit phase would restore the ring to a stale angle for one frame on load.
// Zeroed by reset_relics at program start and at every Run start.
Relic_State :: struct {
	orb_phase:      f32, // radians, accumulating while Playing; wrapped to [0, TAU)
	orb_tick_timer: f32, // counts down to 0, fires a tick for every orb, then resets to 1/RELIC_ORB_TICK_RATE
}

reset_relics :: proc() {
	game.relic_state = {}
}

// how many orbs are on the ring: derived straight from the purchased stack
// count every time it's asked, never cached. A stack of this Relic adds a
// whole orb rather than scaling one, which is what makes the ladder legible
// at a glance instead of only in the damage numbers.
relic_orb_count :: proc() -> int {
	return game.player.relic_stacks[.Orbiting_Orb]
}

// per-tick damage of one orb. Might scales it for the same reason it scales
// weapon damage: it is Account progression's "Damage" stat, and a Relic is
// Account-scoped too, so a Might build wanting its orbs to keep pace is the
// coherent reading. Run-scoped Damage Upgrades deliberately do *not* apply -
// they are bought against the equipped Weapon (apply_upgrades), and an orb is
// not one.
relic_orb_damage :: proc() -> f32 {
	return apply_account_stat_effect(
		RELIC_ORB_BASE_DAMAGE,
		.Might,
		game.player.account_stat_stacks[.Might],
	)
}

// the ring's center: the player's mid-body, the same pivot draw_weapon
// anchors to - not rect.x/y, which is the feet anchor (actor_collision_rect)
relic_orbit_center :: proc() -> Vec2 {
	return Vec2{game.player.x, game.player.y - ACTOR_SIZE.y / 2}
}

// where orb `index` of `count` sits this frame - evenly spaced around the
// ring, the whole set sharing one `phase`. The single source of truth for orb
// placement, read by both update_relics (which hit-tests it) and draw_relics
// (which draws it), so what damages an enemy and what the player sees can
// never disagree.
relic_orb_position :: proc(index, count: int, center: Vec2, phase: f32) -> Vec2 {
	angle := phase + (f32(index) / f32(count)) * math.TAU
	return center + Vec2{math.cos(angle), math.sin(angle)} * RELIC_ORB_ORBIT_RADIUS
}

// rotates the ring and, on each tick, damages every enemy an orb currently
// overlaps. Repeating ticks rather than a single hit on entry, and no
// per-enemy "already hit" bookkeeping - the same shape as a Poison_Cloud's
// DoT (poison_cloud.odin): staying inside the ring stacks damage up, and an
// enemy caught by two orbs on the same tick takes two hits, which is exactly
// what a second stack is bought for.
update_relics :: proc(dt: f32) {
	count := relic_orb_count()
	if count == 0 {
		// no orbs owned: park the ring at rest so buying the first stack
		// mid-session always starts from a predictable phase
		game.relic_state = {}
		return
	}

	game.relic_state.orb_phase += RELIC_ORB_ANGULAR_SPEED * dt
	for game.relic_state.orb_phase >= math.TAU {
		game.relic_state.orb_phase -= math.TAU
	}

	game.relic_state.orb_tick_timer -= dt
	if game.relic_state.orb_tick_timer > 0 {
		return
	}
	game.relic_state.orb_tick_timer += 1.0 / RELIC_ORB_TICK_RATE

	damage := relic_orb_damage()
	center := relic_orbit_center()

	for index in 0 ..< count {
		position := relic_orb_position(index, count, center, game.relic_state.orb_phase)

		// #reverse, and game.enemies re-read per orb, because
		// apply_hit_to_enemy removes a killed enemy by index
		#reverse for enemy, j in game.enemies {
			enemy_box := actor_collision_rect(enemy.rect)
			if !rl.CheckCollisionCircleRec(position, RELIC_ORB_SIZE, enemy_box) {
				continue
			}
			apply_hit_to_enemy(j, damage, Vec2{enemy.x, enemy.y})
		}
	}
}

draw_relics :: proc() {
	count := relic_orb_count()
	if count == 0 {
		return
	}

	center := relic_orbit_center()
	for index in 0 ..< count {
		position := relic_orb_position(index, count, center, game.relic_state.orb_phase)
		rl.DrawCircleV(position, RELIC_ORB_SIZE, RELIC_ORB_COLOR)
		rl.DrawCircleV(position, RELIC_ORB_SIZE * 0.45, RELIC_ORB_CORE_COLOR)
	}
}
