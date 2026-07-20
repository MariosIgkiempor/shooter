package shooter

import rl "vendor:raylib"

KeyCode :: rl.KeyboardKey

is_key_down :: proc(key: KeyCode) -> bool {
	return rl.IsKeyDown(key)
}
