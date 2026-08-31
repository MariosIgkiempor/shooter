Type: grilling
Status: resolved

## Question

Now that the bottom-of-screen HUD is being removed in favor of small indicators drawn above the player (same spatial pattern as `draw_health_bar` already uses above enemies, [hud.odin:142-153](../../../hud.odin)), decide the shape and content of those indicators, precise enough for [Prototype the particle-driven resource indicator](02-prototype-particle-driven-indicator.md) to build against.

Decide:
- **Which resources actually get a live indicator.** Health and ammo are the obvious carryovers from the old bottom HUD (`draw_hud_icon_row` calls for `.Pickup_Heart` and `.Pickup_Ammo`, [hud.odin:63](../../../hud.odin) and [hud.odin:86](../../../hud.odin)). XP is different: per [ADR-0009](../../../docs/adr/0009-xp-is-a-run-end-grant.md), XP is granted once at Run end, not collected in real time anymore — the old bottom XP bar (`draw_hud_label_row`, [hud.odin:58](../../../hud.odin)) may already be showing stale/meaningless live data. Decide whether XP gets an above-player indicator at all, or is simply dropped from the live HUD (it's already shown on the Run End screen).
- **Does ammo need any numeric readout anywhere**, given the old bar was fraction-only (no exact clip/reserve numbers) and the new approach leans on particles rather than a fill bar — is losing precise numbers acceptable, or does something (even a small text readout, rendered in `game.camera` space per the map's Notes so it won't stretch) need to carry it?
- **What size/shape fits above a ~24x24px sprite** ([atlas.odin:85-86](../../../atlas.odin), `.Player_Walk` frame `document_size`) without crowding gameplay or overlapping the player's weapon/aim visuals.
- **Do player and enemy indicators share the same shape**, or only the same particle *language* (e.g. player gets a richer multi-resource cluster, enemies get a single simplified health indicator)? This sets up [Decide the fate of enemy health bars](03-enemy-health-bar-unification.md).

Not blocked — the world-space camera/anchor facts this depends on are already established in the map's Notes.

## Answer

Settled via grilling + domain-modeling (see [CONTEXT.md](../../../CONTEXT.md)'s new **Resource indicator** entry for the canonical vocabulary this answer introduced):

- **XP dropped entirely** from the live HUD — the Run End screen remains its only display, consistent with ADR-0009. No above-player XP indicator.
- **Health indicator**: every entity (Player, Enemy) shows one, always. Icon (`.Pickup_Heart`) + constantly-playing particles, fraction-only — no numeric HP readout.
- **Secondary indicator** (player only, exactly one visible at a time, keyed by the equipped Weapon's family):
  - **Gun → Ammo indicator**: icon (`.Pickup_Ammo`) + particles, clip/reserve fraction. Reload gets a visually distinct particle/icon treatment from plain depletion (exact mechanism left to the prototype ticket). No numeric readout.
  - **Melee_Weapon / Magic → Cooldown indicator**: `cooldown_timer` counting back to Ready. Placeholder icon for now (real icon art for melee/magic is out of scope for this map — see Out of scope on the map). No numeric readout.
  - **Windup gets no indicator of its own, for any weapon family.** Confirmed via code: `draw_weapon` ([main.odin:864-874](../../../main.odin)) already gives Windup a dedicated visual telegraph on the weapon's own draw (arc pull-back for Melee_Weapon, pullback along `aim_dir` for Gun/Magic) — a Resource indicator would be redundant with it. This resolved cleanly and symmetrically across all three weapon families, not just Gun.
- **Composition**: icon + particles for every indicator, never pure particles, never a numeric readout — particles alone risked being illegible mid-combat.
- **Layout**: stacked above the entity, Health indicator closer to the sprite, the secondary indicator (when present) further out. At most two indicators ever shown on the player at once (single currently-equipped Weapon).
- **Enemies reuse the exact same single-indicator shape as the player's Health indicator** — one consistent indicator unit repo-wide; enemies just never get a second slot. (This substantially answers [Decide the fate of enemy health bars](03-enemy-health-bar-unification.md)'s "same shape or not" question — that ticket's remaining scope has been narrowed accordingly.)
- **Icon art**: reuses existing `.Pickup_Heart`/`.Pickup_Ammo` atlas icons; melee/magic get a placeholder shape, real icon art is out of scope for this map.
