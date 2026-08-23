Type: grilling
Blocked by: 02, 03, 04
Status: resolved

## Question

What does the HUD need to display per weapon type — Gun keeps today's ammo/reload bar unchanged, Melee needs a swing-cooldown indicator, Magic needs a cast-cooldown indicator — and what does `draw_weapon` (main.odin) need at a requirements level for each type's on-screen representation (e.g. melee needs a swing rotation, magic needs a cast-moment effect)?

**Scope added 2026-08-23** (map destination redraw, see [ADR-0002](../../../docs/adr/0002-class-locked-weapon-acquisition.md) and tickets [08](08-class-selection-mechanics.md)/[09](09-gold-pickup-mechanism.md)/[10](10-weapon-shop-and-tier-ladder.md)): this ticket now also needs to cover —
- The `Class_Select` screen's requirements (one option per Class — Melee/Magic/Ranged).
- A persistent Gold counter/readout in the main HUD (alongside the existing ammo/health display).
- The on-demand Shop panel's requirements (showing the next tier up, its cost, and whether the player can currently afford it).

Capture this as requirements for a later implementation/art pass, not full animation-curve or sprite design (that's fogged on the map).

## Answer

Locked via grilling (2026-08-23):

**HUD row 3 switches on `weapon.variant`**, mirroring the conditional-dispatch precedent ticket 06 just set for the level-up UI. Gun keeps today's exact ammo/reload row unchanged (clip fraction, `+{reserve_ammo}` text, orange while reloading, red when empty). Melee/Magic replace it with a cooldown-readiness row using the same `draw_hud_icon_row` widget: fraction = `1 - cooldown_timer/(1.0/action_rate)` (0 = just acted, 1 = ready to act again), icon = `weapon_texture_names[weapon.kind]` (the weapon's own icon — no new asset needed), no trailing text (no reserve-ammo equivalent).

**Gold: a separate corner readout, not a 4th bar-stack row.** A small icon + plain number in a screen corner (e.g. top-right), away from the bottom-center fraction-bar stack. Gold has no "max," so rendering it as a fill bar would misrepresent an ever-growing count as "how full."

**`draw_weapon` requirements, triggered by `try_use_weapon`'s existing "acted" signal** (the same point it sets `cooldown_timer`):
- **Melee**: the on-screen sprite plays a brief cosmetic rotation sweep across the arc (`-arc_degrees/2` to `+arc_degrees/2` around `aim_dir`) over `swing_time`, then returns to resting facing `aim_dir`. Purely visual — ticket 03's hit already resolved instantly before this plays, so nothing gates on it.
- **Magic**: a brief particle-based cue fires at the cast origin, reusing the existing particle system (`particle.odin`). Requirement is only that *some* readable on-screen moment happens exactly when a cast succeeds — exact particle look/color/shape stays fog until real spell effects exist (ticket 04).

**Shop panel's max-tier state:** when the player's current weapon is already the top tier of their Class's ladder, the Shop shows a disabled "Fully Upgraded" state in place of a buy option. What (if anything) Gold does once a Class is maxed is new fog, not solved here — nothing in ticket 10's scope calls for a use beyond the ladder.

**`Class_Select` content:** each of the three options shows a label (Class name) plus a short one-line playstyle description, matching the terse style of "Level Up! - choose an upgrade." No starting-weapon icon requirement yet — two of the three Classes (Melee, Magic) have no concrete named `Weapon_Kind` content to show an icon of yet (already-tracked fog).
