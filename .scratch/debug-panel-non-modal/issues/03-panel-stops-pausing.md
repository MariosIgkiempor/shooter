# 03: Stop the debug panel pausing the game

**What to build:** Opening the F8 debug panel no longer stops the world. Enemies
keep moving and attacking, bullets keep travelling, spawn triggers and Run timers
keep advancing, and the player can still move with WASD. Toggling a visualizer
takes effect immediately against the live scene — which is the entire point of
the panel and the thing it could not do while it paused. Watching enemy
steering, Separation, pathfinding, or a weapon's hit area during a
Follow-through no longer has to be reconstructed across a pause boundary.

Three things have to land together for this to be a working state rather than a
broken one.

**The simulation runs.** The pause condition drops its debug-panel term; the Run
End modal and the Shop keep pausing exactly as before. No compensating safety
behaviour is added — God Mode already exists on this very panel for the "do not
kill me while I fiddle" case, and a second implicit invulnerability rule would be
a hidden duplicate of it.

**Clicks on the panel do not reach the weapon.** With gameplay live, the same
left click that presses a panel button would otherwise also fire the equipped
weapon: an Automatic weapon sprays for as long as the pointer rests on the
panel, and a Semi_Automatic weapon burns a Windup on every toggle. Using ticket
01's shared hover flag, firing is suppressed for any frame in which the pointer
is over the panel, covering both the held and the pressed paths. The panel
records hover the same way the editor does, from just inside its window's begin
call.

The accepted consequence is that while the panel is open, the bottom-left corner
of the screen is a dead zone for shooting. That is deliberate: it is a panel a
developer opens on purpose, in the least contested corner, and gating on
individual interactive widgets instead of the whole panel rect would mean a new
concept in the vendor UI library for a problem only a developer hits.

**The panel closes itself on any Screen change.** Once the world runs, a Run can
end while the panel is open, and the panel would draw over the Run End modal —
two UI surfaces in one frame, which the codebase already knows is unsafe because
the vendor library tracks click state in package globals via a single
pointer-state call per frame, and whichever surface draws second can never
register a click. The single proc that already writes the Run End and Shop flags
for a Screen change also clears the panel's open flag, unconditionally, for any
non-nil Screen. One writer, so a future Screen cannot be added that forgets.

Deliberately unchanged: F8 still requires Playing and still refuses during the
Shop or the Run End modal; the Shop key still refuses while the panel is open;
and F1 into the Tilemap Editor still *hides* the panel rather than closing it, so
a quick trip to fix a tile does not cost the developer their visualizer setup.
The panel's state stays unsaved.

Also record ADR-0021: why this panel is non-modal while the Shop and Run End
pause. A future reader will otherwise read the asymmetry as an oversight. It is a
real trade-off — the dead zone and the shared hover flag are its price — and it
constrains how future panels are designed. No CONTEXT.md change: this is a
mechanism decision, not a new domain term.

**Blocked by:** 01 (Share one UI hover flag between the editor and the debug panel)

**Status:** ready-for-agent

- [ ] Opening the panel no longer pauses the simulation; enemies, bullets, particles, spawn triggers and Run timers all keep advancing
- [ ] The player can still move with WASD while the panel is open
- [ ] The Run End modal and the Shop still pause exactly as before
- [ ] No new invulnerability or safety behaviour is tied to the panel being open; God Mode remains the only such concept
- [ ] Clicking a panel button with an Automatic weapon equipped does not fire it, and holding the pointer over the panel does not spray
- [ ] Clicking a panel button with a Semi_Automatic weapon equipped does not start a Windup
- [ ] The panel closes itself when the Run ends, and when the Shop opens
- [ ] The auto-close is written in the single proc that already applies a Screen change, not at individual call sites
- [ ] F8 still refuses to open during the Shop or the Run End modal, and the Shop key still refuses while the panel is open
- [ ] F1 into the Tilemap Editor hides the panel; F1 back reveals it with its toggles intact
- [ ] Panel state is still never saved
- [ ] Tests at the screen-change seam assert: applying the Run End screen closes an open panel; applying the Shop screen closes an open panel; applying nil leaves panel state untouched
- [ ] Those tests follow the existing snapshot/restore discipline for every global they touch
- [ ] ADR-0021 is written, recording why the debug panel is non-modal while the Shop and Run End pause
- [ ] CONTEXT.md is unchanged
- [ ] The full test suite passes
