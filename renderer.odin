package shooter

import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:strings"
import rl "vendor:raylib"

Color :: rl.Color
Texture :: rl.Texture
Font :: rl.Font
Camera :: rl.Camera2D
RenderTexture2D :: rl.RenderTexture2D

ATLAS_DATA :: #load("data/atlas.png")
atlas: Texture
font: Font

// two-pass separable Gaussian blur (renderer.odin's begin_blur_shader_mode/
// ensure_blur_textures) backing the menu backdrop blur - see ADR-0015 and
// hud.odin's blurred_backdrop_strength. Loaded via #load (not a runtime
// rl.LoadShader path) for the same reason ATLAS_DATA is: the compiled binary
// shouldn't depend on `data/` being reachable relative to its own cwd.
BLUR_FS_SOURCE :: #load("data/shaders/blur.fs", string)
blur_shader:         rl.Shader
blur_direction_loc:  i32
blur_texel_size_loc: i32

// lazily allocated by ensure_blur_textures on first use (blurred_backdrop_
// strength() > 0), not unconditionally like atlas/font - a session that
// never opens a Screen over a populated world never allocates these.
blur_scene_texture: RenderTexture2D
blur_pass_texture:  RenderTexture2D

initialize_renderer :: proc() {
	atlas_image := rl.LoadImageFromMemory(".png", raw_data(ATLAS_DATA), i32(len(ATLAS_DATA)))
	atlas = rl.LoadTextureFromImage(atlas_image)
	rl.UnloadImage(atlas_image)
	font = load_atlased_font()
	rl.SetShapesTexture(atlas, SHAPES_TEXTURE_RECT)

	blur_fs_cstring := strings.clone_to_cstring(BLUR_FS_SOURCE, context.temp_allocator)
	blur_shader = rl.LoadShaderFromMemory(nil, blur_fs_cstring)
	blur_direction_loc = rl.GetShaderLocation(blur_shader, "direction")
	blur_texel_size_loc = rl.GetShaderLocation(blur_shader, "texel_size")
}

deinitialize_renderer :: proc() {
	rl.UnloadTexture(atlas)
	delete_atlased_font(font)
	rl.UnloadShader(blur_shader)
	if blur_scene_texture.id != 0 {
		rl.UnloadRenderTexture(blur_scene_texture)
		rl.UnloadRenderTexture(blur_pass_texture)
	}
}

begin_drawing :: proc() {
	rl.BeginDrawing()
}

clear_background :: proc(color: Color = rl.MAGENTA) {
	rl.ClearBackground(color)
}

end_drawing :: proc() {
	rl.EndDrawing()
}

begin_using_camera :: proc(camera: Camera) {
	rl.BeginMode2D(camera)
}

end_using_camera :: proc() {
	rl.EndMode2D()
}

begin_texture_mode :: proc(target: RenderTexture2D) {
	rl.BeginTextureMode(target)
}

end_texture_mode :: proc() {
	rl.EndTextureMode()
}

// direction's magnitude is this pass's blur radius in pixels - (radius, 0)
// for the horizontal pass, (0, radius) for the vertical pass. texel_size is
// 1/resolution, letting the shader turn a pixel-space radius into a UV
// offset without knowing the render texture's size itself.
begin_blur_shader_mode :: proc(direction, texel_size: Vec2) {
	direction := direction
	texel_size := texel_size
	rl.SetShaderValue(blur_shader, blur_direction_loc, &direction, .VEC2)
	rl.SetShaderValue(blur_shader, blur_texel_size_loc, &texel_size, .VEC2)
	rl.BeginShaderMode(blur_shader)
}

end_shader_mode :: proc() {
	rl.EndShaderMode()
}

// draws a RenderTexture2D's color buffer to the currently active target at
// full dest size, flipped right-side-up - raylib stores render-texture
// content upside-down (OpenGL's bottom-left texture origin), corrected here
// by negating the source rect's height.
draw_render_texture :: proc(target: RenderTexture2D, dest: Rect, tint: Color = rl.WHITE) {
	src := Rect{0, 0, f32(target.texture.width), -f32(target.texture.height)}
	rl.DrawTexturePro(target.texture, src, dest, {}, 0, tint)
}

// (re)allocates the offscreen blur render textures to (width, height) only
// when they don't already match - mirrors how game.window_width/height are
// refreshed every frame but only actually change on a real resize
// (main.odin's update_game), never reallocated unconditionally. Called once
// per frame, only on the blurred_backdrop_strength() > 0 path.
//
// Checks both textures independently (not just blur_scene_texture) so a
// partial allocation failure - e.g. blur_scene_texture's LoadRenderTexture
// succeeding but blur_pass_texture's failing - gets retried next frame
// instead of leaving blur_pass_texture permanently zero-valued (which would
// make begin_texture_mode silently target the real backbuffer, id 0, rather
// than an offscreen texture).
ensure_blur_textures :: proc(width, height: int) {
	scene_matches := int(blur_scene_texture.texture.width) == width && int(blur_scene_texture.texture.height) == height
	pass_matches := int(blur_pass_texture.texture.width) == width && int(blur_pass_texture.texture.height) == height
	if scene_matches && pass_matches {
		return
	}
	if blur_scene_texture.id != 0 {
		rl.UnloadRenderTexture(blur_scene_texture)
	}
	if blur_pass_texture.id != 0 {
		rl.UnloadRenderTexture(blur_pass_texture)
	}
	blur_scene_texture = rl.LoadRenderTexture(i32(width), i32(height))
	blur_pass_texture = rl.LoadRenderTexture(i32(width), i32(height))
	// raylib's render textures default to REPEAT wrap - without CLAMP, the
	// blur shader's edge taps (fragTexCoord going outside [0,1] near the
	// screen border) would sample wrapped-around pixels from the opposite
	// edge, producing a visible seam instead of a clean edge fade
	rl.SetTextureWrap(blur_scene_texture.texture, .CLAMP)
	rl.SetTextureWrap(blur_pass_texture.texture, .CLAMP)
}

// an axis-aligned world-space extent, expressed as min/max rather than
// Rect's x/y/width/height - the natural shape for the visible-rect/clamping
// math the enemy-spawn-revamp map's off-screen placement ticket needs
World_Bounds :: struct {
	min_x, max_x, min_y, max_y: f32,
}

point_in_world_bounds :: proc(point: Vec2, bounds: World_Bounds) -> bool {
	return point.x >= bounds.min_x && point.x <= bounds.max_x && point.y >= bounds.min_y && point.y <= bounds.max_y
}

// the world-space rect currently visible through camera, derived from
// target/zoom/screen size - raylib's Camera2D treats offset as screen-center
// (see update_camera_center_smooth_follow), so this is a plain half-extent
// box around target with no rotation handling needed (the game never
// rotates the camera). See the enemy-spawn-revamp map's off-screen
// placement ticket.
camera_visible_world_rect :: proc(camera: Camera) -> World_Bounds {
	// game.camera isn't json:"-" (it's meant to feel continuous across a
	// save/load), so a fresh/corrupted save can hand this a zero zoom - and
	// even on a brand-new Run, game.camera.zoom is still 0 on Playing's very
	// first frame, since update_camera_center_smooth_follow (the only thing
	// that ever sets it) runs in draw_game, one full frame after this can
	// already be called from that frame's update_spawn_triggers. Falling
	// back to GAMEPLAY_ZOOM avoids a divide-by-zero producing an Inf/NaN
	// visible rect (and therefore Inf/NaN spawn positions) in either case.
	zoom := camera.zoom > 0 ? camera.zoom : GAMEPLAY_ZOOM
	half_w := (get_screen_width() / zoom) / 2
	half_h := (get_screen_height() / zoom) / 2
	return {
		min_x = camera.target.x - half_w,
		max_x = camera.target.x + half_w,
		min_y = camera.target.y - half_h,
		max_y = camera.target.y + half_h,
	}
}

draw_rectangle :: proc(rect: Rect, color: Color, origin: Vec2 = {}, rotation: f32 = 0) {
	rl.DrawRectanglePro(rect, origin, rotation, color)
}

draw_rectangle_lines :: proc(rect: Rect, color: Color, thickness: f32 = 1) {
	rl.DrawRectangleLinesEx(rect, thickness, color)
}

draw_atlas_tile :: proc(atlas_rect, dest: Rect, origin: Vec2, rotation: f32 = 0, tint: Color = rl.WHITE) {
	rl.DrawTexturePro(atlas, atlas_rect, dest, origin, rotation, tint)
}

// a thin oriented streak, centered on `position` and elongated along
// `direction` - the shared shape for bullets and streak particles (art-revamp
// tickets 02/03), giving visual continuity between a weapon's muzzle effect
// and the bullet it launches
draw_streak :: proc(position, direction: Vec2, length, width: f32, color: Color) {
	dir := linalg.normalize0(direction)
	angle := math.to_degrees(math.atan2(dir.y, dir.x))
	dest := Rect{position.x, position.y, length, width}
	origin := Vec2{length / 2, width / 2}
	draw_rectangle(dest, color, origin, angle)
}

// a thicker, rounder streak with a small tapered head (art-revamp ticket 03's
// "comet") - reads as "this one explodes" at a glance, distinct from a plain
// bullet streak beyond just color
draw_comet :: proc(position, direction: Vec2, length, width: f32, color: Color) {
	dir := linalg.normalize0(direction)
	draw_streak(position, dir, length, width, color)
	rl.DrawCircleV(position + dir * (length * 0.25), width * 0.7, color)
}

// The rod/wedge helpers art-revamp ticket 02 introduced for the three
// per-family weapon shapes lived here. ADR-0018 replaced them: weapon
// geometry is per-kind now and authored once in icon.odin, drawn through an
// Icon_Frame so the same definition serves both a Shop icon and the world.
// draw_streak/draw_comet/draw_flash below stay - bullets and particles
// still use them.

// a one-shot radial-gradient glow, fully opaque at the center fading to
// transparent at `radius` (art-revamp ticket 02's "flash") - callers fade
// `color`'s own alpha over the effect's lifetime for the non-linear decay
draw_flash :: proc(position: Vec2, radius: f32, color: Color) {
	rl.DrawCircleGradient(i32(position.x), i32(position.y), radius, color, rl.Fade(color, 0))
}

draw_text :: proc(text: string, pos: Vec2, size: f32, spacing: f32 = 0, tint: Color = rl.WHITE) {
	rl.DrawTextEx(
		font,
		strings.clone_to_cstring(text, context.temp_allocator),
		pos,
		size,
		spacing,
		tint,
	)
}

delete_atlased_font :: proc(font: rl.Font) {
	delete(slice.from_ptr(font.glyphs, int(font.glyphCount)))
	delete(slice.from_ptr(font.recs, int(font.glyphCount)))
}

// This uses the letters in the atlas to create a raylib font. Since this font is in the atlas
// it can be drawn in the same draw call as the other graphics in the atlas. Don't use
// rl.UnloadFont() to destroy this font, instead use `delete_atlased_font`, since we've set up the
// memory ourselves.
//
// The set of available glyphs is governed by `LETTERS_IN_FONT` in `atlas_builder.odin`
// The font used is governed by `FONT_FILENAME` in `atlas_builder.odin`
load_atlased_font :: proc() -> rl.Font {
	num_glyphs := len(atlas_glyphs)
	font_rects := make([]Rect, num_glyphs)
	glyphs := make([]rl.GlyphInfo, num_glyphs)

	for ag, idx in atlas_glyphs {
		font_rects[idx] = ag.rect
		glyphs[idx] = {
			value    = ag.value,
			offsetX  = i32(ag.offset_x),
			offsetY  = i32(ag.offset_y),
			advanceX = i32(ag.advance_x),
		}
	}

	return {
		baseSize = ATLAS_FONT_SIZE,
		glyphCount = i32(num_glyphs),
		glyphPadding = 0,
		texture = atlas,
		recs = raw_data(font_rects),
		glyphs = raw_data(glyphs),
	}
}

