# A Map owns its visual identity

Status: accepted

A Map's visual identity is **authored data on the Map**: a floor colour, a wall colour, and the set of ambient effects it runs, riding through `data/maps/*.json` and the bake alongside `player_start`, `time_limit`, `victory_multiplier` and `rung`. `map_icon_colors` — the presentation-only table that holds one swatch colour per `Map_Name` today — is deleted, and the Map Selection swatch derives from the Map's own wall colour instead.

`map_icon_colors`' own comment anticipated this and argued the other way: "Presentation only, so it lives here rather than on Map itself: Map round-trips through data/maps/*.json and the map_builder, and a color baked into that format would need the level editor to grow a color picker to author it." That reasoning was sound when it was written and is now stale in both halves.

The **editor half** is stale because the editor is growing a map-level authoring panel regardless ([ADR-0021](0021-map-layouts-are-hand-authored-places.md) put `player_start`, `time_limit` and `victory_multiplier` on it, and [ADR-0022](0022-map-rungs-are-gated-by-clears.md) added `rung`). And "a colour picker" overstates the work: `vendor/ui` has no picker, but it has `ui.slider`, which `tuning_row` already drives for every `^f32` tunable. Two authored colours is six sliders on a panel that now exists.

The **presentation half** is stale because a swatch is no longer the only per-Map colour. Once a Map has a floor and a wall of its own, a separately-authored swatch is a second source of truth for "what colour is this place", free to disagree with the world it advertises. Deriving the swatch from the wall colour makes that disagreement unrepresentable.

What actually decides it is the failure mode of the alternative. A code-side `[Map_Name]Theme` table is a partial array literal keyed by an enum `map_builder` generates from a filename-sorted directory listing. Adding a sixth map file gives it a fully transparent floor and wall, with nothing at compile time or load time to catch it — the same class of silent-wrong that [ADR-0022](0022-map-rungs-are-gated-by-clears.md) refused for the cleared set. Theming that lives away from the Map it themes is theming a new Map can be silently missing.

## Two colours, not one and not four

A Map authors a floor colour and a wall colour. The bevel is mixed between them and the ambient accent is pushed off the wall, so neither is authored.

One colour was the cheapest promotion — `map_icon_colors` already holds exactly one — and it fails because everything then sits on a single hue ramp, floor included, and the floor is most of the screen. A fuller ramp with an independently authored accent was the other end; it buys an ambient colour that appears nowhere in the tiles, which is a real capability and not one worth two more sliders and two more ways for a Map to be authored ugly. Two is where a floor stops being a darker wall.

## Colour alone does not make a place

The ambient set is authored per Map rather than fixed, and this is the part that is easy to get wrong cheaply. A fixed set — every Map runs every effect, tinted by its own accent — needs no authoring and cannot be authored wrong. It is also just palette variation with an extra step: if two Maps differ only in hue, the ambience is buying texture, not identity, and the ladder's five rungs read as five palettes rather than five places. Floor patches on a clean stone hall are the concrete case.

## Consequences

**Tile rendering is untouched.** Flat fill for floor and wall, wall-vs-floor read off `Tile.collides`, a darker inset bevel, no grid lines and no per-tile colour variation — all of it stands. A theme chooses the colours those rules use and nothing else. The floor-patch layer is a decal layer with no relationship to the tile grid, which is what keeps it clear of the per-tile-noise rule: what that rule protects is the instant floor-vs-wall read, and a blotch spanning several tiles does not attack it the way adjacent tiles differing would.

**Ambient effects keep their own budget.** They are not `game.particles`, which is unbounded, event-driven, cleared by `reset_particles` at a Run boundary, and drawn in one fixed z-slot. Ambience is steady-state and forever, and it needs two z-slots rather than one — motes in front of the actors, patches behind them — so one pool could not express it even if the lifecycle matched.

**No vignette.** A darkened-edge vignette was built and rejected, and the reason generalises: the screen edges are where enemies enter, so an effect that dims them trades legibility for atmosphere in the one place a twin-stick game cannot afford it. Ambient effects carry no information and must never occlude any.

**`Map` grows, so the map-validity test grows.** The theme fields join `rung` in the checks [ADR-0021](0021-map-layouts-are-hand-authored-places.md) established over the baked `maps` table — a Map with a zero-valued (fully transparent) floor or wall colour is invalid, which is precisely the failure the code-side table would have shipped silently.
