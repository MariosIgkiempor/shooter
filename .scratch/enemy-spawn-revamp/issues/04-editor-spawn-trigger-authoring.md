Type: prototype
Blocked by: 03
Status: resolved

## Question

Design the in-editor UX for authoring a map's Spawn Trigger timeline, now
that there is no position to place — this replaces the current
`.Spawners` editor mode's tile-snapped click-to-place flow entirely
(`spawner_place`/`spawner_remove`, `editor.odin:232-260`, and its property
buttons for movement/attack templates, `editor.odin:702-725`).

Needs to settle:

- **Authoring surface.** Likely a list/panel of the map's Spawn Triggers
  (add/remove/reorder), each with editable condition type + value, mode,
  and a sub-list of composition entries (Movement Style + Attack Style +
  count) — using [ticket 03](03-spawn-trigger-data-model.md)'s finalized
  shape.
- **UI pattern to mirror.** Decide between extending the existing
  property-button pattern (`editor.odin:702-725`) or reusing the panel
  system used throughout menus (`renderer.odin:71-147`) — the panel
  system was ruled out for in-world Resource indicators in the
  [HUD redesign map](../../hud-redesign/map.md) for being too heavy at
  small sizes, but this is a full editor panel, not an in-world overlay,
  so that objection may not apply here.
- **Editor mode.** Whether authoring triggers keeps its own dedicated
  editor mode (like today's `.Spawners`) or lives inside an existing
  mode/panel, given there's no map-position component to click on anymore.
- **Prototype it live** in the editor to confirm the authoring flow is
  usable for building out a real trigger timeline (adding several
  triggers with mixed conditions/modes/compositions), not just a single
  entry.

## Answer

Prototyped three structurally different HTML mockups — sharing one mock
trigger data set so switching layouts mid-edit was directly comparable —
on branch `prototype/editor-spawn-trigger-authoring` (commit `2775c04`).
**Variant A won: a vertical list with inline expand.**

- **Authoring surface.** A vertical list, one row per Spawn Trigger. Each
  row's collapsed state is a one-line summary (condition badge, mode
  badge, composition summary, a `✕` to remove). Clicking a row expands an
  inline detail panel directly beneath it — condition type + value,
  mode + its params (interval/duration when `Repeating`), and the
  composition sub-list (Movement Style + Attack Style + count per entry,
  each with its own `+`/`✕`). A single `+ Add Spawn Trigger` button sits
  at the bottom of the list. Rejected: Variant B's tile-grid-plus-fixed-
  side-panel (extra visual indirection for what's fundamentally a linear
  timeline, not a grid of independent items) and Variant C's property-
  button cycling (fine for editing one thing at a time, worse for
  scanning/comparing several triggers at once, which authoring a timeline
  inherently requires).
- **UI pattern.** Neither of the two named alternatives directly — not
  the existing property-button pattern (`editor.odin:702-725`, that's
  Variant C, rejected) and not the heavier `renderer.odin:71-147` panel
  system either. The winning list-with-inline-expand is closer to a
  plain scrollable list of rows than either precedent; the panel system's
  9-slice framing is unnecessary for a functional editor tool (the HUD
  redesign map's "too heavy at small sizes" objection turns out to
  generalize past just in-world overlays).
- **Editor mode.** No dedicated `Editor_Mode` case needed — there's
  nothing to click-place anymore, so the trigger-list panel can be an
  always-visible list/window while in Editing, closer to how the Maps
  map's map-switcher row is "always-visible" rather than its own mode
  than to today's `.Spawners` mode.

**Ripple effects on this map**: none on
[Spawn trigger data model](03-spawn-trigger-data-model.md) — the UI
choice doesn't change the persisted shape, only how it's edited. Unblocks
nothing further (this ticket had no dependents other than being
independently blocked-by-03 alongside
[Map format migration and baking tool](05-map-format-migration-and-baking-tool.md)).
