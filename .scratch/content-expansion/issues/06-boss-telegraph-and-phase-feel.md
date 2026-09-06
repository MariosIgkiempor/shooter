# Boss telegraph and phase feel

Type: prototype
Status: resolved

## Question

Given the machinery decided by [Boss model](05-boss-model.md), what does a boss attack actually *feel* like?

A HITL prototype question, not an architecture one — how long a telegraph reads for and what it looks like can only be judged in motion.

To answer:

- **Telegraph duration.** Long enough to react to, short enough not to be boring on the tenth repetition. Compare directly against the player's own Windup, which is a fraction of the weapon's cycle rather than a fixed duration.
- **Telegraph form.** The existing vocabulary is pull-back along `aim_dir` for Gun/Magic and an arc pull-back for Melee. A boss telegraphing a ground slam or a sweep has no equivalent yet. Flat shapes and particles are the whole toolkit ([Art revamp](../../art-revamp/map.md)) — no sprites.
- **Phase transition legibility.** How does the player know a phase changed? A colour shift, a pause, a burst, a change in movement? A transition nobody notices is not a phase.
- **Screen feedback.** `shake.odin`'s trauma-decay is available. Whether a boss earns screen shake where ordinary enemies do not is part of this.

Build it cheap and throwaway on a `prototype/` branch, link it from this ticket, and judge it at real gameplay zoom in motion — the standard [Art revamp](../../art-revamp/map.md) set for every visual decision in this codebase.

The stage is already decided: [Map ladder shape](03-map-ladder-shape.md) made rung 5's arena deliberately legible — open, simple, few obstructions — precisely so telegraphs can be read. Prototype against that, not against a cluttered arena; if a telegraph only works in open ground, that is the answer working as intended rather than a limitation to design around.

[Boss model](05-boss-model.md) has settled what is being prototyped, and narrowed this ticket considerably:

- **The mechanic is a Tell**, not a Windup — timed in **absolute seconds** ([ADR-0023](../../../docs/adr/0023-enemy-tells-are-absolute-durations.md)), so the duration judged here is the duration authored, not a fraction to be recomputed against a cycle. Comparing against the player's own Windup is still useful as a feel reference, but the two are not the same quantity.
- **A Tell always resolves**, in range or not. A prototype that lets a Tell be cancelled when the player leaves range is testing a different mechanic.
- **Three phases on health thresholds**, and a phase changes **only** the attack rotation and its pacing. `Movement_Style` is fixed for the boss's life and the boss never spawns adds, so those are not available as transition cues — which makes phase legibility a harder and more interesting question here, not an easier one. Colour, pause, burst, and a rotation the player can hear change are what is left.
- **The boss carries a world-space Resource indicator**, so a threshold crossing is visible on the bar. Whether that alone counts as a legible transition is exactly what this prototype answers.
- **The boss is bigger than any enemy today** (`ENEMY_SIZE_MAX` rises), which changes how much screen a telegraph has to cover to read as belonging to it.

Unblocked: [Boss model](05-boss-model.md) is resolved.

## Prototype

Captured on branch `prototype/boss-tell` (commit `aa6b349`), branched from `main`, with a worktree already set up and building at `.claude/worktrees/prototype-boss-tell`. Run it with:

```
cd .claude/worktrees/prototype-boss-tell && odin run . -out:build/shooter.bin
```

Start a Run as normal, then in-game (Playing only):

- **F2** — spawn/respawn the boss ~240px from the player, at full health.
- **F9** — Tell form: **A** body flash / **B** scale swell / **C** ground zone / **D** body pull-back. Defaults to C.
- **F10** — Tell duration: **0.35 / 0.55 / 0.80 / 1.20 s**, absolute seconds per [ADR-0023](../../../docs/adr/0023-enemy-tells-are-absolute-durations.md). Defaults to 0.55.
- **F11** — phase cue: **bar only** / **+ palette** / **+ freeze & burst**. Defaults to bar only.
- **F12** — screen shake on Tell resolve, on/off. Defaults to off.

A yellow readout top-left shows the live settings; an orange line under it shows the boss's phase, health, current step and next attack.

### What it builds

A single `Enemy` with `is_boss` set, 600 health, 84px (what `ENEMY_SIZE_MAX` would have to rise to from 48), Grounded at 46 px/s. It carries the restored world-space Resource indicator. Its attacks are driven by a throwaway state machine rather than an `Attack_Style`, to the machinery [Boss model](05-boss-model.md) settled: the boss **plants for the whole Tell**, the Tell **always resolves** in range or not, and the three health-threshold phases (66% / 33%) change **only** the rotation and its recovery pacing.

Three attacks, so a rotation is actually a rotation:

- **Slam** — committed area centred on the boss, radius 90. Dodged by leaving.
- **Lunge** — committed area along a bearing **fixed at Tell start**, resolving into a real 260px dash. Dodged by stepping aside, not by running.
- **Volley** — five enemy bullets in a 34-degree spread, Tell at 0.7x. **This is the control**: it is the one attack that already works untelegraphed today, so if its Tell reads as noise rather than information, that is the finding that a Tell belongs to committed *area* attacks and not to every enemy attack — which feeds straight back into [Enemy catalog](04-enemy-catalog.md)'s spent `Attack_Style` slot.

Rotations are `{Slam, Volley}` / `{Slam, Lunge, Volley}` / `{Lunge, Slam, Lunge}` with recovery 1.50 / 1.15 / 0.80s.

### The reaction budget to judge against

`PLAYER_BASE_MOVE_SPEED` is 100 px/s ([main.odin](../../../main.odin)), so a Tell of *t* seconds buys the player exactly 100*t* px of escape: **35 / 55 / 80 / 120 px** across F10's four settings, against a 24px player and a 90px slam radius. A player caught adjacent to the boss needs roughly 0.4s just to clear the slam — so **Tell duration and attack radius are one decision, not two**, and 0.35s is included precisely so the unreadable end of the range is visible rather than theoretical.

### Questions it exists to answer

1. Which form reads. The hypothesis on the ticket is that A/B/D say *when* while only C says *where*, and that with ~55px of escape "something is coming" is not actionable on its own.
2. Where the duration lands, and whether one duration serves all three attacks or a Tell is per-attack.
3. Whether the Resource indicator crossing a threshold is a legible phase transition **by itself** (F11 at its default), and if not, what the minimum addition is.
4. Whether the volley's Tell is information or noise.
5. Whether a boss earns screen shake where ordinary enemies do not. Note `damage_player` already shakes proportional to damage taken, so F12 is specifically about shaking on *resolve* regardless of whether the attack connected.

## Answer

**A Tell is the claimed ground plus a body flash, 0.55s for a committed area attack, resolving with screen shake — and a phase change is legible on the Resource indicator alone.** Judged in motion at gameplay zoom on `prototype/boss-tell` (commits `aa6b349`, `bca142d`).

### Settled

- **Form: the ground zone and the body flash together**, not either alone. The floor carries *where*, the body carries *when*, and the ticket's four candidates split cleanly along that line — the body-only forms (flash, scale swell, pull-back) all announce timing without saying where to stand, and at 55px of escape that is not actionable. The combination was added to the bench as a fifth form and confirmed rather than inferred from seeing the two separately.
- **The zone draws at full extent from the Tell's first frame and fills as the Tell runs.** Extent immediately, timing progressively — a zone that grows into its final shape withholds the half of the information the player needs first. Inherited from `spawn_poison_windup_puff`, which already grows an area under the player's own Magic Windup.
- **0.55 seconds** for a committed area attack, as the reference the catalog tunes around. At `PLAYER_BASE_MOVE_SPEED` (100 px/s) that buys 55px of escape against a 90px slam radius — tight, and deliberately so: 0.35s was unreadable when caught adjacent and 1.20s was tedious by the third repetition.
- **Duration is authored per attack, not per Enemy Kind.** What makes a duration fair is how far the player must travel to leave *that* attack's area, and that differs between attacks on the same enemy. The Tell-carrying **Attack Style** variant therefore holds a rotation of *(attack, tell seconds)* pairs rather than a single duration field.
- **A Tell belongs to committed *area* attacks only.** Ordinary `Ranged` fire stays untelegraphed exactly as it is today: enemy bullets travel at 190 px/s against the player's 100 and are readable on sight, so a lane drawn before them restates what the bullets say a moment later. The volley was built into the bench as the control for precisely this, and it read as noise. This narrows the reopened `Attack_Style` slot from "a telegraphed attack" to "an attack that claims ground".
- **The area locks its bearing at the Tell's start** and does not track the player through it. This closes the per-attack question [ADR-0023](../../../docs/adr/0023-enemy-tells-are-absolute-durations.md) explicitly deferred to [ADR-0005](../../../docs/adr/0005-ground-targeted-casts-lock-at-trigger.md)'s split: an area that follows the player cannot be escaped by moving, which makes its own Tell decorative.
- **The enemy plants for the whole Tell.** Committing visibly means committing in place; a Tell that chases while it winds up spends its own warning.
- **Screen shake fires on resolve**, whether or not the attack connected. `damage_player` already shakes in proportion to damage taken, so this is additive and lands only on Tell-resolving attacks — which is what makes it a boss's shake rather than every enemy's.
- **Phase transitions are legible on the world-space Resource indicator alone.** No palette shift, no freeze, no burst. Both richer cues were built and both were judged unnecessary.

### Why bar-only works, which this ticket did not anticipate

[Boss model](05-boss-model.md) ruled out movement and adds as transition cues and concluded that this made phase legibility *harder*. It missed a third cue that comes free: **pacing**. A phase changes the rotation *and its recovery* — 1.50s → 1.15s → 0.80s between attacks in the bench — so the boss visibly gets busier at exactly the moment the bar crosses a threshold. The bar says a threshold was crossed; the pacing says something changed. Neither alone would carry it, and neither had to be designed.

The consequence is that **recovery is authored per phase, not per Enemy Kind** — it is load-bearing for legibility, not just for difficulty.

### Not decided here

- **Every number in the bench is a prototype value**, not authored content: 600 health, 84px, 46 px/s, slam radius 90, lunge 260x70, the volley spread, and the per-phase recovery figures. [Enemy catalog](04-enemy-catalog.md) authors the real ones; only 0.55s carries forward, and as a reference rather than a constant.
- **Whether each committed area attack needs a visually distinct zone shape** (disc for a slam, lane for a lunge) or whether one shape with different extents suffices. The bench used distinct shapes and nothing argued against them, but nothing tested a roster large enough to make them collide either.

### Follow-on

- **[Enemy catalog](04-enemy-catalog.md)** takes a narrower brief for its spent `Attack_Style` slot, plus the 0.55s reference and per-attack durations.
- **[Content-scale integration sweep](09-content-scale-integration-sweep.md)** takes the floor draw layer, the per-attack Tell state, and per-phase recovery.

