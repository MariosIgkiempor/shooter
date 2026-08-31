Type: grilling
Status: resolved
Blocked by: 02

## Question

**Narrowed by [Decide the shape and content of the above-player indicators](01-above-player-indicator-shape-and-content.md)'s resolution**: enemies already reuse the exact same single-indicator shape as the player's Health indicator (icon + constantly-playing particles, fraction-only) — that part is settled, not open here. What's left, given the validated look from [Prototype the particle-driven resource indicator](02-prototype-particle-driven-indicator.md):

- **Particle budget/perf and visual noise at scale.** Unlike the single player, many Enemies can be on screen simultaneously. Does every enemy run the identical constantly-playing particle effect regardless of count, or does it get throttled/simplified past some enemy-count threshold (fewer particles per emitter, or a cheaper effect entirely) to stay legible and performant?
- **Always-visible vs. damage-only.** `draw_health_bar` today only shows while an enemy is damaged (implicit in current call sites). The player's Health indicator is "constantly playing" per the map's destination — does the enemy version match that (always visible, particles running from full health), or keep today's damage-triggered visibility?
- Any resulting change to the flat black/red rect colors `draw_health_bar` currently hardcodes, independent of the HUD color constants — now moot as bar colors once the enemy indicator becomes icon+particle, worth confirming explicitly.

This is the map's last ticket if nothing new surfaces — resolving it should leave the destination's spec complete. Record an ADR at that point (per the pattern in [ui-overhaul's map](../../ui-overhaul/map.md), which recorded [ADR-0010](../../../docs/adr/0010-hand-rolled-menu-ui-no-layout-engine.md) on its own last ticket) summarizing the HUD-to-Resource-indicator migration decision.

## Answer

Settled via grilling (ticket 01's "always visible" decision reconfirmed, not reopened):

- **Shape/visibility**: enemies use the exact same icon+bar Resource indicator as the player's Health indicator — always visible/constantly playing, never damage-only.
- **Particle budget**: a smaller fixed budget than the player's (~5-6 particles at full health vs. the player's 20), applied uniformly regardless of live enemy count — no count-based throttling. Simpler to implement (one constant) and more legible at scale (up to `MAX_ENEMIES :: 24` concurrent) than a dense per-enemy effect would be, independent of raw performance cost.
- **Color**: enemies lerp within a red-only range (bright red at full `ENEMY_MAX_HEALTH :: 50`, fading toward dark/desaturated red near death) rather than the player's green-to-red `HUD_HEALTHY_COLOR`/`HUD_CRITICAL_COLOR` lerp — so color alone reliably signals friend vs. foe now that both share the same shape. Replaces today's flat hardcoded black-background/red-fill `draw_health_bar`.

**Domain-modeling check**: no `CONTEXT.md` update needed — this decision is implementation detail (specific particle counts, specific color values) layered onto the already-recorded **Resource indicator** entry, not new domain vocabulary.

**This was the map's last ticket.** The destination's spec is complete. Recorded as [ADR-0011](../../../docs/adr/0011-in-game-hud-moves-to-world-space-resource-indicators.md), summarizing the full HUD-to-Resource-indicator migration decision across all three tickets.
