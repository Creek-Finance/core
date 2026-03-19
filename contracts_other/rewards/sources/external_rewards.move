module rewards::external_rewards;

use rewards::admin::AdminCap;
use rewards::collateral_vault_rewards::{
    Self,
    RewardPool as CollateralRewardPool
};
use rewards::staking_pool_rewards::{Self, RewardPool as StakingRewardPool};
use std::type_name::{Self, TypeName};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::event;

// ========== 核心对象 ==========

/// 为特定代币 T 创建的独立金库
public struct TokenVault<phantom T> has key, store {
    id: UID,
    balance: Balance<T>,
}

// ========== 事件定义 ==========

/// 存款事件
public struct DepositEvent has copy, drop {
    vault_id: ID,
    coin_type: TypeName,
    amount: u64,
    depositor: address,
}

/// 分配到 StakingRewardPool 事件
public struct DistributeStakingPoolEvent has copy, drop {
    vault_id: ID,
    coin_type: TypeName,
    amount: u64,
    staking_pool_id: ID,
    setter: address,
}

/// 分配到 CollateralRewardPool 事件
public struct DistributeCollateralVaultEvent has copy, drop {
    vault_id: ID,
    coin_type: TypeName,
    amount: u64,
    collateral_pool_id: ID,
    setter: address,
}

/// 紧急提取事件
public struct EmergencyWithdrawEvent has copy, drop {
    vault_id: ID,
    coin_type: TypeName,
    amount: u64,
    recipient: address,
}

/// 添加金库事件
public struct TokenVaultCreatedEvent has copy, drop {
    vault_id: ID,
    coin_type: TypeName,
    creator: address,
}

// ========== Admin 权限函数 ==========

/// 为一种新的代币 T 添加金库支持
public fun add_token_support<T>(_admin_cap: &AdminCap, ctx: &mut TxContext) {
    let vault = TokenVault<T> {
        id: object::new(ctx),
        balance: balance::zero<T>(),
    };
    let vault_id = object::id(&vault);
    transfer::share_object(vault);
    event::emit(TokenVaultCreatedEvent {
        vault_id,
        coin_type: type_name::with_defining_ids<T>(),
        creator: tx_context::sender(ctx),
    });
}

/// 将金库中的部分资金分配给 StakingPoolRewards 合约
public fun distribute_rewards_staking_pool<T>(
    _admin_cap: &AdminCap,
    vault: &mut TokenVault<T>,
    amount: u64,
    staking_reward_pool: &mut StakingRewardPool<T>,
    ctx: &mut TxContext,
) {
    if (amount > 0) {
        let staking_coins = coin::from_balance(balance::split(&mut vault.balance, amount), ctx);
        event::emit(DistributeStakingPoolEvent {
            vault_id: object::id(vault),
            coin_type: type_name::with_defining_ids<T>(),
            amount,
            staking_pool_id: object::id(staking_reward_pool),
            setter: tx_context::sender(ctx),
        });
        staking_pool_rewards::deposit_reward_funds<T>(staking_reward_pool, staking_coins, ctx);
    }
}

/// 将金库中的部分资金分配给 CollateralVaultRewards 合约
public fun distribute_rewards_collateral_vault<T>(
    _admin_cap: &AdminCap,
    vault: &mut TokenVault<T>,
    amount: u64,
    collateral_reward_pool: &mut CollateralRewardPool<T>,
    ctx: &mut TxContext,
) {
    if (amount > 0) {
        let collateral_coins = coin::from_balance(balance::split(&mut vault.balance, amount), ctx);
        event::emit(DistributeCollateralVaultEvent {
            vault_id: object::id(vault),
            coin_type: type_name::with_defining_ids<T>(),
            amount,
            collateral_pool_id: object::id(collateral_reward_pool),
            setter: tx_context::sender(ctx),
        });
        collateral_vault_rewards::deposit_reward_funds<T>(
            collateral_reward_pool,
            collateral_coins,
            ctx,
        );
    }
}

/// 紧急提取金库中的所有资金
#[allow(lint(self_transfer))]
public fun emergency_withdraw<T>(
    _admin_cap: &AdminCap,
    vault: &mut TokenVault<T>,
    ctx: &mut TxContext,
) {
    let total_balance = balance::value(&vault.balance);
    if (total_balance > 0) {
        let all_coins = coin::from_balance(balance::split(&mut vault.balance, total_balance), ctx);
        event::emit(EmergencyWithdrawEvent {
            vault_id: object::id(vault),
            coin_type: type_name::with_defining_ids<T>(),
            amount: total_balance,
            recipient: tx_context::sender(ctx),
        });
        transfer::public_transfer(all_coins, tx_context::sender(ctx));
    }
}

// ========== 公共函数 ==========

/// 存入任何受支持的代币
public entry fun deposit<T>(vault: &mut TokenVault<T>, deposit: Coin<T>, ctx: &mut TxContext) {
    let amount = coin::value(&deposit);
    balance::join(&mut vault.balance, coin::into_balance(deposit));
    event::emit(DepositEvent {
        vault_id: object::id(vault),
        coin_type: type_name::with_defining_ids<T>(),
        amount,
        depositor: tx_context::sender(ctx),
    });
}

// ========== 查询函数 ==========

/// 查询金库余额
public fun get_vault_balance<T>(vault: &TokenVault<T>): u64 {
    balance::value(&vault.balance)
}
