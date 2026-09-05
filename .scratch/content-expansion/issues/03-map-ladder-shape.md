# Map ladder shape

Type: grilling
Blocked by: 02
Status: open

## Question

Maps become an ordered difficulty ladder rather than a flat set of options. What is the ladder's shape?

`Map` already carries the two fields a ladder needs — `time_limit` and `victory_multiplier`, the latter with an in-code comment that anticipates exactly this ("Authored per Map so a later, harder rung of the ladder can pay more for the risk it asks the player to carry", [map.odin](../../../map.odin)). Nothing consumes them as an ordering yet.

To settle:

- **How many rungs**, and what distinguishes each one as an experience rather than as a number.
- **What escalates.** Candidates: enemy mix (harder kinds appearing later), Spawn Trigger density and overlap, `time_limit` tightening, layout hostility, boss presence. Which of these carry the curve, and which stay flat?
- **What it pays.** `victory_multiplier` per rung, against the fact that Gold is the single currency and a Run's *net* take is what banks ([ADR-0016](../../../docs/adr/0016-gold-is-the-single-currency.md)) — a harder rung paying more has to be worth the higher chance of dying with an unbanked wallet.
- **Gating.** Are later rungs locked until an Account Level, cleared-predecessor, or nothing at all? `Account_Stat` already establishes `unlock_level` as this codebase's gating idiom; reusing it for Maps is available but not obviously right, since Level measures banked Gold rather than skill.
- **Presentation.** [hud.odin](../../../hud.odin)'s `draw_map_selection_ui` draws one button per `Map_Name` in a single column, with a swatch icon per map. That does not scale past a handful, and it has no vocabulary for "locked", "cleared", or "harder". Decide what the screen becomes — the layout work itself belongs to the implementation follow-on, but the information it must convey is decided here.
- **Does clearing a rung persist?** Nothing on the Account records which Maps have been cleared today. A ladder may or may not want that.

Blocked by [Map layout authoring model](02-map-layout-authoring-model.md): if layouts are generated, a "rung" may be a parameter set rather than an authored file, which changes what escalating across rungs even means.
