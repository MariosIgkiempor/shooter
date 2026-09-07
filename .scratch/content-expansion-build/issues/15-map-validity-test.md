# 15: Map validity test

**What to build:** A broken Map fails the build rather than the playtest. Every
authored Map is checked for the failures that make one unplayable or
unclearable.

**Blocked by:** 13, 04

**Status:** ready-for-agent

- [ ] Every authored Map is asserted connected, with its start position on a floor tile and its spawn ring reachable
- [ ] Extent is within bound, rung is unique, and rungs cover the full ladder
- [ ] The time limit clears the Map's own timeline end, or the Map is untimed
- [ ] Colours are authored rather than defaulted
- [ ] The existing Map, which fails this today, is patched in the same change
