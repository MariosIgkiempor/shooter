# In-Game HUD Redesign

Label: wayfinder:map

## Destination

An implementation-ready spec for replacing the bottom-of-screen HUD (health/ammo/XP bars, `draw_hud` in [hud.odin](../../hud.odin)) with small particle-driven indicators drawn above the player in world-space, reusing the existing above-enemy health-bar placement pattern (`draw_health_bar`), and unifying enemy health bars into the same visual language. Resource level is communicated primarily through particle behavior (density/color/rate), not a nine-sliced fill bar.

## Notes

- Odin + raylib. Key files: [hud.odin](../../hud.odin) (`draw_hud`, `draw_hud_bar`, `draw_health_bar`, HUD color/size constants), [main.odin](../../main.odin) (draw order at lines 658-721; `game.camera` vs `game.ui_camera`), [particle.odin](../../particle.odin) (`spawn_particle_burst`, `spawn_particle_sprite`), [damage_number.odin](../../damage_number.odin) (existing in-world text).
- **World-space anchor convention** (reuse, don't reinvent): `entity.x/y` is the sprite's bottom-center "feet" anchor ([main.odin:423](../../main.odin)). "Above sprite" = `entity.y - document_size.y - gap`, exactly as `draw_health_bar` already computes it for enemies ([hud.odin:142-153](../../hud.odin)). No dedicated world-to-screen helper exists — every call site inlines this formula; the new player indicator follows the same pattern.
- **Established, not open — the font-stretch problem is already solved by this redesign.** The user's original complaint ("HUD font looks stretched") is specific to `game.ui_camera`, a virtual 180px-tall camera rebuilt every frame as `zoom = window_height / 180` ([main.odin:696-700](../../main.odin)) — its effective zoom *grows with window size*, upscaling the single baked font atlas (`ATLAS_FONT_SIZE :: 32`, [atlas.odin:25](../../atlas.odin)) well past its native resolution. `game.camera` (the world/gameplay camera the new indicators will render in) stays pinned near `GAMEPLAY_ZOOM :: 1.2` ([main.odin:17](../../main.odin)) regardless of window size — `draw_health_bar` and `damage_number.odin` already render crisply there today, proving the camera doesn't stretch. No ticket needed to "fix the font atlas" unless some indicator ends up needing on-screen (`ui_camera`-space) text.
- **Nine-slice is ruled out for these indicators** (see Out of scope) — the panel system exists ([renderer.odin:71-147](../../renderer.odin), used throughout menus) but isn't a fit at this size.
- No continuous/looping particle emitter object exists yet in `particle.odin` — every current effect (`spawn_hit_spark`, `spawn_flame_cone_particle`, etc.) is spawned imperatively, once or per-frame-polled from game logic. A "constantly playing" bar effect needs the same pattern: something calling a spawn function every frame from `update`/`draw`, or a new lightweight continuous-emitter concept if the prototype ticket decides one's worth adding.
- Open thread worth resolving early: per [ADR-0009](../../docs/adr/0009-xp-is-a-run-end-grant.md) / [CONTEXT.md](../../CONTEXT.md), XP is granted once at Run end, not collected in real time. The current bottom XP bar may already be showing stale/meaningless live data — see ticket 01.
- Skills to consult: `frontend-design` for particle/visual direction on the grilling and prototype tickets; the prototype ticket calls the Skill tool for "prototype" per default wayfinder behavior.

## Decisions so far

- [Decide the shape and content of the above-player indicators](issues/01-above-player-indicator-shape-and-content.md): XP dropped entirely (Run End screen keeps it). Every entity gets a Health indicator (icon + particles, fraction-only, always). Player additionally gets exactly one secondary indicator keyed by Weapon family: Ammo indicator (Gun, clip/reserve + distinct reload treatment) or Cooldown indicator (Melee_Weapon/Magic, `cooldown_timer`-to-Ready). Windup gets no indicator anywhere — already telegraphed on the weapon's own draw. Enemies reuse the exact same single-indicator shape as the player's Health indicator. No numeric readouts anywhere; melee/magic icon art is a placeholder for now. New vocabulary recorded in [CONTEXT.md](../../CONTEXT.md) as **Resource indicator**.
- [Prototype the particle-driven resource indicator](issues/02-prototype-particle-driven-indicator.md): refines the indicator's shape — icon beside a flat rect bar (no nine-slice) whose translucent fill is populated by particles that bounce *inside* it ("Simmer" motion won over a flowing-drift alternative), particle count tracked directly to the resource fraction. Reload gets its own distinct fast/chaotic treatment. Two technical findings for the real implementation: bounded particle motion needs its own small local particle set, not the shared drag-based `particle.odin` primitives; and particle positions must be stored as local offsets relative to the bar, not world-space, or they visibly react to player movement. Primary source on `prototype/hud-resource-indicator-bars` (commit `bd6b359`).
- [Decide the fate of enemy health bars](issues/03-enemy-health-bar-unification.md): enemies use the exact same icon+bar indicator as the player, always visible, with a smaller fixed particle budget (~5-6 vs. the player's 20, no count-based throttling) and a distinct red-only color lerp (vs. the player's green-to-red) so color stays a friend/foe signal. Map's last ticket — destination's spec is complete, recorded as [ADR-0011](../../docs/adr/0011-in-game-hud-moves-to-world-space-resource-indicators.md).

## Not yet specified

_(empty — both fog items graduated: numeric-readout was answered directly above; the enemy particle-mapping question narrowed into and lives only in [Decide the fate of enemy health bars](issues/03-enemy-health-bar-unification.md).)_

## Out of scope

- Nine-slice panel art for the new indicators — ruled out by the user (not enough room to render well at this size); particle effects carry the visual language instead.
