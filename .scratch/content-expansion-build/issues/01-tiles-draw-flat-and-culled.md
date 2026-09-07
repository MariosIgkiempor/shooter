# 01: Tiles draw flat and culled

**What to build:** Authoring a Map becomes blocking out rectangles. The tile a
level author places carries no art identity at all — only where it sits and
whether it collides — so the editor's tileset palette disappears and picking a
tile is no longer a step. Drawing a Map costs only what is on screen, so a map
large enough to hold a ladder rung does not cost more per frame than a small one.

The game has drawn tiles as flat fills since the art revamp; the atlas
coordinate has been dead weight in the data ever since, kept alive only by the
editor's palette and the persistence format.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] A tile records only its cell and whether it collides; no atlas coordinate survives in the type, the on-disk Map format, the generated map table, or the map generator's output
- [x] The editor's Tiles mode offers only Pencil, Rect and Erase — no palette grid, no selected-tile readout, no palette allocation
- [x] Placing a tile where one already exists is a no-op rather than a repaint
- [x] The tilemap draw skips tiles outside the camera's visible rect, in both the direct and the blurred-backdrop paths
- [x] The existing Map still loads, plays and saves; the generated map table is regenerated from it

## Comments

Landed. The atlas-builder still emits its `tileset_normal` rect table into the
generated atlas source; nothing reads it any more. It regenerates every build
and the builder is a vendored submodule, so it was left alone rather than
patched out of a dependency — no atlas coordinate survives anywhere the Map,
the editor or the draw path can see.
