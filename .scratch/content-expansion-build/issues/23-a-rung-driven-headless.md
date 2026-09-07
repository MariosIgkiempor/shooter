# 23: A rung driven headless

**What to build:** A whole Run can be played through in a test, so the failures
that only appear when the pieces are assembled — a body stranded where nothing
can reach it, a clear condition that never fires — are caught by the suite
rather than by playing.

**Blocked by:** 17, 11, 04

**Status:** ready-for-agent

- [ ] A test builds an authored Map, ticks its timeline for the Map's full duration, and asserts the Map is cleared
- [ ] The test asserts no enemy is ever stranded outside the reachable field
- [ ] It runs without a window or any rendering
