module rewards::internal_rewards;

use rewards::admin::{AdminCap, KeeperRegistry};
use rewards::staking_pool_rewards::{Self, RewardPool};
use std::type_name::{Self, TypeName};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::event;
use sui::sui::SUI;

// ========== 错误码 ==========
const E_INSUFFICIENT_FUNDS: u64 = 1;
const E_INVALID_PROPORTIONS: u64 = 2;

// ========== 核心对象 ==========

/// 奖励分配比例 (单位: 基点, 1% = 100 bps)
public struct RewardProportions has key, store {
    id: UID,
    staking_pool_rewards_bps: u64,
    external_partner_rewards_bps: u64,
    insurance_fund_bps: u64,
    team_bps: u64,
}

/// 资金分配的目标地址
public struct RewardDestinations has key, store {
    id: UID,
    external_partner_rewards_addr: address,
    insurance_fund_addr: address,
    team_addr: address,
}

/// 为 SUI 准备的专属金库
public struct InternalSuiVault has key, store {
    id: UID,
    balance: Balance<SUI>,
}

// ========== 事件定义 ==========

/// 存款事件
public struct DepositEvent has copy, drop {
    vault_id: ID,
    coin_type: TypeName,
    amount: u64,
    depositor: address,
}

/// 紧急提取事件
public struct EmergencyWithdrawEvent has copy, drop {
    vault_id: ID,
    coin_type: TypeName,
    amount: u64,
    recipient: address,
}

/// 分配事件
public struct DistributeSuiRewardsEvent has copy, drop {
    vault_id: ID,
    staking_pool_amount: u64,
    external_partner_amount: u64,
    insurance_fund_amount: u64,
    team_amount: u64,
    external_partner_addr: address,
    insurance_fund_addr: address,
    team_addr: address,
    setter: address,
}

/// 比例更新事件
public struct ProportionsUpdatedEvent has copy, drop {
    proportions_id: ID,
    old_staking_bps: u64,
    old_external_bps: u64,
    old_insurance_bps: u64,
    new_staking_bps: u64,
    new_external_bps: u64,
    new_insurance_bps: u64,
    setter: address,
}

/// 目标地址更新事件
public struct DestinationsUpdatedEvent has copy, drop {
    destinations_id: ID,
    old_external_partner_addr: address,
    old_insurance_fund_addr: address,
    old_team_addr: address,
    new_external_partner_addr: address,
    new_insurance_fund_addr: address,
    new_team_addr: address,
    setter: address,
}

// ========== 初始化函数 ==========

fun init(ctx: &mut TxContext) {
    transfer::share_object(RewardProportions {
        id: object::new(ctx),
        staking_pool_rewards_bps: 3500,
        external_partner_rewards_bps: 3500,
        insurance_fund_bps: 1500,
        team_bps: 1500,
    });

    transfer::share_object(RewardDestinations {
        id: object::new(ctx),
        external_partner_rewards_addr: @0x0,
        insurance_fund_addr: @0x0,
        team_addr: @0x0,
    });

    transfer::share_object(InternalSuiVault {
        id: object::new(ctx),
        balance: balance::zero<SUI>(),
    });
}

// ========== 公共存款函数 ==========

/// 存入 SUI
public entry fun deposit_sui(
    vault: &mut InternalSuiVault,
    deposit: Coin<SUI>,
    ctx: &mut TxContext,
) {
    let amount = coin::value(&deposit);
    balance::join(&mut vault.balance, coin::into_balance(deposit));
    event::emit(DepositEvent {
        vault_id: object::id(vault),
        coin_type: type_name::with_defining_ids<SUI>(),
        amount,
        depositor: tx_context::sender(ctx),
    });
}

// ========== Admin 权限函数 ==========

/// 修改奖励分配比例
public fun update_proportions(
    _admin_cap: &AdminCap,
    proportions: &mut RewardProportions,
    new_staking_bps: u64,
    new_external_bps: u64,
    new_insurance_bps: u64,
    ctx: &mut TxContext,
) {
    assert!(new_staking_bps + new_external_bps + new_insurance_bps == 8500, E_INVALID_PROPORTIONS);

    let old_staking_bps = proportions.staking_pool_rewards_bps;
    let old_external_bps = proportions.external_partner_rewards_bps;
    let old_insurance_bps = proportions.insurance_fund_bps;

    proportions.staking_pool_rewards_bps = new_staking_bps;
    proportions.external_partner_rewards_bps = new_external_bps;
    proportions.insurance_fund_bps = new_insurance_bps;

    event::emit(ProportionsUpdatedEvent {
        proportions_id: object::id(proportions),
        old_staking_bps,
        old_external_bps,
        old_insurance_bps,
        new_staking_bps,
        new_external_bps,
        new_insurance_bps,
        setter: tx_context::sender(ctx),
    });
}

/// 修改资金分配的目标地址
public fun update_destinations(
    _admin_cap: &AdminCap,
    destinations: &mut RewardDestinations,
    new_external_partner_addr: address,
    new_insurance_fund_addr: address,
    new_team_addr: address,
    ctx: &mut TxContext,
) {
    let old_external_partner_addr = destinations.external_partner_rewards_addr;
    let old_insurance_fund_addr = destinations.insurance_fund_addr;
    let old_team_addr = destinations.team_addr;

    destinations.external_partner_rewards_addr = new_external_partner_addr;
    destinations.insurance_fund_addr = new_insurance_fund_addr;
    destinations.team_addr = new_team_addr;

    event::emit(DestinationsUpdatedEvent {
        destinations_id: object::id(destinations),
        old_external_partner_addr,
        old_insurance_fund_addr,
        old_team_addr,
        new_external_partner_addr,
        new_insurance_fund_addr,
        new_team_addr,
        setter: tx_context::sender(ctx),
    });
}

/// 紧急提取 SUI
#[allow(lint(self_transfer))]
public fun emergency_withdraw_sui(
    _admin_cap: &AdminCap,
    vault: &mut InternalSuiVault,
    ctx: &mut TxContext,
) {
    let total_balance = balance::value(&vault.balance);
    if (total_balance > 0) {
        let coins = coin::from_balance(balance::split(&mut vault.balance, total_balance), ctx);
        event::emit(EmergencyWithdrawEvent {
            vault_id: object::id(vault),
            coin_type: type_name::with_defining_ids<SUI>(),
            amount: total_balance,
            recipient: tx_context::sender(ctx),
        });
        transfer::public_transfer(coins, tx_context::sender(ctx));
    }
}

// ========== Keeper 权限函数 ==========

/// 执行 SUI 分配
fun distribute_sui_rewards_internal(
    vault: &mut InternalSuiVault,
    proportions: &RewardProportions,
    destinations: &RewardDestinations,
    reward_pool: &mut RewardPool<SUI>,
    ctx: &mut TxContext,
) {
    let total_balance = balance::value(&vault.balance);
    assert!(total_balance > 0, E_INSUFFICIENT_FUNDS);

    let total_bps = 10000;

    let staking_amount = total_balance * proportions.staking_pool_rewards_bps / total_bps;
    let external_amount = total_balance * proportions.external_partner_rewards_bps / total_bps;
    let insurance_amount = total_balance * proportions.insurance_fund_bps / total_bps;
    let team_amount = total_balance * proportions.team_bps / total_bps;

    event::emit(DistributeSuiRewardsEvent {
        vault_id: object::id(vault),
        staking_pool_amount: staking_amount,
        external_partner_amount: external_amount,
        insurance_fund_amount: insurance_amount,
        team_amount,
        external_partner_addr: destinations.external_partner_rewards_addr,
        insurance_fund_addr: destinations.insurance_fund_addr,
        team_addr: destinations.team_addr,
        setter: tx_context::sender(ctx),
    });

    if (staking_amount > 0) {
        let staking_coins = coin::from_balance(
            balance::split(&mut vault.balance, staking_amount),
            ctx,
        );
        staking_pool_rewards::deposit_reward_funds<SUI>(reward_pool, staking_coins, ctx);
    };

    if (external_amount > 0) {
        let external_coins = coin::from_balance(
            balance::split(&mut vault.balance, external_amount),
            ctx,
        );
        transfer::public_transfer(external_coins, destinations.external_partner_rewards_addr);
    };

    if (insurance_amount > 0) {
        let insurance_coins = coin::from_balance(
            balance::split(&mut vault.balance, insurance_amount),
            ctx,
        );
        transfer::public_transfer(insurance_coins, destinations.insurance_fund_addr);
    };

    if (team_amount > 0) {
        let team_coins = coin::from_balance(balance::split(&mut vault.balance, team_amount), ctx);
        transfer::public_transfer(team_coins, destinations.team_addr);
    };
}

/// Admin 执行 SUI 分配
public entry fun distribute_sui_rewards_by_admin(
    _admin_cap: &AdminCap,
    vault: &mut InternalSuiVault,
    proportions: &RewardProportions,
    destinations: &RewardDestinations,
    reward_pool: &mut RewardPool<SUI>,
    ctx: &mut TxContext,
) {
    distribute_sui_rewards_internal(vault, proportions, destinations, reward_pool, ctx);
}

/// Keeper 执行 SUI 分配
public entry fun distribute_sui_rewards_by_keeper(
    keep_registry: &KeeperRegistry,
    vault: &mut InternalSuiVault,
    proportions: &RewardProportions,
    destinations: &RewardDestinations,
    reward_pool: &mut RewardPool<SUI>,
    ctx: &mut TxContext,
) {
    rewards::admin::assert_keeper(keep_registry, ctx);
    distribute_sui_rewards_internal(vault, proportions, destinations, reward_pool, ctx);
}

// ========== 查询函数 ==========

/// 查询 SUI 金库余额
public fun get_sui_vault_balance(vault: &InternalSuiVault): u64 {
    balance::value(&vault.balance)
}

/// 查询奖励分配比例
public fun get_proportions(proportions: &RewardProportions): (u64, u64, u64, u64) {
    (
        proportions.staking_pool_rewards_bps,
        proportions.external_partner_rewards_bps,
        proportions.insurance_fund_bps,
        proportions.team_bps,
    )
}

/// 查询配置地址
public fun get_destinations(destinations: &RewardDestinations): (address, address, address) {
    (
        destinations.external_partner_rewards_addr,
        destinations.insurance_fund_addr,
        destinations.team_addr,
    )
}
