Type: grilling
Status: resolved

## Question

How should `Enemy` hold a Movement Style value *and* an Attack Style value simultaneously, given neither existing polymorphism shape in this codebase directly fits?

- `Enemy_Behaviour` today is a bare union (`Melee` | `Ranged`) — the right shape per ADR-0001 when variants share no state, but it only expresses *one* axis, not two independent ones.
- `Weapon` is a wrapper struct (common fields + one `variant` union field) — the right shape when variants share a common header read outside a switch, but it's still a single axis.

Decide the concrete Odin shape for `Enemy` to hold both a Movement Style variant (grounded chase / Floater / Swarmer) and an Attack Style variant (Melee / Ranged / none) at once — e.g. two sibling union-valued fields, some other composition — and whether this warrants a new ADR (it's hard to reverse, surprising without context, and a genuine trade-off, per this repo's ADR criteria).

Call the Skill tool for "grilling" and "domain-modeling" per the wayfinder skill's Ticket Types section.

## Answer

Verified first (grep across enemy.odin/main.odin/editor.odin/hud.odin): every current read of `speed` and `attack_damage` happens inside a `switch` over `enemy.behaviour` — never outside one. Per ADR-0001's own criterion (bare union when variants share no state read outside a switch), that rules out forcing a wrapper struct here.

**Settled shape**: `Enemy` gains two sibling fields, replacing the single `behaviour: Enemy_Behaviour`:
- `movement: Movement_Style` — bare union: `Grounded | Floater | Swarmer` (nil = doesn't move)
- `attack: Attack_Style` — bare union: `Melee | Ranged` (nil = doesn't attack; renamed only conceptually from today's `Enemy_Behaviour`'s `Melee`/`Ranged`, same field shapes minus `speed`)

`speed` moves off `Melee`/`Ranged` and onto each `Movement_Style` variant instead (each of `Grounded`/`Floater`/`Swarmer` gets its own `speed` field) — it's a movement trait, not a combat one, and this keeps Attack Style fully independent of how fast the enemy happens to move.

**Provisional per-variant fields** (naming only, not tuning — final fields are the Floater movement design and Swarmer surround mechanic tickets' job):
- `Grounded`: `speed: f32` (today's `chase_to` behaviour, unchanged)
- `Floater`: `speed: f32`, plus whatever noise/wobble-phase state its ticket settles on
- `Swarmer`: `speed: f32`, plus whatever surround-slot/angle state its ticket settles on

**Naming**: the grounded/BFS-pathing variant is called `Grounded` (named for what distinguishes it from `Floater` — collides with terrain, follows the path — not for "chases", since `Swarmer` also closes on the player via a different route).

**ADR**: skipped, by explicit user call — treated as a natural extension of ADR-0001's existing pattern (two bare unions instead of one), documented here and in `CONTEXT.md` rather than a new ADR file.

`CONTEXT.md` updated with `Grounded`, `Floater`, `Swarmer` entries and revised `Movement Style`/`Attack Style` entries reflecting the `Enemy.movement`/`Enemy.attack` field split.
