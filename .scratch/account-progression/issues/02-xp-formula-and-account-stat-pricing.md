Type: grilling
Status: resolved

## Question

Two related formulas need fixing:

- **End-of-Run XP formula**: how do kill count, survival time, and Gold earned this Run ([D5](../map.md)) combine into a single XP total? Independent weighted sum, or something with diminishing returns per component? Per [D4](../map.md), kills should be summed via a per-Enemy-kind XP-value lookup (even though only one `Enemy` kind exists in the code today — see `enemy.odin`) rather than a flat `kills * constant`, so the formula and the data shape (an `Enemy_Kind -> int` table, or similar) both need fixing even with one entry in it today.
- **`Account_Stat` purchase pricing**: base price, price-growth curve, and (if any) a max-stack cap for spending XP on each of Vigor/Might/Swiftness/Fortune ([D3](../map.md)) — mirroring the existing geometric `base_price`/`price_growth`/`max_stack` shape in `Upgrade_Preset` ([upgrade.odin:26-32](../../upgrade.odin)). Does each `Account_Stat` cap the same way Run-scoped Upgrades do (`max_stack = 10` today), or is Account progression meant to be effectively uncapped/slower-growing since it accumulates across many Runs rather than one?

Exact numeric values can stay placeholder/content-authoring (map's Not yet specified territory) — this ticket needs to fix the *shape* of both formulas concretely enough to build a data table against, matching how [Upgrade catalog contents](../../shop-and-upgrades/issues/01-upgrade-catalog-contents.md) scoped itself for the Run-scoped Upgrade catalog.

Not blocked.

## Answer

Locked via grilling:

**End-of-Run XP formula**: a weighted linear sum of three terms — `xp = kills_xp + survival_xp + gold_xp` — no diminishing returns or caps per component; every term contributes proportionally to the whole Run. `gold_xp` carries a **discounted weight** relative to `kills_xp`/`survival_xp` (exact ratio is content-authoring), since Gold already partly derives from kills via the existing `Pickup_Kind.Gold` drop chance and shouldn't fully double-count the same underlying behavior.

**Kills → XP lookup**: `Enemy_Kind -> Enemy_XP_Preset { base_xp: int, xp_multiplier: f32 }`, `kills_xp = sum over kills of (base_xp * xp_multiplier)` for that kill's kind. Today's single `Enemy` kind gets one placeholder entry (e.g. `{ base_xp: 5, xp_multiplier: 1.0 }`); the struct is intentionally richer than a flat int specifically so a future enemy-variety effort (out of scope here) has a multiplier to tune without a data-shape migration. A raw float multiplier was chosen over an explicit difficulty-tier enum (Normal/Elite/Boss) — no taxonomy is being invented before content needs one.

**`Account_Stat` pricing**: same geometric mechanism as `Upgrade_Preset` (`price = base_price * price_growth ^ stack_count`), but with a gentler `price_growth` than Run-scoped Upgrades and **no `max_stack` cap** — an Account_Stat purchase is always available, just costing meaningfully more XP the more of it a player already owns. This is a deliberate divergence from Run-scoped Upgrades' hard cap of 10, reflecting that Account_Stat accumulates across many Runs rather than one.

**`Account_Stat` effect type**: all four (`Vigor`, `Might`, `Swiftness`, `Fortune`) are `Multiplicative` — including Vigor, which diverges from Max Health's existing `Additive` treatment in the Run-scoped `Upgrade_Kind` set, for internal consistency across the new taxonomy rather than matching its closest Run-scoped analog.
