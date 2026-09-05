Type: grilling
Status: resolved
Blocked by: 01

## Question

Do the entities that are already pure shapes today — Gold pickup (pickup.odin:98-110), poison-cloud AoE (poison_cloud.odin:134-138), most particles (particle.odin:284-303), spawner debug markers (main.odin:823-828), and the Resource-indicator bar/icon system (resource_indicator.odin) — need restyling to match the vocabulary [01-actor-shape-and-movement-transform](01-actor-shape-and-movement-transform.md) establishes, or do they already read consistently and get left alone?

If a restyle is warranted, scope it precisely (which entities, what changes) rather than leaving it as a vague "polish pass" — this is a decision ticket, not an implementation checklist.

## Answer

**Only spawner markers need a change.** They currently reuse Grounded enemy's RED (`draw_spawners`, main.odin) and are drawn unconditionally in `draw_game`'s world-camera block — visible during real gameplay, not just the map editor — sitting independently on the map floor where they could be misread as a distant enemy. **Recolor to a muted gray-blue**, keeping RED exclusively for actual threats (Grounded enemies, enemy bullets, critical health states). Shape (circle outline + dot) is unchanged — only the color collides.

**Everything else is left unchanged, confirmed no restyle warranted**:
- Gold pickup (circle, `GOLD`) — the fixed anchor other pickups were already designed around.
- Poison-cloud AoE (translucent green circle) — thematically distinct, no clash.
- Particles (mostly circles, orange/gold/amber/cyan tones, already actively extended by tickets 01/02's new streak/flash kinds) — already consistent.
- The Resource-indicator system (its own functional palette: healthy/critical green-red gradient, ammo gray, cooldown blue-gray) — a different visual register from world-space "what is this object" shapes, always anchored to a specific actor, no real clash risk despite sharing red/green with other systems.

**Closed a loose end from [Bullets and pickups shape treatment](03-bullets-and-pickups-shape-treatment.md)**, which settled Health/Ammo *shapes* but left colors unspecified: **Health = warm red/pink**, **Ammo = light gray/silver** (echoing the weapon-metal tone already used for Gun/Melee/Magic bodies). Recorded as an amendment on ticket 03, per "a decision lives in exactly one place."
