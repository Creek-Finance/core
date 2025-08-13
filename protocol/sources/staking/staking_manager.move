/// Module: staking_manager
///
/// Manages staking of XAUM tokens in exchange for GR and GY tokens.
/// Supports staking, unstaking, and tracking of staked balances.
/// Interacts with GlobalConfig to access treasury caps for minting/burning.
module protocol::staking_manager;

use coin_gr::coin_gr::{Self, COIN_GR};
use coin_gy::coin_gy::{Self, COIN_GY};
use coin_xaum::coin_xaum::COIN_XAUM;
use global_config::global_config::{Self, GlobalConfig};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::event;

/// Error codes.
const E_INSUFFICIENT_XAUM: u64 = 1;
const E_INSUFFICIENT_GR_GY: u64 = 2;
const E_MISMATCHED_AMOUNTS: u64 = 5;

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
}

/// Event emitted when a user stakes XAUM.
public struct StakeEvent has copy, drop {
    user: address,
    xaum_amount: u64,
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

/// Initializes a new StakingManager and updates its address in GlobalConfig.
public entry fun init_staking_manager(config: &mut GlobalConfig, ctx: &mut TxContext) {
    let admin = tx_context::sender(ctx);
    let manager = StakingManager {
        id: object::new(ctx),
        admin,
        xaum_pool: balance::zero(),
    };
    let manager_address = object::id_address(&manager);

    global_config::update_staking_manager_id(config, manager_address, ctx);

    event::emit(ManagerCreated {
        manager_id: manager_address,
        admin,
    });

    transfer::share_object(manager);
}

/// Stakes XAUM in exchange for GR and GY at the fixed exchange rate.
public entry fun stake_xaum(
    config: &mut GlobalConfig,
    manager: &mut StakingManager,
    xaum_coin: Coin<COIN_XAUM>,
    ctx: &mut TxContext,
) {
    let user = tx_context::sender(ctx);
    let xaum_amount = coin::value(&xaum_coin);
    assert!(xaum_amount >= MIN_STAKE_AMOUNT, E_INSUFFICIENT_XAUM);

    let xaum_balance = coin::into_balance(xaum_coin);
    balance::join(&mut manager.xaum_pool, xaum_balance);

    let gr_amount = xaum_amount * EXCHANGE_RATE;
    let gy_amount = xaum_amount * EXCHANGE_RATE;

    let gr_coin = {
        let gr_treasury_cap = global_config::borrow_gr_treasury_cap(config);
        coin_gr::mint(gr_treasury_cap, gr_amount, ctx)
    };
    let gy_coin = {
        let gy_treasury_cap = global_config::borrow_gy_treasury_cap(config);
        coin_gy::mint(gy_treasury_cap, gy_amount, ctx)
    };

    transfer::public_transfer(gr_coin, user);
    transfer::public_transfer(gy_coin, user);

    event::emit(StakeEvent {
        user,
        xaum_amount,
        gr_minted: gr_amount,
        gy_minted: gy_amount,
    });
}

/// Unstakes by burning GR and GY to redeem XAUM.
public entry fun unstake(
    config: &mut GlobalConfig,
    manager: &mut StakingManager,
    gr_coin: Coin<COIN_GR>,
    gy_coin: Coin<COIN_GY>,
    ctx: &mut TxContext,
) {
    let user = tx_context::sender(ctx);
    let gr_amount = coin::value(&gr_coin);
    let gy_amount = coin::value(&gy_coin);

    assert!(gr_amount == gy_amount, E_MISMATCHED_AMOUNTS);

    let min_gr_gy_amount = MIN_STAKE_AMOUNT * EXCHANGE_RATE;
    assert!(gr_amount >= min_gr_gy_amount, E_INSUFFICIENT_GR_GY);

    let xaum_return_amount = gr_amount / EXCHANGE_RATE;
    assert!(balance::value(&manager.xaum_pool) >= xaum_return_amount, E_INSUFFICIENT_XAUM);

    {
        let gr_treasury_cap = global_config::borrow_gr_treasury_cap(config);
        coin::burn(gr_treasury_cap, gr_coin);
    };
    {
        let gy_treasury_cap = global_config::borrow_gy_treasury_cap(config);
        coin::burn(gy_treasury_cap, gy_coin);
    };

    let xaum_balance = balance::split(&mut manager.xaum_pool, xaum_return_amount);
    let xaum_coin = coin::from_balance(xaum_balance, ctx);
    transfer::public_transfer(xaum_coin, user);

    event::emit(UnstakeEvent {
        user,
        xaum_returned: xaum_return_amount,
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
