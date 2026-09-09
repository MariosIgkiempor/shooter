# 19: Reach and Clip Size

**What to build:** Two upgrades say what they do. The melee upgrade that used to
widen an arc now extends reach, and is named for it. The Clip Size upgrade
scales rather than adding a flat amount, so it stays meaningful across weapons
whose clips differ by an order of magnitude.

**Blocked by:** 18

**Status:** resolved

- [x] The arc-width upgrade extends range and is renamed to Reach
- [x] Clip Size applies multiplicatively
- [x] Existing upgrade purchases and their displayed effects stay coherent

## Comments

`Arc_Width` -> `Reach` throughout: enum case, `display_name`, `apply_upgrades`'
melee arm, `shop.odin`'s shared purchase arm, and the icon. The old glyph was
`icon_sector` - literally a swept fan - so it was redrawn as a blade with the
shared "further" chevron off its tip, which reads as reach and stays distinct
from `icon_upgrade_range`'s measuring rule (Magic's Range extends a cast, not
the weapon). ADR-0026 had already specified this rename verbatim; nothing here
needed a new ADR.

Reach deliberately stays `Additive(10)`. Only Clip Size had the incoherence the
ticket names - Dagger 40 and Sword 60 are within 1.5x of each other, so a flat
px amount means much the same thing on both.

Clip Size is `Multiplicative(1.15)`, matching Damage. The load-bearing edit was
in `apply_upgrades`: it computed `base.clip_size + apply_upgrade_effect(0, ...)`,
whose `0` base returns `0` under a multiplier. That moved into a named
`upgraded_clip_size`, which applies the multiplier to the real baseline and
**rounds** rather than truncating - 1.15 on the Shotgun's six is +0.9 of a
round, and truncation would hand the player nothing for a purchase they just
paid for.

`1.10` was considered and rejected for exactly that reason: the Shotgun's
second stack rounds back onto 7 and buys nothing. Under 1.15 every stack gains
at least one round on all three ranged presets (Shotgun: 7, 8, 9, 10, 12, 14,
16, 18, 21, 24). `test_every_clip_size_stack_grows_every_gun_s_clip` loops all
Gun presets and asserts that property, so issue 20's rifle fails here rather
than in someone's hands if its clip is small enough to stall.

Third checkbox: `try_buy_upgrade` already credited `ammo_in_clip` with the
*delta* between old and new capacity rather than refilling, which is
multiplicative-safe as written and needed no change - `shop_test`'s existing
"grants the bonus as usable ammo not a refill" now locks that under the new
model. The Shop shows only `display_name [stack-max]` and no effect magnitude
anywhere, so no displayed number could go stale. The tuning panel picks its
effect slider range off the union variant, so Clip Size's slider moved from
`(0, 100)` to `(1, 3)` on its own.

`apply_upgrades` had no melee coverage at all, so two tests were added: one
that a Reach stack extends `Melee_Weapon.range` from the preset baseline, and
one in `hit_volume_test` that the Hit volume grows with it end to end - the
two halves passing separately is exactly how a Reach stack could buy a longer
number and no longer blade.

Accepted cost: `Player.upgrade_stacks` is an enumerated array, which
`core:encoding/json` keys by enum-case name, so a save holding `"Arc_Width"`
fails to unmarshal and `load_game` resets the whole save, account progression
included. That is the cost ADR-0028 explicitly took, and no migration shim was
added. `data/game_save.json` is gitignored, so this is one local reset.

Found in review: the F8 tuning panel registered its effect slider under
`upgrade.<name>.effect` regardless of the effect's shape, and `data/tuning.json`
is tracked (unlike the save). An Override of `2` written in the `Additive(2)`
era is a legal Multiplicative value and sits inside the new slider's `(1, 3)`
range, so it would have been re-applied silently as a x2-per-stack multiplier -
the one way this change could have corrupted a tuning file rather than failing
loudly. The slug now carries the shape (`effect_mult` / `effect_add`), so an
Override written under the old shape is an unknown slug, which `load_tuning`
already drops with a warning. That is the same self-healing posture the rest of
the tuning loader takes, and it is what makes the third checkbox true for the
tuning panel and not only for the Shop.
