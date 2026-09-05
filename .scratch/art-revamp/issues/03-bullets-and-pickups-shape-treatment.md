Type: grilling
Status: resolved
Blocked by: 01

## Question

What shapes/colors represent player bullets, enemy bullets, and the Heart/Ammo pickups once sprites are dropped, applying the vocabulary [01-actor-shape-and-movement-transform](01-actor-shape-and-movement-transform.md) establishes?

Bullets currently rotate to velocity via `rl.DrawTexturePro` (`draw_bullets`/`draw_enemy_bullets`, main.odin:830-852) — decide the shape equivalent (e.g. an elongated rect/triangle) that preserves readable direction-of-travel at a glance, and stays visually distinct between player and enemy bullets. Pickups need to stay distinguishable from each other and from the Gold pickup, which is already a plain circle (pickup.odin:98-110) — confirm Heart/Ammo's new shapes don't collide with that existing vocabulary.

## Answer

**Bullets**: reuse ticket 02's streak shape (a thin oriented line, velocity-aligned) rather than inventing a new primitive — free, already validated as legible, and gives visual continuity between a weapon's muzzle flash and the bullet it launches. Colors carry over unchanged from today's tint: player = gold/yellow (`BULLET_TRAIL_COLOR`-ish), enemy = red.

**Fireball bullets** (`Bullet.explosion_radius > 0`): get a distinct *shape*, not just today's distinct trail color (`FIREBALL_TRAIL_COLOR`, orange) — a thicker, rounder streak with a small tapered tail ("comet"), so "this one explodes" reads at a glance rather than only on close color inspection. Plain bullets stay a thin streak.

**Pickups**: Gold is unchanged — it already has no sprite (plain circle, `GOLD` color, radius 5) and stays the anchor the other two are chosen not to collide with. **Health = a plus/cross** (two overlapping short rects) — a standard, unambiguous health glyph built from plain rectangles. **Ammo = a small cluster of 2-3 short parallel bars** ("stacked cartridges") — distinct from the cross, from Gold's circle, and from a single bullet-streak in flight; thematically tied to what it refills. Triangle was explicitly avoided for Ammo (collision risk with Swarmer/Sword on a busy screen).

This completes the shape catalog for every in-scope entity: rect (Player/Grounded), circle (Floater/Gold), triangle (Swarmer/Sword), rod (Gun), rod+orb (Magic), streak (bullets/muzzle effects), comet (explosive bullets), cross (Health), stacked-bars (Ammo) — no two entity categories share both the same shape *and* a colliding context.

## Amendment (Shape-vocabulary consistency pass)

This ticket settled Health/Ammo *shapes* but left colors unspecified. [Shape-vocabulary consistency pass](05-shape-vocabulary-consistency-pass.md) closed that gap while reviewing the whole palette: **Health = warm red/pink**, **Ammo = light gray/silver** (echoing the weapon-metal tone already used for Gun/Melee/Magic bodies).
