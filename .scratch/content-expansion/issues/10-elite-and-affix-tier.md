# Elite and affix tier

Type: grilling
Status: open

## Question

Does an **elite** tier belong between ordinary enemies and bosses — and if so, is an elite its own `Enemy_Kind`, or a modifier layered onto one?

Graduated from this map's fog once [Enemy variety model](01-enemy-variety-model.md) settled what a kind is. The fog item's stated blocker was exactly that: "can't be phrased sharply until Enemy variety model says what a kind is". A kind is now an `Enemy_Preset` entry in a flat `[Enemy_Kind]` table — `movement`, `attack`, `max_health`, `color`, Gold payout — stamped onto an `Enemy` at spawn, and a Map's composition authors `(kind, count)` and nothing else.

That makes the question sharp, and gives it three branches:

- **Elites are ordinary kinds.** An "Armoured Wasp" is simply another `Enemy_Kind` entry with more health and a different colour. Costs nothing new; the enum and the catalog absorb it. But every base × affix combination is a separate authored entry, and the player has no cue that two entries are related.
- **Elites are a modifier applied at spawn.** `Enemy` gains an affix (or a small set), applied on top of a preset — scaling health, tinting the body, adding a behaviour. This is the one thing in the model that would make an `Enemy` no longer a pure stamp of its preset, which [ADR-0020](../../../docs/adr/0020-enemy-kind-is-the-authored-unit.md) deliberately made it. It also reopens the per-rung-scaling question that [Enemy variety model](01-enemy-variety-model.md) closed, from a different direction.
- **No elite tier.** Pressure between ordinary enemies and a boss comes from composition — denser triggers, harder kinds later — which is what [Map ladder shape](03-map-ladder-shape.md) already owns.

To settle:

- **Where an elite is authored.** A Map's composition authors `(kind, count)`; an affix has no place to be authored there without widening the entry that [ADR-0020](../../../docs/adr/0020-enemy-kind-is-the-authored-unit.md) just narrowed. Does the affix come from the kind, from the rung, or from a widened composition entry — and if the last, is that ADR-0020's first amendment?
- **What an elite *does* to the player.** The same bar every roster entry faces: a new pressure, not a stat bump wearing a colour.
- **How it reads.** Colour is now a per-kind preset field with hue-tracks-Movement-Style as an authoring convention. An elite either takes a colour of its own (breaking the convention deliberately, the way a boss may) or is marked some other way — outline, size, particle — with size already spoken for by `max_health`.
- **Its payout.** `Enemy_Preset` carries the Gold payout, so an affixed enemy either pays its base kind's Gold or needs a rule that scales it.
- **Whether the boss shares this machinery.** [Boss model](05-boss-model.md) asks where phases and telegraphs live and lists "a flag or tier on `Enemy_Kind`" as one branch. If elites are a modifier, a boss may be the extreme end of the same mechanism rather than its own type — decide here whether that is a live option for ticket 05, or explicitly not.
