Type: prototype
Status: resolved

## Question

What is the Swarmer's new surround/flank mechanic, concretely?

Settled: Swarmer needs genuinely new mechanics, not just stat tuning on top of grounded chase + Separation (fast/fragile/strong-separation alone was explicitly rejected as sufficient). Needs a decided approach for how multiple Swarmers pick distinct approach angles/points around the player instead of all converging on the same BFS-path goal point — e.g. assigned slots around the player, angular offset per enemy, or some other formation logic — and how that interacts with the existing BFS pathing to the player.

Also see this map's "Not yet specified": how this composes with the Separation force (Not yet specified in map.md) is likely to surface here — capture it as this ticket's answer if it resolves, otherwise leave it in the map's fog.

Build a cheap, rough prototype to react to — per the wayfinder skill's Ticket Types section, call the Skill tool with "prototype".

## Answer

Prototype: an interactive canvas simulation comparing three mechanics — a naive Separation-only baseline (the already-rejected approach, kept for contrast), static per-enemy angular slots assigned at spawn order, and dynamic nearest-free-slot assignment recomputed every frame around a slowly-rotating ring — plus a toggle for layering the resolved Separation force on top of slot-seeking. Prototype preserved on the throwaway branch `prototype/swarmer-surround` (commit bc267b5) — see `.scratch/enemy-behaviours/prototypes/swarmer-surround.html` on that branch for the primary source; the file also sits untracked in the working tree on `main` for convenience.

**Validated after live tuning:**
- **Mechanic**: dynamic nearest-free-slot assignment — slots form a ring around the player (recomputed every frame from current player position and live Swarmer count), each Swarmer seeks whichever unclaimed slot is nearest to it. Rejected: static per-spawn-order slots (reshuffles awkwardly when count changes) and the naive Separation-only baseline (bunches up on approach).
- **Composition with Separation**: resolved — Separation layers on top of slot-seeking, it does not replace it. This closes the map's "Not yet specified" fog item on how the two compose.
- **Swarmer's own Separation tuning**: gentler than Grounded's — **radius ~15px, strength ~0.5**, the same values validated for Floater in ticket 03, not Grounded's 40px/3.0 (a strong separation force was judged likely to fight the slot assignment rather than smooth it).
- **Surround radius**: bound to the Swarmer's own Attack Style's `attack_range` field, not an independently-tuned constant — the ring Swarmers orbit on is exactly their melee contact range, so orbiting and attacking naturally coincide. This is a genuine read from the Attack Style axis by the Movement Style axis; ticket 01's "orthogonal axes" decision means an enemy can pick each independently, not that one axis can never reference the other's current value at runtime.
- **Nil-attack fallback**: needs a fallback surround-radius constant for the edge case where a Swarmer's Attack Style is nil (no `attack_range` to read). Proposed default: **60px**, matching the prototype's own default radius — a minor implementation safety net, not a felt/tuned value, so it's open to revision whenever that edge case is actually built.

Implementation note: `Steering.assignNearestSlots` in the prototype is a simple greedy nearest-unclaimed-slot assignment (not globally optimal, e.g. not the Hungarian algorithm) — validated as good enough at the tested counts (up to 16), consistent with `MAX_ENEMIES :: 24` overall.
