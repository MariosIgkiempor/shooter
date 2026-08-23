package shooter

import "core:slice"
import "core:strings"
import rl "vendor:raylib"

Color :: rl.Color
Texture :: rl.Texture
Font :: rl.Font
Camera :: rl.Camera2D

ATLAS_DATA :: #load("data/atlas.png")
atlas: Texture
font: Font

initialize_renderer :: proc() {
	atlas_image := rl.LoadImageFromMemory(".png", raw_data(ATLAS_DATA), i32(len(ATLAS_DATA)))
	atlas = rl.LoadTextureFromImage(atlas_image)
	rl.UnloadImage(atlas_image)
	font = load_atlased_font()
	rl.SetShapesTexture(atlas, SHAPES_TEXTURE_RECT)
}

deinitialize_renderer :: proc() {
	rl.UnloadTexture(atlas)
	delete_atlased_font(font)
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

draw_rectangle :: proc(rect: Rect, color: Color, origin: Vec2 = {}, rotation: f32 = 0) {
	rl.DrawRectanglePro(rect, origin, rotation, color)
}

draw_rectangle_lines :: proc(rect: Rect, color: Color, thickness: f32 = 1) {
	rl.DrawRectangleLinesEx(rect, thickness, color)
}

draw_atlas_tile :: proc(atlas_rect, dest: Rect, origin: Vec2, rotation: f32 = 0, tint: Color = rl.WHITE) {
	rl.DrawTexturePro(atlas, atlas_rect, dest, origin, rotation, tint)
}

// draws a 9-slice panel: corners at native size (scaled by `corner_scale`,
// useful when the panel is drawn much larger than the source tiles), edges
// stretched along one axis to bridge the gap between corners, middle
// stretched across both axes. `pieces` are ordered row-major top-to-bottom,
// left-to-right (top-left, top-middle, top-right, middle-left, ...,
// bottom-right), matching how a 3x3 grid of source tiles reads.
draw_nine_slice :: proc(pieces: [9]Atlas_Texture, dest: Rect, tint: Color = rl.WHITE, corner_scale: f32 = 1) {
	tl, tm, tr := pieces[0], pieces[1], pieces[2]
	ml, mm, mr := pieces[3], pieces[4], pieces[5]
	bl, bm, br := pieces[6], pieces[7], pieces[8]

	// clamped to half the destination so corners can never together exceed
	// dest's width/height - without this, a panel smaller than the (scaled)
	// corner size would overflow its own bounds instead of shrinking to fit
	left_w := min(tl.document_size.x * corner_scale, dest.width / 2)
	right_w := min(tr.document_size.x * corner_scale, dest.width / 2)
	top_h := min(tl.document_size.y * corner_scale, dest.height / 2)
	bottom_h := min(bl.document_size.y * corner_scale, dest.height / 2)

	mid_w := max(dest.width - left_w - right_w, 0)
	mid_h := max(dest.height - top_h - bottom_h, 0)

	draw_atlas_tile(tl.rect, {dest.x, dest.y, left_w, top_h}, {}, 0, tint)
	draw_atlas_tile(tm.rect, {dest.x + left_w, dest.y, mid_w, top_h}, {}, 0, tint)
	draw_atlas_tile(tr.rect, {dest.x + left_w + mid_w, dest.y, right_w, top_h}, {}, 0, tint)

	draw_atlas_tile(ml.rect, {dest.x, dest.y + top_h, left_w, mid_h}, {}, 0, tint)
	draw_atlas_tile(mm.rect, {dest.x + left_w, dest.y + top_h, mid_w, mid_h}, {}, 0, tint)
	draw_atlas_tile(mr.rect, {dest.x + left_w + mid_w, dest.y + top_h, right_w, mid_h}, {}, 0, tint)

	draw_atlas_tile(bl.rect, {dest.x, dest.y + top_h + mid_h, left_w, bottom_h}, {}, 0, tint)
	draw_atlas_tile(bm.rect, {dest.x + left_w, dest.y + top_h + mid_h, mid_w, bottom_h}, {}, 0, tint)
	draw_atlas_tile(br.rect, {dest.x + left_w + mid_w, dest.y + top_h + mid_h, right_w, bottom_h}, {}, 0, tint)
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

Animation :: struct {
	atlas_anim:    Animation_Name,
	current_frame: Texture_Name,
	timer:         f32,
}

animation_create :: proc(anim: Animation_Name) -> Animation {
	a := atlas_animations[anim]

	return {
		current_frame = a.first_frame,
		atlas_anim = anim,
		timer = atlas_textures[a.first_frame].duration,
	}
}

animation_update :: proc(a: ^Animation, dt: f32) -> bool {
	a.timer -= dt
	looped := false

	if a.timer <= 0 {
		a.current_frame = Texture_Name(int(a.current_frame) + 1)
		anim := atlas_animations[a.atlas_anim]

		if a.current_frame > anim.last_frame {
			a.current_frame = anim.first_frame
			looped = true
		}

		a.timer = atlas_textures[a.current_frame].duration
	}

	return looped
}

animation_length :: proc(anim: Animation_Name) -> f32 {
	l: f32
	aa := atlas_animations[anim]

	for i in aa.first_frame ..= aa.last_frame {
		t := atlas_textures[i]
		l += t.duration
	}

	return l
}

animation_atlas_texture :: proc(anim: Animation) -> Atlas_Texture {
	return atlas_textures[anim.current_frame]
}
