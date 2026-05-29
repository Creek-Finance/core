# Creek Protocol — Domain Checklists

For each module, walk through the relevant checklist. Items marked ⚠ are
known Creek-specific concerns to verify before issuing a finding.

---

## Lending / Borrowing (`contracts/protocol/sources/user/`, `evaluator/`, `market/`)

1. Health factor includes accrued (not just principal) interest
2. `accrue_interest` is the first call in `borrow / repay / withdraw_collateral / liquidate` paths
3. Liquidation bonus covers tx cost for minimum-size positions
4. Self-liquidation not profitable (bonus < penalty)
5. Collateral withdrawal blocked when underwater AND re-checked AFTER mutation
6. Interest accrual stops correctly when paused (or documented to continue)
7. Multi-decimal tokens handled via `coin_decimals_registry` everywhere
8. Oracle price validated: staleness + confidence interval at point of use
9. Bad debt socialization or write-off mechanism
10. Interest rate model can't overflow at extreme utilization (test U=100%)
11. PTB flash loan can't be used to: manipulate price → borrow → repay atomically
12. Partial liquidation doesn't leave unliquidatable dust
13. Collateral factor / risk model changes are timelocked (already present via OneTimeLockValue)
14. Reserve factor deducted correctly from lender yield
15. ⚠ Under-collateralized liquidation scales `actual_repay` by `collateral / total_needed` (Scallop fix pattern) — verify `liquidation_evaluator.move`
16. ⚠ Liquidation cap = 20% of total debt; verify enforced on combined debts, not per-asset
17. Flash loan single cap (`set_flash_loan_single_cap`) is also used (not just limiter)
18. Borrow fee deducted in the correct currency and from the correct pool
19. `update_borrow_limit` / `update_borrow_fee` use `dynamic_field::remove_if_exists` to avoid stale duplicates (already present)
20. `set_gusd_cap` can only be called once (or migration-safe)

---

## Staking (`contracts/protocol/sources/staking/staking_manager.move` + `app.move` staking section)

1. ⚠ **Pause check** present on `stake_xaum` / `unstake` — currently MISSING
2. `version::assert_current_version` present on both — currently OK
3. Fee deduction order: fee first, then cap check (current order)
4. `EXCHANGE_RATE = 100` overflow guard — verify `net_amount * 100` cannot overflow u64
5. Stake cap is enforced ONLY on `xaum_pool`, NOT on `xaum_pool + fee_pool` — verify documented intent
6. ⚠ `owner_withdraw_xaum` (in `app.move` and `staking_manager.move`) has NO check that residual pool covers outstanding GR/GY supply → admin can leave users unable to unstake
7. ⚠ Dual admin model: `AdminCap` (from `protocol::app`) vs `StakingManager.admin` (address field). Verify they cannot diverge — if AdminCap is transferred but `StakingManager.admin` is not, fee updates become impossible
8. `update_stake_fee` / `update_unstake_fee` correctly assert `numerator <= denominator`
9. `take_stake_fee_coin` does not gate by amount — could over-withdraw fee_pool? Verify wrapper in `app.move::take_staking_fee`
10. `unstake` requires `gr_amount == gy_amount` — this is by design (1:1 ratio at stake), but document. A user who lost one side cannot unstake.
11. `unstake` requires `gr_amount % EXCHANGE_RATE == 0` — verify users have a way to know this
12. Burn happens AFTER pool balance check (already correct)
13. Fee in `unstake` taken from XAUM AFTER split from pool — verify pool isn't drained then fee comes from empty pool
14. Event for `UnstakeEvent` records `xaum_returned: xaum_return_amount - unstake_fee_amount` (net) — verify
15. `MIN_STAKE_AMOUNT = 1_000_000` (0.001 XAUM) — verify gas economics
16. `init_staking_manager` is a `public fun` — anyone with both `TreasuryCap<COIN_GR>` and `TreasuryCap<COIN_GY>` can create a StakingManager. After init they no longer have the cap (consumed into Supply), so unique-init is enforced only if caps are minted once and consumed in deploy. Verify via deploy logs.
17. ⚠ Supply<GR> and Supply<GY> are inside `StakingManager` — verify ONLY `stake_xaum` mints and ONLY `unstake` burns

---

## Oracle (`contracts/sui_x_oracle/`, `contracts/xaum_indicator/`)

1. ⚠ Pyth staleness check: ms vs s units handled
2. Confidence interval (`price.conf`) compared against price
3. `price.expo` handled correctly (signed)
4. Multiple price rules — deterministic selection
5. Per-coin rule registry — verify each coin used in lending has a price source
6. Manual rule (`manual_rule`) is testnet only; not enabled on mainnet — verify deploy config
7. ⚠ `xaum_indicator_core` holds `XOracleAdminCap` as a dynamic field of shared storage. Verify ONLY admin-gated push paths borrow it (`push_gr_indicators_to_x_oracle` behind `assert_admin`). Every public write entry (`update_price_storage_admin`, `set_price_9dec`, `init_ema_values`, `bind_pyth_feed_id`, `push_gr_indicators_to_x_oracle`, `set_admin_cap`) must call `assert_current_version` + `assert_admin` first. No `public fun` may mutate `PriceStorage` state without `&AdminCap`.
8. EMA pushed value has sanity bounds (no 0, no extreme jumps)
9. EMA timestamp recorded; consumers can verify freshness
10. `set_gr_indicator` / `set_gr_alpha_beta` are `XOracleAdminCap`-gated
11. `gr_rule` / `gusd_rule` math doesn't divide by zero
12. Price = 0 rejected by consumers
13. ⚠ Auto-pause uses SPOT GUSD price — DoS risk if cheap manipulation
14. Switchboard / Pyth update enforced in same PTB (or consumer asserts recent update_time)
15. `PythRegistryCap` / `XOracleAdminCap` separately held

---

## Coins (`contracts/coins/`)

1. OTW used in `init` (`COIN_GR`, `COIN_GY`, `COIN_GUSD` are OTW structs — verify)
2. `coin_registry::new_currency_with_otw` called (modern path)
3. `make_regulated(true)` returns `DenyCapV2` — verify cap correctly transferred to admin
4. `MetadataCap` transferred to admin (not shared)
5. `TreasuryCap` lifecycle: `coin_gr/gy` → consumed into Supply inside StakingManager; `coin_gusd` → stored inside Market
6. No `public` mint/burn function exists outside the holding module
7. Denylist epoch boundary acceptable (Sui design)
8. Denylist `DenyCapV2` is per-coin SPOF — multisig held
9. ⚠ `mint_from_supply` / `burn_to_supply` are `public fun` — anyone with `&mut Supply<T>` can call. Verify Supply NEVER leaves `StakingManager`.
10. Token icon URL stored in metadata; mutable only via MetadataCap

---

## Pause / Limiter / Versioning (`contracts/protocol/sources/app/app.move`, `market/limiter.move`, `version/`)

1. `pause_protocol` / `resume_protocol` are AdminCap-gated
2. `set_paused` is `public(package)` — only `app.move` calls it
3. ⚠ User functions checking pause: `borrow / repay / deposit / withdraw / flash_loan / gusd_vault::*` (YES); `stake / unstake` (NO — gap)
4. Admin functions: pause check intentionally omitted (admin can act during pause) — document
5. ⚠ `check_and_pause_if_gusd_depeg` is permissionless — verify DoS cost
6. `resume_protocol` does NOT re-validate depeg condition — admin trust
7. Limiter outflow check on `borrow.move` L158 and `flash_loan.move` (verify same on flash path)
8. Limiter `repay` decrements outflow — verify only real repay flows do this
9. Limiter parameter / limit changes timelocked via `OneTimeLockValue`
10. Limiter segment boundary tested
11. ⚠ `extend_interest_model_change_delay` asserts `delay <= 1` but `extend_risk_model_change_delay` and `extend_limiter_change_delay` do NOT — admin can extend by arbitrary u64 → permanently block updates. **Likely HIGH finding.**
12. `Version` and `VersionCap` separately custodied (verify in deploy)
13. ⚠ Every public state-changing function asserts `version::assert_current_version` — admin entries in `app.move` mostly DON'T (post-migration risk)
14. `current_version()` is a `const fun` — bump path goes through `version::upgrade(&mut Version, &VersionCap)` (already correct)

---

## Upgrade / Package (`Move.toml` + each `UpgradeCap`)

1. UpgradeCap multisig-held (per deploy script)
2. Per-package UpgradeCap separately custodied (some are SPOFs — review which)
3. Struct fields append-only — check past upgrades' diff
4. Version field present on every shared object that's expected to persist (only `Version` itself has explicit; market/StakingManager rely on global)
5. Migration function present if structs changed
6. `init` logic NOT depended upon after upgrade
7. Upgrade policy set to `additive` or `dep_only` where applicable (not `immutable`, not `compatible_with_runtime_breaking`)
8. Upgrade announcement / 1-week pre-notice (operational, not on-chain)

---

## Reward / GUSD Vault (`contracts/protocol/sources/user/gusd_usdc_vault.move`)

1. ⚠ Pause check present (`E_IS_PAUSED` at L97, L129)
2. Mint/redeem rate handling — verify no rounding favoring user/protocol asymmetrically
3. USDC vault balance accounting separate from market reserves
4. Vault has no public balance getter that could leak
5. Redeem cannot underflow vault balance

---

## Obligation (`contracts/protocol/sources/obligation/`)

1. `Obligation` is OWNED (verify `transfer::transfer` in `open_obligation`)
2. `ObligationAccessStore` for lock/reward keys — verify witness pattern
3. `obligation_collaterals` / `obligation_debts` tables sized appropriately
4. Lock prevents withdraw but not deposit (verify intended)
5. No way to delete `Obligation` while debts > 0

---

## Library Quirks (`contracts/libs/`)

1. `OneTimeLockValue` — verify creation → apply path requires same cap, full delay
2. `ac_table::AcTableCap` — verify single instance per table
3. `wit_table` — verify keyed by OTW or restricted witness, not arbitrary type
4. `math::fixed_point32_empower` — verify it doesn't lose precision vs std
5. `math::u64 / u128 / u256::mul_div` — verify widening
6. ⚠ `fixed_point32_empower::add/sub` use raw u64 arithmetic without overflow guard — verify each call site bounds its inputs
7. ⚠ `borrow_limit` (u128 in admin setter) vs `balance_sheet.debt` (u64 in state) — confirm setter clamps

---

## Cross-Cutting Adversarial Checks

These checks run across ALL modules, not just one domain.

1. **Permissionless shared-object mutators** — grep every `public fun .* &mut <Shared>` and verify auth gate
2. **`init` shared-object front-running window** — verify init either sets safe defaults OR gates mutators to require cap+caller verification
3. **`add/sub` on raw u64 fields** — every custom math wrapper must widen or assert
4. **Cap field type vs state field type** — admin caps may be u128 but state u64; clamp at setter
5. **Active-state / pause-state coverage** — every user path that mutates pool state must enforce both
6. **Hard-coded oracle for asset that protocol expects to depeg** — depeg detector must read from a different source
7. **Dual-admin (cap + address field)** — verify both can be rotated or are kept in sync
8. **Stale-read-then-mutate** — every cap check must reference up-to-date state (post-accrual)

---

## Severity Calibration Discipline

Before assigning CRITICAL or HIGH, the audit must explicitly check for
mitigating context. These questions are part of the auditor's own due
diligence — answer them from the codebase + deploy scripts + repo docs, NOT
after-the-fact "team negotiation".

For each suspicious finding, ask:

1. **Placeholder / transitional configurations** — is the suspicious value (hard-coded price, disabled feature, zero default) clearly intended as a launch-phase placeholder with a documented migration path? Check: project README, deploy script comments, code comments. If YES → calibrate severity to "real risk during the transition window", not "permanent defect".
2. **One-shot init exposure** — for any `public fun` that mutates a shared object's state where `assert!(!initialized)` is the only guard, check `scripts/src/deploy-all.mjs` for the deploy ordering. If `init_*` is called atomically (or very close to publish) AND the team has a documented redeploy-on-compromise SOP, the init-time window is operational, not architectural. Runtime mutator exposure (i.e. can the same function be called AFTER `init_*` to corrupt state) is a separate, higher-severity concern.
3. **Cap rotation paths** — for every cap-gated function, trace whether a recovery path exists (`OwnerCap` → re-mint `AdminCap`, two-step transfer, multisig setter). If yes, "admin lockout" is NOT a HIGH; the residual risk is operational.
4. **Network-conditional code** — for any code path that is gated by `NETWORK=mainnet` vs `testnet` (e.g. `USE_MANUAL_RULE`), verify the deploy script enforces the constraint. If the constraint relies on operator discipline only, flag as MEDIUM with explicit "config fragility" tag.
5. **Off-chain mitigation coverage** — for any on-chain control that depends on an external trigger (e.g. a permissionless `pause_if_*` function that no one will call without monetary incentive), check `backend/` for an existing keeper. If present + has reasonable cadence → operational concern, not architectural defect.

If none of the calibrations apply → assign the higher severity.
If calibrations apply → assign the lower severity AND state the calibrating
fact in the finding's description (so the reader understands why this isn't
worse).

**Critically: never write a finding that says "CRITICAL, but actually MEDIUM after review". Pick one. If the calibrating context exists, it's MEDIUM from the start.**
