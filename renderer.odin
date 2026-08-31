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

// draws a 9-slice panel from a single square-grid source texture: corners
// drawn once at native size (scaled by `corner_scale`), edges and middle
// *tiled* (repeated) at that same native size rather than stretched - this
// asset's edge/middle cells are their own decorative motif, not a flat
// strip, so stretching them to fill an arbitrary panel size smears the
// pattern; tiling keeps every copy pixel-crisp regardless of panel size. The
// source is sliced into an even 3x3 grid automatically (corner size =
// texture size / 3) - no per-asset slice configuration, so any nine-slice
// sprite just needs to be authored as one square-cornered image and dropped
// in the atlas.
draw_nine_slice :: proc(texture: Atlas_Texture, dest: Rect, tint: Color = rl.WHITE, corner_scale: f32 = 1) {
	src := texture.rect
	src_corner_w := src.width / 3
	src_corner_h := src.height / 3
	src_mid_w := src.width - src_corner_w * 2
	src_mid_h := src.height - src_corner_h * 2

	doc_corner_w := texture.document_size.x / 3
	doc_corner_h := texture.document_size.y / 3

	// shrunk by one *uniform* factor (never width/height independently) so a
	// panel smaller than the (scaled) corner size shrinks the whole corner
	// proportionally instead of squashing it into a non-square shape - a
	// clamp applied per-axis would stretch the art exactly like the mid
	// pieces used to before they were switched to tiling
	shrink := min(1, dest.width / (doc_corner_w * corner_scale * 2), dest.height / (doc_corner_h * corner_scale * 2))
	left_w := doc_corner_w * corner_scale * shrink
	right_w := left_w
	top_h := doc_corner_h * corner_scale * shrink
	bottom_h := top_h

	mid_w := max(dest.width - left_w - right_w, 0)
	mid_h := max(dest.height - top_h - bottom_h, 0)

	tl := Rect{src.x, src.y, src_corner_w, src_corner_h}
	tm := Rect{src.x + src_corner_w, src.y, src_mid_w, src_corner_h}
	tr := Rect{src.x + src_corner_w + src_mid_w, src.y, src_corner_w, src_corner_h}

	ml := Rect{src.x, src.y + src_corner_h, src_corner_w, src_mid_h}
	mm := Rect{src.x + src_corner_w, src.y + src_corner_h, src_mid_w, src_mid_h}
	mr := Rect{src.x + src_corner_w + src_mid_w, src.y + src_corner_h, src_corner_w, src_mid_h}

	bl := Rect{src.x, src.y + src_corner_h + src_mid_h, src_corner_w, src_corner_h}
	bm := Rect{src.x + src_corner_w, src.y + src_corner_h + src_mid_h, src_mid_w, src_corner_h}
	br := Rect{src.x + src_corner_w + src_mid_w, src.y + src_corner_h + src_mid_h, src_corner_w, src_corner_h}

	// corners: drawn once, never stretched
	draw_atlas_tile(tl, {dest.x, dest.y, left_w, top_h}, {}, 0, tint)
	draw_atlas_tile(tr, {dest.x + left_w + mid_w, dest.y, right_w, top_h}, {}, 0, tint)
	draw_atlas_tile(bl, {dest.x, dest.y + top_h + mid_h, left_w, bottom_h}, {}, 0, tint)
	draw_atlas_tile(br, {dest.x + left_w + mid_w, dest.y + top_h + mid_h, right_w, bottom_h}, {}, 0, tint)

	// edges and middle: tiled at the same (uniformly-shrunk) unit size as the
	// corners, instead of stretched - must use the same `shrink` factor or
	// tiles would come out non-square whenever the corners do too
	tile_size := Vec2{doc_corner_w * corner_scale * shrink, doc_corner_h * corner_scale * shrink}
	draw_nine_slice_tiled(tm, {dest.x + left_w, dest.y, mid_w, top_h}, tile_size, tint)
	draw_nine_slice_tiled(bm, {dest.x + left_w, dest.y + top_h + mid_h, mid_w, bottom_h}, tile_size, tint)
	draw_nine_slice_tiled(ml, {dest.x, dest.y + top_h, left_w, mid_h}, tile_size, tint)
	draw_nine_slice_tiled(mr, {dest.x + left_w + mid_w, dest.y + top_h, right_w, mid_h}, tile_size, tint)
	draw_nine_slice_tiled(mm, {dest.x + left_w, dest.y + top_h, mid_w, mid_h}, tile_size, tint)
}

// repeats `src` across `dest` in steps of `tile_size`, clipping the trailing
// partial tile on each axis by shrinking its source rect proportionally
// (rather than stretching a full tile into a smaller leftover space)
draw_nine_slice_tiled :: proc(src, dest: Rect, tile_size: Vec2, tint: Color) {
	if dest.width <= 0 || dest.height <= 0 || tile_size.x <= 0 || tile_size.y <= 0 {
		return
	}

	y: f32 = 0
	for y < dest.height {
		draw_h := min(tile_size.y, dest.height - y)
		src_h := src.height * (draw_h / tile_size.y)

		x: f32 = 0
		for x < dest.width {
			draw_w := min(tile_size.x, dest.width - x)
			src_w := src.width * (draw_w / tile_size.x)

			draw_atlas_tile({src.x, src.y, src_w, src_h}, {dest.x + x, dest.y + y, draw_w, draw_h}, {}, 0, tint)
			x += tile_size.x
		}
		y += tile_size.y
	}
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
