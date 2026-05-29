# Creek Protocol Security Audit Report

**Audit date**: 2026-05-27
**Skill version used**: 1.0.0
**Auditor**: AI-assisted audit using the `creek-audit` skill

`Creek Audit · mode=default · ts=2026-05-27 16:24 UTC+8`

---

## Executive Summary

|  | Count |
|---|---|
| **CRITICAL** | 0 |
| **HIGH** | 12 |
| **MEDIUM** | 7 |
| **LOW** | 4 |
| **INFO** | 3 |
| **LEAD** | 6 |
| **Total distinct findings** | **32** (26 graded + 6 leads) |

### Top actionable items

1. **[HIGH × 4] Pause / active-state / version coverage gaps** — `stake_xaum`, `unstake`, `liquidate`, `borrow` are out of step with the other user paths on the same shared `Market`. Tightening these brings the emergency-pause and version-migration controls back to full coverage.
2. **[HIGH × 2] Arithmetic safety** — `reserve::handle_repay` can underflow on partial repays smaller than accrued interest; `fixed_point32_empower::add/sub` perform raw u64 arithmetic without overflow guards and will abort on whale-scale USD aggregates.
3. **[HIGH × 2] Admin surface** — `extend_risk_model_change_delay` / `extend_limiter_change_delay` lack the `delay <= 1` cap that their sibling has, letting a single admin call brick timelocked parameter updates with `u64::MAX`; `owner_withdraw_xaum` accepts any `amount <= pool` with no residual-backing check.
4. **[HIGH × 4] Other protocol gaps** — stale-debt read in `borrow_limit`; `update_borrow_limit` accepts u128 while debt state is u64; `gusd_usdc_vault::redeem_gusd` burns the full GUSD coin but pays out USDC truncated to 6 decimals, silently losing dust; all admin entries in `protocol::app` are missing `&Version`.
5. **[MEDIUM]** GUSD is currently priced by a constant-$1 rule, which makes the on-chain `check_and_pause_if_gusd_depeg` inert until the keeper-driven off-chain monitor + admin migration to a real GUSD/USD feed lands.
6. **[MEDIUM]** `manual_rule` is permissionless on any registered price update request — its presence in a mainnet `XOracle.price_update_policy` would hand full pricing control to anyone. Verify deploy scripts gate it out on mainnet.

### Severity definitions

| Tag | Meaning |
|---|---|
| CRITICAL | Unprivileged trigger + material fund impact on a reachable production path |
| HIGH | Material loss / lockout / DoS on reachable production paths |
| MEDIUM | Bounded risk, transitional design, config fragility |
| LOW | Defense-in-depth, ops checklist |
| INFO / LEAD | Documentation, positive notes, manual follow-up |

Special tags: `[ADMIN-RISK]` `[OFF-CHAIN]` `[KEEPER-DEPENDENT]` `[POST-UPGRADE]` `[TRANSITIONAL]`.

---

## Audit Scope

|  |  |
|---|---|
| Framework | Sui Move 2024 |
| Files reviewed | 67 in-scope `.move` files (excludes tests) |
| Attack vectors evaluated | 153 (143 generic Sui Move + 10 Creek-specific) |
| Lenses applied | access-control · math · economic · invariant · execution · first-principles · sui-protocol |
| Confidence threshold | 75 |

**In-scope packages**:

- `contracts/protocol/` — borrowing market, StakingManager, GUSD/USDC vault, app admin
- `contracts/coins/` — GR / GY / GUSD (mint / burn / denylist)
- `contracts/sui_x_oracle/` — XOracle + Pyth / Switchboard / Supra / GR / GUSD / manual rules
- `contracts/xaum_indicator/` — `core` + `pyth_adapter` (EMA push to XOracle)
- `contracts/libs/` — `one_time_lock_value`, `ac_table`, `wit_table`, math, `fixed_point32` wrappers

**Out of scope** (trust boundary):

- `contracts_other/vendor/xaum/`, `contracts_other/vendor/usdc/` — third-party RWA / Circle packages
- `contracts_other/test/`, `contracts_other/creek_router/`, `contracts_other/query/`, `contracts_other/gr_price_query/`, `contracts_other/rewards/` — test / auxiliary
- `backend/`, `admin-panel/`, `scripts/`, `sui-creek-frontend/`, `sui-test-client/` — off-chain (referenced only when a finding crosses the chain↔off-chain boundary)
- `**/build/`, `**/tests/`, `**/*_test.move`

---

## Findings

> Sorted by severity DESC, then confidence DESC.

---

### [HIGH · 90] 1. Unbounded `extend_risk_model_change_delay` / `extend_limiter_change_delay`

**Location**: `protocol::app::extend_risk_model_change_delay`, `extend_limiter_change_delay`
**Tags**: `access-control` `[ADMIN-RISK]`

**Description**: `extend_interest_model_change_delay` correctly caps the delta with `assert!(delay <= 1, ...)`. The two sibling functions accept any `u64`, so a single admin call with `u64::MAX` permanently inflates the `risk_model_change_delay` / `limiter_change_delay` counters used when scheduling timelocked changes via `OneTimeLockValue`. No future risk-model or limiter change can be applied because the schedule never becomes due.

```108:119:contracts/protocol/sources/app/app.move
public fun extend_interest_model_change_delay(admin_cap: &mut AdminCap, delay: u64) {
    assert!(delay <= 1, error::invalid_params_error()); // can only extend 1 epoch per change
    admin_cap.interest_model_change_delay = admin_cap.interest_model_change_delay + delay;
}

public fun extend_risk_model_change_delay(admin_cap: &mut AdminCap, delay: u64) {
    admin_cap.risk_model_change_delay = admin_cap.risk_model_change_delay + delay;
}

public fun extend_limiter_change_delay(admin_cap: &mut AdminCap, delay: u64) {
    admin_cap.limiter_change_delay = admin_cap.limiter_change_delay + delay;
}
```

**Proof**: PTB `extend_risk_model_change_delay(admin_cap, 0xffff_ffff_ffff_ffff)` → every subsequent `create_risk_model_change<T>` carries an effectively-infinite delay → `OneTimeLockValue<RiskModel>` is never applicable. Same shape for `limiter_change_delay`.

**Fix** (confidence ≥ 80):

```diff
 public fun extend_risk_model_change_delay(admin_cap: &mut AdminCap, delay: u64) {
+    assert!(delay <= 1, error::invalid_params_error());
     admin_cap.risk_model_change_delay = admin_cap.risk_model_change_delay + delay;
 }

 public fun extend_limiter_change_delay(admin_cap: &mut AdminCap, delay: u64) {
+    assert!(delay <= 1, error::invalid_params_error());
     admin_cap.limiter_change_delay = admin_cap.limiter_change_delay + delay;
 }
```

Matches the interest-model sibling's behaviour.

---

### [HIGH · 88] 2. `staking_manager::stake_xaum` / `unstake` skip emergency pause

**Location**: `protocol::staking_manager::stake_xaum`, `unstake`
**Tags**: `access-control` `pause-coverage` (attack vector 81 / 149)

**Description**: Every other user path on the shared `Market` (`borrow`, `repay`, `deposit_collateral`, `withdraw_collateral`, `flash_loan::*`, `gusd_usdc_vault::*`) gates on `assert!(!market::is_paused(market), ...)`. The two staking entrypoints take only `&Version` and the `StakingManager`, so emergency pause (manual or `check_and_pause_if_gusd_depeg`) does not stop XAUM stake/unstake flows — defeating part of the circuit-breaker design.

```103:113:contracts/protocol/sources/staking/staking_manager.move
public fun stake_xaum(
    version: &Version,
    manager: &mut StakingManager,
    xaum_coin: Coin<XAUM>,
    ctx: &mut TxContext,
) {
    version::assert_current_version(version);
    let user = tx_context::sender(ctx);
    let xaum_amount = coin::value(&xaum_coin);
    assert!(xaum_amount >= MIN_STAKE_AMOUNT, error::staking_min_xaum_error());
```

```152:160:contracts/protocol/sources/staking/staking_manager.move
public fun unstake(
    version: &Version,
    manager: &mut StakingManager,
    gr_coin: Coin<COIN_GR>,
    gy_coin: Coin<COIN_GY>,
    ctx: &mut TxContext,
) {
    version::assert_current_version(version);
    let user = tx_context::sender(ctx);
```

**Proof**: Admin calls `pause_protocol(admin_cap, market)` after a GUSD depeg or oracle anomaly. Borrow / repay / vault are blocked; `stake_xaum(version, manager, xaum_coin, ctx)` succeeds because it never references the `Market`.

**Fix** (confidence ≥ 80):

```diff
-public fun stake_xaum(
-    version: &Version,
-    manager: &mut StakingManager,
-    xaum_coin: Coin<XAUM>,
-    ctx: &mut TxContext,
-) {
+public fun stake_xaum(
+    version: &Version,
+    market: &Market,
+    manager: &mut StakingManager,
+    xaum_coin: Coin<XAUM>,
+    ctx: &mut TxContext,
+) {
     version::assert_current_version(version);
+    assert!(!market::is_paused(market), error::market_paused_error());
```

Apply symmetrically to `unstake`. This is an ABI break — schedule with the next protocol upgrade so callers update PTB construction.

---

### [HIGH · 88] 3. `borrow_internal` skips `is_base_asset_active`

**Location**: `protocol::borrow::borrow_internal` vs `protocol::flash_loan::borrow_flash_loan_internal` L68
**Tags**: `access-control` `active-state` (attack vector 149)

**Description**: The admin control `set_base_asset_active_state<COIN_GUSD>(false)` is meant to halt new borrowing of a base asset. `flash_loan::borrow_flash_loan_internal` enforces it (L68), but the ordinary `borrow` path does not — admin disabling the GUSD base asset blocks flash-loan borrows only, leaving ordinary borrows fully open.

```58:68:contracts/protocol/sources/user/flash_loan.move
fun borrow_flash_loan_internal(
    market: &mut Market,
    amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (Coin<COIN_GUSD>, FlashLoan<COIN_GUSD>) {
    let now = clock::timestamp_ms(clock) / 1000;

    let coin_type = type_name::get<COIN_GUSD>();
    // check if base asset is active
    assert!(market::is_base_asset_active(market, coin_type), error::base_asset_not_active_error());
```

`borrow_internal` reads risk/interest model and checks limiter but never queries `is_base_asset_active`:

```122:160:contracts/protocol/sources/user/borrow.move
    assert!(obligation::borrow_locked(obligation) == false, error::obligation_locked());
    let coin_type = type_name::get<COIN_GUSD>();
    ...
    market::handle_outflow<COIN_GUSD>(market, borrow_amount, now);
```

**Proof**: Admin runs `set_base_asset_active_state<COIN_GUSD>(_admin_cap, market, false)`. `borrow_flash_loan` aborts with `base_asset_not_active_error()`; `borrow_entry` proceeds normally and mints GUSD.

**Fix** (confidence ≥ 80):

```diff
 fun borrow_internal(...) {
     assert!(obligation::borrow_locked(obligation) == false, error::obligation_locked());
     let coin_type = type_name::get<COIN_GUSD>();
+    assert!(
+        market::is_base_asset_active(market, coin_type),
+        error::base_asset_not_active_error(),
+    );
```

---

### [HIGH · 87] 4. `liquidate` skips pause check

**Location**: `protocol::liquidate::liquidate` L63-83
**Tags**: `pause-coverage`

**Description**: `liquidate` only asserts the protocol version. During an oracle anomaly or stablecoin depeg, the admin pauses the market (blocking borrow / repay / vault / flash-loan) but liquidations continue against the same oracle prices that triggered the pause. Liquidators can extract value from healthy-but-misvalued positions while the rest of the protocol is held back from corrective action.

```63:84:contracts/protocol/sources/user/liquidate.move
public fun liquidate<CollateralType>(
    version: &Version,
    obligation: &mut Obligation,
    market: &mut Market,
    available_repay_coin: Coin<COIN_GUSD>,
    coin_decimals_registry: &CoinDecimalsRegistry,
    x_oracle: &XOracle,
    clock: &Clock,
    ctx: &mut TxContext,
): (Coin<COIN_GUSD>, Coin<CollateralType>) {
    version::assert_current_version(version);
    let coin_type = type_name::get<COIN_GUSD>();

    assert!(obligation::liquidate_locked(obligation) == false, error::obligation_locked());
    assert!(coin::value(&available_repay_coin) > 0, error::zero_amount_error());

    let mut available_repay_balance = coin::into_balance(available_repay_coin);
    let now = clock::timestamp_ms(clock) / 1000;

    // Accrue interests for market & obligation
    market::accrue_all_interests(market, now);
```

**Proof**: `check_and_pause_if_gusd_depeg` flips `paused = true` because the GUSD oracle reads $1.10. Borrowers cannot repay (`repay.move` L45 aborts). A liquidator opens a PTB: `liquidate<XAUM>(...)` succeeds, swaps the seized XAUM externally, profits from the depeg the protocol thought it had frozen.

**Fix** (confidence ≥ 80): Add `assert!(!market::is_paused(market), error::market_paused_error());` immediately after the version check, or introduce a dedicated `liquidation_paused` flag controllable independently if liquidations should be allowed in some pause modes.

---

### [HIGH · 86] 5. `force_unlock_unhealthy` has no `&Version`

**Location**: `protocol::lock_obligation::force_unlock_unhealthy`
**Tags**: `[POST-UPGRADE]` `access-control` (attack vector 24, 87)

**Description**: Every other state-mutating user/permissionless entry on `Obligation` takes `&Version` and calls `version::assert_current_version`. `force_unlock_unhealthy` mutates `Obligation.lock_key` and the boolean lock flags via `obligation::set_unlock` without a version gate, so a future `Version` bump leaves it as a back door that bypasses post-upgrade migration logic.

```33:42:contracts/protocol/sources/user/lock_obligation.move
public fun force_unlock_unhealthy<T: drop>(
    obligation: &mut Obligation,
    market: &mut Market,
    coin_decimals_registry: &CoinDecimalsRegistry,
    x_oracle: &XOracle,
    clock: &Clock,
    key: T,
) {
    // Unlock the obligation, this also does the necessary check if the witness is correct
    obligation::set_unlock(obligation, key);
```

**Proof**: Suppose a future upgrade bumps `Version` and adds a new invariant in `obligation::set_unlock_v2`. Migration relies on the version gate so that pre-migration callers abort. `force_unlock_unhealthy` keeps working against the old code path because it has no `assert_current_version`, defeating the migration plan.

**Fix** (confidence ≥ 80):

```diff
 public fun force_unlock_unhealthy<T: drop>(
+    version: &Version,
     obligation: &mut Obligation,
     market: &mut Market,
     coin_decimals_registry: &CoinDecimalsRegistry,
     x_oracle: &XOracle,
     clock: &Clock,
     key: T,
 ) {
+    version::assert_current_version(version);
     obligation::set_unlock(obligation, key);
```

ABI break — schedule with next upgrade.

---

### [HIGH · 85] 6. `owner_withdraw_xaum` can drain pool below GR / GY backing `[ADMIN-RISK]`

**Location**: `protocol::staking_manager::owner_withdraw_xaum` L287-295; admin wrapper at `protocol::app::owner_withdraw_xaum` L464-480
**Tags**: `[ADMIN-RISK]` `invariant` (attack vector 79 / 126)

**Description**: `owner_withdraw_xaum` only checks `pool.value >= amount`. It does not verify that the residual pool covers the outstanding GR/GY redemption claims (`gr_supply / EXCHANGE_RATE`). An admin can withdraw enough XAUM to leave normal stakers unable to `unstake` (which requires `balance::value(&xaum_pool) >= xaum_return_amount`).

```287:295:contracts/protocol/sources/staking/staking_manager.move
public(package) fun owner_withdraw_xaum(
    manager: &mut StakingManager,
    amount: u64,
    ctx: &mut TxContext,
): Coin<XAUM> {
    assert!(balance::value(&manager.xaum_pool) >= amount, error::staking_pool_xaum_not_enough_error());
    let part = balance::split(&mut manager.xaum_pool, amount);
    coin::from_balance(part, ctx)
}
```

**Proof**: Initial state `xaum_pool = 1000 XAUM`, `gr_supply = 100_000 GR` (= 1000 XAUM of redemption claims). Admin calls `owner_withdraw_xaum(_, manager, 500, ctx)`. `assert` passes (1000 ≥ 500). Pool = 500. Any subsequent `unstake` exceeding 500 XAUM equivalent will abort with `staking_pool_xaum_not_enough_error`.

**Fix** (confidence ≥ 80):

```diff
 public(package) fun owner_withdraw_xaum(
     manager: &mut StakingManager,
     amount: u64,
     ctx: &mut TxContext,
 ): Coin<XAUM> {
-    assert!(balance::value(&manager.xaum_pool) >= amount, error::staking_pool_xaum_not_enough_error());
+    let supply_value = balance::supply_value(&manager.gr_supply);
+    let required_backing = supply_value / EXCHANGE_RATE;
+    let pool = balance::value(&manager.xaum_pool);
+    assert!(
+        pool >= amount + required_backing,
+        error::staking_pool_xaum_not_enough_error(),
+    );
     let part = balance::split(&mut manager.xaum_pool, amount);
     coin::from_balance(part, ctx)
 }
```

If fractional-reserve withdrawal is an intended capability, document it explicitly in the protocol spec and add an event that off-chain monitors can alert on.

---

### [HIGH · 85] 7. `borrow_limit` enforced against pre-accrual global debt

**Location**: `protocol::borrow::borrow_internal` L149-160 (cap check) vs L201 (`mint_gusd` triggers accrual)
**Tags**: `math` `economic` (attack vector 146)

**Description**: The borrow-limit check reads `market::total_global_debt(market, coin_type)` before `handle_borrow` runs. `handle_borrow` is what calls `accrue_all_interests` and mints GUSD. A user borrowing right at the boundary slips through by `interest_accrued_since_last_touch`, and a stream of small borrows compounds the slack indefinitely.

```148:160:contracts/protocol/sources/user/borrow.move
    // assert borrow limit
    let borrow_limit_key = market_dynamic_keys::borrow_limit_key(coin_type);
    let borrow_limit =
        *dynamic_field::borrow<BorrowLimitKey, u128>(market::uid(market), borrow_limit_key);
    let current_total_global_debt = market::total_global_debt(market, coin_type);

    let new_total_global_debt = (current_total_global_debt as u128) + (borrow_amount as u128);

    assert!(new_total_global_debt <= borrow_limit, error::borrow_limit_reached_error());

    // Add borrow amount to the outflow limiter, if limit is reached then abort
    market::handle_outflow<COIN_GUSD>(market, borrow_amount, now);
```

```200:202:contracts/protocol/sources/user/borrow.move
    // Call mint_gusd to get Coin<COIN_GUSD>
    let mut borrowed_coin = market::handle_borrow(market, borrow_amount, now, ctx);
```

**Proof**: `borrow_limit = 1_000_000 GUSD`, current debt 999_000, accrued-but-unaccounted interest since last touch ≈ 1_500. User borrows 1_000 — `new_total_global_debt = 999_000 + 1_000 = 1_000_000 ≤ limit`. After `handle_borrow` accrues interest, real debt = 1_000_000 + 1_500 = 1_001_500, exceeding the cap.

**Fix** (confidence ≥ 80):

```diff
+    // Accrue interest BEFORE reading any debt total used for the cap check
+    market::accrue_all_interests(market, now);
     let borrow_limit_key = market_dynamic_keys::borrow_limit_key(coin_type);
     let borrow_limit =
         *dynamic_field::borrow<BorrowLimitKey, u128>(market::uid(market), borrow_limit_key);
     let current_total_global_debt = market::total_global_debt(market, coin_type);
```

---

### [HIGH · 83] 8. `reserve::handle_repay` underflow on partial repay below accrued interest

**Location**: `protocol::reserve::handle_repay` L112; caller `protocol::repay::repay` L72 passes full `debt_interest`
**Tags**: `math` `invariant`

**Description**: Inside `handle_repay`, `debt_to_burn = debt_amount - debt_interest`. The caller always passes the obligation's full accrued `debt_interest`. A repay smaller than `debt_interest` makes `debt_amount` (clamped to `repay_amount`) smaller than `debt_interest`, triggering an arithmetic abort.

```102:112:contracts/protocol/sources/market/reserve.move
    // update balance sheet
    if (balance_sheet.debt >= repay_amount) {
        balance_sheet.debt = balance_sheet.debt - repay_amount;
    } else {
        balance_sheet.debt = 0;
    };

    // insert interest to revenue
    if (interest_to_keep > 0) {
        balance_sheet.revenue = balance_sheet.revenue + interest_to_keep;
    };
    let debt_to_burn = debt_amount - debt_interest;
```

```55:75:contracts/protocol/sources/user/repay.move
    market::accrue_all_interests(market, now);
    obligation::accrue_interests_and_rewards(obligation, market);

    let (debt_amount, _, debt_interest) = obligation::debt(obligation, coin_type);
    assert!(debt_amount > 0, error::no_debt_error());

    let repay_amount = math::min(debt_amount, coin::value(&user_coin));
    let repay_coin = coin::split<COIN_GUSD>(&mut user_coin, repay_amount, ctx);

    // Put the repay asset into market
    market::handle_repay<COIN_GUSD>(market, repay_coin, debt_interest, ctx);
```

**Proof**: Obligation has principal 1000 GUSD + accrued interest 200 GUSD → `debt_amount = 1200`, `debt_interest = 200`. User passes `Coin<GUSD>` worth 100. `repay_amount = min(1200, 100) = 100`. `handle_repay` runs: `debt_amount (local) = min(100, balance_sheet.debt) = 100`. `debt_to_burn = 100 - 200` → abort. Net effect: user can never partially repay an obligation whose accrued interest exceeds the wallet balance.

**Fix** (confidence ≥ 80) — clamp at the caller so `handle_repay` only sees the relevant slice of interest:

```diff
-    market::handle_repay<COIN_GUSD>(market, repay_coin, debt_interest, ctx);
+    let effective_interest = math::min(debt_interest, repay_amount);
+    market::handle_repay<COIN_GUSD>(market, repay_coin, effective_interest, ctx);
```

---

### [HIGH · 82] 9. Admin entries in `protocol::app` are missing `&Version`

**Location**: `pause_protocol`, `resume_protocol`, `set_auto_pause_*`, `take_revenue`, `take_borrow_fee`, `take_staking_fee`, `update_staking_fee`, `update_unstaking_fee`, `update_staking_cap`, `owner_withdraw_xaum`, `owner_deposit_xaum`, `update_borrow_fee`, `update_borrow_limit`, `set_gusd_cap`, `update_reward_address`, `transfer_admin_cap`, `set_flash_loan_single_cap`, the model/limiter `*_change` chain, `set_*_active_state`, `add_*_key` / `remove_*_key` (~25 admin entries)
**Tags**: `[POST-UPGRADE]` (attack vector 24, 87)

**Description**: Every public state-mutating user path takes `&Version`. None of the AdminCap-gated entries in `protocol::app` do. After a `Version` bump (`version::upgrade`) the admin paths bypass migration gating, so old admin behaviour survives indefinitely on the bumped objects.

```108:165:contracts/protocol/sources/app/app.move
public fun extend_interest_model_change_delay(admin_cap: &mut AdminCap, delay: u64) { ... }

public fun pause_protocol(_admin_cap: &AdminCap, market: &mut Market) {
    market::set_paused(market, true);
}

public fun resume_protocol(_admin_cap: &AdminCap, market: &mut Market) {
    market::set_paused(market, false);
}

public fun check_and_pause_if_gusd_depeg(market: &mut Market, x_oracle: &XOracle, clock: &Clock) { ... }
```

**Proof**: Hypothetical migration: a future Version 2 changes how `Market.paused` interacts with a new `Market.kill_switch` field. The migration adds version-gated setters; legacy `pause_protocol` keeps mutating `paused` directly — leaving the protocol in an inconsistent post-migration state.

**Fix** (confidence ≥ 80): Add `version: &Version` parameter + `version::assert_current_version(version);` to every admin entry. This is a broad ABI change — schedule with the next planned upgrade and roll the admin tooling in lock-step.

---

### [HIGH · 80] 10. `fixed_point32_empower::add/sub` raw u64 overflow / underflow

**Location**: `math::fixed_point32_empower::add`, `sub`
**Tags**: `math` `[POST-UPGRADE]` (attack vector 147)

**Description**: Both functions extract raw u64 fixed-point values and apply `a_raw + b_raw` / `a_raw - b_raw` directly. The raw representation is 32.32 fixed point, so the integer part hits ~4.29 × 10⁹. Aggregate-USD sums in evaluators (`collateral_value`, `debt_value`, `liquidation_evaluator`) hit this ceiling at protocol-scale TVL and abort the whole tx — DoS for whale positions, and a bricked health-factor computation.

```7:19:contracts/libs/math/sources/fixed_point32.move
  public fun add(a: FixedPoint32, b: FixedPoint32): FixedPoint32 {
    let a_raw = fixed_point32::get_raw_value(a);
    let b_raw = fixed_point32::get_raw_value(b);
    fixed_point32::create_from_raw_value(a_raw + b_raw)
  }

  // Substract 2 FixedPoint32 numers
  public fun sub(a: FixedPoint32, b: FixedPoint32): FixedPoint32 {
    let a_raw = fixed_point32::get_raw_value(a);
    let b_raw = fixed_point32::get_raw_value(b);
    fixed_point32::create_from_raw_value(a_raw - b_raw)
  }
```

**Proof**: Obligation has aggregate collateral USD value approaching `u32::MAX` (~$4.29B in 32.32 representation). Adding the next collateral entry triggers a Move arithmetic abort. The user's position becomes un-priceable: borrow / withdraw / liquidate all abort on the same `add` call.

**Fix** (confidence ≥ 80):

```diff
 public fun add(a: FixedPoint32, b: FixedPoint32): FixedPoint32 {
   let a_raw = fixed_point32::get_raw_value(a);
   let b_raw = fixed_point32::get_raw_value(b);
-  fixed_point32::create_from_raw_value(a_raw + b_raw)
+  let sum: u128 = (a_raw as u128) + (b_raw as u128);
+  assert!(sum <= (std::u64::max_value!() as u128), error::math_overflow_error());
+  fixed_point32::create_from_raw_value(sum as u64)
 }

 public fun sub(a: FixedPoint32, b: FixedPoint32): FixedPoint32 {
   let a_raw = fixed_point32::get_raw_value(a);
   let b_raw = fixed_point32::get_raw_value(b);
-  fixed_point32::create_from_raw_value(a_raw - b_raw)
+  assert!(a_raw >= b_raw, error::math_underflow_error());
+  fixed_point32::create_from_raw_value(a_raw - b_raw)
 }
```

---

### [HIGH · 80] 11. `update_borrow_limit` accepts u128 against u64 debt state

**Location**: `protocol::app::update_borrow_limit` L545-555
**Tags**: `math` `admin-surface` (attack vector 148)

**Description**: The admin setter takes `limit_amount: u128` and stores it directly as the `BorrowLimitKey` dynamic field. The corresponding `balance_sheet.debt` field used by the limit check (`reserve::BalanceSheet.debt`) and by `accrue_all_interests` is `u64`. If the admin (intentionally or by typo) sets a limit larger than `u64::MAX`, `balance_sheet.debt + debt_increased` can approach `u64::MAX` and abort accrual, freezing the protocol.

```545:555:contracts/protocol/sources/app/app.move
public fun update_borrow_limit<T: drop>(
    _admin_cap: &AdminCap,
    market: &mut Market,
    limit_amount: u128,
) {
    let market_uid_mut = market::uid_mut(market);
    let key = market_dynamic_keys::borrow_limit_key(coin_type);

    dynamic_field::remove_if_exists<BorrowLimitKey, u128>(market_uid_mut, key);
    dynamic_field::add(market_uid_mut, key, limit_amount);
}
```

**Proof**: Admin sets `borrow_limit = (u64::MAX as u128) + 1`. Borrows succeed up to the moment cumulative debt approaches `u64::MAX`. The next `accrue_all_interests` call attempts `balance_sheet.debt = balance_sheet.debt + debt_increased` and aborts → no further borrow / repay / liquidate possible.

**Fix** (confidence ≥ 80):

```diff
 public fun update_borrow_limit<T: drop>(
     _admin_cap: &AdminCap,
     market: &mut Market,
     limit_amount: u128,
 ) {
+    assert!(limit_amount <= (std::u64::max_value!() as u128), error::invalid_params_error());
     let market_uid_mut = market::uid_mut(market);
     let key = market_dynamic_keys::borrow_limit_key(coin_type);

     dynamic_field::remove_if_exists<BorrowLimitKey, u128>(market_uid_mut, key);
     dynamic_field::add(market_uid_mut, key, limit_amount);
 }
```

(Or widen `balance_sheet.debt` to `u128` if the team intentionally wants TVLs above `u64::MAX`.)

---

### [HIGH · 80] 12. `gusd_usdc_vault::redeem_gusd` silently truncates GUSD dust

**Location**: `protocol::gusd_usdc_vault::redeem_gusd` L121-174
**Tags**: `math` `precision`

**Description**: GUSD has 9 decimals, USDC has 6 — the vault converts with `amount_usdc_before_fee = amount_gusd / 1000`. The user's *full* GUSD coin is burned via `market::burn_gusd(market, gusd, ctx)` regardless of whether `amount_gusd` is a clean multiple of 1000, so any sub-1000-raw remainder is lost.

```131:154:contracts/protocol/sources/user/gusd_usdc_vault.move
    let amount_gusd = coin::value(&gusd); // 9 decimals
    assert!(amount_gusd > 0, E_INVALID_AMOUNT);

    // convert precision: GUSD(9) → USDC(6)
    let amount_usdc_before_fee = amount_gusd / 1000;

    assert!(amount_usdc_before_fee > 0, E_INVALID_AMOUNT);

    // check vault balance
    let available = balance::value(&vault.usdc_balance);
    assert!(available >= amount_usdc_before_fee, E_INSUFFICIENT_BALANCE);
    ...
    // burn original GUSD
    market::burn_gusd(market, gusd, ctx);
```

**Proof**: User passes a `Coin<COIN_GUSD>` with value `1_999_999_999`. `amount_usdc_before_fee = 1_999_999_999 / 1000 = 1_999_999`. Vault transfers ≈ 1_999_999 USDC raw (less fee). `market::burn_gusd` burns the entire 1_999_999_999 GUSD raw → user loses 999 GUSD raw per call.

**Fix** (confidence ≥ 80) — choose one:

```diff
+    // option A: require clean multiples
+    assert!(amount_gusd % 1000 == 0, E_INVALID_AMOUNT);
```

or

```diff
+    // option B: refund dust
+    let burnable_gusd = amount_usdc_before_fee * 1000;
+    let dust = coin::split(&mut gusd, amount_gusd - burnable_gusd, ctx);
+    transfer::public_transfer(dust, sender(ctx));
     market::burn_gusd(market, gusd, ctx);
```

Option B is generally friendlier to wallets sending automatically-split coins.

---

### [MEDIUM · 78] 13. Dual-admin model can desynchronize

**Location**: `protocol::app::AdminCap` vs `protocol::staking_manager::StakingManager.admin` (and `protocol::gusd_usdc_vault::USDCVault.admin`)
**Tags**: `access-control` (attack vector 150)

**Description**: `StakingManager` records a fixed `admin: address` at `init_staking_manager` (`tx_context::sender(ctx)`). `update_stake_fee` / `update_unstake_fee` / `update_stake_cap` gate on `sender == manager.admin`. There is no setter for `manager.admin` — if the protocol's `AdminCap` is rotated (`transfer_admin_cap`), the new admin loses the ability to update staking fees / cap until a contract upgrade. `gusd_usdc_vault::USDCVault.admin` does have a two-step `propose_new_admin` / `accept_admin`, so the same divergence does not affect it, but the staking gap is real.

```70:100:contracts/protocol/sources/staking/staking_manager.move
public fun init_staking_manager(
    gr_treasury_cap: TreasuryCap<COIN_GR>,
    gy_treasury_cap: TreasuryCap<COIN_GY>,
    ctx: &mut TxContext,
) {
    let admin = tx_context::sender(ctx);
    ...
    let manager = StakingManager {
        id: object::new(ctx),
        admin,
        ...
    };
```

**Proof**: Multisig calls `transfer_admin_cap(admin_cap, new_admin_address)`. New admin attempts `app::update_staking_fee(_, manager, 5, 10000, ctx)` → `app::update_staking_fee` forwards to `staking_manager::update_stake_fee` which asserts `sender == manager.admin` (the old address) → abort. Stake / unstake fees are frozen until an on-chain upgrade adds a setter for `manager.admin`.

**Fix** (confidence ≥ 75): Add an admin-cap-gated setter to rotate `manager.admin`, e.g.

```diff
+public(package) fun set_admin(
+    manager: &mut StakingManager,
+    new_admin: address,
+    ctx: &mut TxContext,
+) {
+    assert!(tx_context::sender(ctx) == manager.admin, error::staking_not_admin_error());
+    manager.admin = new_admin;
+}
```

Expose through `protocol::app::set_staking_admin(admin_cap, manager, new_admin, ctx)`. Alternatively switch entirely to AdminCap-gated entries on `StakingManager` and retire the address field.

---

### [MEDIUM · 78] 14. `manual_rule` is unauthenticated — full pricing control if registered

**Location**: `manual_rule::rule::set_price_as_primary`, `set_price_as_secondary`
**Tags**: `oracle` `config-fragility`

**Description**: The manual price rule writes arbitrary 9-decimal prices into an `XOraclePriceUpdateRequest<CoinType>` with no capability check. By design, the rule only takes effect for coins where it has been registered in `XOracle.price_update_policy`. If the mainnet deploy ever registers it (e.g. through a copy-paste from a testnet deploy script), anyone holding the relevant `XOraclePriceUpdateRequest` (handed out by `x_oracle::price_update_request`) can mint a fake price.

```12:31:contracts/sui_x_oracle/manual_rule/sources/rule.move
  public fun set_price_as_primary<CoinType>(
    request: &mut XOraclePriceUpdateRequest<CoinType>,
    value_9dec: u64,
    clock: &Clock,
  ) {
    let now = clock::timestamp_ms(clock) / 1000;
    let feed = price_feed::new(value_9dec, now);
    x_oracle::set_primary_price(Rule {}, request, feed);
  }
```

**Proof**: Assume `manual_rule::rule::Rule` is added as a primary rule for `COIN_GR` on mainnet. Attacker constructs a PTB: `x_oracle::price_update_request<COIN_GR>(...)` → `manual_rule::rule::set_price_as_primary(request, 1, clock)` → `x_oracle::confirm_price_update_request(request)`. GR price is now $1 × 10⁻⁹ → borrows against GR become free.

**Fix** (confidence ≥ 75):

1. Gate the rule with a capability:

```diff
 public fun set_price_as_primary<CoinType>(
+    _cap: &ManualRuleAdminCap,
     request: &mut XOraclePriceUpdateRequest<CoinType>,
     value_9dec: u64,
     clock: &Clock,
 ) { ... }
```

2. Add a deploy-time guard in `scripts/src/deploy-all.mjs`:

```js
if (NETWORK === 'mainnet') {
  assert(!config.useManualRule, 'manual_rule must not be registered on mainnet');
}
```

Severity is MEDIUM rather than HIGH because there is no current evidence the rule is registered on mainnet, but the lack of an on-chain auth gate makes a single misconfiguration catastrophic.

---

### [MEDIUM · 78] 15. `protocol::price::get_price` requires exact-second timestamp equality

**Location**: `protocol::price::get_price` L25
**Tags**: `oracle` `liveness`

**Description**: The consumer-side price read asserts `now == last_updated`. Whenever an oracle update is not pulled into the same second as the consuming tx, every protocol path that calls `get_price` aborts with `oracle_stale_price_error()`. The semantics force every PTB to include an oracle update, but the strict equality is brittle: even a 1-second clock skew between `clock::timestamp_ms(clock) / 1000` in the price-update and consumer tx (or back-to-back updates within the same second from a keeper that ran slightly behind wall-clock) trips the assertion.

```23:28:contracts/protocol/sources/evaluator/price.move
    // Check if price is stale
    let now = clock::timestamp_ms(clock) / 1000;
    assert!(now == last_updated, error::oracle_stale_price_error());
    assert!(price_value > 0, error::oracle_zero_price_error());
```

**Proof**: PTB updates price at second `T`, but Sui finalisation runs at second `T+1`. The consumer reads `last_updated = T`, `now = T+1` → abort.

**Fix** (confidence ≥ 75): Use a bounded staleness window so the consumer tolerates the natural drift while still rejecting truly stale prices:

```diff
-    assert!(now == last_updated, error::oracle_stale_price_error());
+    assert!(now >= last_updated, error::oracle_stale_price_error());
+    assert!(now - last_updated <= MAX_STALENESS_SECS, error::oracle_stale_price_error());
```

Pick `MAX_STALENESS_SECS` (e.g. 60) consistent with the Pyth adapter's `60`-second `get_price_no_older_than` window.

---

### [MEDIUM · 77] 16. `set_gr_indicators` lacks delta-bound guards `[KEEPER-DEPENDENT]`

**Location**: `x_oracle::x_oracle::set_gr_indicators` L211-254
**Tags**: `oracle` `[KEEPER-DEPENDENT]` (attack vector 132)

**Description**: The push entrypoint only enforces `updated_time_sec >= self.gr_indicator_last_updated` (monotonic time) and `>0` sanity on EMA / spot. It does not validate per-update deltas against the previously-stored value. A keeper compromise (or a keeper bug) can push arbitrary positive values that swing GR pricing in a single update, instantly re-pricing every collateral position that uses the GR aggregator.

```210:225:contracts/sui_x_oracle/x_oracle/sources/x_oracle.move
  public fun set_gr_indicators(
    self: &mut XOracle,
    admin_cap: &XOracleAdminCap,
    ema120_value_u64: u64,
    ema90_value_u64: u64,
    spot_value_u64: u64,
    updated_time_sec: u64,
    _ctx: &mut TxContext,
  ) {
    verify_admin(self, admin_cap);
    assert!(updated_time_sec >= self.gr_indicator_last_updated, 0);
```

**Proof**: Compromised keeper or off-chain bug pushes `ema120 = previous_value × 100`. Borrowers with GR-denominated collateral instantly look heavily over-collateralized → free borrowing.

**Fix** (confidence ≥ 75): Add a per-update delta cap (e.g. ≤ 25 %) against the prior value:

```diff
+    if (self.xaum_ema120_value_u64 > 0) {
+        let prior = self.xaum_ema120_value_u64;
+        let max_delta = prior / 4; // 25 %
+        assert!(
+            ema120_value_u64 <= prior + max_delta && ema120_value_u64 + max_delta >= prior,
+            E_INDICATOR_DELTA_TOO_LARGE,
+        );
+    };
```

Same shape for `ema90_value_u64`, `spot_value_u64`. Pair with an off-chain alert when the assertion is exercised by a legitimate large move.

---

### [MEDIUM · 76] 17. `flash_loan_single_cap` default `50_000` (~$0.00005)

**Location**: `protocol::market::new` L132
**Tags**: `config-fragility`

**Description**: `Market::new` initialises `flash_loan_single_cap: 50_000`. GUSD has 9 decimals, so 50_000 raw = 0.00005 GUSD. Flash loans of any meaningful size abort with `flashloan_exceed_single_cap_error()` until an admin runs `set_flash_loan_single_cap`. The number reads more like a placeholder than a deliberate dust cap and is easy to overlook in deploy checklists.

```126:135:contracts/protocol/sources/market/market.move
    let market = Market {
        ...
        paused: false,
        auto_pause_enabled: true,
        auto_pause_threshold: fixed_point32::create_from_rational(8, 100), // 8%
        flash_loan_single_cap: 50_000,
    };
```

**Proof**: Fresh deployment exposes `borrow_flash_loan(version, market, 1_000_000_000, clock, ctx)` (= 1 GUSD). `market::borrow_flash_loan` aborts at `assert!(amount <= self.flash_loan_single_cap, ...)`.

**Fix** (confidence ≥ 75): Either pick a meaningful default and document it, or rename the constant to `FLASH_LOAN_DISABLED = 0` and treat `0` as "disabled". Whichever path you take, add a deploy-time assertion in `scripts/src/deploy-all.mjs` that the value is consistent with the production policy.

---

### [MEDIUM · 75] 18. PSM-fungibility lets borrowed GUSD drain the USDC vault

**Location**: `protocol::gusd_usdc_vault::redeem_gusd` (and indirectly `protocol::borrow`)
**Tags**: `economic` (attack vector 153)

**Description**: GUSD is mintable two ways — from a collateralised borrow (`protocol::borrow`) and from a USDC deposit into the vault (`mint_gusd`). The redemption path treats every GUSD as fungible, so a borrower can mint GUSD against XAUM collateral, then immediately redeem it for USDC out of the vault. The vault's USDC backing is consumed by debt-minted GUSD that has nothing to do with vault depositors.

**Proof**: User stakes XAUM for GR/GY, opens an obligation, deposits GR as collateral, borrows X GUSD, then calls `redeem_gusd(version, vault, market, gusd, ctx)`. Vault USDC balance drops by `X / 1000`. A genuine USDC depositor who showed up afterwards may find the vault unable to honour their redemption.

**Fix** (confidence ≥ 75): The simplest mitigation is to enforce that the vault only honours redemptions against its own deposit accounting. One option is to track an `usdc_deposit_total: u64` that is incremented in `mint_gusd` and decremented in `redeem_gusd`, and assert `usdc_balance >= usdc_deposit_total` is maintained as a soft invariant (allow soft drains down to a configurable redemption cap). Alternatively, add a per-tx redemption cap and an off-chain monitor on `usdc_balance / total_gusd_supply` ratio.

---

### [MEDIUM · 75] 19. GUSD oracle is a constant `$1` rule — depeg auto-pause is inert `[TRANSITIONAL]`

**Location**: `gusd_rule::rule::set_price_as_primary` + `protocol::app::check_and_pause_if_gusd_depeg`
**Tags**: `oracle` `[TRANSITIONAL]` (attack vector 152)

**Description**: `gusd_rule` hard-codes `ONE_USD_9DEC = 1_000_000_000` (USD9 = $1). `check_and_pause_if_gusd_depeg` reads from the same `XOracle` store, so the depeg detector always sees $1 and never fires `set_paused(market, true)`. The on-chain circuit breaker is therefore dormant.

```8:21:contracts/sui_x_oracle/gusd_rule/sources/rule.move
  const ONE_USD_9DEC: u64 = 1_000_000_000;

  /// Fixed $1 USD price rule for GUSD only
  public struct Rule has drop {}

  /// Set primary price source to fixed 1 USD (9 decimals)
  public fun set_price_as_primary(
    request: &mut XOraclePriceUpdateRequest<COIN_GUSD>,
    clock: &Clock,
  ) {
    let now = clock::timestamp_ms(clock) / 1000;
    let feed = price_feed::new(ONE_USD_9DEC, now);
    x_oracle::set_primary_price(Rule {}, request, feed);
  }
```

```132:150:contracts/protocol/sources/app/app.move
public fun check_and_pause_if_gusd_depeg(market: &mut Market, x_oracle: &XOracle, clock: &Clock) {
    if (market::is_paused(market)) { return };
    if (!market::auto_pause_enabled(market)) { return };

    let price = price_eval::get_price(x_oracle, type_name::get<COIN_GUSD>(), clock);
    let one = fixed_point32_empower::from_u64(1);
    let diff = if (fixed_point32_empower::gt(price, one)) {
        fixed_point32_empower::sub(price, one)
    } else {
        fixed_point32_empower::sub(one, price)
    };
    let tolerance = market::auto_pause_threshold(market);

    if (fixed_point32_empower::gte(diff, tolerance)) {
        market::set_paused(market, true);
    };
}
```

**Calibration** (per attack vector 152 / Severity Calibration #1): GUSD lacks a tradable market depth that would feed a meaningful external oracle, so the placeholder rule is a launch-phase configuration with a documented migration path:

1. Admin uses `x_oracle::remove_/add_*_price_update_rule_v2<COIN_GUSD, _>` to swap to an external rule (Pyth GUSD/USD when available, or a PSM exchange-rate rule).
2. Backend monitors GUSD market price on CEX / DEX TWAP and triggers manual `pause_protocol` via multisig if it detects depeg before the on-chain feed is migrated.
3. `XOracleOwnerCap` can re-mint `XOracleAdminCap` so a lost admin cap does not block the migration.

Severity stays MEDIUM until the migration ships. Re-rate to LOW once the swap is on mainnet and the placeholder rule is removed.

**Fix** (confidence ≥ 75): Track and execute the migration above; until then, document in operator-facing docs that `check_and_pause_if_gusd_depeg` should not be relied upon and that the off-chain monitor + manual pause is the live control.

---

### [LOW · 74] 20. `wit_table::borrow` permissive reads

**Location**: `x::wit_table::borrow`

**Description**: `wit_table::borrow` returns a `& V` without any witness check. On-chain data is public anyway, so this is informational, but it means any module that gets a `&WitTable<...>` reference can read the contents even if it has no witness. Pair with attack vector 141 — keep an eye on which modules end up with read access to sensitive tables, particularly `BalanceSheets`.

---

### [LOW · 72] 21. `transfer_admin_cap` is one-shot

**Location**: `protocol::app::transfer_admin_cap` L579-581
**Tags**: `access-control` (attack vector 22)

**Description**: One-shot cap transfer means a typo in the destination address bricks the protocol admin. The recovery path is a contract upgrade. Compare with `gusd_usdc_vault::propose_new_admin` / `accept_admin`, which uses a two-step transfer.

**Fix**: Add a `pending_admin: Option<address>` two-step transfer alongside the existing function so multisig keys can recover from misroutes.

---

### [LOW · 70] 22. `stake_xaum` `net_amount * EXCHANGE_RATE` near `u64::MAX`

**Location**: `protocol::staking_manager::stake_xaum` L131-132

**Description**: `gr_amount = net_amount * EXCHANGE_RATE` where `EXCHANGE_RATE = 100`. `net_amount > u64::MAX / 100 ≈ 1.84 × 10¹⁷` aborts. With XAUM at 9 decimals this is ≈ 1.84 × 10⁸ XAUM, comfortably above any single transaction users will perform, but worth bounding explicitly if you ever route institutional stakes through one PTB.

**Fix**: `assert!(net_amount <= u64::max_value!() / EXCHANGE_RATE, ...)`.

---

### [LOW · 70] 23. Pyth-adapter silent early returns on bad price feeds

**Location**: `xaum_indicator_pyth_adapter::xaum_indicator_pyth_adapter::update_xaum_price` L55-58

**Description**: When Pyth returns a negative price or an unsupported positive exponent (>18), the adapter silently `return`s without updating the oracle. The keeper sees a successful tx but no state change — the next push uses the same (potentially stale) EMA. Pair with attack vector 132.

**Fix**: Replace the `return`s with explicit aborts (`assert!(!i64::get_is_negative(&p), ERR_PYTH_NEGATIVE_PRICE)`, etc.) so the keeper / monitor noticeably fails instead of silently no-op'ing.

---

### [INFO] 24. Interest-model parameters validated by caller only

**Location**: `protocol::app::create_interest_model_change`

**Description**: The `app::create_*_change` family forwards `base_rate_per_sec`, `interest_rate_scale`, `scale`, `min_borrow_amount` to `interest_model::create_interest_model_change` without bounds checks. The underlying constructor does its own asserts, but document the expected ranges in the admin runbook so operators don't have to read Move to set safe values.

---

### [INFO] 25. `AdminCap.reward_address = @0x0` at init

**Location**: `protocol::app::init_internal` L100

**Description**: Initial `reward_address` is `@0x0`. `take_revenue` / `take_borrow_fee` / `take_staking_fee` all assert `reward_address != @0x0`, so a fresh deployment will abort revenue extraction until `update_reward_address` is called. Add this step to the deploy SOP.

---

### [INFO] 26. `supra_rule` exposes `set_price_as_secondary` only

**Location**: `supra_rule::rule`

**Description**: The Supra adapter is only registered as a secondary rule. If you ever promote it to primary you'll need a new entrypoint with the appropriate confidence / staleness gates — keep that requirement on the oracle-onboarding checklist.

---

## Leads

_Concrete code smells where the full exploit chain could not be completed in one analysis pass. Not scored; surfaced for manual review._

- **`liquidation_evaluator::max_liquidation_amounts` denominator near zero** — `(1 - liq_penalty) - liq_factor` can collapse to ≤ 0 if risk-model parameters slip outside the intended `liq_penalty + liq_factor < 1` range. The risk-model setter validates each factor individually but not the combined invariant. Trace whether any configured product can reach this state.
- **`liquidate` repay-share scaling under under-collateralized obligations** — when collateral runs out before `liq_amount + protocol_amount` is satisfied, verify Creek's behaviour matches the Scallop post-mortem fix that scales `actual_repay` by `collateral / total_needed` (recent-exploits §4a). The current implementation in `reserve::handle_liquidation` distributes between principal and revenue but does not visibly cap by the supplied collateral.
- **`x_oracle::set_gr_indicators` u128 overflow on extreme inputs** — `alpha * ema120 * scale + alpha_complement * inner_num` is bounded by realistic inputs, but a keeper bug supplying `u64::MAX` for all three values approaches u128 overflow. Worth a Move-Prover spec.
- **`init_staking_manager` is `public fun`** — anyone with both `TreasuryCap<COIN_GR>` and `TreasuryCap<COIN_GY>` can construct a `StakingManager`. Safe in practice because both caps are consumed in deploy, but a fresh redeployment that reorders steps could create a parallel manager. Add a deploy-time assertion that exactly one `StakingManager` exists post-deploy.
- **`obligation_access::add_lock_key<T>` witness coverage on mainnet** — enumerate every type added under `protocol::app::add_lock_key` / `add_reward_key` on mainnet and check that no in-scope module exposes a constructor for those witnesses outside its own module.
- **Move Prover spec for `BalanceSheet.revenue` vs `reserve::revenue_balances`** — write a `spec` that asserts the sum invariant for every coin type, and run Sui Prover on the resulting verification target.

---

## Verified Safe

Positive findings worth recording for traceability:

### XAUM indicator (`xaum_indicator_core` + `pyth_adapter`)

- Every public write entry on `PriceStorage` requires an `&AdminCap` via `assert_admin(storage, admin_cap)` which combines a fresh `assert_current_version(storage)` call and an `object::id(admin_cap) == storage.admin_cap_id` check. Functions covered: `update_price_storage_admin`, `set_price_9dec`, `init_ema_values`, `bind_pyth_feed_id`, `bind_admin_cap`, `push_gr_indicators_to_x_oracle`, `set_admin_cap`. ✅
- `push_gr_indicators_to_x_oracle` asserts `spot_u64 > 0` (`E_INVALID_SPOT`), defending against the EMA-derived spot reaching `XOracle` as `0`. ✅
- `PriceStorage.version: u64` + `CURRENT_VERSION = 1` + `assert_current_version` invoked from `assert_admin` and `set_admin_cap` give a forward-compatibility lane for future in-place upgrades. ✅
- `set_admin_cap(_owner_cap, storage, new_admin)` lets the `OwnerCap` holder rotate the keeper `AdminCap` without re-publishing the package — recovery path for hot-wallet compromise. ✅
- Pyth adapter's `update_xaum_price` validates the bound feed (`is_pyth_feed_bound` + `is_matching_pyth_feed_id`), pulls a price no older than 60 seconds, normalises to 18 decimals and pushes through the admin-gated core write path. ✅

### Protocol / oracle

- Pyth adapter (`pyth_adaptor`) enforces 30 s staleness + confidence interval checks. ✅
- `math::u128::mul_div` / `math::u256::mul_div` widen safely; `math::u64::mul_div` uses the standard helper. ✅
- Flash-loan `FlashLoan<COIN_GUSD>` is a hot potato (no `drop` / `store`), forcing repayment in the same PTB. ✅
- `OneTimeLockValue` enforces the per-cap timelock for interest / risk / limiter changes. ✅
- `risk_model::create_risk_model_change` validates each parameter individually (still see lead on the combined invariant). ✅
- `coin_gr` / `coin_gy` `TreasuryCap`s are consumed into the `Supply<T>` slots inside `StakingManager` at init; only `stake_xaum` mints and only `unstake` burns those supplies. ✅

---

## Out-of-Scope Observations

- **`XAUM_INDICATOR_UPDATE_PRIVATE_KEY`** `[OFF-CHAIN]` — keeper compromise translates directly into oracle manipulation. The on-chain `OwnerCap → set_admin_cap` rotation gives the multisig a recovery path; document it in the ops runbook.
- **`admin-panel` multisig threshold / composition** — verify in ops docs; out of Move scope.
- **`scripts/src/deploy-all.mjs`** should explicitly assert `USE_MANUAL_RULE !== true` on mainnet (covers Finding #14 at deploy time).
- **GUSD off-chain price monitor** — required while the on-chain `gusd_rule` is the constant-$1 placeholder; see Finding #19.
- **`xaum_indicator_core::init_ema_values` is one-shot** (`assert!(!ema_initialized)`). Deploy SOP must invoke `init_ema_values` atomically with publish; the compromise contingency is a redeploy with fresh package IDs.

---

## Findings Index

| # | Severity | Confidence | Title | Location |
|---|---|---|---|---|
| 1 | HIGH | 90 | Unbounded `extend_risk_model_change_delay` / `extend_limiter_change_delay` | `protocol::app` |
| 2 | HIGH | 88 | `stake_xaum` / `unstake` skip emergency pause | `protocol::staking_manager` |
| 3 | HIGH | 88 | `borrow_internal` skips `is_base_asset_active` | `protocol::borrow` |
| 4 | HIGH | 87 | `liquidate` skips pause check | `protocol::liquidate` |
| 5 | HIGH | 86 | `force_unlock_unhealthy` has no `&Version` | `protocol::lock_obligation` |
| 6 | HIGH | 85 | `owner_withdraw_xaum` can drain below GR/GY backing | `protocol::staking_manager` / `protocol::app` |
| 7 | HIGH | 85 | `borrow_limit` enforced against pre-accrual debt | `protocol::borrow` |
| 8 | HIGH | 83 | `reserve::handle_repay` underflow on partial repay | `protocol::reserve` / `protocol::repay` |
| 9 | HIGH | 82 | Admin entries in `protocol::app` missing `&Version` | `protocol::app` |
| 10 | HIGH | 80 | `fixed_point32_empower::add/sub` raw u64 overflow | `math::fixed_point32_empower` |
| 11 | HIGH | 80 | `update_borrow_limit` u128 vs u64 debt | `protocol::app` |
| 12 | HIGH | 80 | `gusd_usdc_vault::redeem_gusd` precision loss | `protocol::gusd_usdc_vault` |
| 13 | MEDIUM | 78 | Dual-admin desync risk | `protocol::staking_manager` |
| 14 | MEDIUM | 78 | `manual_rule` permissionless | `manual_rule::rule` |
| 15 | MEDIUM | 78 | `price::get_price` exact-second equality | `protocol::price` |
| 16 | MEDIUM | 77 | `set_gr_indicators` lacks delta bounds | `x_oracle::x_oracle` |
| 17 | MEDIUM | 76 | `flash_loan_single_cap` default 50_000 | `protocol::market` |
| 18 | MEDIUM | 75 | PSM-fungibility lets borrowed GUSD drain vault | `protocol::gusd_usdc_vault` |
| 19 | MEDIUM | 75 | GUSD constant-$1 placeholder; depeg auto-pause inert | `gusd_rule::rule` |
| 20 | LOW | 74 | `wit_table::borrow` permissive reads | `x::wit_table` |
| 21 | LOW | 72 | `transfer_admin_cap` one-shot | `protocol::app` |
| 22 | LOW | 70 | `stake_xaum` `* EXCHANGE_RATE` near u64::MAX | `protocol::staking_manager` |
| 23 | LOW | 70 | Pyth-adapter silent early returns | `xaum_indicator_pyth_adapter` |
| 24 | INFO | — | Interest-model parameters validated by caller only | `protocol::app` |
| 25 | INFO | — | `AdminCap.reward_address = @0x0` at init | `protocol::app` |
| 26 | INFO | — | `supra_rule` secondary-only API | `supra_rule::rule` |

---

## Recommended Action Plan

### Tier 1 — Protocol HIGH (block release of next upgrade)

1. #1, #11 — Tighten admin setters (`extend_*_change_delay` caps, `update_borrow_limit` u128 clamp).
2. #2, #3, #4 — Pause / active-state coverage across staking / borrow / liquidate.
3. #6 — Solvency check in `owner_withdraw_xaum`.
4. #7, #8 — Accrual ordering before cap check; clamp `debt_interest` at the repay caller.
5. #9, #5 — Add `&Version` to `protocol::app` admin entries and `force_unlock_unhealthy`; schedule the ABI break with the next upgrade.
6. #10 — Widen / guard `fixed_point32_empower::add/sub`.
7. #12 — Refund dust or assert clean multiples in `redeem_gusd`.

### Tier 2 — Oracle / config MEDIUM (next sprint)

8. #14 — Cap-gate `manual_rule::rule::set_price_as_*` (or remove from mainnet deploy + add deploy-script assert).
9. #15 — Switch `price::get_price` to a windowed staleness check matching the Pyth adapter.
10. #16 — Add per-update delta bounds in `set_gr_indicators` + off-chain alarm on triggers.
11. #17 — Pick a meaningful `flash_loan_single_cap` default (or rename / treat `0` as disabled) and assert via deploy script.
12. #18 — Add vault-deposit-tracked redemption invariant or per-tx redemption cap.
13. #19 — Track migration from `gusd_rule` to an external GUSD price source; until then maintain off-chain monitor + manual pause SOP.

### Tier 3 — Hardening

14. #20–#23 — Documentation / two-step transfers / explicit aborts for the small-impact items.
15. Move-Prover specs for the leads (revenue conservation, liquidation scaling, indicator overflow).
16. Continuous monitoring + bug bounty once mainnet TVL stabilises.

---

## Methodology Notes

- Audit performed by AI assistant using `.cursor/skills/creek-audit` v1.0.0.
- 153 attack vectors evaluated across access-control, math/precision, economic, invariant, execution-trace, first-principles, and Sui-protocol lenses.
- 4-gate finding judgement applied to every candidate (Refutation → Reachability → Trigger → Impact); confidence ≥ 80 gets a Fix block, 60–79 gets description + proof only, <60 demoted to LEAD.
- Severity calibrated up-front per `checklists.md` → "Severity Calibration Discipline" (placeholder/transitional configurations, deploy-time guards, cap-rotation recovery paths, off-chain mitigation coverage). No finding is presented in a "CRITICAL but actually …" shape; each lands at its calibrated severity from the start.

---

## Disclaimer

> This review was performed by an AI assistant. AI analysis can never verify the
> complete absence of vulnerabilities and no guarantee of security is given.
> Independent professional audit, formal verification (Sui Prover where
> applicable), bug bounty programs, and continuous on-chain monitoring are
> strongly recommended before mainnet changes.
