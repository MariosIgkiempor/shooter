Type: grilling
Status: resolved
Blocked by: 01

## Question

How do weapon icons (Pistol, Shotgun, SMG, Sword, Dagger, Fire_Wand, Flame_Staff, Poison_Staff) render as shapes once sprites are dropped, applying the vocabulary [01-actor-shape-and-movement-transform](01-actor-shape-and-movement-transform.md) establishes?

This ticket also explicitly reopens a locked decision from [weapon-action-feel](../../weapon-action-feel/map.md): that map's Notes state *"New art (sprite frames/particles, not just transform animation) is assumed needed for every Windup-gated weapon-kind"*, and its prototype tickets ([04-ranged-windup-prototype](../../weapon-action-feel/issues/04-ranged-windup-prototype.md), [05-melee-windup-prototype](../../weapon-action-feel/issues/05-melee-windup-prototype.md), [06-magic-windup-prototype](../../weapon-action-feel/issues/06-magic-windup-prototype.md)) each confirm feel using transform-only motion but flag that real new art is still needed on top. Decide: does a shapes+transform-only treatment (the pivot/angle/scale system `draw_weapon` already implements, main.odin:872-976) actually satisfy what those tickets meant by "new art," or is there a real gap that shapes alone can't close?

Resolution must append an amendment pointer into weapon-action-feel's `## Decisions so far` (and, if the answer is per-weapon rather than blanket, into the affected individual tickets) — do not just note the conflict here and leave weapon-action-feel's map untouched, per this map's Notes and domain-modeling's flag-conflicts rule.

## Answer

> **Amended by [ADR-0018](../../../docs/adr/0018-weapon-visual-identity-is-per-kind-not-per-family.md) (2026-09-05).** The per-family call below is **superseded**: each of the eight `Weapon_Kind`s now gets its own silhouette, in the UI and in the world, distinguished by *countable* geometry (one barrel vs. two, one orb vs. three) rather than by proportion, with weapons growing to roughly 1.5x to make room. Everything else this ticket settled stands unchanged — the rod/wedge/rod+orb family vocabulary remains the base each kind varies from, and the enhanced shape-based effects finding below is untouched except that effect *magnitudes* now vary per kind while their shapes stay per-family.

**Base shape vocabulary**: distinct silhouette per weapon family, not per-kind or fully generic — Gun = thin rod, Melee = wedge/blade, Magic = rod with a circular orb tip. Confirmed via a live prototype (see below), one representative per family: Pistol (Gun), Sword (Melee), Fire_Wand (Magic).

**The reopened weapon-action-feel question, answered**: shape-based effects **do** supply the "punch" that plain icon-transform lacked — but only once the effects layer itself is richer than what exists in `particle.odin` today. Today's actual particle system (`spawn_particle_burst`: flat-color dot circles, linear fade) was implicitly already shown insufficient by weapon-action-feel's own Magic ticket (its cast-particle effects still needed real art layered on top). Testing an *enhanced* shape-based effects layer — never actually tried before — closed that gap:

- **Streak particles**: elongated, oriented to travel direction (a new primitive; today's particles are always circles).
- **A one-shot "flash"**: a bright radial-gradient glow, fast non-linear decay (a new primitive).
- **A motion-trail**: for Sword specifically, several echoed, fading copies of the blade shape sampled through the swing (not a new particle primitive — reuses the same body shape at past angles).
- **Non-linear (ease-out) fades** throughout, replacing today's linear fade.

Confirmed live by the user against the actual prototype ("enhanced shapes look good, lock them in") after two rounds of bug-fixing surfaced by that same live review (an echo-trail coordinate bug on Sword, and under-scaled motion/effect amplitude on Pistol that made a technically-working muzzle flash unreadable) — both fixed and re-verified before the final call.

**Scope**: per weapon-family, as scoped going in. Confirmed for the three tested representatives; expected to generalize to each family's siblings (Shotgun/SMG for Ranged; Dagger for Melee; Poison_Staff/Flame_Staff for Magic) rather than needing individual re-validation, since the family-representative approach was chosen specifically for that generalization.

**Reconciliation**: amendment pointers appended to [weapon-action-feel](../../weapon-action-feel/map.md)'s `## Decisions so far`, its locked-decisions Notes line, and directly into issues [04](../../weapon-action-feel/issues/04-ranged-windup-prototype.md), [05](../../weapon-action-feel/issues/05-melee-windup-prototype.md), and [06](../../weapon-action-feel/issues/06-magic-windup-prototype.md) — their "needs real new art" calls are superseded, not deleted (the timing/motion decisions in those tickets are unchanged and still stand).

**Prototype**: [Weapon Effects Bench](https://claude.ai/code/artifact/3acfe471-59f9-4fe7-a171-dbd7bd97f6f9), also captured at [prototypes/02-weapon-shapes-and-effects.html](../prototypes/02-weapon-shapes-and-effects.html).

**Implementation note for whoever builds this**: `particle.odin` needs two new capabilities it doesn't have today — an oriented/elongated "streak" particle kind, and a one-shot radial-gradient "flash" kind — to reach what this ticket confirmed, not just more of today's dot bursts.
