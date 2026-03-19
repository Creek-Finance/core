module rewards::collateral_vault_rewards;

use rewards::admin::{AdminCap, KeeperRegistry};
use std::type_name::{Self, TypeName};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::event;
use sui::table::{Self, Table};

// ========== 错误码 ==========
const E_NO_REWARD_TO_CLAIM: u64 = 1;
const E_INVALID_INPUT_LENGTH: u64 = 2;
const E_INSUFFICIENT_BALANCE_IN_POOL: u64 = 3;

// ========== 核心对象 ==========

/// 奖励池，管理一种特定代币 T 的奖励
public struct RewardPool<phantom T> has key, store {
    id: UID,
    // 资金库，存放所有待分发的类型为 T 的奖励代币
    vault: Balance<T>,
    // 记录每个用户的待领取奖励
    rewards: Table<address, Balance<T>>,
}

// ========== 事件定义 ==========

/// 存款事件
public struct DepositRewardFundsEvent has copy, drop {
    pool_id: ID,
    coin_type: TypeName,
    amount: u64,
    depositor: address,
}

/// 领取奖励事件
public struct ClaimRewardEvent has copy, drop {
    pool_id: ID,
    coin_type: TypeName,
    amount: u64,
    recipient: address,
}

/// 紧急提取事件
public struct EmergencyWithdrawEvent has copy, drop {
    pool_id: ID,
    coin_type: TypeName,
    amount: u64,
    recipient: address,
}

/// 设置奖励事件
public struct SetRewardsEvent has copy, drop {
    pool_id: ID,
    coin_type: TypeName,
    recipients: vector<address>,
    amounts: vector<u64>,
    setter: address,
}

// ========== Admin 权限函数 ==========

/// 为一种新的代币 T 添加奖励支持
public fun add_reward_token<T>(_admin_cap: &AdminCap, ctx: &mut TxContext) {
    transfer::share_object(RewardPool<T> {
        id: object::new(ctx),
        vault: balance::zero<T>(),
        rewards: table::new<address, Balance<T>>(ctx),
    });
}

/// Admin 紧急提取资金
#[allow(lint(self_transfer))]
public fun emergency_withdraw<T>(
    _admin_cap: &AdminCap,
    pool: &mut RewardPool<T>,
    ctx: &mut TxContext,
) {
    let total_balance = balance::value(&pool.vault);
    if (total_balance > 0) {
        let all_coins = coin::from_balance(balance::split(&mut pool.vault, total_balance), ctx);
        event::emit(EmergencyWithdrawEvent {
            pool_id: object::id(pool),
            coin_type: type_name::with_defining_ids<T>(),
            amount: total_balance,
            recipient: tx_context::sender(ctx),
        });
        transfer::public_transfer(all_coins, tx_context::sender(ctx));
    }
}

// ========== Admin 和 Keeper 权限函数 ==========

/// 设置或增加多个用户的奖励（内部函数）
fun set_rewards_internal<T>(
    pool: &mut RewardPool<T>,
    recipients: vector<address>,
    amounts: vector<u64>,
    ctx: &TxContext,
) {
    assert!(vector::length(&recipients) == vector::length(&amounts), E_INVALID_INPUT_LENGTH);

    let mut i = 0;
    while (i < vector::length(&recipients)) {
        let recipient = *vector::borrow(&recipients, i);
        let amount = *vector::borrow(&amounts, i);

        assert!(balance::value(&pool.vault) >= amount, E_INSUFFICIENT_BALANCE_IN_POOL);

        let reward_balance = balance::split(&mut pool.vault, amount);

        if (table::contains(&pool.rewards, recipient)) {
            let user_reward_balance = table::borrow_mut(&mut pool.rewards, recipient);
            balance::join(user_reward_balance, reward_balance);
        } else {
            table::add(&mut pool.rewards, recipient, reward_balance);
        };
        i = i + 1;
    };

    event::emit(SetRewardsEvent {
        pool_id: object::id(pool),
        coin_type: type_name::with_defining_ids<T>(),
        recipients,
        amounts,
        setter: tx_context::sender(ctx),
    });
}

/// Admin 设置奖励的入口函数
public entry fun set_rewards_by_admin<T>(
    _admin_cap: &AdminCap,
    pool: &mut RewardPool<T>,
    recipients: vector<address>,
    amounts: vector<u64>,
    ctx: &mut TxContext,
) {
    set_rewards_internal(pool, recipients, amounts, ctx);
}

/// Keeper 设置奖励的入口函数
public entry fun set_rewards_by_keeper<T>(
    keep_registry: &KeeperRegistry,
    pool: &mut RewardPool<T>,
    recipients: vector<address>,
    amounts: vector<u64>,
    ctx: &mut TxContext,
) {
    rewards::admin::assert_keeper(keep_registry, ctx);
    set_rewards_internal(pool, recipients, amounts, ctx);
}

// ========== 公共函数 ==========

/// 存入奖励资金
public entry fun deposit_reward_funds<T>(
    pool: &mut RewardPool<T>,
    deposit: Coin<T>,
    ctx: &mut TxContext,
) {
    let amount = coin::value(&deposit);
    balance::join(&mut pool.vault, coin::into_balance(deposit));
    event::emit(DepositRewardFundsEvent {
        pool_id: object::id(pool),
        coin_type: type_name::with_defining_ids<T>(),
        amount,
        depositor: tx_context::sender(ctx),
    });
}

/// 用户领取自己的奖励
public entry fun claim_reward<T>(pool: &mut RewardPool<T>, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);
    assert!(table::contains(&pool.rewards, sender), E_NO_REWARD_TO_CLAIM);

    let reward_balance = table::remove(&mut pool.rewards, sender);
    let reward_amount = balance::value(&reward_balance);
    assert!(reward_amount > 0, E_NO_REWARD_TO_CLAIM);

    let reward_coin = coin::from_balance(reward_balance, ctx);
    transfer::public_transfer(reward_coin, sender);

    event::emit(ClaimRewardEvent {
        pool_id: object::id(pool),
        coin_type: type_name::with_defining_ids<T>(),
        amount: reward_amount,
        recipient: sender,
    });
}

// ========== 查询函数 ==========

/// 查询指定地址的待领取奖励金额
public fun get_pending_reward<T>(pool: &RewardPool<T>, user: address): u64 {
    if (table::contains(&pool.rewards, user)) {
        balance::value(table::borrow(&pool.rewards, user))
    } else {
        0
    }
}

/// 查询奖励池的资金库余额
public fun get_vault_balance<T>(pool: &RewardPool<T>): u64 {
    balance::value(&pool.vault)
}
