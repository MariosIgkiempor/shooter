# Shooter

A top-down twin-stick shooter (Odin + raylib). Single global `game` struct, free-function updates (`update_x`/`draw_x`), enums + `[Enum]T` preset tables as the standing idiom for per-kind data.

## Language

**Weapon**:
The player's single currently-equipped combat tool. Common state (kind, fire mode, damage, action rate, cooldown) lives directly on it; type-specific state lives in one of `Gun`, `Melee_Weapon`, or `Magic` behind its `variant` field. See [ADR-0001](docs/adr/0001-weapon-wrapper-struct.md) for why this differs in shape from `Enemy`'s `Movement_Style`/`Attack_Style` bare unions.
_Avoid_: Loadout, armament

**Gun** / **Melee_Weapon** / **Magic**:
The three concrete `Weapon` variants. Gun keeps the clip/reserve/reload ranged-firing mechanic; Melee_Weapon and Magic are cooldown-only (no stamina/mana economy). Which `Weapon_Kind`s belong to which Class is a separate lookup table — see **Class**.

**Action rate**:
The generic "actions per second" cadence shared by all weapon types — firing (Gun), swinging (Melee_Weapon), casting (Magic). Gates how often `cooldown_timer` lets a weapon act again. **Windup** (when present) is carved out of the front of this same cycle as a proportional slice, not added on top — Action rate stays the true pace of a weapon regardless of whether it Windups, and regardless of how much `action_rate` has grown from upgrades.
_Avoid_: Fire rate (Gun-specific predecessor term, now only correct when talking about Gun specifically)

**Fire mode**:
Whether a weapon's action re-triggers repeatedly while its input is held (`Automatic`) or once per press (`Semi_Automatic`). Applies generically across all three weapon types, not just Gun. Also the sole gate deciding whether a weapon Windups (`Semi_Automatic` only) or gets a Follow-through instead (`Automatic` only) — see **Windup**.

**Trigger**:
The player input event that starts a weapon's action cycle — a press for `Semi_Automatic`, each re-fire tick while held for `Automatic`. Distinct from **Resolve** now that `Windup` can delay the effect after the Trigger; the two were interchangeable before Windup existed, since every weapon acted instantly on Trigger.

**Windup**:
The visible telegraph phase a `Semi_Automatic` weapon shows before it acts, sized by the common `Weapon.windup_fraction` preset (0..1, the portion of the weapon's cycle Windup occupies) and driven at runtime by `windup_timer`. Nested inside the weapon's existing cooldown window (see **Action rate**) as a proportional slice, not an absolute duration — expressing it as a fraction of `1/action_rate` rather than fixed seconds means it stays nested automatically no matter how much `action_rate` has grown from upgrades, with no clamping needed anywhere. Once started, a Windup always completes into **Resolve** — it cannot be cancelled by releasing the trigger early. Aim keeps tracking the mouse live throughout for anything aiming along `aim_dir` (Gun, Melee_Weapon, Fireball, Flamethrower), so the action resolves toward wherever the player is aiming the instant Windup completes, against whatever's actually in range then (it may whiff if the target moved or died) — but a **ground-targeted** cast (Poison_Cloud) is the opposite: its target locks at Trigger and does not track the mouse through Windup at all, see ADR-0005. Mutually exclusive per weapon with **Follow-through**: a weapon shows one or the other, gated by Fire mode, never both — Windup-gated weapons go straight from Resolve to Ready, no separate flourish after.
_Avoid_: Charge, telegraph alone (telegraph is the effect Windup produces, not the name of the mechanic), windup_time (retired name — Windup is a fraction of the cycle, not a fixed duration; contrast with Follow-through, which is a fixed duration since it has no equivalent invariant to protect)

**Resolve**:
The instant a weapon's actual effect executes — the bullet spawns, the hit-check runs, the spell casts. For `Automatic` weapons this happens immediately on **Trigger**, same as before Windup existed. For `Semi_Automatic` (Windup-gated) weapons it happens `windup_fraction / action_rate` seconds after Trigger — recomputed fresh at Trigger time from whatever `action_rate` is at that moment — once **Windup** completes.

**Follow-through**:
The visible cosmetic phase an `Automatic` weapon shows after Resolve, timed by the common `Weapon.follow_through_time`/`follow_through_timer` fields — the generalized, Weapon-level successor to Melee_Weapon's old `swing_time`/`swing_timer` (which drove only Dagger/Sword's post-hit sweep). Purely cosmetic: never gates re-triggering (`cooldown_timer` already does that) or the hit-check (already resolved by the time Follow-through plays). Mutually exclusive per weapon with **Windup** — see there for the split.
_Avoid_: Flourish (used while this was still being named; Follow-through is the settled term), swing_time/swing_timer (retired name, now Weapon-level and not Melee-specific)

**Weapon readiness**:
The three mutually-exclusive states a `Weapon` cycles through between actions: **Ready** (`cooldown_timer <= 0`, can Trigger), **Winding Up** (`windup_timer > 0`, Triggered but not yet Resolved), and **Recovering** (`cooldown_timer > 0` but `windup_timer` already 0 — Resolved, or Follow-through playing, but not yet Ready again). A weapon showing Follow-through is always Recovering; a weapon in Winding Up is never Recovering, and vice versa.

**Movement Style**:
An enemy's per-frame steering archetype, held on `Enemy.movement` as its own bare union — how it gets from where it is to where it's going: `Grounded`, ghostly `Floater` drift, or `Swarmer` surround. Orthogonal to **Attack Style**, held separately on `Enemy.attack`: an enemy picks one of each independently. `speed` belongs to Movement Style (each variant carries its own), not Attack Style, since it's a movement trait.
_Avoid_: Behaviour alone

**Grounded**:
The Movement Style variant matching today's only movement: chases along a BFS path over the tilemap, colliding with terrain like the player does. Named for what distinguishes it from `Floater` (collides with terrain, follows the path) rather than for the chasing behaviour itself, since `Swarmer` also closes on the player via a different route.

**Floater**:
The ghostly Movement Style variant: ignores tilemap collision and drifts erratically rather than beelining, unlike `Grounded`. Exact drift mechanics (noise/wobble shape, how strongly it's still pulled toward the player) are this map's Floater movement design ticket.

**Swarmer**:
The Movement Style variant that flanks the player instead of converging with other Swarmers on the same point — a genuinely new surround/flank mechanic, not just `Grounded` movement with tuned-up **Separation**. Exact mechanic is this map's Swarmer surround mechanic ticket.

**Attack Style**:
An enemy's combat archetype, held on `Enemy.attack` as its own bare union, independent of **Movement Style** — `Melee` (contact damage in range), `Ranged` (fires enemy bullets in a distance band), or nil (no attack). Attack Style's `Melee` is unrelated to `Weapon`'s `Melee_Weapon`/player Class:Melee — enemies keep their own separate combat system by design (see the weapon-types map's Out of scope).

**Separation**:
The steering force that pushes enemies of the same Movement Style apart from each other so they don't clump on the same point or path. Layered on top of Movement Style (e.g. blended with the BFS-chase direction), not integrated into pathfinding itself.
_Avoid_: Flocking (the boids term bundles separation with alignment/cohesion, neither of which is in scope)

**Class**:
The player's permanent choice — made once, at game start — of which `Weapon` family they can ever equip: `Melee`, `Magic`, or `Ranged`. `Weapon_Kind` stays the single flat enum from [ADR-0001](docs/adr/0001-weapon-wrapper-struct.md); a separate lookup table buckets its members by Class. See [ADR-0002](docs/adr/0002-class-locked-weapon-acquisition.md) for why acquisition is Class-locked rather than a free cross-type swap.
_Avoid_: Loadout, role, archetype

**Gold**:
Currency earned from enemy kills (a `Pickup_Kind.Gold` drop), spent entirely within the Shop — on the next tier of the player's Class weapon ladder, and on repeatable stat Upgrades. Wholly a Run concept: resets to zero on Restart, unlike Account progression (XP/Level), which survives it.
_Avoid_: Currency, coins, cash

**Shop**:
The on-demand UI panel where the player spends Gold, pausing the game while open. Sells two things: the next `Weapon_Kind` in the Class's Weapon tier ladder, and repeatable Upgrades (general or Class-specific). Opened at the player's discretion, unlike the level-up popup, which only appears on an XP level-up and (see Account progression) no longer sells anything itself.
_Avoid_: Store, market

**Weapon tier ladder**:
The fixed, sequential order of `Weapon_Kind`s a Class progresses through via Shop purchases (e.g. Ranged: Pistol → SMG → Shotgun). Buying the next tier immediately equips it and discards the previous weapon outright — no unlocking a set of owned kinds, no switching back. Purchased Upgrade stacks are tracked separately from the equipped weapon and are unaffected by a tier purchase — see **Upgrade**.
_Avoid_: Rank (Level already names the separate XP-progression concept)

**Upgrade**:
A repeatable Shop purchase that raises one stat by a fixed amount per purchase, at a rising Gold price, up to a hard per-Upgrade stack cap. Either **general** (available regardless of Class — e.g. move speed, max health) or **Class-specific** (gated by the equipped Class's weapon variant — e.g. Melee's arc width). Purchased stacks are Run-scoped but tier-independent: they persist through a Weapon tier purchase, reapplying on top of whichever tier is currently equipped, and only clear on a new Run. Replaces the retired XP-driven `upgrade_weapon` mechanism (see ADR-0006).
_Avoid_: Stat boost, perk, tier (tier is reserved for the Weapon tier ladder's fixed sequence; an Upgrade's stack count is repeatable, not a sequential ladder)

**Run**:
The current attempt at play, bounded by Restart: Gold balance, the equipped `Weapon_Kind`, and every Upgrade's purchased stack count all belong to a Run and reset to their starting values on Restart. Contrast **Account progression**, which survives it.
_Avoid_: Session, game (ambiguous with the global `game` struct), attempt

**Account progression**:
State that survives Restart: XP, Level, and the player's chosen Class. No login/profile system backs this — "Account" is this repo's chosen name for "survives a Restart" against a single local save file, not a literal user account. Reaching a new Level no longer grants an in-Run Upgrade (see ADR-0006): the level-up popup still appears, but only as a Continue-only acknowledgement, reserved for a future Account-progression payoff not yet designed.
_Avoid_: Meta progression, permanent progression

**Map**:
A named, reusable level definition: tile layout, spawner definitions, and a player start position. Stored as its own file under `data/maps/`, and loaded into the game's runtime state at session start. The same struct shape serves both roles — the on-disk file and the live, mutable copy a session plays on — so no separate blueprint/runtime type exists; loading a map copies its data fresh into runtime state, which means in-session mutation (destructible tiles, ticking spawner timers) never touches the file, and reloading the file always resets it.
_Avoid_: Level (already names the player's XP-progression level, see **Weapon tier ladder**), Blueprint, Room (informal — a map may contain multiple rooms, not itself a modeled concept)
