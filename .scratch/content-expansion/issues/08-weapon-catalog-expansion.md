# Weapon catalog expansion

Type: grilling
Status: resolved

## Question

Which weapons get added, and to which ladders?

Eight `Weapon_Kind`s exist across three families — Ranged (Pistol, SMG, Shotgun), Melee (Dagger, Sword), Magic (Fire_Wand, Flame_Staff, Poison_Staff). Melee is the acknowledged gap: its two entries carry an in-code comment calling them "placeholder melee content... real tier-ladder naming/stats for Melee are still content-authoring for a later ticket", and [Shop and upgrades](../../shop-and-upgrades/map.md) still lists "Concrete named Melee tier-ladder content and Magic tier-ladder numeric stats" as open fog. This ticket graduates that.

To settle, per weapon:

- **Which family and which rung of its tier ladder**, remembering the ladder is strictly sequential and destructive — buying a tier equips it and discards the previous weapon outright, with no owned set and no switching back.
- **The niche it fills** against the enemy roster from [Enemy catalog](04-enemy-catalog.md). A weapon is an answer to something; a tier that is strictly better than its predecessor at everything is a stat bump wearing a name.
- **`fire_mode`**, which is not a free choice: it alone decides whether the weapon gets a **Windup** (`Semi_Automatic`) or a **Follow-through** (`Automatic`) — never both ([ADR-0003](../../../docs/adr/0003-windup-and-follow-through-are-weapon-level.md)).
- **`damage`, `action_rate`, `windup_fraction` / `follow_through_time`**, plus family-specific state (clip/reserve/reload for Gun, range and arc for Melee_Weapon, `Spell_Kind` for Magic — a new Magic tier means a new spell, since each Magic tier is a distinct spell rather than a numeric upgrade).
- **Silhouette geometry.** [ADR-0018](../../../docs/adr/0018-weapon-visual-identity-is-per-kind-not-per-family.md) requires per-kind geometry, authored once in unit space and adapted to both the icon slot and the world, derived from `kind` at draw time and **never stored on `Weapon`** (it serializes into the save file). Distinctions must be **countable** — one barrel vs. two, one orb vs. three — never proportional, because a 20px rod and a 24px rod are indistinguishable with nothing alongside them.
- **Whether a fourth family is warranted at all**, or whether the three existing ladders simply get deeper.

Note what stays fixed: Shop prices and per-Upgrade curves are already standing fog on the shop map and are balance work, not a decision here.

Blocked by [Enemy catalog](04-enemy-catalog.md).

Unblocked: [Enemy catalog](04-enemy-catalog.md) is resolved, and it hands this ticket the target spread the weapons are judged against.

- **The roster spans 20 to ~220 health**, from the 16px Mite to the Warden. The eight current weapons were tuned against a single 50-health enemy, so nothing in `weapon_presets` has ever had to distinguish crowd-clearing from single-target damage — and now both ends exist at once. Rung 4 is authored at **150-250 concurrent bodies**, which is where a weapon that hits one thing at a time stops being a choice and starts being a losing one.
- **Two weapons are labelled placeholders in their own source comment**, and that is this map's Destination calling them out. The Magic tier ladder's numeric stats and concrete named Melee tier-ladder content are the foreign fog item this ticket graduates from [Shop and upgrades](../../shop-and-upgrades/map.md).
- **[ADR-0018](../../../docs/adr/0018-weapon-visual-identity-is-per-kind-not-per-family.md) governs any new weapon**: per-kind geometry authored once in unit space, derived from `kind` at draw time, never stored on `Weapon`, with distinctions that are countable rather than proportional.
- **The enemy roster deliberately did not reserve a weapon answer for itself.** No kind is authored as "the one only AoE beats" — the Mite swarm is a crowd because it is cheap and numerous, not because it is armoured against single-target fire. Whether the weapon ladder should have a hard crowd-clear/single-target split, or stay a smooth ramp, is open here rather than pre-decided by the catalog.

## Answer

**Twelve weapons: the three families stay, each goes four tiers deep, and tier 0 becomes the only free pick.** Each tier is a distinct style rather than a rung of one — generally stronger, but with real situational edges, so a purchase is a decision and not a no-brainer. Two things outgrew the catalog: **melee hit detection stops being a cone from the player's centre** (graduated to [Weapon hit volumes](12-weapon-hit-volumes.md)), and **`Clip_Size`'s Additive effect shape is wrong**, amending [Shop and upgrades](../../shop-and-upgrades/map.md).

### The roster

Family grammars, unchanged and now load-bearing: **Ranged is an aimed line, Melee is an arc around you, Magic is an area you place.**

| Family | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| Ranged | Pistol | SMG | Shotgun | **Rifle** |
| Melee | Dagger | Sword | **Spear** | **Greatsword** |
| Magic | Fire Wand | Flame Staff | Poison Staff | **Lightning Staff** |

- **Rifle** — `Semi_Automatic`, slow, small clip, one shot passing through a whole line of bodies. Ranged's crowd answer.
- **Spear** — long and thin. Maximum standoff on one bearing; punches *into* a crowd without entering it.
- **Greatsword** — long and broad. Clears a wide swathe at moderate standoff. Melee's crowd answer is **space**, not targets: it already sweeps every body in reach with no cap, so its rung-4 problem was never throughput, it was having to stand in the crowd to use it.
- **Lightning Staff** — `Spell_Kind` grows to four: an **instant hitscan bolt**, single target, no area at all.

Numbers stay placeholder content-authoring, the deferral every prior ticket on this map made, with two exceptions called out under **The numbers that are not free** below.

### Settled

- **Run_Start offers tier 0 only — three buttons, one per family.** `weapon_family_kinds` was being read two ways: as the priced ladder ([shop.odin:12](../../../shop.odin)) and as the Run_Start menu ([hud.odin:980](../../../hud.odin)), which listed *every* kind. So Shotgun cost 0 Gold and arrived at Ranged tier 2 with `weapon_next_tier` returning nil — the Shop's weapon slot dead for the whole Run — while Pistol cost 390 Gold to reach the same place. The code already disagreed with itself: `shop.odin:9` asserts "tier 0 is always the family's starting weapon, equipped for free when picked on the Run_Start screen", [ADR-0008](../../../docs/adr/0008-weapon-family-is-run-scoped.md) says "any of the 8". At twelve weapons the free menu would have been twelve buttons, four of them the paid destinations of the other eight. [ADR-0008](../../../docs/adr/0008-weapon-family-is-run-scoped.md) is amended, not reversed — its subject was retiring the *permanent* Class lock, and "any of the 8" rode along unexamined. Family stays Run-scoped and re-picked every Run.
- **Three families, four tiers each. No fourth family.** A fourth costs a fourth family-gated `Upgrade_Kind` (today exactly one each), a fourth Run_Start column, and its own silhouette vocabulary — for capability the three grammars already cover. Melee was not even level at two tiers against three.
- **Climbing a tier buys a different style, not a bigger number.** Rejected: the strict power ramp (the ticket's own bar — "a stat bump wearing a name") and the pure sidegrade (irrational at a geometric price of 150/240/384). Also rejected as too mechanical: a fixed damage-up / rate-down ramp, which would make all four tiers of every family the same shape in different clothes. **Each family's top tier answers what its lower tiers cannot** — Ranged buys the crowd, Melee buys distance, Magic buys the boss.
- **The starters are Pistol, Dagger and Fire Wand, and they are now the only free picks.** Each teaches its family's grammar and each is the most forgiving weapon of its family, which is what a free starter has to be.
- **Dagger and Sword keep tiers 0 and 1; their placeholder comment goes, not the weapons.** They are already correctly shaped — more per swing, fewer swings, longer reach, with Sword picking up the Windup that Dagger's `Automatic` mode structurally cannot have ([ADR-0003](../../../docs/adr/0003-windup-and-follow-through-are-weapon-level.md)). The label was about stats never being authored, not about the shape being wrong.
- **No `fire_mode` rule.** The existing Semi/Auto/Semi in both Ranged and Magic is coincidence, not convention, and no constraint is placed on the top tier either. `fire_mode` follows what each weapon does. The observed outcome is that `Automatic` lands low in every ladder — SMG, Dagger, Flame Staff — because it is the mode with no commitment to express, but that is a result, not a rule to author against.
- **Ranged's crowd answer is piercing, not an explosion.** A grenade launcher would be Fire Wand with a magazine; a line that keeps going is the family's own identity. Melee and Magic already loop every enemy with no cap (`try_swing_melee`, `cast_flamethrower_tick`, `explode_bullet`, the poison cloud), so **Ranged was the only family strictly locked out of rung 4** — every Gun bullet does `hit = true; break` at [bullet.odin:126](../../../bullet.odin) — and Pistol is the first button on the screen.
- **A pierce is tracked by shot identity, not target identity.** A bullet at 400 speed covers ~6.7px/frame against a 24px body, so it re-hits the same enemy for three or four frames; it needs memory. Remembering enemy *indices* is unsafe because `apply_hit_to_enemy` does `unordered_remove`, swapping an unrelated enemy into the recorded slot — certain at swarm density. Remembering *positions* is no better, and a per-hit refractory timer would make pierce depth depend on projectile speed, so an Action Rate upgrade would silently change how many bodies a shot passes through. **`Bullet.id` from a monotonic counter, `Enemy.last_hit_bullet_id` on the enemy, one `u32` compare.** Index and position churn both become irrelevant: a removed enemy takes its field with it and a swapped-in enemy carries its own correct value. Each shotgun pellet is its own `Bullet`, so pellets pierce independently for free. `pierce_count` lives on `Gun` beside `pellet_count`/`spread_angle` — fields only one weapon uses — and defaults to 0, which is exactly today's behaviour.
- **The Lightning Staff is instant, and that is what stops it being a Pistol.** A single-target magic projectile with no area *is* a gun shot — `Bullet` with `explosion_radius = 0` is literally what `fire_pellets` spawns. Hitscan is a property nothing else in the game has: every Gun and the Fireball send a travelling `Bullet`. It is also the right anti-boss property — you cannot mis-lead a target, only mis-commit through the Windup. The name is picked for that reason rather than flavour: lightning is instantaneous in everyone's intuition, so the fiction teaches the mechanic.
- **`reserve_ammo` is declared dead.** `WEAPON_STARTING_RESERVE_CLIPS :: 69420` means it never depletes, so **Gun tiers author `clip_size` and `reload_time` and nothing else** — a reload is a real 1.2–2.2s interruption, a reserve is not. Depleting ammo is a scarcity mechanic the game does not otherwise have, and at 150–250 bodies a 1-in-12 Ammo drop would make it self-solving noise. The consequence is that **the Ammo pickup is a no-op occupying a third of every pickup roll** ([pickup.odin:107](../../../pickup.odin)) — handed to [Content-scale integration sweep](09-content-scale-integration-sweep.md).
- **`Clip_Size` becomes `Multiplicative`.** `Additive(2)` x 10 stacks is a flat **+20 rounds**: +67% on the SMG's 30, **+333% on the Shotgun's 6 today**, and it would be +500% on a small-clip Rifle. It is the only Additive Upgrade whose base varies fivefold across the weapons it gates — Max_Health's base is uniform, Arc_Width and Range sit in narrow bands. This fixes a distortion that already exists rather than one the Rifle would introduce, and it matches Damage, Action_Rate and Move_Speed. **Amends [Shop and upgrades](../../shop-and-upgrades/map.md)'s [Upgrade catalog contents](../../shop-and-upgrades/issues/01-upgrade-catalog-contents.md)**, which left prices and caps as fog but locked effect *shape* as decided.
- **`Melee_Weapon` collapses to a single size field, and `Arc_Width` upgrades that size.** Once the hit volume is the weapon's own collider, `arc_degrees` is redundant with the drawn geometry — the swing path is animation and the coverage is the blade. So there is no separate arc field to upgrade: the Melee family Upgrade scales the weapon, and a bigger weapon sweeps more ground because it physically does. Its `Upgrade_Kind` name should follow the semantics rather than keep describing a deleted field. This also means **the hit volume is derived from `kind` at hit time exactly as the silhouette is derived at draw time** — never stored on `Weapon`, which is [ADR-0018](../../../docs/adr/0018-weapon-visual-identity-is-per-kind-not-per-family.md)'s rule reaching gameplay instead of only art.
- **Flame Staff comes along, as a different shape rather than the same fix.** [weapon.odin:792](../../../weapon.odin) builds `cone := Melee_Weapon{range, arc_degrees}` and calls `enemy_in_melee_arc` — the Flamethrower is a melee arc check wearing a spell's name. Its collider is the *emitted flame*: same principle (what you can see is what hits) from the other side. What goes away is one helper standing in for two different things.
- **Poison Staff's icon is redrawn, and the reason is an existing [ADR-0018](../../../docs/adr/0018-weapon-visual-identity-is-per-kind-not-per-family.md) violation.** [icon.odin:316](../../../icon.odin) and [icon.odin:325](../../../icon.odin) both draw an orb plus two smaller discs; they are **countably identical**, separated only by colour and hundredths of placement — exactly the proportional-not-countable distinction the ADR rules out. Poison Staff goes to three trailing dots against Flame Staff's two.
- **Each family gains one new countable axis rather than more of the same mark.** Gun gets a **stock** (a bar behind the grip) for the Rifle. Melee gets **haft length and blade count** — the Spear a long haft with a short head, the Greatsword a double-width blade. Magic gets **zero orbs** for the Lightning Staff, a bare faceted tip: the cleanest countable inversion available, and it reads instantly as the one that is not throwing an area.

### The numbers that are not free

Balance is standing fog, but two numbers are pinned by something outside the catalog:

- **The Lightning Staff's damage, against the Warden's ~220 health.** Current single-target output is 40–120 DPS across the whole roster of eight, and the `Damage` upgrade is `Multiplicative(1.15)` to 10 stacks — **4.05x**. A boss with three phases on health thresholds ([Boss model](05-boss-model.md)) and a 0.55s reference Tell ([Boss telegraph and phase feel](06-boss-telegraph-and-phase-feel.md)) needs the fight to last long enough for the Tell read to matter at all. Magic's top tier exists to threaten that fight; it must not end it before the second phase.
- **Nothing in the catalog may be answered later by raising enemy health.** `enemy_body_size` is `clamp(10 + 0.28 x max_health, 10, ENEMY_SIZE_MAX)` ([main.odin:841](../../../main.odin)), so below the clamp **health is the silhouette**. A stronger weapon tier cannot be balanced by making ordinary enemies tankier without making every one of them visibly bigger — and [Elite and affix tier](10-elite-and-affix-tier.md) already fixed the heavy ceiling at ~136 health for collision-inflation reasons. Weapon damage is the free variable; enemy health is not.

### Not decided here

- **Prices, damage, action rates, windup fractions, clip sizes and reach values.** Balance, as on every ticket of this map.
- **How a weapon's collider is actually tested** — swept once at Resolve, or continuously across the swing animation. [Weapon hit volumes](12-weapon-hit-volumes.md).

### Follow-on

- **[Weapon hit volumes](12-weapon-hit-volumes.md)** is new and unblocked: the machinery this roster is unauthorable without. Spear-versus-Greatsword under a cone test is two numbers; under a collider it is two shapes.
- **[Content-scale integration sweep](09-content-scale-integration-sweep.md)** takes the dead Ammo pickup, the Run_Start screen's collapse to three buttons, `Melee_Weapon`'s field removal and its save shape, the `Clip_Size` effect-shape change, the twelve icons, and `Bullet.id`/`Enemy.last_hit_bullet_id`.
- **[Shop and upgrades](../../shop-and-upgrades/map.md)** loses its "Concrete named Melee tier-ladder content and Magic tier-ladder numeric stats" fog item to this ticket, and gains an amendment pointer for `Clip_Size` and the Melee Upgrade's re-aim. Its open question about retiring the dev LEFT/RIGHT weapon-cycle hotkey sharpens: that hotkey is now the **only** way to reach a non-tier-0 weapon without paying.
