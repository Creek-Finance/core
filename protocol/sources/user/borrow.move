/// @title A module dedicated for handling the borrow request from user
/// @author Creek Labs
module protocol::borrow;

use coin_decimals_registry::coin_decimals_registry::CoinDecimalsRegistry;
use coin_gusd::coin_gusd::COIN_GUSD;
use protocol::borrow_withdraw_evaluator;
use protocol::error;
use protocol::interest_model;
use protocol::market::{Self, Market};
use protocol::market_dynamic_keys::{Self, BorrowFeeKey, BorrowLimitKey};
use protocol::obligation::{Self, Obligation, ObligationKey};
use protocol::version::{Self, Version};
use std::fixed_point32::{Self, FixedPoint32};
use std::type_name::{Self, TypeName};
use sui::balance::Balance;
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::dynamic_field;
use sui::event::emit;
use x_oracle::x_oracle::XOracle;

#[allow(unused_field)]
public struct BorrowEvent has copy, drop {
    borrower: address,
    obligation: ID,
    asset: TypeName,
    amount: u64,
    time: u64,
}

#[allow(unused_field)]
public struct BorrowEventV2 has copy, drop {
    borrower: address,
    obligation: ID,
    asset: TypeName,
    amount: u64,
    borrow_fee: u64,
    time: u64,
}

public struct BorrowEventV3 has copy, drop {
    borrower: address,
    obligation: ID,
    asset: TypeName,
    amount: u64,
    borrow_fee: u64,
    borrow_fee_discount: u64,
    time: u64,
}

/// @notice Borrow a certain amount of asset from the protocol and transfer it to the sender
/// @dev This function is not composable, and is intended to be called by the frontend
/// @param version The version control object, contract version must match with this
/// @param obligation The obligation object which contains the collateral and debt information
/// @param obligation_key The key to prove the ownership the obligation object
/// @param market The Creek market object, it contains base assets, and related protocol configs
/// @param coin_decimals_registry The registry object which contains the decimal information of coins
/// @param borrow_amount The amount of asset to borrow
/// @param x_oracle The x-oracle object which provides the price of assets
/// @param clock The SUI system Clock object, 0x6
/// @param ctx The SUI transaction context object
/// @custom:T The type of the asset to borrow, such as 0x2::sui::SUI for SUI
public entry fun borrow_entry<T>(
    version: &Version,
    obligation: &mut Obligation,
    obligation_key: &ObligationKey,
    market: &mut Market,
    coin_decimals_registry: &CoinDecimalsRegistry,
    borrow_amount: u64,
    x_oracle: &XOracle,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // global pause check
    assert!(!market::is_paused(market), error::market_paused_error());
    let borrowed_coin = borrow<T>(
        version,
        obligation,
        obligation_key,
        market,
        coin_decimals_registry,
        borrow_amount,
        x_oracle,
        clock,
        ctx,
    );
    transfer::public_transfer(borrowed_coin, tx_context::sender(ctx));
}

/// @notice Borrow a certain amount of asset from the protocol
/// @dev This function is composable, third party contract call this method to borrow from Creek
/// @param version The version control object, contract version must match with this
/// @param obligation The obligation object which contains the collateral and debt information
/// @param obligation_key The key to prove the ownership the obligation object
/// @param market The Creek market object, it contains base assets, and related protocol configs
/// @param coin_decimals_registry The registry object which contains the decimal information of coins
/// @param borrow_amount The amount of asset to borrow
/// @param x_oracle The x-oracle object which provides the price of assets
/// @param clock The SUI system Clock object, 0x6
/// @param ctx The SUI transaction context object
/// @custom:T The type of the asset to borrow, such as 0x2::sui::SUI for SUI
/// @return borrowed assets
public fun borrow<T>(
    version: &Version,
    obligation: &mut Obligation,
    obligation_key: &ObligationKey,
    market: &mut Market,
    coin_decimals_registry: &CoinDecimalsRegistry,
    borrow_amount: u64,
    x_oracle: &XOracle,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<COIN_GUSD> {
    // check if version is supported
    version::assert_current_version(version);

    // global pause check
    assert!(!market::is_paused(market), error::market_paused_error());

    let borrow_fee_discount = 0;
    let (borrowed_coin) = borrow_internal<T>(
        obligation,
        obligation_key,
        market,
        coin_decimals_registry,
        borrow_amount,
        borrow_fee_discount,
        x_oracle,
        clock,
        ctx,
    );

    borrowed_coin
}

// @TODO: borrow fee store in an object
fun borrow_internal<T>(
    obligation: &mut Obligation,
    obligation_key: &ObligationKey,
    market: &mut Market,
    coin_decimals_registry: &CoinDecimalsRegistry,
    borrow_amount: u64,
    borrow_fee_discount: u64,
    x_oracle: &XOracle,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<COIN_GUSD> {
    // check if obligation is locked, if locked, unlock operation is required before calling this function
    assert!(obligation::borrow_locked(obligation) == false, error::obligation_locked());

    let coin_type = type_name::get<T>();

    // Ensure T is COIN_GUSD since only GUSD can be borrowed
    assert!(coin_type == type_name::get<COIN_GUSD>(), error::invalid_coin_type());

    let now = clock::timestamp_ms(clock) / 1000;

    // Check the ownership of the obligation
    obligation::assert_key_match(obligation, obligation_key);

    // Avoid the loop of collateralize and borrow of same assets
    assert!(
        !obligation::has_coin_x_as_collateral(obligation, coin_type),
        error::unable_to_borrow_a_collateral_coin(),
    );

    // Make sure the borrow amount is bigger than the minimum borrow amount
    let interest_model = market::interest_model(market, coin_type);
    let min_borrow_amount = interest_model::min_borrow_amount(interest_model);

    // Calculate the base borrow fee
    let base_borrow_fee_key = market_dynamic_keys::borrow_fee_key(type_name::get<T>());
    let base_borrow_fee_rate = dynamic_field::borrow<BorrowFeeKey, FixedPoint32>(
        market::uid(market),
        base_borrow_fee_key,
    );
    let base_borrow_fee_amount = fixed_point32::multiply_u64(borrow_amount, *base_borrow_fee_rate);

    assert!(
        borrow_amount > min_borrow_amount + base_borrow_fee_amount,
        error::borrow_too_small_error(),
    );

    // assert borrow limit
    let borrow_limit_key = market_dynamic_keys::borrow_limit_key(coin_type);
    let borrow_limit =
        *dynamic_field::borrow<BorrowLimitKey, u64>(market::uid(market), borrow_limit_key);
    let current_total_global_debt = market::total_global_debt(market, coin_type);
    assert!(
        current_total_global_debt + borrow_amount <= borrow_limit,
        error::borrow_limit_reached_error(),
    );

    // Add borrow amount to the outflow limiter, if limit is reached then abort
    market::handle_outflow<T>(market, borrow_amount, now);

    // Call mint_gusd to get Coin<COIN_GUSD>
    let mut borrowed_coin = market::mint_gusd(market, borrow_amount, now, ctx);

    // init debt if borrow for the first time
    obligation::init_debt(obligation, market, coin_type);

    // accrue interests & rewards for obligation
    obligation::accrue_interests_and_rewards(obligation, market);

    //     calc the maximum borrow amount
    // If borrow too much, abort
    let max_borrow_amount = borrow_withdraw_evaluator::max_borrow_amount<T>(
        obligation,
        market,
        coin_decimals_registry,
        x_oracle,
        clock,
    );
    assert!(borrow_amount <= max_borrow_amount, error::borrow_too_much_error());

    // increase the debt for obligation
    obligation::increase_debt(obligation, coin_type, borrow_amount);

    // make sure that their obligation still healthy, so users aren't borrowing over their collateral
    let collaterals_value = protocol::collateral_value::collaterals_value_usd_for_borrow(
        obligation,
        market,
        coin_decimals_registry,
        x_oracle,
        clock,
    );
    let debts_value = protocol::debt_value::debts_value_usd_with_weight(
        obligation,
        coin_decimals_registry,
        market,
        x_oracle,
        clock,
    );
    assert!(
        math::fixed_point32_empower::gt(collaterals_value, debts_value),
        error::borrow_too_much_error(),
    );

    // Split the borrow fee from borrowed coin
    let final_borrow_fee = coin::split(&mut borrowed_coin, base_borrow_fee_amount, ctx);

    let final_borrow_fee_balance: Balance<COIN_GUSD> = coin::into_balance(final_borrow_fee);

    // Add the borrow fee to the market
    market::add_borrow_fee<T>(market, final_borrow_fee_balance, ctx);

    // Emit the borrow event
    emit(BorrowEventV3 {
        borrower: tx_context::sender(ctx),
        obligation: object::id(obligation),
        asset: coin_type,
        amount: borrow_amount,
        borrow_fee: base_borrow_fee_amount,
        borrow_fee_discount,
        time: now,
    });

    // Return the borrowed coin
    borrowed_coin
}
