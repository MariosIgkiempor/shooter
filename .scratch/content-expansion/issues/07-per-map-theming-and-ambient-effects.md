# Per-map theming and ambient effects

Type: prototype
Status: claimed

## Question

How does each Map get its own visual identity, given that tiles are already flat shapes?

This does **not** reopen tile rendering. [Art revamp](../../art-revamp/map.md)'s [tilemap ticket](../../art-revamp/issues/04-tilemap-shape-treatment.md) already locked it: flat fill for floor and wall, walls carrying a darker inset bevel for thickness, wall-vs-floor read from the existing `Tile.collides` bool, no grid lines and no per-tile colour noise, with `Map`/persistence untouched. What is open is everything layered on top.

- **Per-map palette.** `map_icon_colors` ([map.odin](../../../map.odin)) already holds one colour per `Map_Name`, and its own comment says: "Presentation only, so it lives here rather than on Map itself... Promote it onto Map if maps ever gain real per-map theming." This effort is that trigger. Decide what a Map's palette actually is — one swatch, a floor/wall pair, a fuller ramp — and whether promoting it onto `Map` is worth what the comment warns about: `Map` round-trips through `data/maps/*.json` and the editor, so an authored colour means the editor grows a colour picker. Note the generated `maps.odin` is rewritten every build, so nothing hand-added survives there.
- **Procedural ambient effects.** Flat colour alone will make eight maps look like eight palettes. What ambient, code-driven effects give a rung a character — drifting particles, a vignette, subtle floor variation, lighting? `particle.odin`'s vocabulary (streaks, one-shot flashes, non-linear fades, added during the art revamp) is the existing toolkit.
- **Cost.** Ambient effects run every frame over a whole screen of tiles, against an existing standing fog item about unmeasured per-frame transform cost at scale.
- **Where the palette shows.** The Map Selection swatch and the world should agree; today the swatch colour exists only for the menu.

Prototype it — this is a look-at-it question.

[Map layout authoring model](02-map-layout-authoring-model.md) voids the generator caveat this was blocked on: nothing generates a Map, so a Map owns its theming as authored data. It also changes the terms of the `map_icon_colors` promotion question in this ticket's favour — the editor is already growing map-level authoring fields (`name`, `player_start`, `time_limit`, `victory_multiplier`), so a colour picker is one more field on a panel that now exists, not the new burden the original comment warned about. And `Tile.atlas_coords` is deleted, so per-tile visual variation is off the table entirely: whatever identity a Map gets, it comes from a per-*map* palette plus code-driven ambience.

## Prototype

Captured on branch `prototype/map-theming` (commit `e02f899`), branched from `main`, with a worktree already set up and building at `.claude/worktrees/prototype-map-theming`. Run it with:

```
cd .claude/worktrees/prototype-map-theming && odin run . -out:build/shooter.bin
```

Keys work in **Playing or Editing** (Editing is the better view for the floor layer, since you can scroll the whole map):

- **F2** — theme: **Desert / Warren / Hall / Ring / Keep**, one per rung of [Map ladder shape](03-map-ladder-shape.md)'s ladder. Defaults to Desert.
- **F9** — palette depth: **one swatch / floor+wall pair / full ramp**. Defaults to full ramp.
- **F10** — ambient effect, one at a time: **none / motes / vignette / floor patches / light wash**. Defaults to motes.
- **F11** — stack every effect the theme wants instead of showing one. Defaults off.
- **F12** — mote density **32 / 80 / 160**. Defaults to 80.

A yellow readout top-left shows the settings; an orange line under it shows live mote count, live combat-particle count and FPS; below that, the swatch Map Selection would draw for the current theme at the current depth, next to the world it is supposed to stand for.

### What it builds

**Palette depth is the whole promotion question, made visible.** Each theme authors a full four-colour ramp (floor, wall, bevel, accent), and F9 *throws authored colours away* and derives what is missing:

- **One swatch** — the single `Color` `map_icon_colors` already holds, with wall/floor/bevel as fixed multiples of it. If this reads, `Map` gains one field and the editor gains one colour picker.
- **Floor+wall pair** — two authored, bevel mixed between them, accent pushed toward white.
- **Full ramp** — all four authored, and the accent is free to be a colour that appears nowhere in the tiles.

Desert's full ramp is byte-for-byte `TILEMAP_FLOOR_COLOR` / `TILEMAP_WALL_COLOR` / `TILEMAP_WALL_BEVEL_COLOR`, so *Desert + full ramp* is the exact control: it is the game as it ships today.

**Four ambient effects**, each judgeable alone:

- **Motes** — world-space drifting dust, per-theme direction and speed, in the accent colour. From a **fixed 160-slot pool, deliberately not `game.particles`** — that pool is an unbounded `[dynamic]Particle` shared with hit sparks and muzzle flashes, and ambience runs forever.
- **Vignette** — screen-space darkened edges in a shade of the floor colour.
- **Floor patches** — 40 large, seeded, **off-grid** blotches on the floor layer, under actors. Not per-tile tinting: [Art revamp](../../art-revamp/map.md) locked "no per-tile colour noise", and whether a decal layer with no relationship to the tile grid is a different thing or the same thing wearing a hat is a question for the human, not for the bench.
- **Light wash** — a screen-space vertical gradient, accent at the top, darkened floor at the bottom.

Vignette and light wash draw **after `end_using_camera`**, so they stay lens effects and do not scroll with the world.

### Cost

`draw_tilemap` already draws all 1704 tiles of Desert Dungeon every frame with no culling, against ~225 actually visible at gameplay zoom (`tile_size` 16, `PIXEL_WINDOW_HEIGHT` 180 giving a 320×180px view). The ambient layers are small next to that — 160 circles, 40 circles, six gradient rects — which is why the readout shows FPS rather than a profiler: the question is whether anything here is *visibly* expensive, not what it costs in microseconds.

### Questions it exists to answer

1. **How many colours does a Map author?** Cycle F9 on one theme. If one swatch reads as a place, the `map_icon_colors` promotion is one field.
2. **Does palette alone carry five maps?** F2 through all five at F10=none. If they read as five palettes rather than five places, ambience is load-bearing rather than garnish.
3. **Which ambient effect earns its keep**, and whether stacking (F11) reads as atmosphere or as mud.
4. **Do the floor patches reopen the locked "no per-tile colour noise" rule**, or are they a distinct decal layer?
5. **Does the Map Selection swatch have to be authored separately**, or can it just be the wall colour? The corner square shows the derived answer beside the world.
