# Boss telegraph and phase feel

Type: prototype
Status: claimed

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

