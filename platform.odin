package shooter

import rl "vendor:raylib"

get_screen_width :: proc() -> f32 {
	return f32(rl.GetScreenWidth())
}

get_screen_height :: proc() -> f32 {
	return f32(rl.GetScreenHeight())
}

KeyCode :: rl.KeyboardKey

is_key_down :: proc(key: KeyCode) -> bool {
	return rl.IsKeyDown(key)
}

is_key_pressed :: proc(key: KeyCode) -> bool {
	return rl.IsKeyPressed(key)
}

is_any_key_pressed :: proc() -> bool {
	return rl.GetKeyPressed() != .KEY_NULL
}

MouseButton :: rl.MouseButton

get_mouse_position :: proc() -> Vec2 {
	return rl.GetMousePosition()
}

is_mouse_button_down :: proc(button: MouseButton) -> bool {
	return rl.IsMouseButtonDown(button)
}

is_mouse_button_pressed :: proc(button: MouseButton) -> bool {
	return rl.IsMouseButtonPressed(button)
}

// smooth per-frame scroll deltas; a macbook two-finger swipe lands here
get_mouse_wheel_move :: proc() -> Vec2 {
	return rl.GetMouseWheelMoveV()
}
// the next character raylib has queued from the keyboard, or 0 when the queue
// is empty. Layout-aware (a shifted 2 arrives as '@'), unlike is_key_pressed -
// which is why the editor's text field reads this rather than key codes.
get_char_pressed :: proc() -> rune {
	return rl.GetCharPressed()
}
