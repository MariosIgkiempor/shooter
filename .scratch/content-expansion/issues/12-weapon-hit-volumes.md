# Weapon hit volumes

Type: prototype

Status: open

## Question

If an enemy is hit only when the weapon itself touches it, what is the weapon's collider and when is it tested?

Graduated from [Weapon catalog expansion](08-weapon-catalog-expansion.md), which settled the principle and found the roster unauthorable without the machinery: Spear-versus-Greatsword under a cone test is two numbers, under a collider it is two genuinely different shapes.

What is already settled and not reopened here:

- **The cone test is retired.** `enemy_in_melee_arc` measures from the *player's centre*, so a Sword hits everything within 60px and 110 degrees regardless of where the blade actually is — while the blade is drawn sweeping over a 0.15s follow-through. The visual and the hit-check have never agreed.
- **`Melee_Weapon` collapses to a single size field**; `arc_degrees` is deleted, and the Melee family Upgrade scales the weapon rather than a separate arc.
- **The hit volume derives from `kind`, never stored on `Weapon`** — [ADR-0018](../../../docs/adr/0018-weapon-visual-identity-is-per-kind-not-per-family.md)'s rule applied to gameplay. `weapon_world_frame_size`'s comment already says a blade's drawn length is "*reporting* its actual reach, not decorating it"; this makes it *be* the reach.
- **The Flame Staff comes along**, with the emitted flame as its volume rather than a borrowed melee helper.

To settle:

- **Swept or continuous.** A hit resolved once at Resolve against the swing's swept volume, or a hit-check re-run per frame across the animation while the blade is live. Continuous makes the swing a temporal event with an active window, which nothing in `Weapon_readiness` currently expresses — Follow-through is documented as "purely cosmetic: never gates re-triggering or the hit-check". Swept keeps the instant model but decouples the hit from the animation the player is watching, which is the complaint that started this.
- **Whether a body can be hit twice by one swing.** [Weapon catalog expansion](08-weapon-catalog-expansion.md) settled the equivalent for piercing shots with a monotonic `Bullet.id` against `Enemy.last_hit_bullet_id`; a swing may want the same mechanism, or may not need one at all if the test is swept.
- **What the collider actually is** — the drawn glyph's geometry, or a simplified proxy (a capsule along the blade). `icon.odin`'s `icon_blade` authors blade length, guard width and pommel in unit space, and `weapon_icon_reach` already says where each kind's business end sits along the glyph.
- **What this does to a 24px player standing in a crowd of 250.** The whole point of the Greatsword is that its sweep buys space; if the collider is thin, it does not.
- **Whether enemy melee follows.** `Melee.attack_range` is centre-to-centre ([enemy.odin:751](../../../enemy.odin)), and [Enemy catalog](04-enemy-catalog.md) already found that a 46px body with the uniform `attack_range = 10` cannot reach the player at all. The same principle would fix it; whether it should is open.

Prototype it — the deciding question is whether a blade that only hits what it touches *feels* better than one that hits a cone, and that is a look-at-it question. Precedent: [Boss telegraph and phase feel](06-boss-telegraph-and-phase-feel.md).
