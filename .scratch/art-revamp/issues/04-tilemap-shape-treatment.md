Type: prototype
Status: resolved
Blocked by: 01

## Question

How do floor/wall tiles render as flat shapes in place of the Kenney `tileset_normal` tileset, applying the vocabulary [01-actor-shape-and-movement-transform](01-actor-shape-and-movement-transform.md) establishes?

This only changes how existing tile IDs are drawn (`draw_tilemap`, main.odin:801-812) — it does not touch the `Map` struct, `load_map`/`save_map`, or the baking pipeline from [level-maps](../../level-maps/map.md). Cover: how walls read as distinct from floor (fill color, border, or both), whether any tile-type variety beyond wall/floor exists today and needs its own treatment, and whether this needs a real prototype inside a level (not just an isolated tile swatch) to judge readability at play scale.

Prototype this directly (throwaway branch), per this map's Notes.

## Prototype

Captured on branch `prototype/tilemap-shapes` (commit `9491c4b`), branched from `prototype/actor-shape-transform` so actors already show the locked shape treatment while this tests tilemap candidates against the real shipped level (`desert_dungeon`, 1704 tiles). Run it with `odin run . -out:build/shooter.bin` from `main` after checking out that branch, then in-game:

- **F10** cycles four states: Sprites (baseline) → **A** grid lines ("blueprint": flat fill, floor gets a subtle grid, walls solid) → **B** wall bevel (flat fill, walls get a darker inset border for thickness) → **C** color variety (flat fill, subtle per-tile shade noise from `atlas_coords`). Current variant shown top-left, alongside F9's actor variant (defaulted to the locked Variant A so the whole scene reflects the real decision so far).
- Wall vs floor comes from the existing `Tile.collides` bool — no changes to `Map`/persistence/level-maps.
- Warm sand/stone palette, distinct from the cool actor/weapon palette already locked, and a nod to the shipped level's desert theme.
- Walk around the real level (not just an isolated swatch) to judge readability at play scale, per this ticket's own framing.

Awaiting live reaction - this ticket stays claimed, not resolved, until you've run it and we've talked through which variant wins.

## Answer

**Variant B confirmed: flat fill + wall bevel.** Floor renders as a plain flat fill (no grid lines, no per-tile shade noise — both A and C were rejected in favor of B's cleaner read). Walls render as a flat fill plus a darker inset border (`TILEMAP_PROTO_WALL_BEVEL_COLOR`, 3px inset, 2px stroke) suggesting thickness/solidity without needing a texture. Floor/wall distinction comes entirely from the existing `Tile.collides` bool — no changes needed to `Map`, persistence, or the baking pipeline from level-maps.

Warm sand/stone palette (`TILEMAP_PROTO_FLOOR_COLOR` / `TILEMAP_PROTO_WALL_COLOR`) confirmed against the cool actor/weapon palette already locked by tickets 01 and 02 — no palette changes requested.

Judged live at play scale in the real shipped level (`desert_dungeon`), not an isolated swatch, per this ticket's own framing.

**Prototype**: branch `prototype/tilemap-shapes` (commit `9491c4b`).
