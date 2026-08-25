# Weapon action feel

Status: ready-for-agent

## Problem Statement

Ranged and magic weapons fire and cast instantly, with zero visual feedback: pulling the Pistol's trigger or casting a Fire_Wand bolt looks and feels identical to a mouse click doing nothing. Melee weapons already feel good — a swing hits instantly, then plays a cosmetic follow-through sweep — but nothing comparable exists for Gun or Magic, so half the game's weapons read as flat and unresponsive despite working correctly.

## Solution

Every weapon gets a consistent action-timing model: Trigger → Windup → Resolve → Follow-through, gated by `Fire_Mode`. `Semi_Automatic` weapons (Pistol, Shotgun, Sword, Fire_Wand, Poison_Staff) get a visible pre-effect Windup that telegraphs the action — nested inside the weapon's existing cooldown window rather than added on top, so it never slows the weapon down. `Automatic` weapons (SMG, Flame_Staff, Dagger) get a lightweight post-effect Follow-through instead (a recoil-kick, a pulse, a sweep), since a discrete windup on every trigger of a rapid-fire weapon would read as sluggish. The result: every weapon feels like it's doing something the instant it's used, without costing any responsiveness.

## User Stories

1. As a player, I want firing my Pistol to show a quick visible windup before the shot goes off, so that shooting feels like a deliberate action rather than an instant, weightless click.
2. As a player, I want firing my Shotgun to show a heavier, longer windup than my Pistol, so that the weapon's power is communicated through its feel, not just its damage number.
3. As a player, I want my SMG to show a recoil-kick after every shot while I hold the trigger, so that spraying bullets feels like it's doing something even though it never slows down to windup.
4. As a player, I want swinging my Sword to show a visible draw-back before the hit lands, so that melee finally has the same anticipation ranged and magic weapons now have.
5. As a player, I want Sword's swing-through to snap forward with an eased, punchy motion rather than a bouncy spring, so that the hit feels solid and controlled rather than floaty.
6. As a player, I want Dagger's existing post-hit sweep to keep working exactly as it does today, so that the one weapon that already felt good isn't disrupted by this change.
7. As a player, I want casting Fire_Wand to show a charge-up glow before the fireball launches, so that casting a spell feels like gathering and releasing energy.
8. As a player, I want casting Poison_Staff to show a telegraph ring at the ground location where the cloud will land, so that I can see exactly where the danger zone is forming before I commit.
9. As a player, I want Poison_Staff's target to lock in the instant I click, not keep following my mouse while it winds up, so that a ground-targeted cast feels like a deliberate placement, not a wobbling reticle.
10. As a player, I want Flame_Staff to show a distinct flame pulse on every tick while I hold it down, so that channeling fire reads clearly even at its very fast tick rate.
11. As a player, I want none of these windups to ever slow down how fast my weapon actually fires compared to today, so that upgrading my weapon's fire rate still feels meaningfully faster, windup and all.
12. As a player, I want a weapon with an empty clip to skip its windup entirely and just start reloading, so that I'm never stuck watching a windup animation play out into nothing.
13. As a player, I want to be able to keep aiming freely with my mouse while a Windup plays (for anything that aims in a direction), so that winding up never feels like it's taken control away from me.
14. As a player, I want to keep moving and strafing freely while any weapon winds up, so that a slower ranged or magic weapon never feels like it roots me in place.
15. As a player, when I've heavily upgraded a weapon's fire rate over a run, I want its windup to keep shrinking right along with its faster cadence, so that a maxed-out weapon never ends up with a windup longer than the time between its shots.
16. As a player, I want every weapon's total time-to-fire-again to stay exactly what it is today (`1/action_rate`), so that this change is purely about how the wait feels, not about making anything slower.
17. As a player, once I've committed to a windup by pressing fire, I want the shot to definitely go off when it completes, so that I never feel like my input was wasted by a windup that fizzled.
18. As a game developer, I want Windup and Follow-through to live as shared fields on the common `Weapon` struct rather than duplicated per weapon-type, so that adding this system doesn't triple the code needed to express one gating rule.
19. As a game developer, I want `Melee_Weapon`'s old `swing_time`/`swing_timer` fields retired in favor of the new shared fields, so that the codebase doesn't carry two competing concepts for the same kind of animation timing.
20. As a game developer, I want Trigger, Windup, Resolve, and Follow-through clearly named and documented in the project's glossary, so that future work on weapon feel has settled vocabulary to build on instead of re-litigating names.
21. As a game developer, I want a clear rule for which weapon-kinds need genuinely new art versus which can get away with animating their existing sprite, so that the art requirements for this feature are scoped precisely rather than assumed blanket.
22. As a game developer, I want automated tests around the Trigger/Windup/Resolve/Follow-through state machine, so that future changes to weapon presets or upgrade math can't silently break the timing invariants this feature depends on.

## Implementation Decisions

- `Weapon` gains four common fields, alongside `kind`/`fire_mode`/`damage`/`action_rate`/`cooldown_timer`: `windup_fraction: f32` (0..1, the proportion of the weapon's cycle Windup occupies — a proportion, not a duration), `windup_timer: f32` (runtime countdown), `follow_through_time: f32` (a fixed duration in seconds), `follow_through_timer: f32` (runtime countdown). These replace `Melee_Weapon`'s old `swing_time`/`swing_timer` entirely.
- Which field a `Weapon_Kind`'s preset sets is determined entirely by its `Fire_Mode`, never chosen per-variant: `Semi_Automatic` weapons (Pistol, Shotgun, Sword, Fire_Wand, Poison_Staff) set `windup_fraction`; `Automatic` weapons (SMG, Flame_Staff, Dagger) set `follow_through_time`. A weapon always shows exactly one of Windup or Follow-through, never both, never neither.
- `windup_timer`'s actual duration in seconds is derived fresh at Trigger time as `windup_fraction / action_rate`, using whatever `action_rate` is at that moment, upgrades included. This keeps Windup nested inside the weapon's `1/action_rate` cooldown window automatically for any amount of `action_rate` growth — no ceiling on upgrades, no clamping logic needed anywhere.
- Control flow: `try_use_weapon(weapon, origin, aim_dir, mouse_world, enemies)` is the Trigger-time entry point. It gates on `cooldown_timer`. For `Semi_Automatic` weapons it only starts the cycle (`cooldown_timer = 1/action_rate`; `windup_timer = windup_fraction/action_rate`) and returns without resolving. For `Automatic` weapons it resolves immediately via `resolve_weapon_action`, unchanged from today's behavior, and starts `follow_through_timer = follow_through_time` if the action succeeded.
- `update_weapon(weapon, dt, origin, aim_dir, mouse_world, enemies)` runs every frame: ticks `cooldown_timer` down as today; ticks `windup_timer` down and, the instant it crosses to ≤0, calls `resolve_weapon_action` with that frame's live values; ticks `follow_through_timer` down (purely cosmetic, no side effect on completion). Its call site in the main loop moves to after that frame's `aim_dir`/`mouse_world`/player position are freshly computed, not before as today, so a Resolve always fires against current-frame aim state.
- `resolve_weapon_action(weapon, origin, aim_dir, mouse_world, enemies) -> bool` is extracted from today's inline variant-dispatch switch in `try_use_weapon` (unchanged calls into `try_fire_gun`/`try_swing_melee`/`try_cast_magic`), made callable from two call sites: `try_use_weapon` directly (Automatic weapons) and `update_weapon` (Semi_Automatic weapons, on Windup completion).
- `enemies` becomes an explicit parameter threaded through this whole call chain, replacing the current direct reads of the global `game.enemies` inside `try_swing_melee`/`cast_flamethrower_tick` — for consistency with `origin`/`aim_dir`/`mouse_world` already being threaded explicitly rather than read from a global.
- `cooldown_timer` and `windup_timer` start together, at Trigger, from the same instant — not staggered. This is what "Windup nested within cooldown" requires structurally.
- Switching the equipped weapon mid-Windup (today's dev/debug cycling, or the future Shop purchase flow) silently abandons any in-flight Windup — `weapon_create` overwrites the `Weapon` struct outright, as it already does today; no special-case guard is added.
- Gun-specific: the ammo-in-clip check gates Windup starting at all, at Trigger time, mirroring `try_fire_gun`'s existing empty-clip check. An empty clip means neither `windup_timer` nor `cooldown_timer` start; `start_reload` runs exactly as it does today; nothing plays. This check and the equivalent one inside `resolve_weapon_action`'s Gun path should share one helper (e.g. `gun_can_fire`) rather than duplicate the condition. `Melee_Weapon` and `Magic` have no equivalent resource gate — their `Semi_Automatic` kinds always start Windup unconditionally on Trigger.
- Aim-tracking during Windup: anything aiming along `aim_dir` (Gun, Melee_Weapon, Fireball, Flamethrower) keeps tracking the live mouse throughout — Resolve fires toward wherever the player is aiming the instant Windup completes, against whatever's actually in range/arc then (may whiff if the target moved or died). **Exception**: Poison_Cloud is ground-targeted, not `aim_dir`-based, and locks its target the instant Windup starts instead of tracking live — `try_use_weapon`'s `Semi_Automatic` path needs one additional variant-aware hook (a no-op for every other weapon/spell) that captures `mouse_world` into the `Magic` variant at Trigger time when `spell_kind == .Poison_Cloud`; `resolve_weapon_action` reads that locked point for Poison_Cloud instead of live `mouse_world`.
- Once started, a Windup always completes into Resolve — there is no cancel-by-releasing-the-trigger-early path.
- Movement is never locked or slowed by an active Windup, for any weapon.
- Per-weapon-kind starting values, validated via prototype (still tunable content-authoring numbers, not final balance):
  - Pistol: `windup_fraction = 0.24`
  - Shotgun: `windup_fraction = 0.26` — reads heavier than Pistol purely because its cycle is ~2.7x longer at a similar fraction; no separate escalation mechanism needed.
  - SMG: `follow_through_time = 45ms`
  - Sword: `windup_fraction = 0.37`. Its Resolve-moment swing-through is a two-phase eased curve — ease-out from the windup's draw-back angle to the follow-through extreme over ~70ms, then ease-out back to neutral over ~110ms — not a physics spring (a spring was prototyped and explicitly rejected as feeling wrong). Derived purely from time-since-Resolve (itself recoverable from `cooldown_timer`), not a new persisted timer field, consistent with "Windup-gated weapons go straight from Resolve to Ready, no separate flourish timer."
  - Dagger: `follow_through_time = 150ms`, carried over unchanged from its current `swing_time`.
  - Fire_Wand: `windup_fraction = 0.21`
  - Poison_Staff: `windup_fraction = 0.18`
  - Flame_Staff: `follow_through_time = 80ms`, rendered as a discrete per-tick pulse (a small flame burst per tick), not a continuous particle stream — a continuous stream was prototyped and read worse at Flame_Staff's 100ms tick rate.
- All eight `Weapon_Kind`s need genuinely new art (sprite frames and/or particle effects). Plain transform-only animation (rotation/offset/scale on existing sprites) was prototyped for every kind and judged to sell the timing but not the "punch" — none were accepted as convincing on their own. Magic in particular has zero existing art today (all three kinds reuse the Pistol icon placeholder) and needs first-time art, not an upgrade to existing art.
- None of the new runtime state (`windup_timer`, `follow_through_timer`, or Poison_Cloud's locked-target field) is persisted — all transient/frame-driven, the same as `cooldown_timer` already is. No `Weapon_Variant_Save` schema change is expected.

## Testing Decisions

- A good test here asserts on external, observable behavior of the weapon state machine: timer-driven phase transitions (Ready / Winding Up / Recovering) and emitted side effects (a bullet spawned, an enemy took damage, a cloud was placed, ammo was consumed) — not on implementation internals that aren't part of the public contract, and not on `draw_weapon()`'s rendering math. Rendering is cosmetic, raylib-dependent, and was validated visually via three interactive prototypes and direct human review during this feature's design, not something to assert on in code.
- Modules under test: `weapon.odin`'s `try_use_weapon`, `update_weapon`, and the new `resolve_weapon_action`, driven directly with controlled `dt` steps — no real game loop, no rendering, no raylib window needed.
- Worth covering concretely:
  - `Semi_Automatic` weapons never resolve before their Windup completes; `Automatic` weapons resolve immediately on Trigger with no Windup ever observed.
  - A completed Windup resolves exactly once, not once per frame it sits at zero.
  - `cooldown_timer` and `windup_timer` start together at Trigger.
  - Total cycle length (`1/action_rate`) is unaffected by whether a weapon Windups.
  - A Gun with `ammo_in_clip == 0` never starts a Windup and never sets `cooldown_timer`.
  - Simulating several stacked `action_rate` upgrades never lets derived windup duration exceed the cooldown window.
  - Switching weapon kind mid-Windup leaves no dangling windup/cooldown state on the new `Weapon`.
  - Poison_Cloud's locked target is unaffected by `mouse_world` changing between Trigger and Resolve, while Fireball/Flamethrower's target does change with `aim_dir`/`mouse_world` between Trigger and Resolve.
- Prior art: none. This repo has no existing `*_test.odin` files and `build.sh` runs no test step. This spec proposes the repo's first tests, using Odin's standard `core:testing` package (`@(test)`-attributed procs in a new `weapon_test.odin`) — the idiomatic mechanism for the language, not a bespoke addition.
- The game holds a single global `game` struct, and `resolve_weapon_action`'s Melee/Magic paths mutate `game.enemies`/spawn into `game.bullets` etc. via existing globals. Each test should reset the relevant slice of global state it depends on at the top of the test case rather than relying on it being empty by default.

## Out of Scope

- Exact final numeric balance tuning of `windup_fraction`/`follow_through_time` across a full playthrough, including interaction with other upgrades over time — the values above are validated starting points from prototyping, not locked final content.
- Commissioning or producing the actual new art (sprite frames, particle effects) each weapon-kind needs — this spec covers the mechanical/timing model and confirms art is required, not the art itself.
- Any UI/HUD feedback beyond the weapon sprite itself (screen shake, hit-flash, crosshair state changes during Winding Up) — not decided either way, left open for a later pass.
- Sound design for any phase of the action cycle — not discussed, not designed here.
- Revisiting Gun's already-established spring-based recoil motion in light of Sword's eased-curve answer — flagged as worth a sanity check later, not resolved here; Gun's spring stays as originally validated.
- A cancel-by-releasing-early mechanic for Windup — explicitly decided against.
- Movement or aiming restrictions during Windup — explicitly decided against.
- Any general, reusable pattern for future ground-targeted abilities beyond Poison_Cloud — the lock-at-Trigger behavior is scoped to Poison_Cloud specifically; generalizing it is left for whenever (if ever) another ground-targeted ability is added.

## Further Notes

- This spec is the synthesized output of the "Weapon action feel" wayfinder map, worked through across six tickets. The map and each ticket's full resolution detail (including complete rationale for the decisions summarized above) remain at `.scratch/weapon-action-feel/map.md` for reference.
- Five ADRs were produced and should be read alongside this spec: [ADR-0001](../../docs/adr/0001-weapon-wrapper-struct.md) and [ADR-0002](../../docs/adr/0002-class-locked-weapon-acquisition.md) (pre-existing context on `Weapon`'s shape and Class-locked acquisition), [ADR-0003](../../docs/adr/0003-windup-and-follow-through-are-weapon-level.md) (why Windup/Follow-through live on `Weapon`, not per-variant), [ADR-0004](../../docs/adr/0004-windup-fraction-not-duration.md) (why Windup is a fraction, not a duration), [ADR-0005](../../docs/adr/0005-ground-targeted-casts-lock-at-trigger.md) (why Poison_Cloud locks its target at Trigger).
- `CONTEXT.md`'s glossary now defines Trigger, Windup, Resolve, Follow-through, and Weapon readiness — read these before touching `weapon.odin`.
- Three throwaway prototype branches capture the validated motion/feel decisions as a visual reference for implementation: `prototype/ranged-windup`, `prototype/melee-windup`, `prototype/magic-windup` (each a single HTML/canvas file, not production code, not merged to main).
