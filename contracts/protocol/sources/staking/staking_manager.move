/// Module: staking_manager
///
/// Manages staking of XAUM tokens in exchange for GR and GY tokens.
/// Supports staking, unstaking, and tracking of staked balances.
/// Internally stores and manages GR and GY token supplies for security.
module protocol::staking_manager;

use coin_gr::coin_gr::{Self, COIN_GR};
use coin_gy::coin_gy::{Self, COIN_GY};
use test_coin::coin_xaum::COIN_XAUM;
use std::fixed_point32::{Self, FixedPoint32};
use sui::balance::{Self, Balance, Supply};
use sui::coin::{Self, Coin, TreasuryCap};
use sui::event;
use protocol::error;

/// Minimum stake amount: 0.001 XAUM (with 9 decimals).
const MIN_STAKE_AMOUNT: u64 = 1_000_000;

/// Exchange rate: 1 XAUM = 100 GR + 100 GY.
const EXCHANGE_RATE: u64 = 100;

/// Staking manager object.
public struct StakingManager has key {
    id: UID,
    admin: address,
    /// XAUM staking pool balance.
    xaum_pool: Balance<COIN_XAUM>,
    /// XAUM fee pool balance (accumulated fees from stake/unstake)
    xaum_fee_pool: Balance<COIN_XAUM>,
    /// Staking fee rate for XAUM, expressed as FixedPoint32 (numerator/denominator)
    stake_fee_rate: FixedPoint32,
    /// Unstaking fee rate for XAUM, expressed as FixedPoint32 (numerator/denominator)
    unstake_fee_rate: FixedPoint32,
    /// GR token supply - only StakingManager can mint GR
    gr_supply: Supply<COIN_GR>,
    /// GY token supply - only StakingManager can mint GY
    gy_supply: Supply<COIN_GY>,
}

/// Event emitted when a user stakes XAUM (includes fee details)
public struct StakeEvent has copy, drop {
    user: address,
    xaum_gross: u64,
    xaum_fee: u64,
    xaum_net: u64,
    gr_minted: u64,
    gy_minted: u64,
}

/// Event emitted when a user unstakes.
public struct UnstakeEvent has copy, drop {
    user: address,
    xaum_returned: u64,
    gr_burned: u64,
    gy_burned: u64,
}

/// Event emitted when a staking manager is created.
public struct ManagerCreated has copy, drop {
    manager_id: address,
    admin: address,
}

/// Initializes a new StakingManager with GR and GY TreasuryCaps.
/// The TreasuryCaps are converted to Supply and stored internally.
public fun init_staking_manager(
    gr_treasury_cap: TreasuryCap<COIN_GR>,
    gy_treasury_cap: TreasuryCap<COIN_GY>,
    ctx: &mut TxContext,
) {
    let admin = tx_context::sender(ctx);
    
    // Convert TreasuryCaps to Supply objects
    let gr_supply = coin_gr::treasury_into_supply(gr_treasury_cap);
    let gy_supply = coin_gy::treasury_into_supply(gy_treasury_cap);
    
    let manager = StakingManager {
        id: object::new(ctx),
        admin,
        xaum_pool: balance::zero(),
        xaum_fee_pool: balance::zero(),
        stake_fee_rate: fixed_point32::create_from_rational(0, 1),
        unstake_fee_rate: fixed_point32::create_from_rational(0, 1),
        gr_supply,
        gy_supply,
    };
    let manager_address = object::id_address(&manager);

    event::emit(ManagerCreated {
        manager_id: manager_address,
        admin,
    });

    transfer::share_object(manager);
}

/// Stakes XAUM in exchange for GR and GY at the fixed exchange rate.
public fun stake_xaum(
    manager: &mut StakingManager,
    xaum_coin: Coin<COIN_XAUM>,
    ctx: &mut TxContext,
) {
    let user = tx_context::sender(ctx);
    let xaum_amount = coin::value(&xaum_coin);
    assert!(xaum_amount >= MIN_STAKE_AMOUNT, error::staking_min_xaum_error());

    // staking fee
    let fee_amount = fixed_point32::multiply_u64(xaum_amount, manager.stake_fee_rate);
    assert!(xaum_amount > fee_amount, error::staking_fee_exceeds_amount_error());

    let mut xaum_balance = coin::into_balance(xaum_coin);
    let fee_balance = balance::split(&mut xaum_balance, fee_amount);
    balance::join(&mut manager.xaum_fee_pool, fee_balance);
    balance::join(&mut manager.xaum_pool, xaum_balance);

    let net_amount = xaum_amount - fee_amount;
    let gr_amount = net_amount * EXCHANGE_RATE;
    let gy_amount = net_amount * EXCHANGE_RATE;

    // Mint GR and GY tokens using internal supply objects
    let gr_coin = coin_gr::mint_from_supply(&mut manager.gr_supply, gr_amount, ctx);
    let gy_coin = coin_gy::mint_from_supply(&mut manager.gy_supply, gy_amount, ctx);

    transfer::public_transfer(gr_coin, user);
    transfer::public_transfer(gy_coin, user);

    event::emit(StakeEvent {
        user,
        xaum_gross: xaum_amount,
        xaum_fee: fee_amount,
        xaum_net: net_amount,
        gr_minted: gr_amount,
        gy_minted: gy_amount,
    });
}

/// Unstakes by burning GR and GY to redeem XAUM.
public fun unstake(
    manager: &mut StakingManager,
    gr_coin: Coin<COIN_GR>,
    gy_coin: Coin<COIN_GY>,
    ctx: &mut TxContext,
) {
    let user = tx_context::sender(ctx);
    let gr_amount = coin::value(&gr_coin);
    let gy_amount = coin::value(&gy_coin);

    assert!(gr_amount == gy_amount, error::staking_gr_gy_mismatch_error());

    let min_gr_gy_amount = MIN_STAKE_AMOUNT * EXCHANGE_RATE;
    assert!(gr_amount >= min_gr_gy_amount, error::staking_insufficient_gr_gy_error());

    let xaum_return_amount = gr_amount / EXCHANGE_RATE;
    assert!(balance::value(&manager.xaum_pool) >= xaum_return_amount, error::staking_pool_xaum_not_enough_error());

    // Burn GR and GY tokens using internal supply objects
    coin_gr::burn_to_supply(&mut manager.gr_supply, gr_coin);
    coin_gy::burn_to_supply(&mut manager.gy_supply, gy_coin);

    // Unstaking fee: deducted from the XAUM returned to user
    let mut xaum_balance = balance::split(&mut manager.xaum_pool, xaum_return_amount);
    let unstake_fee_amount = fixed_point32::multiply_u64(xaum_return_amount, manager.unstake_fee_rate);
    assert!(xaum_return_amount > unstake_fee_amount, error::staking_fee_exceeds_amount_error());
    if (unstake_fee_amount > 0) {
        let fee_part = balance::split(&mut xaum_balance, unstake_fee_amount);
        balance::join(&mut manager.xaum_fee_pool, fee_part);
    };
    let xaum_coin = coin::from_balance(xaum_balance, ctx);
    transfer::public_transfer(xaum_coin, user);

    event::emit(UnstakeEvent {
        user,
        xaum_returned: xaum_return_amount - unstake_fee_amount,
        gr_burned: gr_amount,
        gy_burned: gy_amount,
    });
}

/// Returns the XAUM balance in the staking pool.
public fun get_pool_balance(manager: &StakingManager): u64 {
    balance::value(&manager.xaum_pool)
}

/// Returns the admin address of the staking manager.
public fun get_admin(manager: &StakingManager): address {
    manager.admin
}

/// Returns the total supply of GR tokens.
public fun get_gr_total_supply(manager: &StakingManager): u64 {
    balance::supply_value(&manager.gr_supply)
}

/// Returns the total supply of GY tokens.
public fun get_gy_total_supply(manager: &StakingManager): u64 {
    balance::supply_value(&manager.gy_supply)
}

/// Returns the XAUM fee pool balance.
public fun get_fee_pool_balance(manager: &StakingManager): u64 {
    balance::value(&manager.xaum_fee_pool)
}

/// View for fee pool balance (for devInspect to read return value)
public fun read_fee_pool_balance(manager: &StakingManager): u64 {
    balance::value(&manager.xaum_fee_pool)
}

/// Event emitted when staking fee is taken by admin
public struct TakeStakeFeeEvent has copy, drop {
    manager: ID,
    amount: u64,
    sender: address,
}

/// Update staking fee rate (numerator/denominator) by admin
public fun update_stake_fee(
    manager: &mut StakingManager,
    numerator: u64,
    denominator: u64,
    ctx: &mut TxContext,
) {
    assert!(tx_context::sender(ctx) == manager.admin, error::staking_not_admin_error());
    assert!(denominator > 0 && numerator <= denominator, error::staking_invalid_params_error());
    manager.stake_fee_rate = fixed_point32::create_from_rational(numerator, denominator);
}

/// Update unstaking fee rate (numerator/denominator) by admin
public fun update_unstake_fee(
    manager: &mut StakingManager,
    numerator: u64,
    denominator: u64,
    ctx: &mut TxContext,
) {
    assert!(tx_context::sender(ctx) == manager.admin, error::staking_not_admin_error());
    assert!(denominator > 0 && numerator <= denominator, error::staking_invalid_params_error());
    manager.unstake_fee_rate = fixed_point32::create_from_rational(numerator, denominator);
}

/// Take staking XAUM fee from the fee pool by admin
public fun take_stake_fee(
    manager: &mut StakingManager,
    amount: u64,
    ctx: &mut TxContext,
) {
    assert!(tx_context::sender(ctx) == manager.admin, error::staking_not_admin_error());
    let fee_part = balance::split(&mut manager.xaum_fee_pool, amount);
    let fee_coin = coin::from_balance(fee_part, ctx);

    event::emit(TakeStakeFeeEvent {
        manager: object::id(manager),
        amount,
        sender: tx_context::sender(ctx),
    });

    transfer::public_transfer(fee_coin, tx_context::sender(ctx));
}

/// Internal helper: split fee pool and return Coin without admin gate or event.
/// Intended to be called by protocol::app which performs admin gating and event emission.
public fun take_stake_fee_coin(
    manager: &mut StakingManager,
    amount: u64,
    ctx: &mut TxContext,
): Coin<COIN_XAUM> {
    let fee_part = balance::split(&mut manager.xaum_fee_pool, amount);
    coin::from_balance(fee_part, ctx)
}

/// Event emitted when owner withdraws XAUM from pool
public struct OwnerWithdrawXAUMEvent has copy, drop {
    manager: ID,
    amount: u64,
    sender: address,
}

/// Event emitted when owner deposits XAUM back to pool
public struct OwnerDepositXAUMEvent has copy, drop {
    manager: ID,
    amount: u64,
    sender: address,
}

/// Owner-only: withdraw XAUM from staking pool to owner wallet
public fun owner_withdraw_xaum(
    manager: &mut StakingManager,
    amount: u64,
    ctx: &mut TxContext,
) {
    assert!(tx_context::sender(ctx) == manager.admin, error::staking_not_admin_error());
    assert!(balance::value(&manager.xaum_pool) >= amount, error::staking_pool_xaum_not_enough_error());

    let part = balance::split(&mut manager.xaum_pool, amount);
    let coin_out = coin::from_balance(part, ctx);

    event::emit(OwnerWithdrawXAUMEvent {
        manager: object::id(manager),
        amount,
        sender: tx_context::sender(ctx),
    });

    transfer::public_transfer(coin_out, tx_context::sender(ctx));
}

/// Owner-only: deposit XAUM from owner wallet into staking pool
public fun owner_deposit_xaum(
    manager: &mut StakingManager,
    xaum_coin: Coin<COIN_XAUM>,
    ctx: &mut TxContext,
) {
    assert!(tx_context::sender(ctx) == manager.admin, error::staking_not_admin_error());
    let xaum_balance = coin::into_balance(xaum_coin);
    let amount = balance::value(&xaum_balance);
    balance::join(&mut manager.xaum_pool, xaum_balance);

    event::emit(OwnerDepositXAUMEvent {
        manager: object::id(manager),
        amount,
        sender: tx_context::sender(ctx),
    });
}
