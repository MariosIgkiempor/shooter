# Shell page and loading

Type: prototype
Status:
Blocked by: 01

## Question

What surrounds the canvas? Web toolchain recipe confirmed the shell page is ours (`--shell-file`, driving `main_start`/`main_update`/`main_end` from `requestAnimationFrame`), so the loading splash — what the player sees before the first frame while the ~1.2 MB wasm + atlas arrives — graduated from the map's fog into this ticket. The page needs: a viewport-filling canvas, a loading state while the ~1.2 MB wasm + atlas arrives, a page background that suits the game, and a sane message when WebGL is unavailable.

Build a throwaway shell page to react to — rough HTML/CSS with a fake loading bar is enough — and lock: whether loading shows progress or a static splash, what the page looks like around the canvas at odd aspect ratios, and what the WebGL-failure state says. Links the prototype as an asset.

Lower priority than the tickets above it.
