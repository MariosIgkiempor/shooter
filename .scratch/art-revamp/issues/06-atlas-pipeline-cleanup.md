Type: grilling
Status: resolved
Blocked by: 02, 03, 04

## Question

Once the in-scope entities (player, enemies, weapons, bullets, pickups, tilemap) move to shapes, what happens to their now-unused `Texture_Name` atlas entries and `data/textures/*.aseprite`/`.png` source files — deleted outright, or kept for reference/possible revert? Does the `vendor/atlas-builder` pipeline (atlas_builder.odin, generated atlas.odin) need any change given it still serves the UI chrome (9-slice panels/buttons, splash background, both out of scope for this map) and the baked font (`data/font.ttf` → `atlas_glyphs`)? Note also that `rl.SetShapesTexture(atlas, ...)` currently makes raylib's shape-drawing primitives sample from this same atlas texture — confirm whether a shrunken atlas has any implication there.

Depends on 02/03/04 resolving first since the exact list of now-dead `Texture_Name` entries isn't known until each entity category's shape treatment is decided.

## Answer

**`rl.SetShapesTexture`: confirmed no implication.** `SHAPES_TEXTURE_RECT` is dynamically computed by `vendor/atlas-builder` on every run (a packed 10×10 white patch from the rectangle-packer, `atlas_builder.odin:906-914,1105`), not a hardcoded pixel coordinate — a shrunken atlas just gets a freshly valid rect on the next build. No pipeline code change needed for this.

**Poison gas particles — brought into scope, decided directly (no follow-up ticket needed):** `Particle_Poison_Gas0-3` (the one remaining standalone sprite animation, `spawn_poison_gas_puff`/`spawn_poison_windup_puff`) becomes **square particles that fade over time** — reusing the existing particle lifetime/fade infrastructure (`particle.odin`), just a square draw instead of the sprite-frame animation. This is separate from the Poison_Cloud AoE's own translucent-green circle (already confirmed unchanged, ticket 05) — this decision is specifically about the gas-puff particle effect layered on top of it.

**Level editor's tile picker: unchanged.** Keeps showing real Kenney tileset thumbnails (`tileset_normal`) for tile selection in Editing mode — editor tooling, not world-facing game art, same reasoning that already excluded UI chrome. `tileset_normal`'s backing texture data (`data/textures/tileset_normal.aseprite`) is therefore **kept**, not deleted, despite gameplay no longer visually using it (ticket 04's flat-fill+bevel is a gameplay-render-only change; the `Tile`/`Map` data model, including `atlas_coords`, is untouched).

**Dead source files: deleted outright.** Final list — `Player0`/`Player1`, all 8 `Weapon_*` (`Smg`/`Pistol`/`Shotgun`/`Fire_Wand`/`Poison_Staff`/`Flame_Staff`/`Dagger`/`Sword`), `Pickup_Heart`/`Pickup_Ammo`, `Bullet`, all 8 `Enemy_*_Placeholder` frames, and now `Particle_Poison_Gas0-3` — 24 `Texture_Name` entries and their backing `data/textures/*.aseprite`/`.png` files, deleted along with the code that references them (e.g. `weapon_texture_names`, `pickup_texture_names`'s Health/Ammo cases). Git history preserves them if ever needed; the enemy placeholders were never meant to be final art in the first place. `tileset_ping.png` — already noted as unused/legacy before this map even started — gets swept up in the same cleanup, a pre-existing loose end, not a new one.

**Survives untouched**: `Ui_9square_Panel`/`Button`/`Button_Pressed`, `Splash_Background` (UI chrome, out of scope), `tileset_normal` (kept for the editor, see above), the baked font/`atlas_glyphs` (`data/font.ttf`, never in question).

**`vendor/atlas-builder` itself needs no code change** — it generically re-packs whatever's present under `data/textures/` and regenerates `atlas.odin`/`Texture_Name` from that; deleting the dead source files and their now-invalid enum references is sufficient.

This is the last ticket on this map — every decision needed before the implementation follow-on starts is now closed.
