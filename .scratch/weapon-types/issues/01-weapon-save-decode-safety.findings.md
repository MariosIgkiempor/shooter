Type: research

## Question

How can `Weapon` become a tagged union and still be safely persisted in `data/game_save.json`,
given `core:encoding/json`'s union decode picks the *first* variant that parses without error, and
every struct field is optional on decode (missing fields are just left zeroed)?

## Answer

**There is no per-type "hook" convention (no Go-style `MarshalJSON`/`UnmarshalJSON` method
lookup) and no discriminant-field convention respected during union decode.** `core:encoding/json`
does expose a real custom-codec mechanism, but it is a **global registry keyed by `typeid`**
(`register_user_unmarshaler` / `register_user_marshaler`), not a method Odin looks for on the type
itself. Registering a per-typeid proc for `Weapon` is a legitimate option, but the more idiomatic
and lower-ceremony fix, given what the package actually supports, is:

**Do not make the persisted, on-disk shape of the weapon a `union` at all.** Keep `Weapon` as a
real Odin `union { Gun, Melee, Magic }` for runtime ergonomics (`switch &w in weapon` dispatch,
mirroring `Enemy_Behaviour`), but add a **separate plain (non-union) DTO struct** with an explicit
`kind: Weapon_Kind` field plus one optional payload field per variant (`Maybe(Gun)`,
`Maybe(Melee)`, `Maybe(Magic)`), and convert union → DTO on save / DTO → union on load. The load
path switches on the decoded `kind` field explicitly — it never lets `json.unmarshal` guess by
variant-declaration-order. This sidesteps the guessing behavior entirely because the persisted
type is no longer a `union` from the json package's point of view.

## Evidence

All findings below were read directly from the local Odin installation at
`/Users/mario/Software/odin/core/encoding/json/` (the `odin` binary on this machine is aliased to
`~/Software/odin/odin`; `odin version` reports `dev-2026-05-nightly:ea5175d`, i.e. build commit
`ea5175d`, so the same lines should be visible at
`https://github.com/odin-lang/Odin/blob/ea5175d/core/encoding/json/<file>` if that commit is
reachable on GitHub's default branch history). No secondary sources (blog posts, forum threads)
were used for any claim below.

### 1. Custom marshal/unmarshal hook per type?

**Yes, but it's a global typeid registry, not a per-type method/interface convention.**

File: `/Users/mario/Software/odin/core/encoding/json/unmarshal.odin`, lines 29–109.

```odin
User_Unmarshaler :: #type proc(p: ^Parser, v: any) -> Unmarshal_Error

// NOTE(Jeroen): This is a pointer to prevent accidental additions
_user_unmarshalers: ^map[typeid]User_Unmarshaler

set_user_unmarshalers :: proc(m: ^map[typeid]User_Unmarshaler) {
	assert(_user_unmarshalers == nil, "set_user_unmarshalers must not be called more than once.")
	_user_unmarshalers = m
}

register_user_unmarshaler :: proc(id: typeid, unmarshaler: User_Unmarshaler) -> Register_User_Unmarshaler_Error {
	...
	_user_unmarshalers[id] = unmarshaler
	return .None
}
```

And it's actually consulted, first thing, inside the generic decode dispatcher:

`unmarshal.odin` lines 362–371 (`unmarshal_value`):
```odin
unmarshal_value :: proc(p: ^Parser, v: any) -> (err: Unmarshal_Error) {
	UNSUPPORTED_TYPE := Unsupported_Type_Error{v.id, p.curr_token}
	token := p.curr_token

	if _user_unmarshalers != nil {
		unmarshaler := _user_unmarshalers[v.id]
		if unmarshaler != nil {
			return unmarshaler(p, v)
		}
	}
	...
```

Mirror on the encode side, `/Users/mario/Software/odin/core/encoding/json/marshal.odin` lines
65–128: `User_Marshaler :: #type proc(w: io.Writer, v: any, opt: ^Marshal_Options) -> Marshal_Error`,
`set_user_marshalers`, `register_user_marshaler`.

This is a real, usable mechanism (register a proc for `typeid_of(Weapon)` once at program start,
and it fires for every `Weapon` anywhere in the tree — including nested inside `Player`/`game`).
But it is process-global state requiring an explicit one-time `set_user_marshalers`/
`set_user_unmarshalers` call before any (un)marshal call, it is opt-in per typeid rather than a
`MarshalJSON`-style method Odin discovers automatically, and — critically — it fires for
**every** value of that typeid anywhere in the object graph being (un)marshaled, so it's a bigger
hammer than just "this one field." It's viable, but the wrapper-struct approach below is simpler
and keeps the persistence logic colocated with the DTO rather than living in global registration
state that has to run before `load_game`/`save_game`.

### 2. Discriminant-field convention or `json:"..."` tag support for unions?

**No.** The only things `json:"..."` tags do are field renaming and `omitempty` (plus an unrelated
`jsoncomment` tag for doc comments on marshal). No tag or convention exists to pick a union
variant.

Evidence — the *only* tag handling in the whole package:

- Decode side, `unmarshal.odin` line 556: `tag_value := reflect.struct_tag_get(field.tag, "json")`
  then `json_name_from_tag_value` (lines 513–521) splits on the first comma into `json_name` and
  an `extra` string — `extra` is read but (searching the file) never interpreted as anything
  beyond marshal's `omitempty`; on the unmarshal side it isn't consulted for anything besides
  the name at all.
- Encode side, `marshal.odin` lines 481–508: `json_name, extra := json_name_from_tag_value(...)`
  then `#partial switch` on tokens of `extra` — the only case handled is `"omitempty"` (line
  491–492); there is no `"discriminant"` or similar case.
- The union encode path (`marshal.odin` lines 534–560, quoted under Q3 below) writes only the
  chosen variant's own fields as a plain `{...}` object — it does **not** inject any kind/type
  marker key alongside them. So a hand-written discriminant convention isn't even latent in the
  wire format today; nothing during encode writes out which variant was active.

### 3. Exact union-decode-order logic

File: `/Users/mario/Software/odin/core/encoding/json/unmarshal.odin`, lines 374–401
(inside `unmarshal_value`):

```odin
ti := reflect.type_info_base(type_info_of(v.id))
if u, ok := ti.variant.(reflect.Type_Info_Union); ok && token.kind != .Null {
	// NOTE: If it's a union with only one variant, then treat it as that variant
	if len(u.variants) == 1 {
		variant := u.variants[0]
		v.id = variant.id
		ti = reflect.type_info_base(variant)
		if !reflect.is_pointer_internally(variant) {
			tag := any{rawptr(uintptr(v.data) + u.tag_offset), u.tag_type.id}
			assign_int(tag, 1)
		}
	} else if v.id != Value {
		for variant, i in u.variants {
			variant_any := any{v.data, variant.id}
			variant_p := p^
			if err = unmarshal_value(&variant_p, variant_any); err == nil {
				p^ = variant_p

				raw_tag := i
				if !u.no_nil { raw_tag += 1 }
				tag := any{rawptr(uintptr(v.data) + u.tag_offset), u.tag_type.id}
				assign_int(tag, raw_tag)
				return
			}
		}
		return UNSUPPORTED_TYPE
	}
}
```

This confirms, word for word, the ticket's premise:

- It iterates `u.variants` **in declaration order** (`for variant, i in u.variants`).
- For each variant it takes a **copy** of the parser state (`variant_p := p^`) and recursively
  calls `unmarshal_value` against that variant's type. If that returns `err == nil`, the parser
  state is committed (`p^ = variant_p`), the tag is set to that variant's index, and it **returns
  immediately** — no comparison of variants, no "best match," first success wins, permanently.
  If a variant fails partway, the copied parser state (`variant_p`) is simply discarded and the
  next variant is tried from the original position `p^`.
- `token.kind != .Null` guard means an explicit JSON `null` bypasses variant-guessing entirely and
  zeroes the union (handled a few lines up in the same function, the `.Null` case at line
  411–414 zero-fills `v.data` for `ti.size` bytes).
- A struct variant "succeeds" via `unmarshal_object` (lines 525–743), which — per field in the
  incoming JSON object — looks up a matching struct field by name/tag (lines 555–573); if a JSON
  key doesn't match any field it is **silently skipped** (lines 630–643, "allows skipping unused
  struct fields") rather than erroring, and any struct field that isn't mentioned in the JSON
  object is simply never touched, so it stays at whatever `mem.zero`'d/default value the
  destination memory had going in. There is no "all fields must be present" requirement anywhere
  in `unmarshal_object`. So yes: a lone `{}` (or any object whose keys don't happen to collide
  with the wrong type in an incompatible way, e.g. string-vs-number) will "successfully" decode
  into whichever variant is tried first, exactly as the ticket and the `enemy.odin:23-32` comment
  describe. There is no `Maybe`-specific special case in this path — `Maybe(T)` decodes as
  whatever `T`'s own decode does since `Maybe` is itself represented as a 2-variant union
  (`T` and nothing) and goes through this same one-variant-vs-multi-variant branch.

### 4. Manual workaround support (two-pass decode via `json.Value`)

**Yes — `core:encoding/json` fully supports decoding into a generic value first.**

- `Value` is a plain union of JSON primitive shapes: `types.odin` lines 51–67:
  ```odin
  Null    :: distinct rawptr
  Integer :: i64
  Float   :: f64
  Boolean :: bool
  String  :: string
  Array   :: distinct [dynamic]Value
  Object  :: distinct map[string]Value

  Value :: union {
  	Null, Integer, Float, Boolean, String, Array, Object,
  }
  ```
- `unmarshal_value` special-cases `Value` explicitly (`unmarshal.odin` line 385: `else if v.id != Value`
  skips the variant-guessing loop for `Value` itself, and lines 403–408:
  `case Value: dst = parse_value(p) or_return; return` — so unmarshaling into a `json.Value`
  field/variable always works and always gives back the real, un-guessed structural JSON, letting
  you inspect it before deciding anything).
- Standalone parse entry points exist independent of a target type — `parser.odin` line 31:
  `parse :: proc(data: []byte, ...) -> (Value, Error)` and line 35: `parse_string :: proc(data: string, ...) -> (Value, Error)`.
- Once you have a `Value`, you can type-assert `v.(Object)` (a `map[string]Value`), pull out a
  `"kind"` key, read it as a `String`/`Integer`, and then decide which concrete struct to
  re-marshal-and-unmarshal (or manually walk) into. This is a completely ordinary,
  fully-supported two-pass pattern with this package — nothing about it fights the library.
- I did not find any existing Odin core/vendor source, official example, or GitHub issue/PR
  specifically titled around "union json marshal" while reading the source tree locally (only the
  source files above were available for direct reading in this environment: no network fetch of
  odin-lang/Odin's GitHub issues was performed as part of this pass since the local install fully
  answered questions 1–4 with primary-source certainty; if github.com/odin-lang/Odin is reachable,
  the equivalent lines to cite there are the same line numbers/content quoted above against commit
  `ea5175d`, e.g. `https://github.com/odin-lang/Odin/blob/ea5175d/core/encoding/json/unmarshal.odin#L374-L401`).
- The plain-wrapper-struct-with-explicit-kind-and-Maybe-payloads pattern described in the ticket
  is workable and is in fact simpler than the two-pass-`Value` approach for this case: you don't
  even need `json.Value`/`json.parse` if the wrapper struct's `kind` field is decoded losslessly
  by ordinary struct decode (it's just an enum field on a plain, non-union struct — no
  variant-guessing applies to it at all, since `Weapon_Save` below is a `struct`, not a `union`).
  The only place manual logic is required is converting DTO → union after decode (a single
  `switch dto.kind` need read only the *chosen* `Maybe(...)` field) — see code sketch.

## Code sketch

```odin
package shooter

// ---- runtime shape: real union for ergonomic switch-dispatch ----

Weapon_Kind :: enum {
	Gun,
	Melee,
	Magic,
}

Weapon :: union {
	Gun,
	Melee_Weapon, // named to avoid clashing with enemy.odin's Melee
	Magic,
}

Gun :: struct {
	fire_mode:        Fire_Mode,
	damage:           f32,
	projectile_speed: f32,
	fire_rate:        f32,
	cooldown_timer:   f32,
	clip_size:        int,
	ammo_in_clip:     int,
	reserve_ammo:     int,
	reload_time:      f32,
	reload_timer:     f32,
	pellet_count:     int,
	spread_angle:     f32,
	bullet_lifetime:  f32,
}

Melee_Weapon :: struct {
	damage:         f32,
	attack_range:   f32,
	cleave_angle:   f32,
	swing_cooldown: f32,
	cooldown_timer: f32,
}

Magic :: struct {
	damage:         f32,
	cast_cooldown:  f32,
	cooldown_timer: f32,
	// effect payload: fog for now
}

// ---- persistence shape: plain struct, NOT a union, so json.unmarshal
// never has to guess a variant. `kind` is the only discriminant and it's
// read/written with zero ambiguity because Weapon_Save is a struct. ----

Weapon_Save :: struct {
	kind:  Weapon_Kind,
	gun:   Maybe(Gun)          `json:"gun,omitempty"`,
	melee: Maybe(Melee_Weapon) `json:"melee,omitempty"`,
	magic: Maybe(Magic)        `json:"magic,omitempty"`,
}

weapon_to_save :: proc(w: Weapon) -> Weapon_Save {
	switch v in w {
	case Gun:          return {kind = .Gun,   gun = v}
	case Melee_Weapon: return {kind = .Melee, melee = v}
	case Magic:        return {kind = .Magic, magic = v}
	}
	unreachable()
}

// Explicit switch on the *decoded* kind field - never lets json.unmarshal's
// union-variant-guessing loop run, because Weapon itself is never the type
// passed to json.unmarshal/json.marshal; only Weapon_Save is.
weapon_from_save :: proc(s: Weapon_Save) -> Weapon {
	switch s.kind {
	case .Gun:   return s.gun.?   or_else Gun{}
	case .Melee: return s.melee.? or_else Melee_Weapon{}
	case .Magic: return s.magic.? or_else Magic{}
	}
	return Gun{} // unreachable if kind is always one of the above
}

// In Player, replace the raw union field with the DTO for persistence,
// or (equivalently) keep `weapon: Weapon` on Player tagged `json:"-"` and
// persist `weapon_save: Weapon_Save` alongside it, converting at load/save
// boundaries in load_game/save_game:

// save_game():
//   player_copy := game.player
//   ... game.player.weapon is Weapon (union) at runtime ...
//   Build a save-DTO view of `game` where `weapon` has been swapped for
//   `weapon_to_save(game.player.weapon)` before calling json.marshal, OR
//   give Player a `weapon_save: Weapon_Save` field populated right before
//   marshal and tag the runtime `weapon: Weapon` field `json:"-"`.

// load_game(): after json.unmarshal succeeds,
//   game.player.weapon = weapon_from_save(game.player.weapon_save)
```

The exact plumbing of "does `Player` carry both fields, or does `save_game`/`load_game` build a
separate save-view struct" is a ticket-02 field-layout decision, not something this research needs
to settle — either shape avoids ever calling `json.marshal`/`json.unmarshal` directly on a
`Weapon` union value.

## Recommendation for ticket 02

The `Weapon` union itself can and should stay a real, idiomatic Odin `union { Gun, Melee_Weapon,
Magic }` for runtime dispatch (mirroring `Enemy_Behaviour`) — nothing about the persistence
problem requires flattening runtime code into a big `switch kind` everywhere. The one hard
constraint this research places on ticket 02: **`Weapon` must never be the direct argument type of
`json.marshal`/`json.unmarshal`** (whether that's because `Player.weapon` is `json:"-"` and a
`Weapon_Save` sibling field is what actually gets saved/loaded, or because `save_game`/`load_game`
convert into/out of a `Weapon_Save`-shaped view of `Player` before calling into `core:encoding/json`
at all). Ticket 02 should lock: (a) the exact field layout of the three payload structs, (b) the
`Weapon_Save` DTO shape (kind enum + one `Maybe(_)` per variant, following the sketch above), and
(c) where the `weapon_to_save`/`weapon_from_save` conversion calls live relative to `save_game`/
`load_game` (main.odin ~lines 76–135) and `weapon_create`/`upgrade_weapon`/`try_fire_weapon` in
weapon.odin, so a build session can implement it without further design questions.

## Provenance

Full research performed by a background subagent in an isolated worktree, committed on throwaway
branch `worktree-agent-ac353cd78af9e09d0` (commit `484d6fe`); this file is that branch's findings
copied into the main tree so the pointer survives worktree cleanup.
