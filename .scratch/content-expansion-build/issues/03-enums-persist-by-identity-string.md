# 03: Enums persist by identity string

**What to build:** Renaming or reordering an authored enum stops silently
rewriting saved data. A persisted enum value round-trips through its own name,
and a name that no longer exists is an error the load path reports rather than a
value that quietly resolves to whatever now sits at ordinal zero.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] One parametric helper pair converts any enum to and from its identity string; the hand-written per-enum converters collapse into it
- [x] Reading an unrecognised name fails loudly instead of returning the zero value
- [x] Every enum currently persisted by ordinal round-trips by name
- [x] Existing saved data still loads
