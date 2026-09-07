# Content expansion

Status: ready-for-agent

Source: the [Content expansion](map.md) wayfinder map, all twelve tickets resolved. Every decision below is settled and linked; this spec re-states them as one buildable whole. Where this spec and a ticket disagree, the ticket wins and this file is stale.

Governing ADRs: [0020](../../docs/adr/0020-enemy-kind-is-the-authored-unit.md), [0021](../../docs/adr/0021-map-layouts-are-hand-authored-places.md), [0022](../../docs/adr/0022-map-rungs-are-gated-by-clears.md), [0023](../../docs/adr/0023-enemy-tells-are-absolute-durations.md), [0024](../../docs/adr/0024-a-map-owns-its-visual-identity.md), [0025](../../docs/adr/0025-enemies-steer-by-a-shared-flow-field.md), [0026](../../docs/adr/0026-a-weapon-hits-only-what-it-touches.md), [0027](../../docs/adr/0027-the-editor-generates-source-it-does-not-gain-a-data-format.md).

## Problem Statement

The game is mechanically dense and content-thin. Every system needed to carry variety already exists and is fully specified — the Movement and Attack axes, the Spawn Trigger timeline, the Weapon tier ladder, the Shop, Account progression, Relics, and `Map` with its objective fields — but almost nothing has been authored into them.

From the player's side that reads as a game with one place, one enemy and one difficulty. There is a single Map, so every Run happens in the same room; a single `Enemy_Kind`, so every threat is the same threat; and eight weapons of which two are labelled placeholders in their own source comment, so the tier ladder is a price list rather than a set of choices. Nothing on the enemy side can catch the player — every enemy moves at 30–50 against a player at 100 — so kiting is unconditionally correct and never stops working. There is no ending: a Run has a win condition but the game has no last room, so clearing is a thing that happens rather than a thing you were climbing towards.

The result is that the player learns the game in one Run and then repeats it. Account progression keeps handing out numbers, but there is nothing new for the numbers to be spent against.

## Solution

Author content along four axes at once, because each one alone is defeated by the others: more enemies in the same room is still one room, and a harder room with the same weapons is still the same fight.

The player gets a **ladder of five Maps**, each a distinct hand-drawn place with its own colours and its own ambient character, entered from the Map Selection screen and unlocked by clearing the rung below. They get **nine Enemy Kinds** that arrive across those rungs, each one debuting to teach a lesson the rung below could not — a thing that ignores walls, a thing that punishes running in a straight line, a thing that claims ground you must leave, and finally a swarm where individual bodies stop mattering. They get **twelve weapons** — three families, four tiers — where climbing a tier buys a different way to fight rather than a bigger number, and the top tier of each family answers the thing that family cannot currently handle. And the ladder ends at a **boss**, a single large enemy that telegraphs its attacks, changes its rotation as its health falls, and is beatable by a player who learns to read it.

Underneath, three pieces of machinery are replaced rather than extended, because the content cannot land on top of them: per-enemy pathfinding becomes one shared flow field, a melee weapon's hit volume becomes the weapon the player can actually see, and the Map's own composition entries stop carrying behaviour templates and carry a Kind and a count.

## User Stories

### Playing the ladder

1. As a player, I want to see five Maps on the Map Selection screen, so that I can see how far the game goes before I have played it.
2. As a player, I want each Map to show whether I have cleared it, so that I know where I am on the ladder.
3. As a player, I want a locked Map to be visibly locked rather than absent, so that a rung I have not reached still reads as a destination.
4. As a player, I want the lock to say what unlocks it, so that I do not have to guess whether the requirement is a clear, a Level, or an amount of Gold.
5. As a player, I want rung 1 always open, so that a fresh Account has somewhere to start.
6. As a player, I want clearing a rung to unlock exactly the next one, so that progress up the ladder is legible and monotone.
7. As a player, I want my cleared rungs to survive quitting the game, so that the ladder is Account progress rather than session progress.
8. As a player, I want to replay a rung I have already cleared, so that I can farm a rung I am comfortable with or practise one I barely survived.
9. As a player, I want a cleared lower rung to still be worth playing, so that the safe choice is a real choice rather than a wasted Run.
10. As a player, I want each rung to look different at a glance, so that I can tell which rung a screenshot or a mid-Run glance is from.
11. As a player, I want each rung to be the same place every time I enter it, so that I can learn its geometry and get better at it specifically.
12. As a player, I want a Run to be one attempt at one rung, so that a death costs me one rung's worth of time and not a whole ladder climb.
13. As a player, I want the reward for clearing to grow as I climb, so that the harder rung pays for its own risk.
14. As a player, I want to bank my Gold even when I fail, so that a lost Run is still progress.
15. As a player, I want the time limit to be slack for mopping up rather than a race, so that a rung is hard because of what is in it and not because of a clock.

### Facing the roster

16. As a player, I want more than one kind of enemy, so that a Run is a set of problems rather than one problem repeated.
17. As a player, I want to tell an enemy's kind apart at a glance in a crowd, so that I can prioritise under pressure.
18. As a player, I want an enemy's colour to tell me how it moves, so that I can read an unfamiliar body the first time I see it.
19. As a player, I want an enemy's size to tell me roughly how much health it has, so that I can judge whether to commit to it.
20. As a player, I want a new kind to debut on a specific rung, so that I meet it in a controlled setting rather than in a swarm.
21. As a player, I want at least one enemy that ignores walls, so that a corner is not an unconditional safe spot.
22. As a player, I want at least one enemy that can out-run me for a moment, so that backing away in a straight line stops being free.
23. As a player, I want that charging enemy to commit to a line I can see, so that its speed is something I dodge rather than something that catches me.
24. As a player, I want at least one enemy that claims a patch of ground, so that standing still has a cost.
25. As a player, I want an enemy that shoots from cover, so that some threats have to be approached rather than kited.
26. As a player, I want a swarm rung where individual enemies stop mattering, so that the crowd itself is the problem.
27. As a player, I want swarming enemies to surround me around the outside of walls rather than through them, so that the crowd behaves like a crowd.
28. As a player, I want an enemy that never chases me, so that some of a rung's threat is positional rather than pursuing.
29. As a player, I want heavier enemies to be worth more Gold, so that the risk of engaging them is paid for.
30. As a player, I want the enemies chasing me to path around geometry rather than grinding into it, so that a wall is cover and not an exploit.
31. As a player, I want an enemy never to spawn somewhere it cannot reach me from, so that a Run never stalls waiting for a body I cannot find.
32. As a player, I want a hundred-plus enemies on screen without the frame rate collapsing, so that the swarm rung is playable.
33. As a player, I want enemies to spread out rather than stacking into one body, so that a crowd is a crowd and not a single overlapping blob.
34. As a player, I want enemies not to hard-block each other, so that a wall of bodies does not become an invulnerable shield for the shooters behind it.

### Fighting the boss

35. As a player, I want the final rung to have a boss, so that the ladder ends in something rather than stopping.
36. As a player, I want the boss to have visible health, so that I can tell whether I am winning.
37. As a player, I want the boss to telegraph a big attack before it lands, so that being hit is my mistake.
38. As a player, I want the telegraph to show me where the attack will land, so that I know which way to move.
39. As a player, I want the telegraph to show me when it will land, so that I know how long I have.
40. As a player, I want the telegraphed area to appear at its full size immediately, so that I never mistake a growing zone for a smaller attack.
41. As a player, I want the telegraph's duration to be the same every time regardless of the boss's state, so that my reaction time is a skill I can learn.
42. As a player, I want the boss to commit to an attack once telegraphed, so that dodging is possible at all.
43. As a player, I want the boss to plant itself while telegraphing, so that a committed attack has a cost for the boss too.
44. As a player, I want a landing attack to shake the screen whether or not it hit me, so that the world reacts to it.
45. As a player, I want the boss to change how it fights as its health falls, so that the fight has an arc.
46. As a player, I want to be able to tell which phase the boss is in, so that its change of behaviour reads as a phase rather than as randomness.
47. As a player, I want the boss's adds to arrive on the rung's own schedule, so that killing it faster is never punished with more enemies.
48. As a player, I want the boss to drop a guaranteed payout, so that beating it is unambiguously worth it.
49. As a player, I want killing the boss to clear the rung, so that the win condition matches what the fight looks like.
50. As a player, I want the boss room to be readable, so that the last fight is about the boss and not about the geometry.

### Choosing and using a weapon

51. As a player, I want twelve weapons rather than eight, so that the families are worth choosing between.
52. As a player, I want each family to have four tiers, so that a Run has a ladder to climb inside the Shop.
53. As a player, I want a higher tier to fight differently rather than just harder, so that buying up is a decision and not an inevitability.
54. As a player, I want a free starting pick at the bottom of each family, so that starting a Run is a choice about how I want to play.
55. As a player, I want the free pick never to skip me up the ladder, so that the Shop's weapon slot stays useful for the whole Run.
56. As a player, I want the Ranged family to have an answer to a crowd, so that picking Ranged does not lock me out of the swarm rung.
57. As a player, I want a piercing weapon to hit each body once per shot, so that a pierce is a line through a crowd and not a stutter of hits on one enemy.
58. As a player, I want the Melee family to buy reach, so that its swarm problem — standing inside the crowd — has an answer.
59. As a player, I want the Magic family to buy single-target burst, so that it has something to say about the boss.
60. As a player, I want a melee weapon to hit exactly what its blade touches, so that what I see is what connects.
61. As a player, I want a melee hit to register during the swing rather than after it, so that the animation is the attack.
62. As a player, I want a fast weapon not to skip past a small enemy between frames, so that a Mite cannot be swung through.
63. As a player, I want one hit per swing per enemy, so that a slow sweep is not secretly a multi-hit.
64. As a player, I want a thrusting weapon to thrust rather than sweep, so that its silhouette and its motion agree.
65. As a player, I want each weapon to look distinct in the world and in the menu, so that I can tell what I am holding.
66. As a player, I want to stop being told about reserve ammo that does not exist, so that the indicator only shows me things that can change.
67. As a player, I want every pickup I collect to do something, so that a drop is never a no-op.

### Reading the world

68. As a player, I want each Map to have its own floor and wall colours, so that the rungs are distinguishable without reading a label.
69. As a player, I want the Map Selection swatch to match the Map, so that the menu never advertises a colour the world does not have.
70. As a player, I want each Map to have its own ambient character, so that colour alone is not carrying five places.
71. As a player, I want ambient effects never to hide an enemy, so that atmosphere never costs me information.
72. As a player, I want the screen edges kept clear, so that I can see enemies entering.
73. As a player, I want telegraphed ground and floor decoration to draw beneath the bodies standing on them, so that the actors are never occluded by the ground.
74. As a player, I want my own poison clouds to draw above the enemies they are killing, so that I can see my own effect landing.
75. As a player, I want the world's lighting to stay the same when a menu opens over it, so that opening the Shop does not recolour the game behind it.

### Authoring the content

76. As a developer, I want to author an enemy as a named Kind with its stats in one place, so that adding an enemy is one table entry.
77. As a developer, I want a Map's spawn composition to name a Kind and a count, so that authoring an encounter does not mean re-specifying behaviour.
78. As a developer, I want an enemy's identity fixed at its Kind, so that nothing modifies a body after it spawns and every enemy on screen is explainable by its colour and size.
79. As a developer, I want to tune enemy stats in the editor with sliders, so that balancing does not mean a rebuild per value.
80. As a developer, I want those tuned values exported back into source, so that the roster stays in version control and diffable.
81. As a developer, I want the roster never to become a loadable data file, so that it never re-enters the marshaller that is known to guess union variants wrong.
82. As a developer, I want to draw a Map's layout by blocking out rectangles, so that authoring five places is a session's work rather than a tile-by-tile job.
83. As a developer, I want to create a new Map from inside the editor, so that adding a rung does not start with hand-writing a file.
84. As a developer, I want to author a Map's rung, start position, time limit, victory multiplier and colours in the editor, so that everything a Map owns is authored in one place.
85. As a developer, I want a broken Map to fail a test rather than ship, so that an unreachable spawn or an off-floor start is caught before a player finds it.
86. As a developer, I want a malformed preset to fail a test, so that the roster's conventions are enforced rather than remembered.
87. As a developer, I want a persisted Kind to survive its enum being renumbered, so that inserting an enemy does not silently rewrite existing saves.
88. As a developer, I want an unrecognised persisted name to be an error, so that a dropped Kind is never silently skipped into a rung that spawns fewer enemies and clears anyway.
89. As a developer, I want to see the flow field as a debug overlay, so that I can tell reachability problems from steering problems.
90. As a developer, I want the debug visualiser named for what it draws, so that the overlay list does not describe a deleted system.

## Implementation Decisions

### The substrate: how enemies move

- **Per-enemy pathfinding is deleted and replaced by one shared flow field flooded outward from the player.** The per-enemy BFS, its path type, its node budget, and the per-enemy stored path all go, as does the Swarmer slot assignment. At 250 bodies the old model cost up to 256,000 node visits and roughly a thousand allocate/free pairs per frame; the field is one flood of about 2,600 visits. [ADR-0025](../../docs/adr/0025-enemies-steer-by-a-shared-flow-field.md).
- **The field rebuilds when the player changes cell, not on a timer** — so it is exact rather than merely fresh.
- **Inverting the search is the point.** A cell the flood never reached is unreachable, which is a better answer than a path search that failed. The old node budget was propping up a second bug: absent tiles read as walkable, so nothing bounded the world at all.
- **The field is keyed by inflation radius**, so the boss's larger body gets its own second field rather than a special case.
- **Steering splits on whether a Movement Style collides.** A non-colliding style never reads the field. Its straight-line movement, which was wrong for a retreating ranged enemy, is correct for one that shoots from inside geometry.
- **Swarmer's ring slots are deleted rather than fixed**: follow the field to the surround radius, then drift along that contour. This makes both known Swarmer bugs unrepresentable and produces a ring that wraps walls instead of cutting through them.
- **Actor-versus-tile movement uses the field's cell-indexed solid set.** The current scan checks every tile twice per actor per frame — about 852,000 rect checks a frame at 250 bodies, larger than the pathing it survives alongside. This fixes the player's movement too.
- **Spawn points are reachability-checked against the field.** An unreachable spawn currently holds the Cleared condition open forever.
- **No hard enemy-enemy collision.** A solid crowd would be a shield for the shooters behind it. Separation stays, sampling a bounded neighbour count rather than degenerating to n² in the converging case.
- **The debug visualiser for pathing is renamed to name the field**, and the Swarmer ring it used to draw is cut.

### The roster: what an enemy is

- **`Enemy_Kind` is the authored unit.** It keys a preset table carrying movement, attack, max health, colour and Gold; the separate Gold preset table is absorbed into it, and the base-gold-times-multiplier pair collapses to one field. [ADR-0020](../../docs/adr/0020-enemy-kind-is-the-authored-unit.md).
- **A Map's spawn composition entry collapses to a Kind and a count.** This removes enemy behaviour unions from persistence entirely, taking their save mirrors and the map builder's literal writers with them.
- **Behaviour lives on the axes; identity lives on the Kind.** The Movement and Attack axes stay open and shared; what makes a Grunt a Grunt is its preset row, not a private branch.
- **Nothing modifies an enemy after it spawns** — no elite tier, no affix, no per-rung scaling, no aura, no Run-wide multiplier. All three identity channels are already spent: colour on the Kind, size derived from max health, opacity on the health fade, so a modifier has nowhere to mark itself. A heavier enemy is an ordinary Kind with more health. "Elite" gets no glossary entry, because a term with no mechanism is how the idea returns under a new name.
- **The per-rung health ceiling constant is deleted**; there is no health scaling by rung.
- **The concurrent-enemy cap rises to 4096 and stops being a design input** — it is a safety rail against a runaway repeating trigger, not a budget. The swarm rung is authored at 150–250 concurrent, a number set by screen legibility.
- **The body-size clamp rises** so the boss can be drawn at its authored health without the size derivation changing.
- **A composition entry persists its Kind by name, not by ordinal**, so inserting a Kind does not renumber existing saves.
- **The roster is nine Kinds across six of the fifteen movement-by-attack cells:**

| # | Kind | Movement | Attack | Health → px | Hue | Debuts | Gold | The pressure |
|---|---|---|---|---|---|---|---|---|
| 1 | Grunt | Grounded 40 | Melee | 50 → 24 | green | 1 | 30 | the baseline; kiting works |
| 2 | Spitter | Grounded 35 | Ranged | 35 → 20 | pale green | 1 | 20 | the light ranged accent |
| 3 | Wraith | Floater 45 | Melee | 55 → 25 | violet | 2 | 35 | you cannot put a wall between you and it |
| 4 | Lancer | Charger 55 / dash | Melee | 60 → 27 | red | 2 | 50 | punishes kiting in a straight line |
| 5 | Sentry | Inert | Ranged | 70 → 30 | cyan | 3 | 35 | chip from fixed ground; you must cross to it |
| 6 | Breaker | Grounded 30 | Tell-area | 130 → 46 | deep green | 3 | 80 | claims ground; survives standing still |
| 7 | Mite | Swarmer 65 | Melee | 20 → 16 | yellow | 4 | 3 | count, not quality |
| 8 | Gazer | Floater 25 | Ranged | 30 → 18 | pale violet | 4 | 20 | shoots from inside the geometry |
| 9 | Warden | Grounded, fixed | Tell-area rotation, 3 phases | ~220 → ~72 | near-white | 5 | 250 | the boss |

- **Each Kind debuts on one rung and thins as later rungs add their own** rather than accumulating flatly.
- **Nothing on the current roster can catch the player.** The rule is sustained speed under 70, with **`Charger`** — the one new Movement Style — the only thing exceeding it, and only along a locked line for a bounded dash. The dash reuses the Tell's vocabulary with lane geometry instead of a patch, so it spends no Attack Style slot.
- **Five movement families force an evenly spaced repalette** — Grounded green, Swarmer yellow, Floater violet, Charger red, Inert cyan — held in named constants that the preset table reads, so hue-means-family is enforced rather than advised. This is the change that must land in the same commit as the preset rewrite: two of the three current colour constants are *inverted* against the new palette, not merely stale, so a build that lands one without the other reads the roster wrong.
- **The boss's licence to break the hue convention is a licence on value, not hue** — the Warden is near-white, because no hue is left.
- **Payout anchors at 0.6 × max health**, with named deviations. The Mite is the largest deviation at 3 Gold: Gold rolls per body, so at swarm density an anchored Mite would break the ladder's shallow victory multiplier.
- **Heavy Kinds cap at roughly 136 health**, because one shared inflated collision field serves every ordinary enemy; the boss's own second field is affordable only because there is exactly one boss.
- **The one remaining Attack Style slot is banked.** Fifteen cells is far more than a nine-entry roster exhausts.

### The ladder: what a Map is

- **Map layouts stay hand-authored — one drawn file per rung.** Generation and hybrid chunk assembly were both rejected: the ladder's rungs are meant to be distinct learnable places, and generation would have to re-earn by construction the connectivity and spawn-placement guarantees hand-drawing gives by eye. [ADR-0021](../../docs/adr/0021-map-layouts-are-hand-authored-places.md).
- **The tile atlas coordinate field and the editor's tileset palette are deleted.** Nothing has read them since tiles became flat fill keyed off whether they collide, which is what makes drawing a map a matter of blocking out rectangles.
- **The editor gains map-level authoring it currently has none of**: new map, player start, time limit, victory multiplier, rung, and the Map's colours.
- **A Map is a fixed place with a variable encounter.** There is no Run seed.
- **Five rungs, ordered by an authored rung field on `Map`, each gated by clearing the rung below**, with rung 1 always open. [ADR-0022](../../docs/adr/0022-map-rungs-are-gated-by-clears.md).
  1. **Desert Dungeon** — exists, re-tuned.
  2. **Warren** — tight geometry; melee from an unseen bearing.
  3. **Hall** — open ground with fixed threats to cross to.
  4. **Ring** — swarm density at peak trigger overlap.
  5. **Boss keep** — deliberately legible geometry; escalation stops here.
- **Gating on a Level was rejected**: Level measures banked Gold, so a Fortune-style stat would compound into ladder access.
- **The Account gains a cleared set, one flag per Map, persisted by identity string rather than enum ordinal**, since the Map name enum is generated in filename order.
- **A Run is one rung attempt.** The gauntlet reading — climbing several rungs in one Run — was rejected.
- **The difficulty curve is carried by roster and Spawn Trigger density**, with layout hostility secondary. Footprint, Run length and enemy health stay flat across rungs.
- **The time limit is mop-up slack** — the timeline's end plus slack — authored per Map, not a difficulty axis. A tighter limit makes a rung unwinnable rather than hard. A limit of zero or less still means untimed.
- **The victory multiplier rises shallowly** across the ladder, because gross income already climbs with the roster. Failing still banks at face value, so reliability is what keeps a lower rung worth playing.
- **Map footprint is held near its current size.** The original reason (a node budget that could not span the existing map) is gone with the flow field, but the reason to hold it — a rung should be a learnable place — stands.
- **Map Selection reworks to show the ladder**: rung order, cleared state, and a lock glyph with its requirement. Its visual language is otherwise unchanged.

### The Map's own look

- **A Map authors a floor colour, a wall colour and its set of ambient effects, on `Map` itself.** The separate presentation-only icon colour table is deleted and the Map Selection swatch derives from the wall colour, so the menu cannot advertise a colour the world lacks. [ADR-0024](../../docs/adr/0024-a-map-owns-its-visual-identity.md).
- **Two authored colours, not three or four.** The floor sits on the wall's hue ramp; a third authored colour buys an accent nothing asked for.
- **A code-side theme table keyed by map name was rejected** on its failure mode: a sixth map file would get a transparent floor with nothing to catch it.
- **Colour alone does not carry five Maps**, so the ambient set is authored per Map rather than fixed and tinted. The three effects are motes, off-grid floor patches, and a directional light wash.
- **No vignette.** The screen edges are where enemies enter. This establishes the general rule: an ambient effect carries no information and must never occlude any.
- **Ambience keeps its own budget and its own two z-slots**, never the shared particle pool.
- **Tile rendering is untouched.** Flat fill for floor and wall, a darker inset bevel on walls, wall-versus-floor read from whether the tile collides. Floor patches are a decal, so the locked no-per-tile-colour-noise rule stands.
- **The world introduces a named ground layer, defined by whose information it carries.** Floor patches and Tell zones draw under the actors, because they are the world speaking. Poison clouds stay above the bodies they are killing, because a cloud is the player's own output.
- **The light wash draws inside the world pass as a world-space quad**, so the world does not change colour when a menu opens over it.
- **The tilemap draw culls to the visible rect.**

### The boss

- **The boss is an `Enemy_Kind` in the ordinary enemy pool**, not its own type — so killing it *is* the last enemy dying, and the existing Cleared condition needs no change.
- **Three phases on health thresholds, changing the attack rotation and nothing else.** Movement Style is fixed for life.
- **Adds come from the timeline, never from the boss**, so the timeline stays the only answer to "can more enemies arrive".
- **Attacks go through a new Attack Style variant carrying a Tell** — the enemy-side telegraph — shared with ordinary Kinds rather than reserved for the boss. The phase rotation lives inside that variant.
- **A Tell is timed in absolute seconds, not as a fraction of a cycle.** The fraction-based invariant that governs weapon windup has no enemy-side existence, and a learned reaction time must stay stable across phases. [ADR-0023](../../docs/adr/0023-enemy-tells-are-absolute-durations.md).
- **A Tell belongs to committed area attacks only.** Telegraphing an ordinary volley read as noise, so the reopened Attack Style slot narrows to "an attack that claims ground". The committed-action rule carries over: once telegraphed, the attack resolves.
- **A Tell shows as the claimed ground plus a body flash** — the floor says *where*, the body says *when*. Body-only forms were rejected: at the distances involved, "something is coming" is not actionable.
- **The zone draws at full extent from the first frame and fills as the Tell runs**, so a growing zone is never mistaken for a smaller attack.
- **0.55 seconds is the reference for a committed area attack, authored per attack rather than per Kind.** From the prototype on `prototype/boss-tell`, the variant holds a rotation of attack-and-tell-duration pairs, per phase:

  ```
  Tell_Area :: struct {
      phases: [3][]struct { attack: Area_Attack, tell_seconds: f32 },
      ...
  }
  ```

- **The area locks its bearing at Tell start** and the enemy plants for the whole duration. This closes the deferred question about whether the enemy-side telegraph follows the existing ground-targeted-cast lock rule: it does.
- **Screen shake on resolve, hit or miss.**
- **Phases are legible on the resource indicator alone** — no palette shift, freeze, or burst. There is a third cue that comes free: pacing, since a phase tightens recovery as well as changing the rotation.
- **The boss carries a health indicator.** Ordinary enemies have had none since the body-fade change, so this is a restoration rather than an exception to the world-space indicator rule.
- **The boss spawns from its own one-shot trigger at t=0 with a reserved concurrency slot**, and paths against a size-derived inflation radius — its own second flow field.
- **The boss's guaranteed drop is a field on its preset**, read where the pickup roll already reads the payout, not a branch at the call site.

### Weapons

- **Twelve weapons — three families, four tiers each:**

| Family | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| Ranged | Pistol | SMG | Shotgun | **Rifle** |
| Melee | Dagger | Sword | **Spear** | **Greatsword** |
| Magic | Fire Wand | Flame Staff | Poison Staff | **Lightning Staff** |

- **Tier 0 is the only free pick**, amending [ADR-0008](../../docs/adr/0008-weapon-family-is-run-scoped.md). The family kind list was being read two ways at once — as the Shop's priced ladder and as the Run Start menu — so a tier-2 free pick cost 0 Gold, arrived mid-ladder, and left the Shop's weapon slot dead for the whole Run. There is one list, with a corrected comment, and one reader.
- **The developer hotkey that cycles weapon kinds is retired**, removing that list's second reader and a cheat that skips the priced ladder.
- **Climbing a tier buys a different style, not a bigger number.** Each family's top tier answers what its lower tiers cannot: **Ranged buys the crowd** (a piercing Rifle — every gun bullet currently stops on first hit, which is why Ranged was the family locked out of the swarm rung), **Melee buys distance** (Spear then Greatsword — melee already sweeps uncapped, so its swarm problem was standing inside the crowd, not throughput), **Magic buys the boss** (an instant hitscan Lightning Staff — the only thing in the game that spawns no travelling projectile, which is what stops a no-area magic bolt being a Pistol).
- **Dagger and Sword keep tiers 0 and 1** and lose only their placeholder comment. Fire mode gets no rule: it is not a tier axis.
- **A pierce is tracked by shot identity, not target identity** — a per-shot id recorded on the enemy — because index-based memory names the wrong enemy after an unordered removal at swarm density, and positions are no better.
- **A weapon's hit volume is the weapon itself, tested live across the swing.** The melee cone is deleted. [ADR-0026](../../docs/adr/0026-a-weapon-hits-only-what-it-touches.md).
- The prototype on `prototype/weapon-hit-volumes` drew the two failures sharper than the ticket had: a Sword resolved with its blade at one extreme of a cone it had already swept, so the sweep the player watches was entirely *after* the attack; and the cone measured from the feet anchor while the blade draws from a pivot 12px above it.
- **The volume is an arbitrary set of polygons per kind, authored in the glyph's unit space and rigid on its pivot frame**, in a parallel table with a test. The guard and grip carry no volume.
- **Overlap is swept between consecutive frames.** A Greatsword crosses its arc in about 0.07s and moves its tip 50–90px on the opening frame — enough for a 16px Mite to be touched by nothing. Sampling only at the resolve instant re-tells the same lie quietly.
- **One damage per swing per body, on its own id counter** rather than sharing the bullet counter, so a future weapon switch gives the two independent lifetimes.
- **The swing's active window stops being reconstructed inside the draw call** from cooldown arithmetic. Follow-through carries both fire modes and stops being cosmetic: a Sword now has both a windup and a follow-through, which ends fire mode's role as the sole gate.
- **`Arc_Width` is Melee's only family Upgrade slot and it scaled the deleted arc.** It repoints to range and is renamed **Reach**.
- **`Clip_Size` changes from Additive to Multiplicative.** It is the only Additive Upgrade whose base varies fivefold across the family, so its flat bonus reads as +333% on one weapon and a rounding error on another.
- **The per-kind swing arc moves onto the weapon's visual record, which stops being cosmetic-only.** This buys the Spear its thrust for free: an arc near zero is a plant rather than a broken sweep.
- **Enemies get no hit volumes.** No drawn weapon, no lie to fix. Enemy melee uses its attack range measured surface to surface, which is what makes the Breaker reachable at all.
- **The cone survives as the flamethrower's own**, where it was always honest.
- **Per-kind weapon geometry stays derived from the kind at draw time and never stored on the weapon** (it serialises into the save file), with distinctions that are **countable rather than proportional** — a rule that now binds the weapon visual table too, not just the icons. [ADR-0018](../../docs/adr/0018-weapon-visual-identity-is-per-kind-not-per-family.md).
- **The gun reserve is deleted entirely** — the reserve count, the refill, both clip constants, the reload arithmetic that reads them, and an unreachable empty-weapon indicator state. Its starting value was an absurd constant written as a joke, which pinned open the machinery for a mechanic the game had decided not to have.
- **The Ammo pickup kind is deleted with it.** It was a no-op on a third of every drop roll. Pickups are Gold and Health.

### Persistence and the editor

- **One parametric enum-to-identity-string helper**, used for both Map names and Enemy Kinds.
- **Its read path errors on an unrecognised name** rather than falling through to the zero value. The existing silent skip is survivable for a menu default and not for a spawn composition, where a dropped Kind means a rung spawns fewer enemies and clears anyway.
- **Union variant guessing is confirmed broken here.** A trigger round-tripped back as a different variant, silently wrong. Spawn Trigger's own condition and mode unions still go through it and still need their explicit discriminants; enemy behaviour unions no longer touch persistence at all.
- **The editor keeps a tuning surface, in its own mode, and persists by writing the preset table's Odin literal.** It does not gain a loadable data format: a preset file would undo the Kind-as-authored-unit decision and hand the roster back to the union-guessing marshaller exactly as the boss's phase rotation makes it a nested union. [ADR-0027](../../docs/adr/0027-the-editor-generates-source-it-does-not-gain-a-data-format.md).
- **The generated-source path is one-directional and diffable**, and the roster stays in git. The precedent is the existing map literal writer.
- **The existing spawn-composition sliders are deleted** along with the behaviour templates they tuned; the new mode replaces them.
- **The existing authored Map fails the new validity test today** — it has untitled holes that are its doorways, its start position among them, walkable only because an absent tile reads as non-colliding. It is patched in the same change that lands the test.

### Landing order

The stages are dependency-ordered rather than grouped by system, because the concrete failure mode is landing the roster before the substrate and concluding the roster is the mistake.

1. **Substrate** — flow field, pathfinder deletion, cell-indexed solid set, collide-or-not steering split, spawn reachability, separation neighbour cap, visualiser rename.
2. **Persistence shape** — identity-string helper, composition entry to Kind-and-count, save-mirror deletions, the existing map file rewritten, the Account's cleared set.
3. **Roster** — the preset table, health-ceiling deletion, raised concurrency cap and size clamp, `Charger`, per-Kind attack range, the preset test, the editor's Presets mode.
4. **Maps and ladder** — atlas coordinate deletion, `Map` gains rung and theming, the editor's map-level panel, the validity test, the existing map patched, Map Selection rework.
5. **Weapons** — hit volumes, Reach rename, Clip Size to Multiplicative, twelve icons, hitscan, pierce ids, hotkey retirement, reserve deletion.
6. **Boss and presentation** — Tell variant, guaranteed drop, boss collision field, boss indicator, ground layer, ambient pool, light wash, tilemap culling.

## Testing Decisions

A good test here asserts external behaviour: what a caller can observe from a proc's return value or from the game state after a tick. It does not assert on intermediate structure, and it does not restate the implementation. Tests are package-level Odin test procs in an area's own test file, calling the real proc with throwaway structs — no harness, no mocks, no fixtures. Where a test touches the shared game global it must be run single-threaded, and the existing files say so in a comment at the top; prefer constructing a local value so the discipline is unnecessary.

Three kinds of seam, and only one of them is new.

**Content validity — new in kind.** These assert over the *authored tables* rather than over behaviour, which no existing test does. Two of them.

- *Map table validity*, in the existing map test file: every authored Map is connected, its start position is on a floor tile, its spawn ring is reachable, its extent is within bound, its rung is unique and the rungs cover 1 through 5, its time limit clears its timeline end or is untimed, and its colours are authored. Seven checks. The existing Desert Dungeon fails this today and is patched alongside it.
- *Preset well-formedness*, its own file: each Kind's hue matches its movement family's constant, its size is within the clamp and within the inflation envelope, its sustained speed is under 70 unless it is a `Charger`, its payout sits near the 0.6× anchor or is one of the named deviations, and every Kind appears in at least one authored composition. This turns the roster's conventions from remembered rules into checked ones.

**Behaviour, at seams that already exist.** No new files, no new abstractions.

- *Flow field and steering*, where the spawn tests already build throwaway tilemaps: a flood over a hand-built tilemap descends towards the player, an enclosed pocket is never filled, a non-colliding style ignores the field, and a Swarmer reaching its surround radius drifts along the contour rather than crossing a wall.
- *Hit volumes*, on the icon test file's precedent — those tests already assert weapon reach in the glyph's unit space, which is the same space the volumes are authored in. Assert containment of the volume within the drawn glyph, that a body crossed between two frames is caught by the sweep, and that one swing damages one body once.
- *Ladder gating and the cleared set*, on the account progression file: rung 1 open on a fresh Account, clearing rung *n* opening exactly *n+1*, a cleared set round-tripping through the identity strings, and an unrecognised name erroring rather than resolving to the zero value.
- *Tell timing*, on the weapon test file's lock-at-trigger precedent: the Tell duration is unchanged across phases, the bearing is fixed at Tell start and not at resolve, and the attack resolves even if the enemy would rather not.

**One integration seam.** In the run objective file, which already ticks the Cleared and timeout conditions against a fabricated timeline but never involves a real Map or real enemies. Extend it to drive one authored rung headless: build the Map, tick the timeline for its duration, assert Cleared fires, and assert no enemy is ever stranded outside the field. This is the only seam above the parts, and it covers the two risks that are individually on record — a pocket spawn holding Cleared open forever, and the roster landing before the substrate — which every part-level test passes through unnoticed.

Deliberately untested: rendering of any kind (ground layer, light wash, tilemap culling, the twelve icons), the editor's export path, and every balance number. The first two have no assertable output short of pixel comparison; the third is playtesting.

## Out of Scope

- **Implementation is the point of this spec, but balance is not.** Every number in the tables above is a starting point for playtesting. Three are not free to move and are called out in the map's fog: the Breaker's health against the inflation envelope, the Warden's against the size clamp, the Mite's Gold against a per-body drop roll at swarm density. Two more come from weapons: the Lightning Staff's damage against the Warden's health and the Damage upgrade ceiling, and the Spear's tip width — the one number whose being wrong reads as broken machinery rather than a weak weapon, since a blade's collider is narrowest exactly where it reaches furthest. Every melee range needs re-tuning rather than renaming, because the volume moved 12px from the feet to the pivot.
- **Procedural map layout generation.** Considered and rejected; a coherent future effort if a rung count ever outgrows what a person will draw, but a fresh one.
- **Endless, prestige or ascension modes.** What happens after all five rungs are cleared is past this destination. Rungs stay replayable and Account progression is already unbounded.
- **New Relics, Upgrades and Account stats.** Adjacent content axes, not among the four selected; each needs its own balance frame.
- **UI and menu chrome redesign.** Map Selection's *information* needs are in scope; its visual language is settled elsewhere.
- **Audio for any new content.** Untouched here and standing fog on two other maps.
- **New pickup kinds.** Half-answered by the Ammo deletion, which leaves a coin-flip drop roll. Whether the roster grows is still open, now with the rule the deletion established: the game rolls once per death, so every kind added dilutes every other one.

## Further Notes

- **Three file-placement questions are the implementer's**, handed over deliberately rather than guessed at: where the flow field lives relative to the enemy code, where the hit-volume table lives relative to the glyph geometry, and where the ground layer's draw sits relative to the existing world draw. Each has a defensible answer either way and none of them changes a decision above.
- **Three prototypes are on branches** and are primary sources for the decisions they settled: `prototype/boss-tell`, `prototype/map-theming`, `prototype/weapon-hit-volumes`. They are throwaway; only the decisions came back.
- **This effort amends two other maps' scope boundaries.** The enemy behaviours map had ruled Attack Style expansion out of scope; that is reopened, with an amendment pointer recorded there. The shop and upgrades map's weapon-cycle hotkey fog is closed by the retirement above. The art revamp map's per-frame transform fog is closed by the tilemap culling — the cost was real and in neither place that map suspected.
- **The colour constants are the one ordering trap inside a stage.** Two of the three current enemy colour constants are inverted rather than stale against the new palette, so the repalette must land in the preset rewrite's own commit.
- **Where an existing comment argues against a decision here, the comment is usually right about its own moment and wrong about now.** Three cases: the icon colour table's own comment anticipated its promotion and warned what it would cost; the weapon pivot comment defended keeping visuals from changing reach, reasoning that inverts once the volume *is* the visual; and the shop's comment already asserted the opposite of the ADR it was implementing.
