# 17: The four new Maps

**What to build:** Four more places to play, each a different shape of fight and
each pulling from the roster differently — so climbing the ladder means meeting
new enemies in rooms that suit them, not the same room with bigger numbers.

**Blocked by:** 14, 15, 11

**Status:** resolved

- [x] Four Maps are authored beyond the existing one, filling rungs two through five
- [x] Each has its own layout, palette, ambient set, time limit and payout multiplier
- [x] Each has a composition timeline that introduces its rung's debuting Kinds
- [x] All five pass the Map validity test

## Comments

Rung two is currently occupied by `data/maps/cold_hall.json`, a second Map
added while building ticket 13 so per-Map theming had two Maps to be tested
against. Its layout is generated (a colonnaded hall) rather than hand-drawn
and its timeline is the Desert Dungeon's re-paced, so it is a fixture, not
one of this ticket's four. Replace or rebuild it here rather than authoring
around it.

Done. The ladder is Desert Dungeon (1), Root Warren (2), Cold Hall (3),
Ember Ring (4), Pale Keep (5), each a `data/maps/<slug>.json` baked into
`maps.odin`. Cold Hall was rebuilt rather than replaced: its name, cold
palette and `{Floor_Patches, Light_Wash}` set were already the Hall's, so it
kept those and got the rung-3 layout (a nave between two colonnades, one
dais of cover, full-width sightlines) and the rung-3 timeline in place of
the generated colonnade and re-paced Desert timeline it had as a fixture.

Layouts follow the briefs in `../../content-expansion/issues/03-map-ladder-shape.md`.
Every passage is at least three cells wide, because enemies steer by the
flow field at a Chebyshev inflation radius of one: a two-wide corridor is a
place the player can stand and nothing can follow, which no Map may have
(the sweep's spawn-ring check only samples 64 points; the authoring pass
checked every floor cell against `flow_field_reaches`'s rule, and none of
the four has one an enemy cannot get to). The Warren's tunnels are three
wide with a corner or hairpin in every one and root columns breaking its
chambers, so its longest straight run is 21 cells against a 50-cell view;
the Ring is an eight-wide track around a core, with four-deep spurs
staggered from both walls so the loop is walked as a zigzag, and the core
is a dense pillar field on a five-cell pitch entered by one offset cut per
face - cover against everything that walks and nothing against a Gazer; the
Keep is one court with four buttresses.

Timelines follow `04-enemy-catalog.md`'s per-rung mixes. Desert Dungeon was
re-tuned to its own rung: Grunt and Spitter only, two `Time_Elapsed`
triggers, no kill gate — its Wraith/Gazer/Mite/Lancer entries were there so
every Kind appeared in some composition before the other rungs existed. The
first `Kills_Reached` gate is Cold Hall's. Ember Ring is `Time_Elapsed`
only, per the catalog's note that a swarm satisfies a kill gate in seconds.
Slack runs 90/75/60/45/30 s and multipliers 1.5/1.75/2.0/2.25/2.5.

Rung 5 has no boss to place — `Enemy_Kind` has no Warden until ticket 21 —
so Pale Keep's second trigger is a stand-in: two Breakers every 30 s, the
heaviest body the roster has, with the catalog's "thin Mite and Grunt only"
around it and nothing else. Ticket 21 replaces that line with the Warden;
noted there. Its wall is pale stone rather than near-white, which the
catalog reserves for the Warden.

Not measured here: the catalog's rung-4 target of 150–250 concurrent
bodies. Ember Ring feeds Mites at 2.7/s rising to 5.2/s, and what that
peaks at depends on kill rate; ticket 23's headless Run is where the number
can be read. Tune the Ring's intervals there if it lands short.

Two tests joined the validity sweep in `map_test.odin`, both over the baked
table: the Map at rung *r* places every Kind that debuts on *r* and no Map
places a Kind from above its rung (the debut table is authored in the test,
since it is a fact about the ladder rather than the preset); and the stakes
escalate — `victory_multiplier` strictly rising, slack past the timeline's
earliest end non-increasing. The Desert Dungeon load pin and the ambient-set
pin were re-pinned to the five Maps, and the account-progression test that
lifted rung 2 to a nonexistent rung 3 was deleted: the loop beside it now
has real rungs 3–5 to check. 320 tests pass.
