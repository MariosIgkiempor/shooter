# Save export/import

Type: prototype
Status:
Blocked by: 02, 03

## Question

How do the main menu's "Export save" and "Import save" work?

Charting locked that these exist and live in the main menu, as the mitigation for a player wiping site data and as desktop↔web save portability (same JSON blob). To lock: their placement in the hand-rolled menu (ADR-0010, ADR-0012's folded-in account progression), what export produces (a downloaded `.json` via the mechanism Browser save store recommends), what import accepts and how it confirms before overwriting the current save, and what a rejected import shows — ADR-0028 fails the load on an unknown identity, and on web there's no log for the player to read.

Build a rough menu prototype to react to. Links the prototype as an asset.

Lower priority than the tickets above it.
