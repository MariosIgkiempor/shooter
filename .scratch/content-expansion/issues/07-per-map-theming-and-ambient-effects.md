# Per-map theming and ambient effects

Type: prototype
Status: open

## Question

How does each Map get its own visual identity, given that tiles are already flat shapes?

This does **not** reopen tile rendering. [Art revamp](../../art-revamp/map.md)'s [tilemap ticket](../../art-revamp/issues/04-tilemap-shape-treatment.md) already locked it: flat fill for floor and wall, walls carrying a darker inset bevel for thickness, wall-vs-floor read from the existing `Tile.collides` bool, no grid lines and no per-tile colour noise, with `Map`/persistence untouched. What is open is everything layered on top.

- **Per-map palette.** `map_icon_colors` ([map.odin](../../../map.odin)) already holds one colour per `Map_Name`, and its own comment says: "Presentation only, so it lives here rather than on Map itself... Promote it onto Map if maps ever gain real per-map theming." This effort is that trigger. Decide what a Map's palette actually is — one swatch, a floor/wall pair, a fuller ramp — and whether promoting it onto `Map` is worth what the comment warns about: `Map` round-trips through `data/maps/*.json` and the editor, so an authored colour means the editor grows a colour picker. Note the generated `maps.odin` is rewritten every build, so nothing hand-added survives there.
- **Procedural ambient effects.** Flat colour alone will make eight maps look like eight palettes. What ambient, code-driven effects give a rung a character — drifting particles, a vignette, subtle floor variation, lighting? `particle.odin`'s vocabulary (streaks, one-shot flashes, non-linear fades, added during the art revamp) is the existing toolkit.
- **Cost.** Ambient effects run every frame over a whole screen of tiles, against an existing standing fog item about unmeasured per-frame transform cost at scale.
- **Where the palette shows.** The Map Selection swatch and the world should agree; today the swatch colour exists only for the menu.

Prototype it — this is a look-at-it question.

[Map layout authoring model](02-map-layout-authoring-model.md) voids the generator caveat this was blocked on: nothing generates a Map, so a Map owns its theming as authored data. It also changes the terms of the `map_icon_colors` promotion question in this ticket's favour — the editor is already growing map-level authoring fields (`name`, `player_start`, `time_limit`, `victory_multiplier`), so a colour picker is one more field on a panel that now exists, not the new burden the original comment warned about. And `Tile.atlas_coords` is deleted, so per-tile visual variation is off the table entirely: whatever identity a Map gets, it comes from a per-*map* palette plus code-driven ambience.
