# 16: The ladder gates on clears

**What to build:** Maps are a ladder, not a menu. The first rung is open on a
fresh Account; clearing a rung opens the next and nothing further. Map Selection
shows the locked rungs with what they need, so the player can see where the
ladder goes before they can walk it.

**Blocked by:** 13, 03

**Status:** resolved

- [x] The Account records which Maps have been cleared, persisted by identity string
- [x] Rung one is always available; clearing rung n opens exactly rung n+1
- [x] Locked rungs render with a lock glyph and their requirement, and cannot be selected
- [x] Clearing a Map already cleared changes nothing

## Comments

**Implemented.** `Player.maps_cleared: [Map_Name]bool` tagged `json:"-"`, with
`maps_cleared_save: []string` as its on-disk form - the same shape as
`Map.ambient`/`ambient_save`. `save_game` rebuilds the identity list from the
live set into a temp slice and blanks it on every way out; `load_game` blanks
the live set first (a pre-field save loads as no clears) and treats an unknown
name as the same load failure as an unknown weapon. `end_run` records the
clear inside its existing double-fire guard, named through
`game.active_map_pointer` since `current_map` is a clone with no `Map_Name`.

**Open/locked, not unlock.** `map_rung_open`, `map_rung_requirement`,
`map_name_at_rung`, `record_map_cleared`, `maps_in_rung_order` in
`account_progression.odin`. Not `map_unlocked`: `unlock_*` in this codebase is
the Account-Level gate, which is exactly the gate ADR-0022 rejects for Maps.

**The gate is enforced at the choice.** `try_choose_map` (map.odin) re-checks
`map_rung_open` before cloning and applying, the way `try_buy_account_stat`
re-checks its own unlock - so "cannot be selected" is assertable without a
window, and the disabled button is belt to that brace.

**The lock swaps the swatch rather than graying it.** `draw_menu_button`
overrides `icon_tint` to `text_disabled` on any disabled button, so a locked
row could not show the Map's colour even if it wanted to - and a gray swatch is
what an unaffordable row looks like, not a shut one. `icon_lock` is a body
under a squared shackle, no keyhole (a tint would fill it in). The requirement
reads "Clear Desert Dungeon to open"; the panel widened 300 -> 360 to fit it.

**Map Selection now lists rung order.** `Map_Name` is filename-sorted, so Cold
Hall (rung 2) sorted above Desert Dungeon (rung 1). Sorted rather than walked
rung-by-rung so a mis-authored table still lists every Map once.

**Ticket 15 is still open, so the predicates fail soft.** A rung-0 Map is
treated as rung 1 (an authoring mistake makes the ladder wrong, not a Map
unreachable); a gap below a rung closes it. The validity sweep is where those
become build failures. The "clearing n opens exactly n+1" test can't see a
third rung in today's two-Map table, so a second test lifts rung 2 to rung 3
and asserts a clear of rung 1 doesn't reach across the gap.

**One test fixed in passing.** `save_game_test.odin`'s weapon fallback test
asserted while `context.logger` was `nil_logger()` - `testing.expect` reports
through that logger, so the assertions could never fail. Narrowed to the
`load_game()` call; the new map fallback test copies the corrected shape. The
same pattern exists in `persistence_test.odin`, `map_test.odin` and
`weapon_test.odin` - out of scope here, flagged separately.
