Type: research
Status: resolved

## Question

How can `Weapon` become a tagged union and still be safely persisted in `data/game_save.json`, given `core:encoding/json`'s union decode picks the *first* variant that parses without error, and every struct field is optional on decode (missing fields are just left zeroed)?

`Player.weapon` has no `json:"-"` tag today — it round-trips through save/load as real run progression, so a mis-decode here (e.g. a saved Magic weapon coming back as a zeroed-out Gun) is a real player-facing bug, not just an editor-template quirk like the existing `Enemy_Behaviour`/`Spawner.template` case (see enemy.odin:23-32).

Investigate what Odin's `core:encoding/json` actually supports for this:

- Does it support a custom `unmarshal`/`marshal` proc per type (so `Weapon` could hand-roll safe decode/encode instead of relying on automatic union-member guessing)?
- Does it support any documented discriminant-field convention for unions, or `json:"..."` tag behavior that would help?
- Failing those, what does a manual two-step decode look like — e.g. decode a plain `kind: Weapon_Kind` field first, then explicitly construct/decode into the matching variant instead of letting `json.unmarshal` guess?

Report back: the concrete mechanism to use, with a sketch of what the `Weapon` struct / custom (un)marshal proc would look like, so ticket 02 ("Design the Weapon union shape") can lock the exact field layout and discriminant around it.

## Answer

Confirmed by reading the local Odin stdlib source directly (`core:encoding/json`, build `ea5175d`): there is no per-type marshal/unmarshal hook Odin discovers automatically, and no discriminant-tag convention for unions — `json.unmarshal` decodes a union by trying each variant in declaration order and committing the first one that parses without error (`unmarshal.odin` lines 374-401), and every struct field is optional on decode, exactly as the `enemy.odin:23-32` comment warns.

**Mechanism to use**: never pass `Weapon` (the union) directly to `json.marshal`/`json.unmarshal`. Add a plain, non-union DTO — `Weapon_Save :: struct { kind: Weapon_Kind, gun: Maybe(Gun), melee: Maybe(Melee_Weapon), magic: Maybe(Magic) }` — and convert union → DTO on save, DTO → union on load via an explicit `switch` on the decoded `kind` field. Since `Weapon_Save` is a struct, not a union, `json.unmarshal` never runs its variant-guessing loop on it at all. `Weapon` itself stays a real Odin union for runtime `switch &w in weapon` dispatch, mirroring `Enemy_Behaviour` — this only changes how persistence happens, not the runtime shape.

Full findings (evidence, exact source line citations, code sketch) captured in [01-weapon-save-decode-safety.findings.md](./01-weapon-save-decode-safety.findings.md).
