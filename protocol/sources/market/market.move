module protocol::market;

use math::fixed_point32_empower;
use protocol::asset_active_state::{Self, AssetActiveStates};
use protocol::borrow_dynamics::{Self, BorrowDynamics, BorrowDynamic};
use protocol::collateral_stats::{Self, CollateralStats, CollateralStat};
use protocol::error;
use protocol::incentive_rewards::{Self, RewardFactors, RewardFactor};
use protocol::interest_model::{Self, InterestModels, InterestModel};
use protocol::limiter::{Self, Limiters, Limiter};
use protocol::market_dynamic_keys::{Self, IsolatedAssetKey};
use protocol::reserve::{Self, Reserve, MarketCoin, FlashLoan};
use protocol::risk_model::{Self, RiskModels, RiskModel};
use std::fixed_point32;
use std::type_name::{Self, TypeName, get};
use std::vector;
use sui::balance::Balance;
use sui::coin::Coin;
use sui::dynamic_field as df;
use sui::object::{Self, UID};
use sui::tx_context::TxContext;
use x::ac_table::{Self, AcTable, AcTableCap};
use x::wit_table::{Self, WitTable};
use x::witness::Witness;

public struct Market has key, store {
    id: UID,
    borrow_dynamics: WitTable<BorrowDynamics, TypeName, BorrowDynamic>,
    collateral_stats: WitTable<CollateralStats, TypeName, CollateralStat>,
    interest_models: AcTable<InterestModels, TypeName, InterestModel>,
    risk_models: AcTable<RiskModels, TypeName, RiskModel>,
    limiters: WitTable<Limiters, TypeName, Limiter>,
    reward_factors: WitTable<RewardFactors, TypeName, RewardFactor>,
    asset_active_states: AssetActiveStates,
    vault: Reserve,
}

public fun uid(market: &Market): &UID { &market.id }

public fun uid_mut_delegated(market: &mut Market, _: Witness<Market>): &mut UID { &mut market.id }

public(package) fun uid_mut(market: &mut Market): &mut UID { &mut market.id }

public fun borrow_dynamics(market: &Market): &WitTable<BorrowDynamics, TypeName, BorrowDynamic> {
    &market.borrow_dynamics
}

public fun interest_models(market: &Market): &AcTable<InterestModels, TypeName, InterestModel> {
    &market.interest_models
}

public fun vault(market: &Market): &Reserve { &market.vault }

public fun risk_models(market: &Market): &AcTable<RiskModels, TypeName, RiskModel> {
    &market.risk_models
}

public fun reward_factors(market: &Market): &WitTable<RewardFactors, TypeName, RewardFactor> {
    &market.reward_factors
}

public fun collateral_stats(market: &Market): &WitTable<CollateralStats, TypeName, CollateralStat> {
    &market.collateral_stats
}

public fun total_global_debt(market: &Market, pool_type: TypeName): u64 {
    let balance_sheet = wit_table::borrow(reserve::balance_sheets(&market.vault), pool_type);
    let (_, debt, _, _) = reserve::balance_sheet(balance_sheet);
    debt
}

public fun borrow_index(self: &Market, type_name: TypeName): u64 {
    borrow_dynamics::borrow_index_by_type(&self.borrow_dynamics, type_name)
}

public fun interest_model(self: &Market, type_name: TypeName): &InterestModel {
    ac_table::borrow(&self.interest_models, type_name)
}

public fun risk_model(self: &Market, type_name: TypeName): &RiskModel {
    ac_table::borrow(&self.risk_models, type_name)
}

public fun reward_factor(self: &Market, type_name: TypeName): &RewardFactor {
    wit_table::borrow(&self.reward_factors, type_name)
}

public fun has_risk_model(self: &Market, type_name: TypeName): bool {
    ac_table::contains(&self.risk_models, type_name)
}

public fun has_limiter(self: &Market, type_name: TypeName): bool {
    wit_table::contains(&self.limiters, type_name)
}

public fun is_base_asset_active(self: &Market, type_name: TypeName): bool {
    asset_active_state::is_base_asset_active(&self.asset_active_states, type_name)
}

public fun is_collateral_active(self: &Market, type_name: TypeName): bool {
    asset_active_state::is_collateral_active(&self.asset_active_states, type_name)
}

public fun is_isolated_asset(self: &Market, pool_type: TypeName): bool {
    let isolated_asset_key = market_dynamic_keys::isolated_asset_key(pool_type);
    if (!df::exists_<IsolatedAssetKey>(&self.id, isolated_asset_key)) {
        return false
    };
    *df::borrow<IsolatedAssetKey, bool>(&self.id, isolated_asset_key)
}

public(package) fun new(
    ctx: &mut TxContext,
): (Market, AcTableCap<InterestModels>, AcTableCap<RiskModels>) {
    let (interest_models, interest_models_cap) = interest_model::new(ctx);
    let (risk_models, risk_models_cap) = risk_model::new(ctx);
    let market = Market {
        id: object::new(ctx),
        borrow_dynamics: borrow_dynamics::new(ctx),
        collateral_stats: collateral_stats::new(ctx),
        interest_models,
        risk_models,
        limiters: limiter::init_table(ctx),
        reward_factors: incentive_rewards::init_table(ctx),
        asset_active_states: asset_active_state::new(ctx),
        vault: reserve::new(ctx),
    };
    (market, interest_models_cap, risk_models_cap)
}

public(package) fun handle_outflow<T>(self: &mut Market, outflow_value: u64, now: u64) {
    let key = type_name::get<T>();
    limiter::add_outflow(&mut self.limiters, key, now, outflow_value);
}

public(package) fun handle_inflow<T>(self: &mut Market, inflow_value: u64, now: u64) {
    let key = type_name::get<T>();
    limiter::reduce_outflow(&mut self.limiters, key, now, inflow_value);
}

public(package) fun set_base_asset_active_state<T>(self: &mut Market, is_active: bool) {
    let type_name = get<T>();
    asset_active_state::set_base_asset_active_state(
        &mut self.asset_active_states,
        type_name,
        is_active,
    );
}

public(package) fun set_collateral_active_state<T>(self: &mut Market, is_active: bool) {
    let type_name = get<T>();
    asset_active_state::set_collateral_active_state(
        &mut self.asset_active_states,
        type_name,
        is_active,
    );
}

public(package) fun register_coin<T>(self: &mut Market, now: u64) {
    let type_name = get<T>();
    reserve::register_coin<T>(&mut self.vault);
    let interest_model = ac_table::borrow(&self.interest_models, type_name);
    let base_borrow_rate = interest_model::base_borrow_rate(interest_model);
    let interest_rate_scale = interest_model::interest_rate_scale(interest_model);
    borrow_dynamics::register_coin<T>(
        &mut self.borrow_dynamics,
        base_borrow_rate,
        interest_rate_scale,
        now,
    );
    asset_active_state::set_base_asset_active_state(&mut self.asset_active_states, type_name, true);
}

public(package) fun register_collateral<T>(self: &mut Market) {
    let type_name = get<T>();
    collateral_stats::init_collateral_if_none(&mut self.collateral_stats, type_name);
    asset_active_state::set_collateral_active_state(&mut self.asset_active_states, type_name, true);
}

public(package) fun set_flash_loan_fee<T>(self: &mut Market, fee: u64) {
    reserve::set_flash_loan_fee<T>(&mut self.vault, fee)
}

public(package) fun risk_models_mut(
    self: &mut Market,
): &mut AcTable<RiskModels, TypeName, RiskModel> {
    &mut self.risk_models
}

public(package) fun interest_models_mut(
    self: &mut Market,
): &mut AcTable<InterestModels, TypeName, InterestModel> {
    &mut self.interest_models
}

public(package) fun rate_limiter_mut(
    self: &mut Market,
): &mut WitTable<Limiters, TypeName, Limiter> {
    &mut self.limiters
}

public(package) fun reward_factors_mut(
    self: &mut Market,
): &mut WitTable<RewardFactors, TypeName, RewardFactor> {
    &mut self.reward_factors
}

public(package) fun handle_borrow<T>(self: &mut Market, borrow_amount: u64, now: u64): Balance<T> {
    accrue_all_interests(self, now);
    let borrowed_balance = reserve::handle_borrow<T>(&mut self.vault, borrow_amount);
    update_interest_rates(self);
    borrowed_balance
}

public(package) fun handle_repay<T>(self: &mut Market, balance: Balance<T>) {
    reserve::handle_repay(&mut self.vault, balance);
    update_interest_rates(self);
}

public(package) fun handle_add_collateral<T>(self: &mut Market, collateral_amount: u64) {
    let type_name = get<T>();
    let risk_model = ac_table::borrow(&self.risk_models, type_name);
    collateral_stats::increase(&mut self.collateral_stats, type_name, collateral_amount);
    let total_collateral_amount = collateral_stats::collateral_amount(
        &self.collateral_stats,
        type_name,
    );
    let max_collateral_amount = risk_model::max_collateral_amount(risk_model);
    assert!(
        total_collateral_amount <= max_collateral_amount,
        error::max_collateral_reached_error(),
    );
}

public(package) fun handle_withdraw_collateral<T>(self: &mut Market, amount: u64, now: u64) {
    accrue_all_interests(self, now);
    collateral_stats::decrease(&mut self.collateral_stats, get<T>(), amount);
    update_interest_rates(self);
}

public(package) fun handle_liquidation<DebtType, CollateralType>(
    self: &mut Market,
    balance: Balance<DebtType>,
    revenue_balance: Balance<DebtType>,
    liquidate_amount: u64,
) {
    reserve::handle_liquidation(&mut self.vault, balance, revenue_balance);
    collateral_stats::decrease(&mut self.collateral_stats, get<CollateralType>(), liquidate_amount);
    update_interest_rates(self);
}

public(package) fun handle_redeem<T>(
    self: &mut Market,
    market_coin_balance: Balance<MarketCoin<T>>,
    now: u64,
): Balance<T> {
    accrue_all_interests(self, now);
    let redeem_balance = reserve::redeem_underlying_coin(&mut self.vault, market_coin_balance);
    update_interest_rates(self);
    redeem_balance
}

public(package) fun handle_mint<T>(
    self: &mut Market,
    balance: Balance<T>,
    now: u64,
): Balance<MarketCoin<T>> {
    accrue_all_interests(self, now);
    let mint_balance = reserve::mint_market_coin(&mut self.vault, balance);
    update_interest_rates(self);
    mint_balance
}

public(package) fun borrow_flash_loan<T>(
    self: &mut Market,
    amount: u64,
    ctx: &mut TxContext,
): (Coin<T>, FlashLoan<T>) {
    reserve::borrow_flash_loan<T>(&mut self.vault, amount, ctx)
}

public(package) fun repay_flash_loan<T>(self: &mut Market, coin: Coin<T>, loan: FlashLoan<T>) {
    reserve::repay_flash_loan(&mut self.vault, coin, loan)
}

public(package) fun compound_interests(self: &mut Market, now: u64) {
    accrue_all_interests(self, now);
    update_interest_rates(self);
}

public(package) fun take_revenue<T>(self: &mut Market, amount: u64, ctx: &mut TxContext): Coin<T> {
    reserve::take_revenue<T>(&mut self.vault, amount, ctx)
}

public(package) fun take_borrow_fee<T>(
    self: &mut Market,
    amount: u64,
    ctx: &mut TxContext,
): Coin<T> {
    reserve::take_borrow_fee<T>(&mut self.vault, amount, ctx)
}

public(package) fun add_borrow_fee<T>(self: &mut Market, balance: Balance<T>, ctx: &mut TxContext) {
    reserve::add_borrow_fee<T>(&mut self.vault, balance, ctx);
}

public(package) fun accrue_all_interests(self: &mut Market, now: u64) {
    let asset_types = reserve::asset_types(&self.vault);
    let n = vector::length(&asset_types);
    let mut i = 0;

    while (i < n) {
        let type_name = *vector::borrow(&asset_types, i);
        let last_updated = borrow_dynamics::last_updated_by_type(&self.borrow_dynamics, type_name);
        if (last_updated == now) {
            i = i + 1;
            continue;
        };

        let old_borrow_index = borrow_dynamics::borrow_index_by_type(
            &self.borrow_dynamics,
            type_name,
        );
        borrow_dynamics::update_borrow_index(&mut self.borrow_dynamics, type_name, now);
        let new_borrow_index = borrow_dynamics::borrow_index_by_type(
            &self.borrow_dynamics,
            type_name,
        );

        let debt_increase_rate = fixed_point32_empower::sub(
            fixed_point32::create_from_rational(new_borrow_index, old_borrow_index),
            fixed_point32_empower::from_u64(1),
        );

        let interest_model = ac_table::borrow(&self.interest_models, type_name);
        let revenue_factor = interest_model::revenue_factor(interest_model);

        reserve::increase_debt(&mut self.vault, type_name, debt_increase_rate, revenue_factor);

        i = i + 1;
    };
}

fun update_interest_rates(self: &mut Market) {
    let asset_types = reserve::asset_types(&self.vault);
    let mut i = 0;
    let n = vector::length(&asset_types);
    while (i < n) {
        let type_name = *vector::borrow(&asset_types, i);
        let util_rate = reserve::util_rate(&self.vault, type_name);
        let interest_model = ac_table::borrow(&self.interest_models, type_name);
        let (new_interest_rate, interest_rate_scale) = interest_model::calc_interest(
            interest_model,
            util_rate,
        );
        borrow_dynamics::update_interest_rate(
            &mut self.borrow_dynamics,
            type_name,
            new_interest_rate,
            interest_rate_scale,
        );
        i = i + 1;
    };
}
