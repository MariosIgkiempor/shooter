# 12: The editor's Presets mode

**What to build:** Tuning an enemy is done by dragging sliders and watching the
game, then exporting the result — the editor gains a Presets mode that edits the
live preset table and writes it back out as source, the same way the map
generator already produces source rather than a second data format to keep in
sync.

**Blocked by:** 08, 11

**Status:** ready-for-agent

- [ ] A Presets mode lists every Kind and exposes its authored parameters
- [ ] Edits take effect in the running session
- [ ] Export writes the preset table's source literal, ready to paste or overwrite
- [ ] Nothing about presets is persisted as data; source stays the only authority
