Type: grilling
Status: resolved

## Question

What Upgrades does the Shop actually sell? Fix the item list and its shape:

- The **general** Upgrades (available to every Class) — at minimum move speed and max health need designing, since neither exists as a modifiable stat today (`Player` has no `move_speed` field; movement uses a hardcoded `100` literal at `main.odin:290`, and `PLAYER_MAX_HEALTH :: 100` is a constant, not a per-Player field). Does a max-health purchase also heal the player to match the new cap, or only raise it (current health unchanged until topped up)?
- The **Class-specific** Upgrades, one set per Class, each gated to the equipped Class's weapon variant fields (Melee_Weapon: `range`/`arc_degrees`; Gun: `clip_size`/`reserve_ammo`/`reload_time`/`spread_angle`/etc.; Magic: `range`/`arc_degrees`/`cloud_radius`/`cloud_duration`/etc. — see `weapon.odin`). Decide which fields are worth exposing as purchasable Upgrades per Class, and whether any of today's retired `upgrade_weapon` behavior (damage, action_rate, Gun clip bonus) becomes a general Upgrade instead of a Class-specific one.
- For each item: a conceptual base price, price-growth shape (e.g. `x1.15` per stack, matching the existing `WEAPON_UPGRADE_ACTION_RATE_MULT`-style growth idiom), max stack cap, and per-purchase effect size. Exact numbers can stay rough/placeholder (content-authoring/balance is fog, not this ticket's job) — but the *list* of Upgrades and which category (general vs Class-specific) each belongs to must be concrete enough to build a Shop UI and a data table against.

Blocks [03-shop-ui-and-ux](03-shop-ui-and-ux.md), which needs concrete Upgrade names/categories to prototype against.

## Answer

Locked via grilling:

**General Upgrades** (any Class, four slots): **Move Speed** (`Player.move_speed`, new field replacing the hardcoded `100` literal at `main.odin:290`), **Max Health** (`Player.max_health`, new field replacing the `PLAYER_MAX_HEALTH` constant), **Damage** and **Action Rate** (the two `Weapon` header fields the now-retired `upgrade_weapon` used to raise for free on level-up — folded into the Shop as deliberate purchases instead of automatic ones, so nothing the old system granted simply vanishes).

**Max Health purchase heals on buy**: each stack raises the cap and immediately heals current health by the same amount (a net heal, not just a bigger empty cap) — buying it mid-fight should read as an immediate improvement, not a trap.

**Class-specific Upgrades** (one slot each, gated by equipped Class):
- **Ranged**: Clip Size (`Gun.clip_size`/`ammo_in_clip`)
- **Melee**: Arc Width (`Melee_Weapon.arc_degrees`)
- **Magic**: Range (`Magic.range`/`cast_range` — the one field meaningful across all three spell kinds: Fireball's throw range, Flamethrower's cone reach, Poison_Cloud's placement range)

Total catalog: 4 general + 1 Class-specific = 5 Upgrades visible to any given Class at once. Exact base prices, per-stack price growth, and max stack caps stay placeholder/content-authoring (map's Not yet specified) — this ticket fixes the item list and categorization only, per its own scope note.
