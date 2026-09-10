# 08: Enemy Kind keys a preset table

**What to build:** An enemy is authored once, as a named Kind, and referred to
everywhere else by that name. A spawn composition entry becomes a Kind and a
count — a level author picks "six Spitters", not a bundle of movement and attack
parameters re-specified at every trigger. Every field an enemy needs comes from
the Kind's preset.

The movement-family colour constants land in this same change: the presets and
the palette are one decision, and two of the existing constants are inverted
relative to the families they will name, so splitting them across changes would
leave the roster mid-repaint.

**Blocked by:** 03

**Status:** resolved

- [x] A preset table keyed by Kind holds every authored enemy parameter
- [x] A composition entry is a Kind and a count; the movement/attack template fields and their save mirrors are deleted
- [x] The map generator no longer writes movement/attack literals
- [x] The existing Map file is rewritten to the new composition shape and still plays
- [x] The editor's composition UI collapses to picking a Kind and a count
- [x] Movement-family colour constants are authored to match the families they name
