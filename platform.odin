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

get_mouse_position :: proc() -> Vec2 {
	return rl.GetMousePosition()
}

is_mouse_button_down :: proc(button: rl.MouseButton) -> bool {
	return rl.IsMouseButtonDown(button)
}