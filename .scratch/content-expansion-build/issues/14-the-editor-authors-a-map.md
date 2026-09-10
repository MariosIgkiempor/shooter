# 14: The editor authors a Map

**What to build:** A new Map can be made start to finish without leaving the
editor: create it, set where the player starts, set its time limit and payout
multiplier, place it at a rung, and pick its colours.

**Blocked by:** 01, 13

**Status:** resolved

- [x] The editor can create a new Map and save it
- [x] Player start is placeable from the editor
- [x] Time limit, payout multiplier and rung are editable
- [x] Floor and wall colours are pickable and preview live

## Comments

Landed as a fourth `EditorMode`, `Map`, holding everything about the open Map
that isn't a tile, plus a `+ New Map` button at the end of the switcher's list.

Four things worth knowing:

**The editor grew a text field.** ADR-0021 scoped "fields for `name`" onto this
panel, but `vendor/ui` has no text widget and no keyboard capture at all, so
one is built here on the same `layout.node` escape hatch `selectable_button`
uses, over a fixed-capacity `Text_Buffer`. `game.editing_map.name` is a view
into that buffer for as long as a Map is open in the editor, which is what
lets a name be edited without an allocation for the Map to own. It does not
blur on Escape: nothing calls `rl.SetExitKey`, so Escape is still raylib's
default exit key and would close the window rather than the field.

**Editing now draws the Map it is editing.** `draw_world_contents` drew
`game.current_map` unconditionally, so nothing the editor changed was visible
in the world behind it - the colour sliders would have been a guess rather
than a preview. It now draws `game.editing_map` while Editing, which also
means tile and collider edits show up in the world for the first time.

**Save is a save-as for a Map the editor created**, deriving
`data/maps/<slug>.json` from the name (`"Cold Hall"` -> `cold_hall.json` ->
`.Cold_Hall`, the round trip `map_builder`'s `strings.to_ada_case` closes). It
refuses to write where a file already exists: an authored place is only
recoverable by redrawing it (ADR-0021), and renaming is one field away. The
bake round trip ADR-0021 calls inherent is unchanged - a new Map has no
`Map_Name` case, and so appears in neither the switcher nor Map Selection,
until the next `./build.sh`.

**Renaming an already-saved Map changes the name, not the file.** `Save` keeps
writing to the path the Map was opened from, so the `Map_Name` case keeps the
old slug while the displayed name changes. The Map row prints the file path
next to the name so the two are never silently apart.

Not covered here, and deliberately: the ambient set is authorable data on the
Map (ADR-0024) but has no draw layers yet (ticket 22), so it has no control on
this panel. Ticket 15's validity sweep is what will catch a Map authored with
an unreachable start or a floor lighter than its wall - `new_map_stub` starts
valid on both counts, but nothing stops the sliders leaving it otherwise.
