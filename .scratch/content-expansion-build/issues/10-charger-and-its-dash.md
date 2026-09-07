# 10: Charger and its dash

**What to build:** The first enemy that can catch a running player. A Charger
telegraphs a straight lane, then crosses it faster than the player can run,
travelling a bounded distance and stopping — so the counter is to move out of
the lane during the Tell, not to outrun it.

**Blocked by:** 09, 04

**Status:** ready-for-agent

- [ ] A movement style that telegraphs a lane, then dashes along it
- [ ] The lane is locked when the Tell starts and the dash covers a bounded distance
- [ ] The dash speed exceeds the player's run speed; sustained speed between dashes does not
- [ ] The lane telegraph uses the same Tell vocabulary as the area attack
