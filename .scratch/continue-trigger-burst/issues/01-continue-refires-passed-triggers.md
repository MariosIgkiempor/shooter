# Continue re-fires every passed Spawn Trigger at once

Status: needs-triage

Surfaced by the [Web build](../../web-build/map.md) map's [Save points](../../web-build/issues/03-save-points.md) ticket; pre-existing on Desktop and independent of the web build.

## Problem

A mid-Run Continue (ADR-0013) restores `Player.survival_seconds` and `Player.kills` from the save, but `Spawn_Trigger.fired` is `json:"-"` (`enemy.odin:345`) and `try_choose_map` re-clones the Map from the baked table with every latch false. On the first Playing frame `update_spawn_triggers` (`enemy.odin:905`) therefore finds every `Time_Elapsed` trigger with `seconds <= survival_seconds` and every `Kills_Reached` trigger with `count <= total_kills` unfired-and-met, and fires them all in one burst — every `One_Shot` composition the Run had already faced lands again on top of the player, and every `Repeating` trigger activates at once.

Reproduce: play Desert Dungeon past its second trigger, quit, relaunch, Continue, pick the same Map.

## Possible fixes

- On resume, fast-forward: mark as `fired` (without spawning) every trigger whose condition is already met at the moment the Map is applied, so only triggers *ahead* of the restored clock fire. Repeating triggers whose window has partly elapsed need their `elapsed` set accordingly or be skipped outright.
- Or persist the latches — but `fired` is `json:"-"` on purpose (see its doc comment: the Map is level data, and baking a latch into `data/maps/*.json` would make a saved map file unplayable), so this would need a separate per-Run trigger-state record on `game`, which is more machinery than the fast-forward.

Either way it belongs with the Continue semantics, not the save format.
