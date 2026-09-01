Type: prototype
Status: resolved

## Question

Specify how enemies get positioned when they spawn so they are always
off-screen relative to the camera, replacing today's fixed
`spawner.position` placement (`enemy.odin:419-437`) entirely — no authored
spawn positions survive this effort.

Needs to settle:

- **Camera visible-world-rect helper.** No such utility exists today
  (`platform.odin` only exposes raw screen pixel dimensions via
  `get_screen_width`/`get_screen_height`; the only world↔screen conversion
  in the codebase is ad hoc `rl.GetScreenToWorld2D` calls for mouse
  picking). Derive the camera's visible world rect from `camera.target`,
  `camera.zoom` (`GAMEPLAY_ZOOM :: 1.2`, `main.odin:17`), and screen
  dimensions, and decide where this helper lives (likely alongside
  `renderer.odin` or `platform.odin`).
- **Placement algorithm.** Pick a point guaranteed outside that visible
  rect by some margin — decide between a random angle around the player at
  a fixed off-screen distance vs. a random point along a randomly-chosen
  screen edge extended outward. Either way, the point must stay off-screen
  even as the camera pans/follows the player between the moment it's
  chosen and the moment the enemy is actually visible.
- **Validity checks.** Decide whether the chosen point needs to be
  checked against tilemap collision / map bounds (an off-screen point could
  land inside a wall or entirely outside the playable map), and what the
  retry/fallback behavior is if it does.
- **Interaction with `MAX_ENEMIES`.** Confirm the existing global cap
  (`enemy.odin:10`, currently 24) still gates spawning the same way
  regardless of how positions are chosen.
- **Prototype it live** (in-game or a standalone scene) to confirm enemies
  never visibly pop into existence even during normal camera movement,
  before locking the algorithm in.

## Answer

**Camera visible-world-rect helper.** New small helper (no existing
equivalent): given `camera.target`, `camera.zoom`, and screen dimensions,
the visible world rect is `target ± (screen_w/zoom/2, screen_h/zoom/2)` —
raylib's `Camera2D` treats `offset` as screen-center, so this is a plain
half-extent box around `target`, no rotation handling needed (the game
never rotates the camera). Lives as a new proc near `renderer.odin`'s
camera helpers (`begin_using_camera`/`end_using_camera`), returning a
simple rect struct.

**Placement algorithm: angle-around-player, not edge-based.** Prototyped
both in [the demo](../prototypes/offscreen-spawn-placement.html) (commit
`2bebf71` on branch `prototype/offscreen-spawn-placement`); angle-around
is simpler (one distance, one angle, no edge selection) and produces the
same guarantee. Distance = `hypot(visible_rect_half_width,
visible_rect_half_height) + margin` (margin ~30px validated in the demo),
angle = uniform random 0..2π around the player's *current* position at
spawn time. Confirmed live: spawn points stayed off-screen through
several player-movement steps in the "camera panning race" scenario — the
half-diagonal-plus-margin distance comfortably outpaces how far
`update_camera_center_smooth_follow`'s lerp can close the gap in the time
before the enemy itself starts moving toward the player. (Caveat: the
demo's movement scale is coarse — a few large steps — worth a quick sanity
check against the real per-frame smooth-follow lerp rate during
implementation, but the safety margin here is generous enough that this
is a low-risk assumption, not an open question.)

**Validity checks: yes to both, retry then clamp.** The demo's
`pickSpawnPoint` loop retries (up to a small fixed cap, 6 in the demo) any
candidate that's either still inside the visible rect or inside a
blocking obstacle, then clamps the final point into the map's bounds.
Confirmed live via the "wall collision retry" scenario (candidate
re-picked when it landed inside an obstacle) and "map edge" scenario
(clamping engaged near a map corner without needing all retries). Real
implementation should check the clamped point against tilemap solid-tile
collision (mirroring however `Grounded` movement already checks
`move_actor`'s wall collision) rather than simple circular obstacles like
the demo's placeholder walls. If every retry is exhausted, fall back to
the clamped-but-still-blocked/visible point rather than skipping the
spawn entirely — a single enemy occasionally appearing slightly early or
inside a rare double-wall pocket is a smaller problem than a trigger
silently under-spawning.

**`MAX_ENEMIES` interaction.** Unchanged — placement is orthogonal to the
existing global cap (`enemy.odin:10`); `spawn_enemy` still checks
`len(game.enemies) < MAX_ENEMIES` before this placement logic ever runs.
