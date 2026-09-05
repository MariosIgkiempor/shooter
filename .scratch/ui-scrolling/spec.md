# vendor/ui scroll containers

Status: Done

The shooter's Tuning editor is clipped off the bottom of the screen: its list of
35 Tuning Groups is ~1600px tall collapsed, and `vendor/ui` has no way to bound
a region and scroll inside it. The accordion (one group expanded at a time) was
built precisely to work around that absence; this adds the missing primitive.

## Decisions

Settled in a design interview; recorded here because none of it is derivable
from the code.

### Engine (`vendor/ui/layout.odin`)

- **Sizing** — `scroll: Scroll{x, y: bool}` on `Node`, orthogonal to `SizeKind`
  so it composes with `fixed`/`grow`/`percent`. On a scrolling axis the node
  records its natural size in `content_width`/`content_height` and then reports
  only its `size_info` floor to its parent, so content never inflates ancestors
  and never gets squashed by the shrink pass. `fit` on a scrolling axis is a
  hard `assert` - there is nothing for a scroll box to fit to.
- **Axes** — both live in the data model (the engine is already axis-generic),
  but only vertical is wired end-to-end and tested.
- **Clipping** — `clip: Rect` on `RenderCommand`, with nested intersection
  computed in the engine. Backends stay dumb: scissor to `cmd.clip` and draw.
  Commands entirely outside their clip are not emitted at all, so the command
  budget tracks the visible window rather than the content.
- **Input** — the library owns offset and input. `set_pointer_state` takes a
  wheel delta, the engine routes it to the innermost hovered scroll container,
  and offsets live in a retained `scroll_offsets: map[u32]Vec2`, clamped to
  `max(0, content - box)` after sizing each frame and pruned of ids not declared
  this frame. No scroll chaining: an inner area at its end simply stops.
  Scrolling snaps; easing would need per-container velocity and a frame `dt`
  the API never asks for.
- **Scrollbar** — engine-emitted `Rectangle` commands, track + thumb,
  non-interactive (no drag). Colours come from `Node` fields the caller sets,
  following the `background_color` precedent. The bar is **inset**: it
  unconditionally reserves its width from the content box. Reserving it only on
  overflow is circular - reserving can remove the overflow, which un-reserves
  it, which restores it - and the engine has no multi-pass settling to absorb
  the oscillation.
- **Hit-testing** — `element_rects` carries the clip alongside the rect, and
  `is_node_with_id_hovered` intersects the two, so a scrolled-out button is not
  clickable. `Element` embeds its `Rect` with `using`, so existing readers of
  `element_rects[id].x` keep compiling.

### Widget layer (`vendor/ui/ui/ui.odin`)

`ui.scroll_area(key, opts)` is a distinct proc with a **mandatory key**, not a
`scroll: bool` on `Container_Options`. `row`/`column` derive their node ids from
their child *index*, so a scroll offset keyed off one would be silently swapped
or lost whenever the sibling count changed - which is exactly what the Tuning
accordion does every time a group expands.

`Scroll_Options.speed` is a single scalar for both axes where `0` falls back to
`layout.DEFAULT_SCROLL_SPEED`; not a `Maybe`, because a frozen scroll area is a
contradiction. The tick-to-pixel constant is per-area rather than global or
caller-multiplied, so one panel can scroll faster than another.

### Shooter

- Only the Tuning group list scrolls. The mode buttons and the Save Tuning /
  Reset All footer stay pinned outside the scroll area, and the accordion
  **stays**: without it the ~275 tunables would be ~1700 nodes against a 1024
  cap.
- The list gets a height derived from the window height rather than growing
  into the window's slack, so Tiles and Collisions mode lay out exactly as
  before. The Debug window and the Spawn Trigger list are deliberately left
  alone.
- `update_editor_camera` skips wheel pan/zoom when `layout.scroll_consumed()`
  was true, matching the existing one-frame-stale `editor.ui_hovered` pattern.

### Landing

One `vendor/ui` commit, one shooter commit bumping the submodule pin. No ADR:
the ADRs record game-design commitments, and a UI library gaining a scroll
container is a capability - `CONTEXT.md` is its home.
