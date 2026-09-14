package shooter

import "core:testing"

// resource_indicator_row_rects is pure geometry - feet, a document size and
// a row in, an icon slot and a bar rect out - so the Boss's Health indicator
// is pinned here without a `game`. Rendering (fill, particles, notches) is
// deliberately untested, as every other indicator's is.

@(test)
test_a_row_rect_keeps_the_players_width_unless_asked_for_more :: proc(t: ^testing.T) {
	feet := Vec2{100, 100}
	_, default_bar := resource_indicator_row_rects(feet, ACTOR_SIZE, 0, false)
	_, unwidened := resource_indicator_row_rects(feet, ACTOR_SIZE, 0, false, min_width = 10)

	testing.expect_value(t, default_bar.width, f32(RESOURCE_BAR_ICON_SIZE + RESOURCE_BAR_ELEMENT_GAP + RESOURCE_BAR_WIDTH))
	testing.expect_value(t, unwidened, default_bar)
}

@(test)
test_the_boss_health_bar_is_at_least_as_wide_as_its_body_and_sits_above_it :: proc(t: ^testing.T) {
	boss := Enemy{rect = {200, 300, 0, 0}, max_health = 220, health = 220}
	size := enemy_body_size(boss.max_health)

	bar := boss_health_bar_rect(boss)

	testing.expectf(t, bar.width >= size, "a %vpx body should carry a bar at least that wide, got %v", size, bar.width)
	testing.expectf(t, abs((bar.x + bar.width / 2) - boss.x) < 0.001, "the bar should be centred on the body, got centre %v for feet %v", bar.x + bar.width / 2, boss.x)
	testing.expectf(t, bar.y + bar.height < boss.y - size, "the bar should clear the top of the body (%v), got bottom %v", boss.y - size, bar.y + bar.height)
}
