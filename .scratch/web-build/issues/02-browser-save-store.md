# Browser save store

Type: research
Status: resolved

## Question

Where should the ~1.5 KB `game_save.json` blob live in the browser — `localStorage`, IndexedDB, or Emscripten's IDBFS (a persisted virtual filesystem, so `core:os`-style file writes "just work" after a `FS.syncfs`)?

Facts to pin, each against primary sources (MDN, WebKit/Chromium docs, Emscripten's FS docs):

- **Sync vs async**: `localStorage` is synchronous; IndexedDB and IDBFS's `syncfs` are async. The web-only `visibilitychange`/`beforeunload` hook that charting locked as belt-and-braces can only be trusted with a synchronous write — confirm, and confirm whether `visibilitychange` (not `beforeunload`) is the reliable event on current Chrome, Firefox and Safari.
- **Quotas and eviction**: per-origin limits for each; **Safari's Intelligent Tracking Prevention deleting all script-writable storage after seven days without interaction** — does it apply to a first-party GitHub Pages origin the player navigates to directly, and does IndexedDB fare any differently from `localStorage`?
- **Origin on GitHub Pages**: `<user>.github.io/<repo>` shares one origin with every other Pages site under `<user>.github.io` — so the storage key must be namespaced, and another project's misbehaving script could read or clear it. Confirm, and note whether a custom domain changes the calculus (it does, but that's out of scope to *do*).
- **Runtime cost**: IDBFS adds Emscripten FS + IDB glue to the payload; quantify roughly.
- **Fit with the foreign-import mechanism** from Web toolchain recipe: the JS shim shape (`save(key, ptr, len)` / `load(key) -> ptr, len`) and how a string crosses the boundary in each direction, including who frees it.
- **Export/import**: which option makes "download the blob as a file" and "read a dropped file" easiest (`Blob` + `<a download>` and `<input type=file>` are independent of the store, but IDBFS would want the file re-synced).

End with a recommendation and the one-paragraph reasoning a build session can act on. Capture the findings as a Markdown file in the repo on a throwaway `research/browser-save-store` branch, and link it from this ticket's answer.

## Answer

**`localStorage`, one namespaced key (`shooter:game_save:v1`), the JSON blob as a string, behind the Save-store seam.** The web Target implements the seam with four `contextless` foreign procs — `save_store_write(key, value: string) -> bool`, `save_store_length(key) -> int` (-1 = absent), `save_store_read(key, buf: []byte) -> int`, `save_store_delete(key)` — following `core:sys/wasm/js`'s `(ptr, len)`-in / caller-buffer-out convention, so Odin owns every allocation and JS never mallocs. The belt-and-braces hook is `visibilitychange` (on `hidden`) plus `pagehide`, calling an exported Odin proc that saves synchronously; `beforeunload` is not registered at all.

Facts that decided it:

1. `localStorage.setItem` is synchronous and complete on return (MDN); IndexedDB and IDBFS's `FS.syncfs` are asynchronous, and Chrome's Page Lifecycle doc says an IDB transaction's `onsuccess` "may not run — even if the transaction has committed successfully" once the page is hidden. Only the synchronous write is trustworthy from the unload hook; MDN and Chrome both name `visibilitychange → hidden` as the last reliable signal and warn `beforeunload` is unreliable and disables Firefox's bfcache.
2. Safari's ITP deletes *all* script-writable storage — WebKit lists "Indexed DB, LocalStorage, Media keys, SessionStorage, Service Worker registrations and cache" — after seven days of Safari use without a click/tap on the site, first-party GitHub Pages origin included; IndexedDB fares no differently, so the store choice can't mitigate Safari. Export/import is the mitigation, and the failed-load UX should treat an empty store as "no save", not an error.
3. `<owner>.github.io/<repo>` sites all share the origin `https://<owner>.github.io` (GitHub docs + MDN's origin definition), hence one `localStorage`; a sibling project's script can read or clear the save, so the key is namespaced. `github.io` is on the Public Suffix List, so other GitHub users' sites are a different site for ITP and Firefox group limits. A custom domain would give a private origin; out of scope.
4. IDBFS's "core:os writes just work" premise is false here: on `js_wasm32`, `core:os` is `#panic("core:os is unsupported on js/wasm")` (`core/os/wasm.odin`), so the save crosses a JS shim whatever the store is — and IDBFS would add ~20 KB of Emscripten FS JS (≈8 KB gzip, per Emscripten's own code-size baselines) to persist one 1.5 KB file it still has to be told to sync.

Findings: `docs/research/browser-save-store.md` on branch `research/browser-save-store`.
