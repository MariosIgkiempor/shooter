# Weapon action feel

Label: wayfinder:map

## Destination

A spec, ready to hand off for implementation, for a Trigger → Windup → Resolve → Follow-through action-timing model applied across all three `Weapon` variants (Gun, Melee_Weapon, Magic) — gated by Fire_Mode so `Semi_Automatic` weapons get a visible pre-effect Windup (Pistol, Shotgun, Sword, Fire_Wand, Poison_Staff) and `Automatic` weapons get a lightweight post-effect Follow-through instead (SMG, Flame_Staff, Dagger). Fixes ranged/magic weapons not feeling good to use, without making them feel unresponsive.

## Notes

- Vocabulary is settled in [CONTEXT.md](../../CONTEXT.md) (Windup, Resolve, Follow-through, Trigger, Weapon readiness) and [ADR-0003](../../docs/adr/0003-windup-and-follow-through-are-weapon-level.md) (why Windup/Follow-through live on `Weapon`, not per-variant). Read both before resolving any ticket.
- This map is a **spec to hand off**, not execution — tickets decide, they don't implement. Default wayfinder behavior applies, not overridden.
- Prototype tickets should call the Skill tool for "prototype" (HITL); grilling tickets should call it twice for "grilling" and "domain-modeling" per the default.
- Locked destination-level decisions (don't reopen without a strong reason — see full reasoning in the grilling transcript this map was charted from):
  - Windup is nested inside the existing cooldown window (`action_rate` unchanged, not slowed down).
  - Once started, Windup always completes into Resolve — not cancelable.
  - Aim tracks the mouse live throughout Windup for anything aiming along `aim_dir` (Gun, Melee_Weapon, Fireball, Flamethrower); Resolve may whiff if the target moved or died. **Exception**: ground-targeted casts (Poison_Cloud) lock their target at Trigger instead — see ADR-0005.
  - Movement is never locked or slowed during Windup.
  - Windup and Follow-through are mutually exclusive per weapon (by Fire_Mode) — never both, never neither.
  - ~~New art (sprite frames/particles, not just transform animation) is assumed needed for every Windup-gated weapon-kind.~~ **Superseded** — see [Art revamp](../art-revamp/map.md)'s [Weapon shape and reconcile weapon-action-feel](../art-revamp/issues/02-weapon-shape-and-reconcile-weapon-action-feel.md): richer shape-based particle effects (streaks, an impact flash/ring, non-linear ease-out fades — none of which exist in `particle.odin` today) confirmed sufficient, live-tested per weapon family. Not sprite frames; not today's plain dot-burst particles either — both were re-confirmed insufficient.

## Decisions so far

- **Amended by [ADR-0018](../../docs/adr/0018-weapon-visual-identity-is-per-kind-not-per-family.md) (2026-09-05)** — the second amendment to this map's art assumptions, after the Art revamp's. Weapon *effect shapes* stay per-family exactly as settled below; their **magnitudes** now vary per `Weapon_Kind` (a Pistol's muzzle flash is smaller than a Shotgun's), and weapon silhouettes become per-kind rather than per-family. Nothing about the Trigger/Windup/Resolve/Follow-through model, the timing values, or the effect *vocabulary* this map settled is reopened — only how far those effects are scaled per weapon.

- [Naming the destination + mapping the frontier](map.md): Trigger/Windup/Resolve/Follow-through model, gated by Fire_Mode, Windup lives within the cooldown window, common Weapon-level timer fields (not per-variant). See CONTEXT.md and ADR-0003 for the full settled vocabulary and structure.
- [Trigger/Windup/Resolve state machine](issues/01-trigger-windup-resolve-state-machine.md): `update_weapon` gains explicit origin/aim_dir/mouse_world params (plus `game.enemies` also becomes an explicit param, unifying weapon.odin's call chain); the variant-dispatch switch extracts into a new `resolve_weapon_action`, called immediately for Automatic weapons and on Windup completion for Semi_Automatic ones; `cooldown_timer`/`windup_timer` start together at Trigger; switching weapon mid-Windup just abandons it.
- [Gun empty-clip Windup](issues/02-gun-empty-clip-windup.md): ammo is checked before Windup starts (mirroring today's `try_fire_gun`), same as an empty-clip Trigger does nothing today — Windup never plays into a wasted dry-fire. Gun-specific; Melee_Weapon/Magic's Semi_Automatic kinds always start Windup unconditionally.
- [Windup vs action-rate upgrades](issues/03-windup-vs-action-rate-upgrades.md): Windup is stored as `windup_fraction` (0..1, proportion of the cycle) instead of a fixed duration, so it stays nested inside the cooldown window automatically no matter how much `action_rate` has grown from upgrades — no ceiling on upgrades, no clamping. `follow_through_time` is unaffected, stays a fixed duration. See ADR-0004.
- [Ranged windup prototype](issues/04-ranged-windup-prototype.md): feel confirmed for Pistol (`windup_fraction=0.24`), Shotgun (`0.26`, reads heavier via its longer cycle), and SMG (`follow_through_time=45ms`, survives sustained fire) as good starting points. Its "all three need real new art" call is **superseded** — see the Art revamp map's amendment note above; Pistol's shape+enhanced-effects treatment is confirmed and expected to generalize to Shotgun/SMG. Prototype captured on throwaway branch `prototype/ranged-windup`.
- [Melee windup prototype](issues/05-melee-windup-prototype.md): Sword `windup_fraction=0.37` confirmed; its Resolve motion is a two-phase eased sweep-through (no spring/bounce — spring was tried and rejected as "feels wrong"), still derived from `cooldown_timer` with no new timer field. Dagger's `follow_through_time=150ms` confirmed unchanged from today. Its "both need real new art" call is **superseded** — see the Art revamp map's amendment note above; Sword's shape+enhanced-effects treatment is confirmed and expected to generalize to Dagger.
- [Magic windup prototype](issues/06-magic-windup-prototype.md): Fire_Wand `windup_fraction=0.21` confirmed. Poison_Staff `windup_fraction=0.18` confirmed, but its ground target locks at Trigger rather than tracking live — a confirmed exception to the map's aim-tracking rule, see ADR-0005. Flame_Staff `follow_through_time=80ms`, discrete pulse confirmed over continuous stream. Its "all three need real new art" call is **superseded** — see the Art revamp map's amendment note above; Fire_Wand's shape+enhanced-effects treatment is confirmed and expected to generalize to Poison_Staff/Flame_Staff. Prototype captured on throwaway branch `prototype/magic-windup`.

## Not yet specified

- Cross-weapon balance tuning of `windup_fraction`/`follow_through_time` over a full run, across all eight `Weapon_Kind`s and their upgrade paths — every kind now has a confirmed starting value (see the three prototype tickets), but none of this has been played through a real run yet. Genuine content-authoring/playtesting work, not a wayfinder-shaped decision.
- What Sword's Resolve-motion answer (a two-phase eased curve, not a spring) implies for Gun's already-approved spring-based recoil — the two are different weapon feels by design (confirmed independently, not compared head-to-head), but worth a sanity check once more of the real implementation exists side by side, in case the spring choice for Gun deserves a second look now that a non-spring alternative is proven out.
- Any UI/HUD feedback beyond the weapon sprite itself (screen shake, hit-flash, crosshair state change during Winding Up) — not yet raised as a real question; may turn out to be its own ticket, may turn out unnecessary once the sprite-level prototypes are seen in motion.
- Sound design for Trigger/Windup/Resolve/Follow-through — not discussed at all yet. Genuinely unspecified, not assumed out of scope.
- Whether any other future ability ends up ground-targeted like Poison_Cloud, and so needs the same lock-at-Trigger treatment ADR-0005 established — not a live concern for any weapon-kind that exists today, just a pattern to remember.

## Out of scope

(none yet)
