# 02: Dock the debug panel bottom-left and drop its Gold line

**What to build:** F8 opens the debug panel in the bottom-left corner of the
screen instead of centred over the action, and the panel's redundant "Gold:"
readout is gone.

Today the panel is centred, directly over the thing a developer is trying to
observe. Bottom-left is the least contested corner during play: the HUD counter
row (kills, clock, gold) is anchored hard against the top-right, and the only
bottom-anchored panel in the game is the Confirm New Run dialog, which is Main
Menu only and can never coexist with this panel.

The panel must be *anchored* to the corner, not offset by a measured amount. An
offset would couple the panel's layout to a HUD constant that can change
underneath it; anchoring needs no magic number and stays correct at any window
size.

The "Gold:" line exists only because the panel used to pause and cover the HUD.
With the panel in the corner, the HUD's gold counter is on screen at the same
time, so the line is a second readout of a number already shown a few inches
away. Remove it and let the HUD counter be the single Gold readout. The Add Gold
button stays exactly as it is, including the way it moves the Run's starting-Gold
baseline alongside the wallet so a dev grant still settles as exactly zero into
Account progression.

This ticket lands green on its own: the panel still pauses the game at this
point. It is demoable as "the panel is now out of the way and reads correctly".

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] The panel's root container anchors bottom-left, using the layout library's existing alignment values
- [ ] No new positional constant is introduced, and nothing measures against the HUD
- [ ] The panel sits clear of the HUD counter row at a small window size and at a large one
- [ ] The panel's "Gold:" text line is removed
- [ ] The Add Gold button is unchanged, and still raises the Run's starting-Gold baseline by the same amount it adds to the wallet
- [ ] The five visualizer toggles, God Mode and Close are unchanged
- [ ] The full test suite passes
