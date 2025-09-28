/// @title Module for handling the liquidation request
/// @author Creek Labs
/// @notice Creek adopts soft liquidation. Liquidation amount should be no bigger than the amount that would drecrease the risk level of obligation to 1.
module protocol::liquidate;

use coin_decimals_registry::coin_decimals_registry::CoinDecimalsRegistry;
use coin_gusd::coin_gusd::COIN_GUSD;
use protocol::error;
use protocol::liquidation_evaluator::liquidation_amounts;
use protocol::market::{Self, Market};
use protocol::obligation::{Self, Obligation};
use protocol::price;
use protocol::version::{Self, Version};
use std::fixed_point32::FixedPoint32;
use std::type_name::{Self, TypeName};
use sui::balance;
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::event::emit;
use x_oracle::x_oracle::XOracle;

#[allow(unused_field)]
public struct LiquidateEvent has copy, drop {
    liquidator: address,
    obligation: ID,
    debt_type: TypeName,
    collateral_type: TypeName,
    repay_on_behalf: u64,
    repay_revenue: u64,
    liq_amount: u64,
}

public struct LiquidateEventV2 has copy, drop {
    liquidator: address,
    obligation: ID,
    debt_type: TypeName,
    collateral_type: TypeName,
    repay_on_behalf: u64,
    repay_revenue: u64,
    liq_amount: u64,
    collateral_price: FixedPoint32,
    debt_price: FixedPoint32,
    timestamp: u64,
}

public entry fun liquidate_entry<CollateralType>(
    version: &Version,
    obligation: &mut Obligation,
    market: &mut Market,
    available_repay_coin: Coin<COIN_GUSD>,
    coin_decimals_registry: &CoinDecimalsRegistry,
    x_oracle: &XOracle,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // Try to liquidate the obligation
    let (remain_coin, collateral_coin) = liquidate<CollateralType>(
        version,
        obligation,
        market,
        available_repay_coin,
        coin_decimals_registry,
        x_oracle,
        clock,
        ctx,
    );
    // Transfer the remaining base asset back to the sender
    transfer::public_transfer(remain_coin, tx_context::sender(ctx));
    // Transfer the liquiated collateral to the sender
    transfer::public_transfer(collateral_coin, tx_context::sender(ctx));
}

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

    assert!(obligation::liquidate_locked(obligation) == false, error::obligation_locked());

    let mut available_repay_balance = coin::into_balance(available_repay_coin);
    let now = clock::timestamp_ms(clock) / 1000;

    // Accrue interests for market & obligation
    market::accrue_all_interests(market, now);
    obligation::accrue_interests_and_rewards(obligation, market);

    // calculate liquidation amounts
    // including repay_on_behalf, repay_revenue, liq_amount
    let available_repay_amount = balance::value(&available_repay_balance);
    let (repay_on_behalf, repay_revenue, liq_amount) = liquidation_amounts<
        COIN_GUSD,
        CollateralType,
    >(obligation, market, coin_decimals_registry, available_repay_amount, x_oracle, clock);

    assert!(liq_amount > 0, error::unable_to_liquidate_error());

    // withdraw collateral from obligation
    let collateral_balance = obligation::withdraw_collateral<CollateralType>(
        obligation,
        liq_amount,
    );

    // decrease debt from obligation
    obligation::decrease_debt(obligation, type_name::get<COIN_GUSD>(), repay_on_behalf);

    // handle liquidation in market & reserve
    let repay_on_behalf_balance = balance::split(&mut available_repay_balance, repay_on_behalf);
    let revenue_balance = balance::split(&mut available_repay_balance, repay_revenue);

    market::handle_liquidation<CollateralType>(
        market,
        repay_on_behalf_balance,
        revenue_balance,
        liq_amount,
        ctx,
    );

    emit(LiquidateEventV2 {
        liquidator: tx_context::sender(ctx),
        obligation: object::id(obligation),
        debt_type: type_name::get<COIN_GUSD>(),
        collateral_type: type_name::get<CollateralType>(),
        repay_on_behalf,
        repay_revenue,
        liq_amount,
        collateral_price: price::get_price(x_oracle, type_name::get<CollateralType>(), clock),
        debt_price: price::get_price(x_oracle, type_name::get<COIN_GUSD>(), clock),
        timestamp: now,
    });

    // return the remaining repay coin and the collateral coin
    (coin::from_balance(available_repay_balance, ctx), coin::from_balance(collateral_balance, ctx))
}
