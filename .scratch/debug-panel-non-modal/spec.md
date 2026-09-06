# Non-modal debug panel

Status: ready-for-agent

## Problem Statement

The F8 debug panel pauses the game. Every dev-view visualizer, God Mode, and
the Gold grant sit behind a modal that stops the world dead the moment it
opens — so the only way to see whether flipping Colliders or Movement Styles
actually shows what you need is to toggle it, close the panel, resume, watch,
and reopen. The panel is also centred on screen, directly over the thing you
are trying to observe.

The result is that the panel is unusable for the job it exists to do: watching
a live behaviour while turning visualizers off and on to isolate it. Any
observation that depends on motion — enemy steering, Separation, pathfinding,
weapon hit areas during a Follow-through — has to be reconstructed across a
pause boundary from memory.

## Solution

The debug panel becomes a non-modal overlay docked in the bottom-left corner.
Opening it no longer pauses the simulation: enemies keep moving, bullets keep
travelling, timers keep running, and toggling a visualizer takes effect
immediately against the live scene you are already watching. The panel sits in
the least contested corner of the screen, clear of the HUD counters in the
top-right and clear of the player, who tends to hold the centre.

Because gameplay is live, a click on a panel button must not also fire the
equipped weapon. The Tilemap Editor already solved this: it records whether
the pointer is over its own UI and suppresses world interaction for that
frame. The debug panel adopts the same mechanism, and the two surfaces share
one implementation rather than keeping parallel copies.

## User Stories

1. As a developer, I want the debug panel to leave the simulation running, so
   that I can watch enemy movement while toggling the visualizer that explains
   it.
2. As a developer, I want to toggle a visualizer and see the effect on the
   current frame, so that I do not have to reconstruct what I saw across a
   pause boundary.
3. As a developer, I want the panel docked in the bottom-left corner, so that
   it does not cover the action I am inspecting.
4. As a developer, I want the panel clear of the HUD counters, so that the
   kills/clock/gold row stays readable while the panel is open.
5. As a developer, I want the panel's position to hold at any window size, so
   that resizing the window does not push it under the HUD or off-screen.
6. As a developer, I want clicking a panel button not to fire my weapon, so
   that turning Colliders on does not also empty a clip into the floor.
7. As a developer, I want holding the mouse over the panel with an Automatic
   weapon equipped not to spray bullets, so that a slow deliberate click is
   safe.
8. As a developer, I want a Semi_Automatic weapon not to start a Windup when I
   press a panel button, so that a toggle never costs me a wasted action
   cycle.
9. As a developer, I want to keep moving with WASD while the panel is open, so
   that I can reposition to see a behaviour better without closing it.
10. As a developer, I want enemies to keep attacking while the panel is open,
    so that what I observe is the real behaviour and not a special paused mode.
11. As a developer, I want God Mode to be the way I stay safe while fiddling
    with the panel, so that there is exactly one concept for invulnerability
    rather than an implicit second one hidden in the panel's open state.
12. As a developer, I want spawn triggers and Run timers to keep advancing
    while the panel is open, so that opening it does not silently extend a
    timed Run.
13. As a developer, I want the Gold readout to live in one place, so that I am
    not reading two numbers that could disagree.
14. As a developer, I want the Add Gold button to keep working, so that I can
    test Shop purchases without playing for the Gold.
15. As a developer, I want Add Gold to keep moving the Run's Gold baseline with
    it, so that a dev grant still settles as exactly zero into Account
    progression.
16. As a developer, I want the panel to close itself when the Run ends, so that
    it never draws over the Run End modal.
17. As a developer, I want the panel to close itself when I open the Shop, so
    that two UI surfaces never fight over the same frame's pointer state.
18. As a developer, I want the Shop to stay unopenable while the panel is up,
    so that the mutual exclusion holds from both directions.
19. As a developer, I want F8 to keep refusing to open during the Shop or the
    Run End modal, so that the existing guard is unchanged by this work.
20. As a developer, I want F1 into the Tilemap Editor to hide the panel and F1
    back to reveal it again, so that a quick trip to fix a tile does not cost
    me my visualizer setup.
21. As a developer, I want the Tilemap Editor to keep suppressing world
    interaction under its own windows exactly as it does today, so that sharing
    the hover mechanism with the debug panel changes nothing about the editor.
22. As a developer, I want the panel state to stay unsaved, so that loading a
    save never reopens a dev panel over a fresh session.
23. As a maintainer, I want the reason the debug panel does not pause — while
    the Shop and Run End do — written down, so that the asymmetry does not read
    as an oversight to the next person.
24. As a maintainer, I want the auto-close to have exactly one writer, so that
    a future Screen cannot be added that forgets to close the panel.
25. As a maintainer, I want the hover suppression to have exactly one
    implementation, so that the editor's copy and the panel's copy cannot
    drift.

## Implementation Decisions

### Anchor

- The panel's root row aligns bottom-left instead of centre-centre, using the
  vendor layout library's existing `AlignX`/`AlignY` values and the panel's
  current padding. No new constant, no measurement against the HUD.
- Bottom-left was chosen over the right edge (the original request) once it
  emerged that the top-right is already occupied by the HUD counter row.
  Bottom-centre is taken by the Confirm New Run dialog, but that is Main Menu
  only, so it never coexists with the panel.
- Anchoring rather than offsetting is deliberate: an offset would couple the
  panel's layout to a HUD constant that can change underneath it.

### Pausing

- `update_game_state`'s pause condition drops its debug-panel term. `run_ended`
  and `shopping` continue to pause exactly as before.
- No compensating safety behaviour is added. God Mode already exists on the
  panel for the "do not kill me while I fiddle" case, and a second implicit
  invulnerability rule would be a hidden duplicate of it.

### Pointer ownership

- The Tilemap Editor's hover-recording helper and its `ui_hovered` flag are
  hoisted out of the editor into the shared HUD module, which is already
  documented as the home for what the debug panel and the editor both use. The
  editor's own copy of the flag is deleted and the editor reads the shared one.
- The debug panel records hover the same way the editor does, from just inside
  its window's begin call.
- Weapon firing is suppressed for any frame in which the pointer is over the
  panel. This covers both the Automatic (held) and Semi_Automatic (pressed)
  paths, so a toggle can neither spray nor consume a Windup.
- The flag is one frame stale by construction — the UI is declared during the
  draw phase — which is the same tolerance the editor already accepts, and is
  correct here because it describes where the pointer *is*, not that an event
  arrived.
- One shared flag is safe because the panels remain mutually exclusive (below),
  so at most one UI surface is live in any frame.
- Accepted consequence: while the panel is open, the bottom-left corner of the
  screen is a dead zone for shooting. Gating on individual interactive widgets
  rather than the whole panel rect was rejected as a new concept in the vendor
  library for a problem only a developer hits.

### Mutual exclusion

- Unchanged. F8 still requires Playing and refuses during the Shop or Run End
  modal; the Shop key still refuses while the panel is open. The underlying
  constraint — the vendor UI library tracks click state in package globals via
  a single pointer-state call per frame, so the second surface drawn in a frame
  can never register a click — is untouched by this work.
- Unifying both panels into one UI frame would lift that constraint but is a
  separate piece of work, and the Shop pauses anyway, so it is not in tension
  with the goal here.

### Auto-close

- The screen-change applier — documented as the one place that actually writes
  the Run End and Shop flags for a Screen change — also clears the panel's open
  flag, unconditionally, for any non-nil Screen. Individual closes at the Run
  End and Shop call sites were rejected for the same reason that applier exists:
  one writer, no missed path.
- Entering the Tilemap Editor is not a Screen change and is deliberately not
  covered. The panel's existing draw guard already hides it there, and hiding
  rather than closing is the wanted behaviour.

### Panel contents

- The panel's Gold readout line is removed. It existed because the panel used
  to pause and cover the HUD; with the simulation live and the panel in the
  corner, the HUD counter is on screen simultaneously and becomes the single
  Gold readout.
- The Add Gold button is unchanged, including its adjustment of the Run's
  starting-Gold baseline so a dev grant settles as zero into Account
  progression.
- God Mode, the five visualizer toggles, and Close are unchanged.

### Decision record

- A new ADR (next free number, 0021) records why the debug panel is non-modal
  while the Shop and Run End pause. It meets all three bars: the asymmetry is
  surprising without the reason, it is the result of a real trade-off (the dead
  zone and the shared hover flag are the price), and it constrains how future
  panels are designed.
- `CONTEXT.md` gets no change. Nothing here introduces or redefines a domain
  term; this is a mechanism decision, not vocabulary.

## Testing Decisions

A good test here asserts external behaviour through an existing seam and does
not encode how the code is shaped. Three of the four changes deliberately get
no test, because the only thing a test could assert about them is their
implementation.

### What is tested

- **The auto-close**, through the screen-change applier. That proc is already
  established as the testable seam for screen transitions: it is a plain proc
  over the global game state with no rendering and none of the Dismiss-window
  waiting that the request/transition path involves. The prior art is the
  existing suite of tests around it, which follow exactly this shape.
- Assertions: an open panel is closed after applying the Run End screen; an
  open panel is closed after applying the Shop screen; applying nil (back to
  Playing) leaves the panel's state untouched.
- Tests live alongside the existing God Mode tests for the debug module, and
  follow that file's snapshot/restore discipline — capture and restore every
  global touched, since the suite mutates shared game state and races if run in
  parallel.

### What is not tested, and why

- **The anchor** is a layout value consumed during draw. A test would assert
  that the vendor layout library aligns things, which it already tests itself,
  not that the panel is where it should be.
- **The unpause** is the removal of a term from a condition. Asserting the
  shape of a boolean expression is not a behaviour test; the deleted term is
  its own documentation.
- **The hover suppression** is written during the draw phase and read on the
  following frame's update, behind raylib input. The editor's equivalent has no
  test today, and adding one means building a new seam over input for a
  developer-only affordance — against the principle of preferring the fewest
  seams.

No new seams are introduced by this work.

## Out of Scope

- **Keyboard shortcuts for the visualizers.** The number keys are entirely
  unbound and would make toggling faster still, but unpausing already removes
  the expensive part of the loop (losing the run's flow state). If it still
  feels slow in practice, that is a cheap follow-up on top of this.
- **A shared UI frame for the debug panel and the Shop.** This would lift the
  one-pointer-state-call-per-frame constraint and remove the need for mutual
  exclusion, but it is a change to how every panel is driven, not to this one.
- **Eliminating the bottom-left dead zone.** Gating suppression on individual
  interactive widgets rather than the whole panel rect is a vendor-library
  change, explicitly deferred.
- **Any change to the Shop or Run End modals.** Both keep pausing.
- **Any change to what the visualizers draw**, or to God Mode's behaviour at
  the two damage seams it touches.
- **Persisting panel state across saves.** It stays unsaved, on the same
  rationale as the Run End and Shop flags.

## Further Notes

- The original request asked for the right edge of the screen. That changed to
  bottom-left mid-design once the HUD counter row's occupancy of the top-right
  surfaced; the bottom-left choice is the user's, made with that fact in hand.
- The hover mechanism being hoisted has a comment in the editor explaining why
  it is one frame stale. That reasoning applies unchanged in its new home and
  should travel with it.
- The existing comments on the F8 guard and the panel's draw guard both explain
  the two-surfaces-in-one-frame hazard. They remain accurate after this change
  and should not be weakened; the mutual exclusion they protect is still load
  bearing.
