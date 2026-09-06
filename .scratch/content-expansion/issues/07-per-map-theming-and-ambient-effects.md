# Per-map theming and ambient effects

Type: prototype
Status: resolved

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

## Answer

**A Map authors a floor colour, a wall colour, and the set of ambient effects it runs — on the Map itself, not in a table beside it.** `map_icon_colors` is deleted and the Map Selection swatch derives from the wall colour. Judged in motion at gameplay zoom on `prototype/map-theming` (commit `e02f899`). [ADR-0024](../../../docs/adr/0024-a-map-owns-its-visual-identity.md).

### Settled

- **Two authored colours: floor and wall.** The bevel is mixed between them; the ambient accent is pushed off the wall toward white. One authored colour was rejected — everything then hangs off a single hue ramp including the floor, which is most of the screen. A fuller ramp with an independently authored accent was rejected as two more sliders and two more ways to author a Map ugly, for a capability (an ambient colour appearing nowhere in the tiles) that nothing asked for.
- **The palette is promoted onto `Map`**, riding through `data/maps/*.json` and the bake beside `player_start`, `time_limit`, `victory_multiplier` and `rung`. The `map_icon_colors` comment argued against exactly this, and both halves of its argument are now stale: the editor is growing a map-level panel regardless ([Map layout authoring model](02-map-layout-authoring-model.md), [Map ladder shape](03-map-ladder-shape.md)), and "a colour picker" is really six `ui.slider` rows — the widget `tuning_row` already drives for every `^f32` tunable. What actually decided it is the alternative's failure mode: a code-side `[Map_Name]Theme` table is a partial array literal over an enum `map_builder` generates from a filename listing, so a sixth map file gets a fully transparent floor and wall with nothing to catch it.
- **The Map Selection swatch derives from the wall colour**; it is not separately authored. A separate field is a second source of truth for "what colour is this place", free to disagree with the world it advertises — which is the exact failure this ticket named. Deriving makes it unrepresentable. `map_icon_colors` and `icon_swatch`'s "placeholder vocabulary, worth replacing at map two" note both resolve here.
- **Three ambient effects: motes, floor patches, light wash.** Drifting motes in the air above the actors; large off-grid patches on the floor beneath them; a directional screen-space gradient.
- **No vignette.** Built and rejected. The screen edges are where enemies enter, so darkening them trades legibility for atmosphere in the one place a twin-stick game cannot afford it. The general rule it establishes: an ambient effect carries no information and must never occlude any.
- **The ambient set is authored per Map, not fixed.** A fixed set tinted per Map needs no authoring and cannot be authored wrong — and is just palette variation with an extra step. Colour alone does not carry five Maps: with one footprint and one tile vocabulary across rungs 1–4, five hues read as five palettes rather than five places, so the variation has to be in the ambience or it is not there at all. Floor patches on a clean stone hall are the case that makes it concrete.
- **Floor patches do not reopen the locked per-tile-colour-noise rule.** They are a decal layer with no relationship to the tile grid. What that rule protects is the instant floor-vs-wall read, and it is attacked by *adjacent tiles differing*, not by a blotch spanning several of them.
- **Tile rendering is untouched**, as the ticket promised: flat fill, `Tile.collides`, the darker inset bevel, no grid lines. A theme chooses the colours those rules use.
- **Ambient effects keep their own fixed budget, separate from `game.particles`.** That pool is unbounded, event-driven, cleared by `reset_particles` at a Run boundary, and drawn in one fixed z-slot. Ambience is steady-state, outlives nothing in particular, and needs two z-slots — motes in front of actors, patches behind them — so one pool could not express it even if the lifecycle matched.

### Not decided here

- **The actual five palettes.** The bench's Desert / Warren / Hall / Ring / Keep colours are legible stand-ins picked to separate the extremes, not authored content — the same deferral every other ticket on this map made for its numerics. Authoring them belongs with the maps themselves.
- **Which effects each rung runs.** Same reason: it is authoring, and it is authored in the editor beside the palette.

### Follow-on

- **[Content-scale integration sweep](09-content-scale-integration-sweep.md)** takes the `Map` format growth, the two new draw layers, the unculled tilemap loop, and the light wash's interaction with the blurred backdrop.
