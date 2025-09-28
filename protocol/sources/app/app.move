module protocol::app;

use coin_gusd::coin_gusd::COIN_GUSD;
use test_coin::coin_xaum::COIN_XAUM;
use math::fixed_point32_empower;
use protocol::error;
use protocol::interest_model::{Self, InterestModels, InterestModel};
use protocol::limiter::{Self, LimiterUpdateParamsChange, LimiterUpdateLimitChange};
use protocol::market::{Self, Market};
use protocol::market_dynamic_keys::{
    Self,
    BorrowFeeKey,
    SupplyLimitKey,
    BorrowLimitKey,
    IsolatedAssetKey
};
use protocol::obligation_access::{Self, ObligationAccessStore};
use protocol::price as price_eval;
use protocol::risk_model::{Self, RiskModels, RiskModel};
use protocol::staking_manager::{Self as staking_manager, StakingManager};
use std::fixed_point32::{Self, FixedPoint32};
use std::type_name::{Self, TypeName};
use sui::clock::{Self, Clock};
use sui::coin::TreasuryCap;
use sui::dynamic_field;
use sui::event;
use sui::package;
use x::ac_table::AcTableCap;
use x::one_time_lock_value::OneTimeLockValue;
use x_oracle::x_oracle::XOracle;

/// OTW
public struct APP has drop {}

public struct AdminCap has key, store {
    id: UID,
    interest_model_cap: AcTableCap<InterestModels>,
    interest_model_change_delay: u64,
    risk_model_cap: AcTableCap<RiskModels>,
    risk_model_change_delay: u64,
    limiter_change_delay: u64,
    reward_address: address,
}

public struct RewardAddressUpdatedEvent has copy, drop {
    old_address: address,
    new_address: address,
    sender: address,
}

public struct TakeRevenueEvent has copy, drop {
    market: ID,
    amount: u64,
    coin_type: TypeName,
    sender: address,
    recipient: address,
}

public struct TakeBorrowFeeEvent has copy, drop {
    market: ID,
    amount: u64,
    coin_type: TypeName,
    sender: address,
    recipient: address,
}

public struct TakeStakingFeeEvent has copy, drop {
    manager: ID,
    amount: u64,
    coin_type: TypeName,
    sender: address,
    recipient: address,
}

fun init(otw: APP, ctx: &mut TxContext) {
    init_internal(otw, ctx)
}

#[test_only]
public fun init_t(ctx: &mut TxContext) {
    init_internal(APP {}, ctx)
}

#[allow(lint(self_transfer, share_owned))]
fun init_internal(otw: APP, ctx: &mut TxContext) {
    let (market, interest_model_cap, risk_model_cap) = market::new(ctx);
    let adminCap = AdminCap {
        id: object::new(ctx),
        interest_model_cap,
        interest_model_change_delay: 0,
        risk_model_cap,
        risk_model_change_delay: 0,
        limiter_change_delay: 0,
        reward_address: @0x0,
    };
    package::claim_and_keep(otw, ctx);
    transfer::public_share_object(market);
    transfer::transfer(adminCap, tx_context::sender(ctx));
}

/// ===== AdminCap =====
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

/// ===== Emergency pause controls =====
/// Manually pause the protocol. Only admin can call.
public entry fun pause_protocol(_admin_cap: &AdminCap, market: &mut Market) {
    market::set_paused(market, true);
}

/// Manually resume the protocol. Only admin can call.
public entry fun resume_protocol(_admin_cap: &AdminCap, market: &mut Market) {
    market::set_paused(market, false);
}

/// Anyone can call. If GUSD price deviates from 1 by >= 0.8%, auto-pause protocol.
/// Deviation threshold: 0.008
public entry fun check_and_pause_if_gusd_depeg(
    market: &mut Market,
    x_oracle: &XOracle,
    clock: &Clock,
) {
    if (market::is_paused(market)) { return }; // already paused

    let price = price_eval::get_price(x_oracle, type_name::get<COIN_GUSD>(), clock);
    let one = fixed_point32_empower::from_u64(1);
    let diff = if (fixed_point32_empower::gt(price, one)) {
        fixed_point32_empower::sub(price, one)
    } else {
        fixed_point32_empower::sub(one, price)
    };
    let tolerance = fixed_point32::create_from_rational(8, 1000); // 0.008

    if (fixed_point32_empower::gte(diff, tolerance)) {
        market::set_paused(market, true);
    };
}

/// ===== Auto-pause configuration =====
public entry fun set_auto_pause_enabled(_admin_cap: &AdminCap, market: &mut Market, enabled: bool) {
    market::set_auto_pause_enabled(market, enabled);
}

public entry fun set_auto_pause_threshold(
    _admin_cap: &AdminCap,
    market: &mut Market,
    numerator: u64,
    denominator: u64,
) {
    let threshold = fixed_point32::create_from_rational(numerator, denominator);
    market::set_auto_pause_threshold(market, threshold);
}

/// For extension of the protocol
public fun ext(_: &AdminCap, market: &mut Market): &mut UID {
    market::uid_mut(market)
}

public fun create_interest_model_change<T>(
    admin_cap: &AdminCap,
    base_rate_per_sec: u64,
    interest_rate_scale: u64,
    borrow_rate_on_mid_kink: u64,
    mid_kink: u64,
    borrow_rate_on_high_kink: u64,
    high_kink: u64,
    max_borrow_rate: u64,
    revenue_factor: u64,
    borrow_weight: u64,
    scale: u64,
    min_borrow_amount: u64,
    ctx: &mut TxContext,
): OneTimeLockValue<InterestModel> {
    let interest_model_change = interest_model::create_interest_model_change<T>(
        &admin_cap.interest_model_cap,
        base_rate_per_sec,
        interest_rate_scale,
        borrow_rate_on_mid_kink,
        mid_kink,
        borrow_rate_on_high_kink,
        high_kink,
        max_borrow_rate,
        revenue_factor,
        borrow_weight,
        scale,
        min_borrow_amount,
        admin_cap.interest_model_change_delay,
        ctx,
    );
    interest_model_change
}

public fun add_interest_model<T>(
    market: &mut Market,
    admin_cap: &AdminCap,
    interest_model_change: OneTimeLockValue<InterestModel>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    update_interest_model<T>(market, admin_cap, interest_model_change, ctx);
    let now = clock::timestamp_ms(clock) / 1000;
    market::register_coin<T>(market, now);
}

public fun update_interest_model<T>(
    market: &mut Market,
    admin_cap: &AdminCap,
    interest_model_change: OneTimeLockValue<InterestModel>,
    ctx: &mut TxContext,
) {
    let interest_models = market::interest_models_mut(market);
    interest_model::add_interest_model<T>(
        interest_models,
        &admin_cap.interest_model_cap,
        interest_model_change,
        ctx,
    );
}

public fun create_risk_model_change<T>(
    admin_cap: &AdminCap,
    collateral_factor: u64, // exp. 70%,
    liquidation_factor: u64, // exp. 80%,
    liquidation_penalty: u64, // exp. 7%,
    liquidation_discount: u64, // exp. 5%,
    scale: u64,
    max_collateral_amount: u64,
    ctx: &mut TxContext,
): OneTimeLockValue<RiskModel> {
    let risk_model_change = risk_model::create_risk_model_change<T>(
        &admin_cap.risk_model_cap,
        collateral_factor, // exp. 70%,
        liquidation_factor, // exp. 80%,
        liquidation_penalty, // exp. 7%,
        liquidation_discount, // exp. 5%,
        scale,
        max_collateral_amount,
        admin_cap.risk_model_change_delay,
        ctx,
    );
    risk_model_change
}

public entry fun add_risk_model<T>(
    market: &mut Market,
    admin_cap: &AdminCap,
    risk_model_change: OneTimeLockValue<RiskModel>,
    ctx: &mut TxContext,
) {
    update_risk_model<T>(market, admin_cap, risk_model_change, ctx);
    market::register_collateral<T>(market);
}

public entry fun update_risk_model<T>(
    market: &mut Market,
    admin_cap: &AdminCap,
    risk_model_change: OneTimeLockValue<RiskModel>,
    ctx: &mut TxContext,
) {
    let risk_models = market::risk_models_mut(market);
    risk_model::add_risk_model<T>(
        risk_models,
        &admin_cap.risk_model_cap,
        risk_model_change,
        ctx,
    );
}

public entry fun add_limiter<T>(
    _admin_cap: &AdminCap,
    market: &mut Market,
    outflow_limit: u64,
    outflow_cycle_duration: u32,
    outflow_segment_duration: u32,
    _ctx: &mut TxContext,
) {
    let limiter = market::rate_limiter_mut(market);
    limiter::add_limiter<T>(
        limiter,
        outflow_limit,
        outflow_cycle_duration,
        outflow_segment_duration,
    );
}

public fun create_limiter_params_change<T>(
    admin_cap: &AdminCap,
    outflow_cycle_duration: u32,
    outflow_segment_duration: u32,
    ctx: &mut TxContext,
): OneTimeLockValue<LimiterUpdateParamsChange> {
    let one_time_lock_value = limiter::create_limiter_params_change<T>(
        outflow_cycle_duration,
        outflow_segment_duration,
        admin_cap.limiter_change_delay,
        ctx,
    );
    one_time_lock_value
}

public fun create_limiter_limit_change<T>(
    admin_cap: &AdminCap,
    outflow_limit: u64,
    ctx: &mut TxContext,
): OneTimeLockValue<LimiterUpdateLimitChange> {
    let one_time_lock_value = limiter::create_limiter_limit_change<T>(
        outflow_limit,
        admin_cap.limiter_change_delay,
        ctx,
    );
    one_time_lock_value
}

#[allow(unused_type_parameter)]
public entry fun apply_limiter_limit_change<T>(
    _admin_cap: &AdminCap,
    market: &mut Market,
    one_time_lock_value: OneTimeLockValue<LimiterUpdateLimitChange>,
    ctx: &mut TxContext,
) {
    let limiter = market::rate_limiter_mut(market);
    limiter::apply_limiter_limit_change(
        limiter,
        one_time_lock_value,
        ctx,
    );
}

#[allow(unused_type_parameter)]
public entry fun apply_limiter_params_change<T>(
    _admin_cap: &AdminCap,
    market: &mut Market,
    one_time_lock_value: OneTimeLockValue<LimiterUpdateParamsChange>,
    ctx: &mut TxContext,
) {
    let limiter = market::rate_limiter_mut(market);
    limiter::apply_limiter_params_change(
        limiter,
        one_time_lock_value,
        ctx,
    );
}

/// ======= management of asset active state =======
public entry fun set_base_asset_active_state<T>(
    _admin_cap: &AdminCap,
    market: &mut Market,
    is_active: bool,
) {
    market::set_base_asset_active_state<T>(market, is_active);
}

public entry fun set_collateral_active_state<T>(
    _admin_cap: &AdminCap,
    market: &mut Market,
    is_active: bool,
) {
    market::set_collateral_active_state<T>(market, is_active);
}

/// ======= take revenue =======
public entry fun take_revenue<T>(
    admin_cap: &AdminCap,
    market: &mut Market,
    amount: u64,
    ctx: &mut TxContext,
) {
    event::emit(TakeRevenueEvent {
        market: object::id(market),
        amount,
        coin_type: type_name::get<T>(),
        sender: tx_context::sender(ctx),
        recipient: admin_cap.reward_address,
    });

    let coin = market::take_revenue<T>(market, amount, ctx);
    transfer::public_transfer(coin, admin_cap.reward_address);
}

/// ======= take borrow fee =======
public entry fun take_borrow_fee<T>(
    admin_cap: &AdminCap,
    market: &mut Market,
    amount: u64,
    ctx: &mut TxContext,
) {
    event::emit(TakeBorrowFeeEvent {
        market: object::id(market),
        amount,
        coin_type: type_name::get<T>(),
        sender: tx_context::sender(ctx),
        recipient: admin_cap.reward_address,
    });

    let coin = market::take_borrow_fee<T>(market, amount, ctx);
    transfer::public_transfer(coin, admin_cap.reward_address);
}

/// ======= staking fee (XAUM) =======
public entry fun update_staking_fee(
    _admin_cap: &AdminCap,
    manager: &mut StakingManager,
    fee_numerator: u64,
    fee_denominator: u64,
    ctx: &mut TxContext,
) {
    assert!(fee_numerator <= fee_denominator, error::invalid_params_error());
    staking_manager::update_stake_fee(manager, fee_numerator, fee_denominator, ctx);
}

public entry fun update_unstaking_fee(
    _admin_cap: &AdminCap,
    manager: &mut StakingManager,
    fee_numerator: u64,
    fee_denominator: u64,
    ctx: &mut TxContext,
) {
    assert!(fee_numerator <= fee_denominator, error::invalid_params_error());
    staking_manager::update_unstake_fee(manager, fee_numerator, fee_denominator, ctx);
}

public entry fun take_staking_fee(
    admin_cap: &AdminCap,
    manager: &mut StakingManager,
    amount: u64,
    ctx: &mut TxContext,
) {
    event::emit(TakeStakingFeeEvent {
        manager: object::id(manager),
        amount,
        coin_type: type_name::get<COIN_XAUM>(),
        sender: tx_context::sender(ctx),
        recipient: admin_cap.reward_address,
    });

    let coin = staking_manager::take_stake_fee_coin(manager, amount, ctx);
    transfer::public_transfer(coin, admin_cap.reward_address);
}

/// ======= Management of obligation access keys
public entry fun add_lock_key<T: drop>(
    _admin_cap: &AdminCap,
    obligation_access_store: &mut ObligationAccessStore,
) {
    obligation_access::add_lock_key<T>(obligation_access_store);
}

public entry fun remove_lock_key<T: drop>(
    _admin_cap: &AdminCap,
    obligation_access_store: &mut ObligationAccessStore,
) {
    obligation_access::remove_lock_key<T>(obligation_access_store);
}

public entry fun add_reward_key<T: drop>(
    _admin_cap: &AdminCap,
    obligation_access_store: &mut ObligationAccessStore,
) {
    obligation_access::add_reward_key<T>(obligation_access_store);
}

public entry fun remove_reward_key<T: drop>(
    _admin_cap: &AdminCap,
    obligation_access_store: &mut ObligationAccessStore,
) {
    obligation_access::remove_reward_key<T>(obligation_access_store);
}

public entry fun update_borrow_fee<T: drop>(
    _admin_cap: &AdminCap,
    market: &mut Market,
    fee_numerator: u64,
    fee_denominator: u64,
) {
    assert!(fee_numerator <= fee_denominator, error::invalid_params_error());

    let market_uid_mut = market::uid_mut(market);
    let key = market_dynamic_keys::borrow_fee_key(type_name::get<T>());
    let fee = fixed_point32::create_from_rational(fee_numerator, fee_denominator);

    dynamic_field::remove_if_exists<BorrowFeeKey, FixedPoint32>(market_uid_mut, key);
    dynamic_field::add(market_uid_mut, key, fee);
}

public entry fun update_borrow_limit<T: drop>(
    _admin_cap: &AdminCap,
    market: &mut Market,
    limit_amount: u64,
) {
    let market_uid_mut = market::uid_mut(market);
    let key = market_dynamic_keys::borrow_limit_key(type_name::get<T>());

    dynamic_field::remove_if_exists<BorrowLimitKey, u64>(market_uid_mut, key);
    dynamic_field::add(market_uid_mut, key, limit_amount);
}

public entry fun update_isolated_asset_status<PoolType: drop>(
    _admin_cap: &AdminCap,
    market: &mut Market,
    is_isolated: bool,
) {
    let market_uid_mut = market::uid_mut(market);
    let key = market_dynamic_keys::isolated_asset_key(type_name::get<PoolType>());

    dynamic_field::remove_if_exists<IsolatedAssetKey, bool>(market_uid_mut, key);
    dynamic_field::add(market_uid_mut, key, is_isolated);
}

public entry fun set_gusd_cap(
    _admin_cap: &AdminCap,
    market: &mut Market,
    gusd_cap: TreasuryCap<COIN_GUSD>,
) {
    market::set_gusd_cap(market, gusd_cap);
}

public entry fun update_reward_address(
    admin_cap: &mut AdminCap,
    new_address: address,
    ctx: &mut TxContext,
) {
    let old_address = admin_cap.reward_address;
    admin_cap.reward_address = new_address;
    event::emit(RewardAddressUpdatedEvent {
        old_address,
        new_address,
        sender: tx_context::sender(ctx),
    });
}

public entry fun transfer_admin_cap(admin_cap: AdminCap, new_admin: address) {
    transfer::transfer(admin_cap, new_admin);
}

public entry fun set_flash_loan_single_cap(
    _admin_cap: &AdminCap,
    market: &mut Market,
    single_cap: u64,
) {
    market::set_flash_loan_single_cap(market, single_cap);
}
