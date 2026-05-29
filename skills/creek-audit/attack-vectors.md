# Sui Move Attack Vectors — Curated for Creek

Format per item: `D` = description / `FP` = false-positive pattern (when NOT to flag).

Sourced from: Sui Move public audit knowledge (sanbir/move-auditor-skills v3),
Cetus / Typus / Nemo post-mortems, Monethic Sui workshop, Zellic "Move Fast &
Break Things", Trail of Bits flash-loan analysis, Hacken/Movebit checklists.

---

## A. Object Model · Abilities · Visibility (1–15)

**1. Missing Capability Check on Admin Function**
- D: Privileged function callable without requiring a capability object (`AdminCap`, `OwnerCap`, `TreasuryCap`). Anyone can call.
- FP: Cap parameter required (`_: &AdminCap`) OR address check (`assert!(sender == admin)` — weaker but acceptable).

**2. Address-Based Access Control Instead of Capability**
- D: Uses `tx_context::sender(ctx) == @admin` instead of capability pattern. Hardcoded addresses break on upgrade, can't be delegated.
- FP: Designed for that, OR address stored in mutable config object.
- Creek note: **`StakingManager.admin` uses this pattern** — verify it never diverges from AdminCap holder.

**3. Object Has `copy` Ability — Value Duplication**
- D: A coin/badge/receipt with `copy` ability lets anyone duplicate. Especially fatal on capabilities and receipts.
- FP: Object is read-only config data.

**4. Object Has `drop` — Obligation/Receipt Destruction**
- D: Debt record, flash loan receipt, lock object with `drop` can be silently destroyed → unpaid debts.
- FP: Hot potato (no `drop`, no `store`) used.
- Creek note: check `FlashLoan`, `Obligation`, `OneTimeLockValue` abilities.

**5. Object Has `store` — Unauthorized Wrapping**
- D: A capability with `store` can be wrapped inside another object (dynamic field, shared object) and extracted unexpectedly.
- FP: Required for legitimate wrap (e.g. AdminCap bound into PriceStorage — Creek does this; document, do not flag).

**6. Object Leakage via Public Function Return**
- D: A `public fun` returns a capability or admin object.
- FP: Returns value/data only.

**7. Capability Created Outside `init` — Unrestricted Minting**
- D: New `AdminCap`/`TreasuryCap` constructible at runtime by anyone.
- FP: Creation requires existing cap (mint-by-cap pattern) — Creek does this for XOracle.

**8. Missing OTW (One-Time-Witness)**
- D: Coin created without OTW; TreasuryCap may be re-mintable.
- FP: `coin::create_currency` called with OTW struct.

**9. `public entry` Combination**
- D: `public entry` blocks PTB composition in some contexts; usually a smell of confused intent.
- FP: Designed not to be composed.

**10. `public(package)` Trust Boundary Confusion**
- D: `public(package)` functions are callable by ANY module in the same package, including buggy/exploitable modules. Don't treat as "internal".
- FP: All callers vetted.

**11. Shared Object — No Application-Level Auth**
- D: Shared object is accessible by ANY transaction. Functions on shared objects MUST implement explicit auth.
- FP: Cap-gated, or `sender ==` check present.

**12. Shared Capability Object (UpdateAuthority pattern)**
- D: A capability struct wrongly `transfer::share_object`'d — anyone can use it.
- Real exploit: **Typus Finance Oct 2025 — `UpdateAuthority` was a shared object; whitelist check was computed but result not asserted → $3.44M loss.**
- FP: Transferred to specific address.

**13. Missing `assert!` on Boolean Check Result**
- D: `vector::contains(...)` / `is_some(...)` called but result discarded — no abort.
- Real exploit: Typus Finance (see above).
- FP: Result used in `if` and the false branch aborts/returns.

**14. `init` Logic Not Re-Run on Upgrade**
- D: Post-upgrade setup depended on `init` behavior, which only fires on first publish.
- FP: Migration function present.

**15. Owned-Object Confusion**
- D: Logic assumes only owner can pass an object — but later code shares it or passes it to a wrapper that exposes it.
- FP: Object lifecycle traced and locked.

---

## B. Access Control — Caller / Sender / Witness (16–25)

**16. `caller: address` Parameter Trusted Instead of `tx_context::sender(ctx)`**
- D: Function takes `caller: address` and uses it for auth without verifying `caller == sender`. Attacker passes any address.
- Real exploit pattern: Monethic Lab 1.
- FP: `assert!(caller == tx_context::sender(ctx))` present.

**17. Generic Witness Reused Across Roles**
- D: `RoleCap<R>` checked but `R` unconstrained — attacker mints a `RoleCap<Attacker>` and bypasses.
- FP: Explicit type checks.

**18. Comment-Out Validation**
- D: Commented-out validation lines that should be active. (Frequent in code freezes.)
- FP: Comment is intentional / has TODO + new check.

**19. Inconsistent Guards on Same Resource**
- D: Two functions write the same shared object — one cap-gated, the other not.
- FP: Both guarded.

**20. Reward / Withdraw to `tx_context::sender(ctx)` While Function Is Public**
- D: Helper transfers funds to `sender` but is callable by anyone — attacker steals fees/rewards.
- FP: Caller is restricted by cap, or the recipient address is from cap config not sender.

**21. Sender Used as Authority on Behalf of Multisig**
- D: Multisig wallet sends tx → `tx_context::sender(ctx)` = multisig address; but logic assumes single signer semantics.
- FP: Logic correctly handles multisig (no per-signer assumption).

**22. `transfer_admin_cap` Without Two-Step**
- D: One-shot cap transfer — typo in address = bricked admin.
- FP: Two-step transfer (propose → accept).
- Creek: `protocol::app::transfer_admin_cap` is **one-shot**.

**23. AdminCap with `key, store` Held by Wrapper**
- D: Cap stored in wrapper object whose access control is weaker — wrapper leaks the cap.
- FP: Wrapper explicitly cap-protected.

**24. Admin Functions Bypass Version Check**
- D: Admin functions don't `assert_current_version` while user functions do. Stale admin paths usable post-migration.
- FP: All public admin entries version-checked.
- Creek: many admin entries in `app.move` lack `version::assert_current_version`.

**25. Admin Functions Bypass Pause Check**
- D: Admin pulls revenue / withdraws pool while protocol is paused (defeats pause intent).
- FP: Documented design choice (admin SHOULD be able to act during pause).

---

## C. Math · Precision · Decimals · Overflow (26–40)

**26. `mul_div` Intermediate Overflow in Custom Math**
- D: `a * b / c` where `a*b` overflows the intermediate type before division saves it. Custom libraries (not std `mul_div`) may not widen.
- Real exploit: **Cetus May 2025 — `checked_shlw` overflow guard wrong constant + wrong operator → $223M.**
- FP: Verified widening to u256, or explicit bound check.

**27. Wrong Rounding Direction**
- D: Deposits round shares DOWN, withdrawals round assets DOWN, debt rounds UP, fees round UP. Reverse any of these and user/protocol gets value asymmetry.
- FP: Per-path rounding documented and matches.

**28. Zero-Round Truncation**
- D: Tiny amount → fee/reward/share truncates to 0; attacker spams and free-rides.
- FP: Minimum-input gate, or rounding-up pattern.

**29. Division-Before-Multiplication**
- D: `(a / b) * c` instead of `(a * c) / b` — loses precision.
- FP: Bounded c << b, documented acceptable loss.

**30. Decimal Mismatch (Hardcoded 9-decimal Assumption)**
- D: Code assumes 9 decimals (SUI) but accepts arbitrary tokens (USDC = 6, ETH = 18).
- FP: Per-coin decimals registry lookup.
- Creek: `coin_decimals_registry` exists — verify EVERY math path uses it.

**31. Cross-Scale Math (FixedPoint32 × token raw)**
- D: Mixing `FixedPoint32` raw value (2^32 scale) with token raw amount without explicit unscaling.
- FP: `fixed_point32::multiply_u64` / `divide_u64` used.

**32. Downcast u128 → u64 Without Bounds**
- D: `(x as u64)` where x > u64::MAX → truncation.
- FP: `assert!(x <= u64_max)` before cast.

**33. Overflow in `* EXCHANGE_RATE`**
- D: `net_amount * 100` overflows u64 if net_amount > u64::MAX / 100.
- FP: Upper bound on input.
- Creek: `staking_manager::stake_xaum` does `net_amount * EXCHANGE_RATE` (100). u64::MAX / 100 ≈ 1.84e17 — possibly safe for XAUM (9 decimals) but verify there's no realistic overflow.

**34. First-Depositor Inflation**
- D: First depositor mints tiny shares, then `coin::join`s a donation into vault Balance to inflate share price; subsequent depositors round to 0.
- FP: Virtual shares, minimum deposit, dead shares.

**35. Donation-Inflation via `balance::join`**
- D: Any user can call `balance::join` if there's a public wrapper, or the pool reads `balance::value` for pricing.
- FP: Internal accounting separate from raw balance.

**36. Interest Rate Overflow at Extreme Utilization**
- D: Utilization → 100% may make rate formula overflow before clamping.
- FP: Rate capped before multiplication.

**37. Compounding Rounding**
- D: Even tiny rounding errors compound when called per-block.
- FP: Time-weighted index, not per-call accumulation.

**38. Fee = 0 At Small Amounts**
- D: `fee = amount * fee_rate` truncates to 0 for small amounts → MEV-free spam.
- FP: Min fee floor.

**39. Round-Trip Profit**
- D: `deposit(X) → withdraw(all)` returns > X (rounding favors user) OR < X consistently (silent loss).
- FP: Round-trip = X within ±1 wei.

**40. `mul_div` With `c = 0` (Division by Zero)**
- D: Denominator can be 0 (e.g. total_supply before first deposit).
- FP: Pre-check denominator.

---

## D. Oracle · Price · Time (41–55)

**41. No Staleness Check (Clock Timestamp)**
- D: Price read without comparing `clock::timestamp_ms` against `price.timestamp`.
- FP: `assert!(now - price_ts <= MAX_STALENESS)`.

**42. Units Mismatch: ms vs s**
- D: Pyth `price.timestamp` is in SECONDS; `clock::timestamp_ms` is in MILLISECONDS. Direct subtraction is 1000× wrong.
- FP: Explicit `/ 1000` or `* 1000` conversion.

**43. No Confidence Interval Check**
- D: Pyth provides `price.conf`; if `conf / price > 5%`, the price is too noisy.
- FP: Explicit conf threshold.

**44. Single-Oracle Dependency**
- D: One oracle source down = protocol frozen.
- FP: Fallback oracle.

**45. Price From Internal Pool Reserves (Spot)**
- D: Reading reserve ratio as price → flash-loan manipulable.
- Real exploit: **Cetus** (oracle was self-sampled reserves).
- FP: External Pyth/Switchboard.

**46. Stale Indicator Push (Keeper Down)**
- D: EMA push relies on keeper; if keeper down, oracle still serves the old value with no abort.
- FP: Indicator value carries a timestamp; consumers check freshness.
- Creek: check `xaum_indicator_core` push function + how consumers verify EMA timestamp.

**47. Price Update Authority on Shared Object**
- D: See vector 12 (Typus pattern).

**48. Negative Exponent Handling**
- D: Pyth prices can have negative exponent; misuse of `u64::pow` on `expo` field bug.
- FP: `i32::abs` or explicit sign handling.

**49. `EMA90 > EMA120` Inversion Not Validated**
- D: Indicator-driven pricing assumes a relation; if violated (e.g. keeper pushes garbage), GR/GY prices flip.
- FP: Sanity assertion in setter.

**50. Price Used Across PTB Without Re-Reading**
- D: Price read once at start of PTB, reused after a state change that could have updated it.
- FP: Re-read at point of use.

**51. Confidence-Spread Asymmetric Use**
- D: Protocol uses `price - conf` for borrow value (conservative) but `price + conf` for collateral value (also conservative — but might over-conservatize).
- FP: Symmetric or per-side reasoned.

**52. Bypass Validity by Calling Outside `update_price_feeds` PTB**
- D: On Sui, Pyth requires explicit update in same PTB; if not enforced, anyone can read arbitrary stale prices.
- FP: Consumer asserts `update_time` is recent.

**53. Auto-Pause Threshold Bypass via Off-by-One Rounding**
- D: Depeg auto-pause uses `>=` comparison; rounding makes price equal threshold exactly without firing.
- FP: Comparator inclusive on the safe side.

**54. Multiple Price Rules — Inconsistent Selection**
- D: Multiple rules for same coin; aggregator returns first/min/max in inconsistent order.
- FP: Deterministic selection documented.
- Creek: x_oracle uses `price_update_policy` — verify rule selection determinism.

**55. Price = 0 Not Rejected**
- D: Stale or uninitialized price returns 0; downstream uses it → divide-by-zero or free liquidation.
- FP: `assert!(price > 0)`.

---

## E. Lending / Liquidation Specifics (56–70)

**56. Health Factor Excludes Accrued Interest**
- D: HF computed from principal, not principal + accrued interest. Users hover under threshold longer.
- FP: `accrue_interest` called before HF check.

**57. Self-Liquidation Profitable**
- D: Borrower can liquidate self for the liquidation bonus → free money.
- FP: Bonus < penalty enforced.

**58. Collateral Withdraw While Underwater**
- D: `withdraw_collateral` doesn't recompute HF after withdrawal — only before.
- FP: Post-withdrawal HF check.

**59. Liquidation Bonus < Tx Cost for Dust Positions**
- D: Tiny positions become un-liquidatable.
- FP: Dust threshold allowing full liquidation.

**60. Bad Debt Not Socialized**
- D: When collateral < debt, residual debt sits on Obligation forever; never written off.
- FP: Bad-debt write-off function.

**61. Multi-Decimal Asset Liquidation Math Wrong**
- D: Liquidator pays in `DebtType`, receives `CollateralType` with different decimals; conversion forgets to normalize.
- FP: Per-coin decimals applied.

**62. Partial Liquidation Leaves Unliquidatable Dust**
- D: After 20%-cap liquidation, remaining collateral can't be liquidated further due to dust threshold.
- FP: Final-pass full liquidation for dust.

**63. Collateral Factor Update Retroactively Liquidates**
- D: Admin lowers CF; existing positions instantly liquidatable with no grace period.
- FP: Timelock + announcement.

**64. Reserve Factor Off-By-One**
- D: Reserve takes too much or too little of interest revenue.
- FP: Verified by test, documented.

**65. Borrow Without Limiter Check on Flash Loan Path**
- D: Outflow limiter on regular borrow but flash-loan borrow path skips it.
- FP: Same limiter call on both paths.
- Creek: check `flash_loan.move` vs `borrow.move`.

**66. Flash Loan Receipt Consumable by Unintended Function**
- D: Hot-potato struct can be consumed by ANY function in the package (including a malicious upgrade), not just `repay_flash_loan`.
- FP: Receipt fields locked to specific repay function.

**67. Flash-Loan-Inside-Liquidation State Inconsistency**
- D: PTB chain: `flash_borrow → manipulate price → liquidate → repay_flash`. Price oracle reads pool state instead of external.
- FP: External oracle, plus liquidation uses TWAP.

**68. Liquidation Without `accrue_interest` First**
- D: Liquidates against stale debt — bonus calculation under-pays liquidator.
- FP: `accrue_interest` is first call in liquidate.

**69. Liquidator Repays Less Than Cap, But Cap Path Skipped**
- D: Multi-step cap calc divided across paths inconsistently; one path skips the cap.
- FP: Single function computes cap.

**70. Under-Collateralized Liquidation Pays Out Too Much**
- D: When collateral < expected discounted share, liquidator gets full discounted amount → eats from protocol.
- Real fix: Scallop scaled `actual_repay` down by `eth_amount / total_needed`.
- FP: Same scaling present.

---

## F. Staking Specifics (71–80)

**71. Flash Stake/Unstake Reward Capture**
- D: Stake → claim rewards → unstake atomically. No time-weighted requirement.
- FP: Cooldown or time-weighted rewards.

**72. Rewards Accumulator Updated After Balance Change**
- D: New balance applied before reward index → user gets retroactive rewards on new stake.
- FP: Settle first, then update balance.

**73. Direct Donation to Pool Inflates Reward Rate**
- D: Anyone can `coin::join` into pool Balance if there's a public deposit path, skewing per-share rewards.
- FP: Internal accounting separate.

**74. Unstake Returns Less Than Promised**
- D: `unstake` deducts fee from XAUM but uses gross amount in event/return.
- FP: Net amount reported.
- Creek: `staking_manager::unstake` — verify event uses `xaum_return_amount - unstake_fee_amount`, not gross.

**75. GR ≠ GY Pair Forced**
- D: `assert!(gr_amount == gy_amount)` — but if user has only GR (no GY left from gifting/trading), unstake permanently blocked.
- FP: Documented, user can buy GY on market.
- Creek: `unstake` requires GR == GY — this is by design (XAUM was staked 1:1); document.

**76. Stake Cap Bypass via Fee Accounting**
- D: Cap checked against `xaum_pool` only; if fee_pool counts as TVL too, accounting misleading.
- FP: Stake cap correctly excludes fee_pool from "total staked".

**77. Minimum Stake Below Practical Cost**
- D: `MIN_STAKE_AMOUNT = 1_000_000` (= 0.001 XAUM). If XAUM = $3000/oz → $3 minimum. OK, but verify gas economics for dust positions.

**78. Stake Doesn't Re-Read Oracle**
- D: Staking exchange rate hardcoded (1 XAUM = 100 GR + 100 GY) — independent of price. Verify this is correct for the protocol design.
- FP: Documented.

**79. Owner Withdraw of Pool Beyond Required Reserve**
- D: `owner_withdraw_xaum` has no check that residual pool covers outstanding GR/GY supply.
- FP: Check `pool >= total_gr_supply / EXCHANGE_RATE`.
- Creek: **`owner_withdraw_xaum` in `staking_manager.move` only checks `pool >= amount`, NOT pool ≥ outstanding redemption claims** — admin can withdraw funds users need to unstake. By design? Document and flag as ADMIN-RISK.

**80. Burn Math Mismatch in Unstake**
- D: `gr_amount / EXCHANGE_RATE` integer division; if `gr_amount % EXCHANGE_RATE != 0`, user loses dust.
- FP: Explicit modulo check (Creek does this — see `staking_gr_amount_not_divisible_error`).

---

## G. Pause / Limiter / Versioning (81–90)

**81. Pause Check Missing on User Path**
- D: pause flag set but a user-facing fund-moving function doesn't check it.
- Creek: `stake_xaum` / `unstake` lack pause check.

**82. Pause Check Order: After State Mutation**
- D: pause check after state already mutated.
- FP: Check first.

**83. Resume Without Sanity Re-Validation**
- D: `resume_protocol` doesn't re-check that the condition causing pause is gone.
- FP: Resume requires depeg below threshold.
- Creek: `resume_protocol` is unconditional — admin trust required.

**84. Auto-Pause Cannot Trigger Without Keeper**
- D: `check_and_pause_if_gusd_depeg` is permissionless but needs someone to call. If no incentive, won't fire fast.
- FP: Keeper SLA, or on-borrow auto-check.

**85. Limiter Bypassed by Repay Flow**
- D: Limiter decrements on repay; an attacker can fake repay (with mint?) to free up outflow capacity.
- FP: Only real repay flows decrement.

**86. Limiter Segment Boundary Off-By-One**
- D: Segment rotation drops outflows at exactly the boundary tick.
- FP: Tested with boundary inputs.

**87. Version Mismatch Not Asserted in User Path**
- D: Version bumped → old objects bypass new logic if version not asserted.
- FP: Every public state-changing function asserts.

**88. Version Cap Held by Same Multisig as AdminCap**
- D: Compromise of one cap = compromise of both.
- FP: Separate keys.

**89. `extend_*_change_delay` Asymmetric Limit**
- D: `extend_interest_model_change_delay` asserts `delay <= 1`; `extend_risk_model_change_delay` and `extend_limiter_change_delay` don't. Admin can extend by arbitrary epochs → permanently blocks legitimate updates.
- Creek: confirmed in `app.move` L108-119. **Likely finding.**

**90. Timelock Bypass via OneTimeLockValue Reuse**
- D: `OneTimeLockValue` consumed and re-created — does it actually wait the full delay?
- FP: Internal epoch check on `apply`.

---

## H. Coin / Token Custody (91–100)

**91. Denylist Not Checked on Mint**
- D: Mint allowed to a denylisted address.
- FP: Sui's `coin::deny_list_v2_contains_current_epoch` check OR DenyList enforced at transfer-time only.

**92. TreasuryCap Held by Module — Surface Audit**
- D: Module holds TreasuryCap; verify every mint path is access-controlled.
- Creek: GUSD TreasuryCap in Market — borrow mints; verify only borrow path mints.

**93. Burn Function Public — Anyone Can Burn**
- D: `coin::burn` exposed publicly; griefer burns someone else's coin if they get it.
- FP: Owner-only.

**94. Supply Object Held Inside Shared Object**
- D: `Supply<T>` inside a shared object is mutable by anyone with access to the shared object → infinite mint.
- FP: Mutation gated by sender check or cap.
- Creek: `StakingManager` holds `gr_supply` and `gy_supply` — verify ONLY `stake_xaum` mints and ONLY `unstake` burns.

**95. Mint Without Updating Total-Supply Accounting**
- D: Direct mint via Supply skips an off-chain accounting record.
- FP: Mint and counter updated atomically.

**96. Coin Type Confusion via Generic Function**
- D: `<T>` left unbound; attacker substitutes a fake type they control.
- FP: Type witness or `type_name::get<T>` whitelist.
- Creek: many generics in `app.move`; verify each has implicit type discipline.

**97. Denylist Capability Single Point of Failure**
- D: One `DenyCapV2` compromise = freeze all users.
- FP: Multisig.

**98. Metadata Edit During Pause**
- D: Metadata change while protocol paused causes off-chain UI inconsistency.
- FP: Acceptable.

**99. Coin Decimals Registry Manual Registration**
- D: New coin registered with wrong decimals → liquidation/borrow math off by 10^N.
- FP: Decimals fetched from on-chain Metadata, not hand-entered.

**100. Wormhole / Bridged Coin Decimal Drift**
- D: Wrapped USDC may have different decimals across chains.
- FP: Per-coin verified, fixed at registration.

---

## I. Sui-Specific Behaviors (101–115)

**101. PTB Atomicity Assumption**
- D: Code assumes a series of calls happen atomically without enforcing via hot potato.
- FP: Hot potato pattern enforces.

**102. Shared Object Contention Front-Run**
- D: Multiple txs target same shared object same block; later tx sees state after earlier — front-runnable price-sensitive ops.
- FP: Deadline parameter, or oracle-based reference.

**103. Dynamic Field Access — Anyone Reads/Writes**
- D: Dynamic fields on shared objects accessible without auth if exposed.
- FP: Mutation gated by cap.

**104. `transfer::public_*` Bypass of Custom Transfer Policy**
- D: `transfer::public_transfer` skips type-specific transfer policy.
- FP: Use `transfer::transfer` (key-only).

**105. Frozen Object Misuse**
- D: An object with `store` ability can be frozen and shared; then anyone uses it as immutable input. If it should be mutable for one party, this is a freeze attack.
- FP: Object lifecycle controls freezing.

**106. UpgradeCap as Single Point of Failure**
- D: A single multisig holds every UpgradeCap → one compromise = all packages.
- FP: Per-package multisig, or rotation.

**107. Upgrade Without Version Bump**
- D: Code upgraded but version field stays the same → existing objects bypass new checks.
- FP: Bump version + migrate.

**108. Struct Field Reordering Breaks Storage**
- D: Move serializes by position; reordering fields breaks existing objects.
- FP: Append-only fields.

**109. Removing Public Function Breaks Callers**
- D: PTBs referencing removed public fun fail.
- FP: Mark `#[deprecated]`, keep ABI.

**110. Init Re-Execution on Upgrade Assumed**
- D: Logic assumes `init` re-runs to set up new objects post-upgrade. It does not.
- FP: Migration function present.

**111. `clock` Object Passed but Not Used / Used Inconsistently**
- D: `clock` parameter exists but the function reads from a different time source (e.g. `tx_context::epoch_timestamp_ms`).
- FP: Same source throughout.

**112. `tx_context::sender` in `view` Function Cached**
- D: Reading sender in a query function; another caller uses cached value.
- FP: View functions don't use sender.

**113. Random Number from `tx_context::epoch`**
- D: Predictable randomness used as a security primitive.
- FP: VRF / commit-reveal.

**114. Deny List Epoch Boundary Race**
- D: `deny_list_v2_contains_current_epoch` returns based on epoch; user gets one tx in the new epoch before lists refresh.
- FP: Acceptable per Sui design.

**115. Object Wrapping Hides Ownership Chain**
- D: Wrapper conceals true owner; transfer of wrapper transfers nested objects opaquely.
- FP: Wrapper documented; off-chain indexer aware.

---

## J. Cross-Module / Composition / Economic (116–130)

**116. `public(package)` Caller Trusts Other Module Without Check**
- D: Module A's `public(package)` fun callable by module B; B has weaker auth.
- FP: A's own checks suffice.

**117. PTB-Composable Flash Stake Then Borrow**
- D: PTB: stake XAUM → use GY as collateral → borrow → unstake. Verify no atomicity exploit.
- FP: Borrow uses oracle, not staking state.

**118. Donate to Manipulate `balance::value`-Based Reads**
- D: External `coin::transfer` to a pool Balance moves the raw balance; if anything reads `balance::value` for accounting (not internal counter), it skews.
- FP: Internal counter used.

**119. Oracle-Free Liquidation Math**
- D: Liquidation amount derived from `Obligation` data without re-pricing → uses stale value.
- FP: `price_eval::get_price` called inside liquidate.

**120. Self-Borrow Through Multiple Obligations**
- D: User opens N obligations, splits debt, dodges per-obligation limits.
- FP: Global per-user accounting or hard system-wide cap.

**121. Deposit-and-Borrow Same Tx → Oracle Manipulation Window**
- D: PTB: oracle update at start (Pyth) → deposit at inflated price → borrow → repay.
- FP: Pyth updates required in same PTB AND no price diff allowed.

**122. Repay With Smaller Amount Than Outstanding → Locks Position**
- D: `repay(small_amount)` fails due to a `assert!(amount >= outstanding)` — user can never repay partial.
- FP: Partial repay supported.

**123. Borrow Fee Charged in DebtType but Deducted From Collateral**
- D: Asymmetric accounting causes silent loss.
- FP: Both same coin.

**124. Auto-Pause Threshold Manipulable by Single Trade**
- D: Threshold reads spot oracle; one-block manipulation triggers pause maliciously (DoS).
- FP: TWAP or multi-sample.
- Creek: `check_and_pause_if_gusd_depeg` reads spot — potential **DoS** by triggering pause maliciously cheaply.

**125. Permissionless Pause Trigger = Free DoS**
- D: Anyone can call `check_and_pause_if_gusd_depeg` repeatedly; if depeg even briefly, attacker pauses protocol for free.
- FP: Resume is admin-only; documented (Creek path).
- Creek: explicitly worth a LEAD — confirm cost-of-griefing.

**126. Owner Withdraw Drains Pool Below Stake Backing**
- D: Admin withdraws XAUM; users can't unstake.
- Creek: confirmed — see vector 79.

**127. Take_revenue Allows Negative Reserve**
- D: `take_revenue` doesn't check reserve ≥ amount.
- FP: Internal check.

**128. Fee Pool / Pool Cross-Funding**
- D: `take_stake_fee_coin` splits from `fee_pool` — if `take_revenue` ever pulls from `xaum_pool`, mixing.
- FP: Strict separation.

**129. Reward Address `@0x0` Bypass**
- D: `take_revenue` aborts on `@0x0`; admin can set valid `@0x0`-like address? — N/A on Sui (no zero address ambiguity).
- FP: N/A.

**130. Composable PTB Lock + Reward Drain**
- D: Lock obligation → claim rewards on locked → unlock → repeat. Verify reward access store doesn't allow multiple claims per cycle.
- FP: Reward settled per-claim, idempotent.

---

## K. Sui DeFi-2026-Specific (131–143)

---

**144. EMA / price storage public update entrypoint without auth**
- D: A "price storage" module exposes `update_price_*_external` or similar as `public fun` to support an adapter package. Without admin/cap gate, the shared storage is poisonable: spot field set in one tx, EMAs shifted progressively. Even if downstream push is admin-gated, the poisoned state propagates on next push.
- FP: Entry takes `&AdminCap` or `&PolicyCap`. Adapter calls with its own admin cap.

**145. One-shot EMA init with no admin reset**
- D: `init_ema_values` asserts `!ema_initialized`. Combined with vector 144, attacker can pre-emptively `init` EMAs to any value during deploy window, OR after a successful poison there's no admin clean-restart path.
- FP: Admin `force_reinit: bool` or a separate `circuit_breaker_reset` function.

**146. Stale debt total used in borrow-limit check**
- D: `borrow_limit` checked against `balance_sheet.debt` BEFORE `accrue_all_interests` runs. Post-accrual debt can exceed limit by the accrual delta. Compounds across many borrows.
- FP: `accrue_all_interests(market, now)` is called BEFORE reading any debt total used for caps.

**147. `fixed_point32_empower::add/sub` raw u64 ± without overflow guard**
- D: Custom FixedPoint32 wrappers do `a_raw + b_raw` (u64) without widening or assertion. At protocol scale (>$4B aggregate USD) sums hit u64::MAX → DoS for whale positions.
- FP: Cast to u128 for the intermediate, assert ≤ u64::MAX.

**148. Borrow limit / cap stored as u128 but consumed against u64 state field**
- D: Admin can set `borrow_limit: u128` larger than `balance_sheet.debt: u64` can hold. As debt approaches u64::MAX, accrual aborts and protocol freezes.
- FP: Assert `limit ≤ u64::MAX` in setter, OR upgrade backing field to u128.

**149. Active-state check inconsistent across sibling user paths**
- D: One module checks `is_base_asset_active` / `is_collateral_active`; sibling module that mutates the same shared state doesn't. Admin's deactivation control is unreliable.
- FP: Same check on all sibling paths (or document the asymmetry intentionally).

**150. Dual-admin model where one cap rotates and the other field doesn't**
- D: Shared object has both `&AdminCap` parameter (rotatable via cap transfer) AND `admin: address` field (never updated). After AdminCap rotation, half the admin entries are reachable; the other half permanently frozen.
- FP: Single auth path, OR setter for the address field gated by the cap.

**151. Front-runnable shared-object initialization**
- D: A shared object exposing public mutators is created in `init` and immediately shared. Between deploy block and the first admin setup tx, anyone can call the mutators to lock in adversarial initial state.
- **Severity calibration (apply BEFORE flagging):**
  - **If the public mutator can ALSO be called post-init** → severity governed by the runtime exposure (typically CRITICAL/HIGH). The init-time window is a sub-concern, not the dominant attack. Report the runtime issue; mention init-time as one paragraph of the description, not a separate finding.
  - **If the public mutator is ONLY reachable during a narrow deploy window** AND the team has a documented deploy SOP that handles compromise (e.g. "if init fails, abandon and redeploy with fresh package IDs") → LOW (operational hardening recommendation), not HIGH.
  - **If neither condition holds (post-init exploitable AND no deploy SOP)** → CRITICAL.
- FP (do not flag at all): `init` itself sets safe defaults AND atomically gates mutators; OR the setup is part of the same PTB as the publish via custom init function.

**152. Hard-coded stablecoin price masks the depeg detector**
- D: A "stablecoin rule" hard-codes price = $1 in `set_price_as_primary`. The depeg detector reads from the same XOracle store, so it always sees $1 and never triggers. Auto-pause is non-functional while this configuration persists.
- **Severity calibration (apply BEFORE flagging — do NOT default to CRITICAL):**
  - **If the hard-coded rule is the protocol's final/permanent design** AND there is no other depeg-detection mechanism → CRITICAL (genuine dead-code circuit breaker on a stablecoin).
  - **If the hard-coded rule is documented as a transitional/launch-phase placeholder** AND the on-chain rule swap is admin-only (via `XOracleAdminCap`) with lockout protection (`XOracleOwnerCap` can re-mint AdminCap) AND off-chain monitoring + manual `pause_protocol` covers the gap → **MEDIUM** (acceptable transitional state; surface the migration plan in the finding, do not over-rate).
  - **If the rule appears hard-coded without documented intent** (no migration plan, no off-chain monitor) → CRITICAL.
- FP (do not flag at all): depeg check reads from a SEPARATE source (external Pyth feed for the stablecoin, PSM exchange-rate ratio, etc.); OR the stablecoin rule reads real market price; OR the hard-coded value matches an enforced peg backed by a separate redemption mechanism.

**153. Vault PSM redemption fungibility with debt-minted token**
- D: A token (e.g. GUSD) is mintable two ways — collateralized borrow AND USDC-vault deposit. The redemption path treats all instances as fungible, so borrowed-token holders can drain the vault, starving genuine USDC depositors.
- FP: Per-mint tracking (hard for fungible coins) OR vault redemption cap = vault_deposit_total OR per-tx redeem cap.

**131. AdminCap Bound Into Shared Object as Dynamic Field**
- D: AdminCap stored in shared object can be borrowed by anyone with mut access to the shared object → privilege escalation.
- FP: Mutation gated.
- Creek: `xaum_indicator_core` does this — `dynamic_object_field::add<AdminCapKey, XOracleAdminCap>(&mut storage.id, AdminCapKey {}, admin_cap)`. Verify only `push_indicator_to_xoracle` borrows it AND only behind a guard.

**132. EMA Push Skip Validation**
- D: EMA value pushed without sanity bounds (e.g. delta from prior > 50%).
- FP: Sanity assertion.
- Creek: check `xaum_indicator_core::push_*`.

**133. GR Pricing Formula α/β Misuse**
- D: `set_gr_alpha_beta` accepts u64 scaled to 1e9; verify boundary handling (α + β = 1?).
- FP: Constraint asserted.

**134. Coin Decimals Registry Trust**
- D: Registry mutable — admin changes coin decimals → math reinterprets old positions.
- FP: One-time registration per coin.

**135. Switchboard On-Demand No Update In Same PTB**
- D: Switchboard requires explicit update — if consumer reads without ensuring update, stale data.
- FP: Atomic update in PTB.

**136. Reserve Drift via Repeated Tiny Borrows**
- D: Repeated 1-unit borrows accumulate reserve dust that bypasses fee math.
- FP: Min borrow amount.
- Creek: `min_borrow_amount` in interest model — verify enforced.

**137. Flash Loan Single Cap vs Borrow Limit Inconsistency**
- D: `set_flash_loan_single_cap` separately from regular borrow limit.
- Creek: verify both used in `flash_loan::borrow_flash_loan`.

**138. Obligation Access Key Replay**
- D: `obligation_access` keys allow lock/reward modules; if key witnessing bypassed, anyone can lock arbitrary obligation.
- FP: Per-key drop witness required at use.

**139. PriceUpdatePolicy Insufficient Rules**
- D: Policy registered with 1 rule = single oracle.
- FP: 2+ rules with quorum.

**140. AC Table Cap Cloning**
- D: `AcTableCap` stored inside another struct; verify only one copy exists.
- FP: Single-witness pattern.

**141. Wit Table Witness Forgery**
- D: `wit_table` keyed by witness; if witness type not OTW, forgery possible.
- FP: OTW or restricted witness.

**142. `OneTimeLockValue` Created Without Cap**
- D: Verify creation requires the matching cap; otherwise anyone schedules a change.
- FP: Cap required in `create_*_change`.

**143. AdminCap-Gated `ext` Function Returns `&mut UID`**
- D: `ext` returns `&mut UID` → anyone holding AdminCap can add dynamic fields → escalate.
- FP: Documented as intended.
- Creek: `app::ext` does this — acceptable but high-risk.
