# Weapon hit volumes

Type: prototype

Status: resolved

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

## Answer

**The hit volume is the drawn blade, live across the swing, and the cone is deleted.**

Prototype: [`12-weapon-hit-volumes.html`](../prototypes/12-weapon-hit-volumes.html), also on branch `prototype/weapon-hit-volumes`. It runs the live `enemy_in_melee_arc` alongside a swept-blade volume and a per-frame blade test, against a crowd you can stand in, with Dagger and Sword at their real numbers and Spear and Greatsword as proposals.

### What the bench showed

Two of the ticket's complaints turned out to be sharper than written.

**The blade is at one extreme of the cone on the frame the damage lands.** `draw_weapon` starts its swing at `sword_swing_offset(arc, 0)`, which is `-arc/2`: a Sword resolves with its blade drawn back at **-55 degrees** while the cone has already killed everything at +55. A Dagger is the same at -35. The sweep the player is watching is not the attack — it is the animation that plays *after* the attack, and its first frame points away from most of what just died.

**The cone and the blade do not even share an origin.** `enemy_in_melee_arc` measures from `origin`, the player's feet anchor. `draw_weapon` and `weapon_muzzle_position` both work from `weapon_pivot_position` — chest height, `ACTOR_SIZE.y / 2` above the feet. They are **12px apart**, and `weapon.odin`'s own comment states the separation as a deliberate safety property: "Gameplay hit-checks deliberately keep using `origin`, so moving the visuals never quietly changes reach." That reasoning inverts the moment the volume *is* the visual.

### Settled

- **Continuous, not swept.** The blade is re-tested every frame while the swing runs. A swept volume resolved once keeps the instant model but re-tells the same lie more quietly: a body at the far end of the sweep still dies on the first frame, before the blade arrives. Continuous is the only model where the drawn blade and the hit are the same object, which is the entire complaint.
- **The hit volume is an arbitrary set of colliders per `Weapon_Kind`**, authored as polygons in the glyph's own unit space — not one shape. Dagger, Sword and Greatsword each need exactly one (the blade triangle), but a Spear may want a head and a haft authored separately, and nothing in the machinery should assume a single volume. The **guard, hilt and pommel carry no collider**: they are the part in the player's hand, and a volume there means hitting things behind you at the start of a sweep.
- **The set lives in a parallel per-kind table, kept honest by a test.** `weapon_icon_reach` is already exactly this — a per-kind table beside `weapon_icons`, with `icon_test.odin` asserting the tip lands where it claims. Having the icon procs emit their own colliders is the pure answer and would cost rewriting every glyph into data to buy a guarantee an assertion already gives. The test asserts each polygon's points lie inside what the glyph draws.
- **The set is rigid.** Every polygon rides the same pivot frame at the same angle, exactly as the glyph does. A collider with its own motion is a second animation system.
- **The volume hangs off the pivot, not the feet.** This retires melee's last use of `origin` and the comment quoted above with it. Reach moves 12px up the screen, which is a real retune of every melee `range` against a body's top edge, not a free correction.
- **A body is damaged once per swing, whatever touched it** — the swing is the event, the polygons are how it is described. Per-collider damage would make "author a second collider" silently mean "double this weapon's damage against small bodies".
- **Swing identity gets its own counter and its own field**, rather than sharing [Weapon catalog expansion](08-weapon-catalog-expansion.md)'s `Bullet.id` / `Enemy.last_hit_bullet_id`. The mechanism is copied; the id space is not. A player able to switch weapons mid-Run would give bullets and swings independent lifetimes, and one shared counter couples two things that have no reason to be coupled.
- **The blade is tested across the gap between frames, not only at each frame's pose.** A Greatsword crosses its full arc in `SWORD_SWING_OUT_TIME` (0.07s) — about four frames at 60fps, front-loaded by `ease_out_cubic`, so the opening frame moves the tip **50-90px**. A 16px Mite standing between two samples is touched by nothing at all. Each collider tests the volume between its previous and current pose. Sub-stepping the swing fixes the same bug by doing the same work several times; the between-poses sweep costs one extra polygon per collider per frame. Note the shape of this: the swept model returns, but per frame rather than per swing, which is the version that does not lie.
- **The swing arc becomes per-kind, on `Weapon_Visual`.** `arc_degrees` is deleted from `Melee_Weapon`, which leaves `sword_swing_offset`, the Windup pullback and the Follow-through sweep with no source. `Weapon_Visual` is already the per-kind, derived-from-`kind`, never-stored-on-`Weapon` home [ADR-0018](../../../docs/adr/0018-weapon-visual-identity-is-per-kind-not-per-family.md) built, and `Melee_Weapon` keeps exactly one field as this ticket required. The consequence is stated rather than hidden: **`Weapon_Visual` stops being cosmetic-only**. What it buys is that **an arc near zero is a thrust, not a broken sweep** — a Spear plants a static volume along the aim line for its whole window with no new machinery. One mechanism, two feels.
- **A blade's tip is a point, and that is allowed to stay.** The triangle is broad at the guard and pointed at the tip, so every blade is narrowest exactly where it reaches furthest — precise on a Spear, potentially whiffy. A minimum collider width is the rejected capsule proxy sneaking back in under another name, and tip width is already an authored number. If it whiffs, widen the Spear.
- **`Melee.attack_range` becomes surface-to-surface** — both half-extents subtracted, as `enemy_in_melee_arc` already does with `enemy_radius`. This fixes [Enemy catalog](04-enemy-catalog.md)'s finding that a 46px Breaker with the uniform `attack_range = 10` cannot reach the player at all. Enemies get **no** hit volumes: they have no drawn weapon, so there is no disagreement between visual and hit-check for a collider to fix. If an enemy ever gains a drawn weapon, the principle applies to it unchanged.
- **The cone survives, as the flamethrower's own.** `cast_flamethrower_tick` builds a `Melee_Weapon` out of its own range/arc to borrow `enemy_in_melee_arc`; that borrowing ends with the field. The cone test was never wrong in general — it was wrong for *blades*, which are thin things pretending to be wedges. An emitted flame really is a spreading wedge, so the helper moves to the Magic side and the Flame Staff keeps the shape it always had.
- **Melee stays out of the F8 `weapon_visual_scale` slider, for the opposite reason to today's.** The comment excludes it because scaling a blade "would decouple its drawn length from the reach it is reporting". After this they are one quantity, so the slider would be a live reach cheat rather than a silhouette tool. The comment is rewritten, not deleted — as written it stops being true the moment this lands, and would read as licence to include melee.

### The window that was hiding in the renderer

Continuous testing needs an active window, and the ticket assumed `Weapon_readiness` has nowhere to express one. It half does, in the wrong file. A Semi-Automatic melee weapon's swing window is reconstructed **inside `draw_weapon`** from cooldown arithmetic — `time_since_resolve := (cycle - windup_duration) - cooldown_timer` ([main.odin:1246](../../../main.odin)) — while `follow_through_time` is documented as Automatic-only and "purely cosmetic: never gates re-triggering or the hit-check".

**`follow_through_time` carries both fire modes.** Semi-Automatic melee sets it at Resolve exactly as Automatic does; `draw_weapon`'s cooldown arithmetic is deleted; the animation and the hit-check read one timer. Reintroducing a `swing_timer`/`swing_time` pair would restore precisely what `follow_through_time` was generalized *from*. [ADR-0004](../../../docs/adr/0004-windup-fraction-not-duration.md) protects `windup_fraction`'s proportionality and is untouched — Follow-through has always been a fixed duration, and it is only its *cosmetic* status that ends here.

This breaks a rule stated in three places: Fire mode is no longer "the sole gate deciding whether a weapon Windups or gets a Follow-through instead", and Windup and Follow-through are no longer mutually exclusive per weapon. A Sword has both.

### Two things that outgrew the ticket

- **`Arc_Width` is Melee's only family Upgrade slot, and it scales the deleted field** ([upgrade.odin:161](../../../upgrade.odin)). It **repoints to `range` and is renamed "Reach"**. Scaling `range` scales `weapon_world_frame_size`, so the blade grows and its volume grows with it, honestly; scaling the arc instead sweeps the same volume faster and buys nothing under a blade collider. The rename is not cosmetic — a name outliving its mechanism is how a retired concept walks back in, which is the rule [Elite and affix tier](10-elite-and-affix-tier.md) already wrote down for "Elite".
- **The tunnelling gap is not melee-specific in principle**, but it is in practice: nothing else in the game moves a hit volume. Bullets travel, but `Bullet` is a point tested against bodies each frame at up to 500 px/s, which at 60fps is 8px a frame against a 16px Mite. It survives. A Greatsword tip at 50-90px a frame does not.

### Not decided here

Blade widths, tip widths, the per-kind swing arcs, and the four melee weapons' `range` values are balance numbers, and they join the map's existing balance fog. The Spear's tip width is now a **named** exception there, in the same class as the Breaker's health against the inflation envelope: it is the one number whose being wrong looks like broken machinery rather than a weak weapon.

### Follow-on

[Content-scale integration sweep](09-content-scale-integration-sweep.md) picks up the deletion and repointing inventory. It is now unblocked — this was the last ticket standing in front of it.
