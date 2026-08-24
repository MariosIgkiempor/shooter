Type: task
Status: resolved
Blocked by: 01, 02, 03, 04

## Question

Update the in-game level editor and debug overlay to work with the new Movement Style / Attack Style axes and the Floater/Swarmer archetypes, once their shapes and tunable parameters are decided.

Concretely, in `editor.odin:544-619`: today there's one button row (pick Melee or Ranged) plus one field-switch rendering per-variant sliders, tied 1:1 to the old union variants. This needs reworking into whatever shape the data-structure ticket settles on (likely two independent selectors — Movement Style and Attack Style — each with its own slider block), plus new button/slider blocks for Floater and Swarmer using the parameters their design tickets settle on. Note there's also no existing way to select "Inert" explicitly (nil template shows no sliders and no button) — decide whether to add one while reworking this.

In `main.odin:665-677` (`draw_debug_attack_ranges`): the only debug-overlay function that switches on the old union shape (draws an attack_range circle for Melee, min/max_range circles for Ranged). Extend it for the new Attack Style shape, and consider whether Movement Style now needs its own debug visualization (e.g. drawing a Separation radius, or a Swarmer's assigned surround point) alongside the existing variant-agnostic `draw_path`.

This is manual implementation work gated on other tickets' decisions, not a decision itself — work it directly once unblocked, no research/prototype/grilling skill call needed unless a genuine ambiguity turns up.

## Answer

Kept as a handoff checklist rather than executed now: the map's Destination explicitly defers implementation to a separate follow-on, and this ticket's own edits (as scoped) can't actually be made yet because ticket 01's `Enemy.movement`/`Enemy.attack` split hasn't been applied to `enemy.odin` — that's real code, not a decision, and belongs to that follow-on too. Checked with the user directly on this ambiguity; confirmed keeping this map decision-only.

**Checklist for the implementation follow-on**, using every value settled in tickets 01–04:

`editor.odin:544-619` — replace the single button-row + field-switch with two independent selector blocks:
- **Movement Style row**: buttons for `Grounded`, `Floater`, `Swarmer`, plus an explicit "none" option (today's nil-template gap — no button exists to pick Inert at all; add one while this is being reworked)
  - `Grounded` sliders: `speed`
  - `Floater` sliders: `speed`, wobble amplitude (ceiling 80px), wobble frequency (3Hz validated), pull-toward-player (0.35 validated), plus toggles for "respects arena bounds" (off) and "separates from other Floaters" (radius ~15px / strength ~0.5)
  - `Swarmer` sliders: `speed`, separation radius/strength (~15px / ~0.5, same as Floater); surround radius is *not* an independent slider — it reads the enemy's own Attack Style `attack_range` at runtime (fallback 60px if Attack Style is none), so the editor should display it as derived/read-only, not editable here
- **Attack Style row**: buttons for `Melee`, `Ranged`, plus explicit "none" (same existing gap)
  - `Melee` sliders: `attack_damage`, `attack_range`, `attack_cooldown` (unchanged from today, minus `speed` which moved to Movement Style)
  - `Ranged` sliders: `attack_damage`, `min_range`, `max_range`, `projectile_speed`, `fire_rate` (unchanged from today, minus `speed`)

`main.odin:665-677` (`draw_debug_attack_ranges`) — the existing switch-on-attack-range-circles logic carries over almost unchanged, just switching on `enemy.attack` instead of `enemy.behaviour`. Add a sibling debug visualization for Movement Style: a Separation-radius circle (tuned per variant: 40px for Grounded, ~15px for Floater/Swarmer), and for Swarmer specifically, a line or marker to its currently-assigned slot target (`Steering.assignNearestSlots`'s equivalent in the real code). `draw_path` (main.odin:532-538) stays variant-agnostic and needs no changes — Floater/Swarmer simply have an empty path.

Reference implementations for the exact formulas: `prototype/separation-force` (separation blend), `prototype/floater-movement` (wobble/drift), `prototype/swarmer-surround` (slot assignment) — all three branches, not just this ticket's answer.
