# 22: Per-Map ambience

**What to build:** Standing still in a Map tells you which Map you are in.
Drifting motes, patches on the floor, and a wash of coloured light give each
place a mood, drawn as part of the world so they sit under the action rather
than over it.

**Blocked by:** 13, 09

**Status:** resolved

- [x] Motes, floor patches and a light wash are authored per Map
- [x] They draw inside the world pass, in their own layers relative to actors
- [x] They draw from their own budget and cannot starve gameplay effects
- [x] A Map that authors none of them looks exactly as it does today

## Comments

Implemented in `ambience.odin`. `Map.ambient` (ticket 13) is now read: the
editor's Map mode gains one toggle per effect, and the two shipped Maps
author sets - Desert Dungeon `{Motes, Light_Wash}`, Cold Hall
`{Floor_Patches, Light_Wash}` - re-baked into `maps.odin`.

The pure seams (`ambience_test.odin`, no `game` reads): `seed_mote` /
`update_motes` keep a fixed field inside a bounds and reseed leavers;
`seed_floor_patches` places blotches deterministically (a fixed seed, so a
place's patches are its patches) and only centred on floor tiles - never on a
wall or in an untiled gap; `ambience_ensure` places them once per Map and
again when the tiles underneath change (`flow_field_ensure`'s idiom, so the
editor re-places them as tiles are painted). `map_accent_color` (`map.odin`)
is the wall pushed toward white, per CONTEXT.md's Map theme entry.

Budget: two fixed arrays on `game.ambience` (`AMBIENT_MOTE_MAX` 96,
`AMBIENT_PATCH_MAX` 40), never `game.particles`. Layers, all inside
`draw_world_contents` and read-only (it runs twice under the blur): patches
at the top of `draw_ground_layer`; the light wash as a world-space gradient
quad over `camera_visible_world_rect` plus the shake margin, drawn between
the tilemap and the Ground layer so it lights the place and tints neither a
Tell's disc nor a body - the "never occlude information" rule applied
literally, and world-space so the blurred backdrop blurs it (spec.md:213);
motes after `draw_particles`, before damage numbers and resource indicators.
`update_ambience` runs outside `update_game_state`'s Shop / Run End pause and
in Editing, so ambience keeps drifting behind a menu and previews live under
the editor's toggles. Alphas and motion are Tunables under a new `Ambience`
group; colours derive from the Map's own.

Rendering is deliberately untested; an empty set drawing nothing is by
construction (every draw call gated on `Map.ambient`), and
`test_the_baked_maps_run_their_authored_ambient_sets` guards the bake.
