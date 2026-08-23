# Weapon uses a wrapper struct, not a bare union like Enemy_Behaviour

Status: accepted

`Enemy_Behaviour :: union { Melee, Ranged }` is a bare union with no shared header — each variant is fully self-contained, and it's the only polymorphism precedent in the codebase. `Weapon` needed a shape for Gun/Melee/Magic with genuinely shared state (`kind`, `fire_mode`, `damage`, `action_rate`, `cooldown_timer`), so mirroring `Enemy_Behaviour` exactly — each variant embedding a common header via `using` — was the obvious first reach.

We rejected that: Odin unions don't expose fields without a `switch`/type-assertion first, even when every variant embeds the same `using` header. Two existing call sites read weapon fields directly with no switch (`main.odin:231` — `weapon.fire_mode`, `main.odin:523` — `weapon.kind`), and the bare-union shape would force both into a switch just to read a common field, with the same tax paid by every future direct read of a shared field.

Instead `Weapon` is a plain struct — common fields live directly on it — with one field, `variant: Weapon_Variant`, holding `union { Gun, Melee_Weapon, Magic }`. Only variant-specific reads need a `switch`; common-field reads stay flat, zero-churn field access, as they are today.

This means the codebase now has two different polymorphism shapes for a reason: reach for the bare-union pattern (`Enemy_Behaviour`) when variants share no state, and the wrapper-struct pattern (`Weapon`) when they share a common header that's read outside of variant-specific logic.
