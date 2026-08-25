Type: grilling
Status: resolved

## Question

`try_fire_gun` today checks `ammo_in_clip <= 0` and, if empty, starts a reload and returns `false` ("did not act") — no cooldown is consumed, nothing plays. Pistol and Shotgun are both `Semi_Automatic` and will be Windup-gated once this map's model lands.

Decide: when the player Triggers a Gun with an empty clip, does Windup start at all?

- **Gate before Windup** (ammo check happens at Trigger time, same as today; Windup never starts if the clip is empty — pressing fire on empty just starts reload silently, exactly today's behavior, Windup only ever plays when a shot will actually fire), or
- **Windup plays, then Resolve discovers the empty clip** (Windup always starts on Trigger regardless of ammo; when it completes, Resolve re-checks the clip and starts a reload if it's empty instead of firing — the player sees the windup animation play out into nothing, which could read as a deliberate "dry-fire" beat or could just read as broken)?

This has a real feel consequence and should be decided deliberately, not left to fall out of however ticket 01's state machine happens to be implemented.

## Answer

**Gate before Windup.** `try_use_weapon`'s Semi_Automatic branch (from [Trigger/Windup/Resolve state machine](01-trigger-windup-resolve-state-machine.md)) checks `ammo_in_clip` for a Gun before starting the cycle — mirroring `try_fire_gun`'s existing empty-clip check today. If empty: neither `windup_timer` nor `cooldown_timer` start, `start_reload` runs exactly as it does today, and nothing plays. Windup only ever begins when a shot is actually going to fire.

Rationale: the alternative (Windup always starts, Resolve discovers the empty clip) would lock the player into a full wasted windup+cooldown cycle on an empty trigger-pull, directly against this map's "still responsive" goal — a dry-fire tell wasn't worth that cost. This check is Gun-specific; Melee_Weapon and Magic have no equivalent "can't act" resource gate today, so their Semi_Automatic kinds (Sword, Fire_Wand, Poison_Staff) always start Windup unconditionally on Trigger.

Implementation note for whoever picks this up: the ammo check that gates Windup-start and the one inside `try_fire_gun`'s eventual `resolve_weapon_action` call are the same check — worth factoring into one shared helper (e.g. `gun_can_fire(gun: Gun) -> bool`) rather than duplicating the `ammo_in_clip <= 0` condition in two places.
