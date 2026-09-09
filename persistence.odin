package shooter

import "base:intrinsics"
import "core:reflect"

// -- Identity strings ---------------------------------------------------
// The canonical form every persisted enum value is written and compared as:
// the enum case's own name, read straight out of Odin's static type info.
// Not allocated - the string points into the binary's type-info tables, so
// it's safe to store, compare and marshal indefinitely.
//
// An ordinal is not a contract anyone declared. core:encoding/json writes a
// bare integer for an enum unless `use_enum_names` is passed, so inserting a
// case above another, or sorting an enum alphabetically, silently rewrites
// the meaning of every save file that referred to it - a different weapon in
// the player's hands, different enemies in a map, no error anywhere.
//
// This pair exists rather than json.marshal's `use_enum_names` option
// because that option's read side is silently lossy in exactly the way this
// is meant to prevent: core:encoding/json loops an enum's names and, finding
// no match, returns `true, nil` and leaves the zero value in place - see the
// `// TODO(bill): should this be an error or not?` in
// core/encoding/json/unmarshal.odin's string-token path. So a persisted enum
// is a plain `string` field, converted explicitly here, and a name no case
// carries reaches the load path as a failure it reports. See ADR-0028.

// No `ok` return, deliberately. The only way this fails is a value outside
// the enum's declared set - a bad cast or a bit pattern from outside this
// program, never a value the type system produced - so threading an `ok`
// through every write site would buy nothing. The failure is still loud
// rather than silent, just deferred: "" is not a name any case carries, so
// it fails on the way back in through enum_from_identity_string.
enum_identity_string :: proc(value: $E) -> string where intrinsics.type_is_enum(E) {
	name, ok := reflect.enum_name_from_value(value)
	if !ok {
		log_error("No {} case carries this value - persisting an empty identity", typeid_of(E))
		return ""
	}
	return name
}

// Resolves a persisted identity back to its enum case. ok is false for a
// name no case carries - one renamed or deleted since the data was written -
// and the zero value is never substituted for it.
//
// Reports the offending name and its enum itself, rather than leaving that
// to callers: every caller would say the same sentence, and typeid_of names
// the enum as precisely as a hand-written message would. What a caller adds
// on top is the context this can't see - which file, and which record inside
// it (see load_map) - so the two lines together say exactly which edit is
// needed.
enum_from_identity_string :: proc(
	$E: typeid,
	identity: string,
) -> (
	value: E,
	ok: bool,
) where intrinsics.type_is_enum(E) {
	value, ok = reflect.enum_from_name(E, identity)
	if !ok {
		log_error("`{}` is not a {} this build knows", identity, typeid_of(E))
	}
	return
}

// Frees an identity string that came off disk and clears the field, for a
// load path that resolves one and is done with it.
//
// Only ever call this on a field json.unmarshal populated, on a value it
// populated wholesale. The strings enum_identity_string hands out point into
// static type info and must never be freed - hence the pointer and the
// blanking, so a second call can't double-free and a stale pointer can't be
// read back. load_map qualifies: it unmarshals into a fresh local Map, so a
// non-empty identity there is always heap. load_game does not - it unmarshals
// into the long-lived `game`, where a key absent from the file leaves the
// previous (possibly static) string in place - and it deliberately doesn't
// call this, since it runs once per process and leaks at most three small
// strings, the same posture the rest of load_game already takes toward what
// json.unmarshal allocates for it.
delete_identity_string :: proc(identity: ^string) {
	delete(identity^)
	identity^ = ""
}
