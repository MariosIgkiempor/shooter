# 12: The editor's Presets mode

**What to build:** Tuning an enemy is done by dragging sliders and watching the
game, then exporting the result — the editor gains a Presets mode that edits the
live preset table and writes it back out as source, the same way the map
generator already produces source rather than a second data format to keep in
sync.

**Blocked by:** 08, 11

**Status:** resolved

- [x] A Presets mode lists every Kind and exposes its authored parameters
- [x] Edits take effect in the running session
- [x] Export writes the preset table's source literal, ready to paste or overwrite
- [x] Nothing about presets is persisted as data; source stays the only authority

## Comments

Landed as a fifth `EditorMode`, `Presets`: every Enemy Kind as a collapsible
row (one open at a time, the Tuning accordion's node-budget shape), each
exposing the whole authored preset - a family switch and the variant's own
numbers for Movement and Attack, then max health, Gold and a swatch picker
over the family colour constants. Sliders write into `enemy_presets` itself
through the union, so the next body a Spawn Trigger stamps takes the new
numbers and a colour shows on bodies already on the field; a body keeps the
numbers it was born with (ADR-0020), which the panel says. `Export Source`
writes the table back out as Odin; `Revert` (per Kind, or all) restores the
numbers this build compiled with.

Four things worth knowing:

**The table moved into its own generated file.** `enemy_presets.odin` is
wholly the exporter's, the way `maps.odin` is `map_builder`'s - Export
overwrites it in place, so a tuning session is a `git diff` of that file. A
regenerated literal cannot carry comments, so the roster's per-row design
notes moved onto `Enemy_Kind`'s cases in `enemy.odin`. ADR-0027 is amended
to say so.

**A test pins the file to the generator.** `enemy_presets_source_test`
asserts the checked-in file is byte-for-byte what `enemy_presets_source`
writes for the live table, so a field added to a variant and forgotten by
the writer, or a hand edit that changes the shape, fails the suite rather
than the next Export. Numbers are written as the shortest decimal that
parses back to the same f32 (`0.35`, not `fmt`'s `0.34999999`), so a slid
value reads like one a person typed while stamping exactly the value the
session was tuned at. Colours are written by constant name when they are a
family colour, so the literal still says which family a Kind belongs to.

**The per-Kind Tunables are gone.** `enemy.<kind>.max_health` and
`gold.<kind>` were the stopgap this ticket replaces; a Tunable over a preset
is a path by which `Save Tuning` persists the roster into `tuning.json`,
which is the second authority ADR-0027 forbids. Nothing in `tuning.odin`
points into `enemy_presets` now.

**The bake round trip is unchanged.** An edit is live in the running
session, but only Export persists it and only the next build ships it - the
same lag a new Map file has. Not verified by driving the panel: `vendor/ui`
is immediate-mode and cannot be run from a test, so the pieces the mode
stands on (the writer, the file round trip, the family defaults it stamps
on a switch) are what the tests cover, per `editor_test`'s convention.
