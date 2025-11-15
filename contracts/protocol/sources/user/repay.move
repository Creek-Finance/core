/// @title Module for hanlding withdraw collateral request from user
/// @author Creek Labs
/// @notice User can withdarw collateral as long as the obligation risk level is lower than 1
module protocol::repay;

use coin_gusd::coin_gusd::COIN_GUSD;
use protocol::error;
use protocol::market::{Self, Market};
use protocol::obligation::{Self, Obligation};
use protocol::version::{Self, Version};
use std::type_name::{Self, TypeName};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::event::emit;
use sui::math;

public struct RepayEvent has copy, drop {
    repayer: address,
    obligation: ID,
    asset: TypeName,
    amount: u64,
    time: u64,
}

/// @notice Repay debt for an obligation using COIN_GUSD only
/// @dev Anyone can repay the debt of the obligation, not only the owner of the obligation.
///      If repay amount is more than the debt, the remaining amount will be refunded to the sender
/// @param version The version control object, contract version must match with this
/// @param obligation The Creek obligation object, debt will be decreased according to repay amount
/// @param market The Creek market object, it contains base assets, and related protocol configs
/// @param user_coin The coin object that user wants to repay
/// @param clock The SUI system clock object, used to get current timestamp
/// @param ctx The SUI transaction context object
/// @custom:T The type of asset that user wants to repay
public fun repay(
    version: &Version,
    obligation: &mut Obligation,
    market: &mut Market,
    mut user_coin: Coin<COIN_GUSD>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // global pause check
    assert!(!market::is_paused(market), error::market_paused_error());
    // Check contract version
    version::assert_current_version(version);

    assert!(coin::value(&user_coin) > 0, error::zero_repay_amount_error());

    // check if obligation is locked, if locked, unlock is needed before calling this
    // This is a mechanism to enforce some actions to be done before repay
    assert!(obligation::repay_locked(obligation) == false, error::obligation_locked());

    let now = clock::timestamp_ms(clock) / 1000;
    let coin_type = type_name::get<COIN_GUSD>();

    // always accrued all the interest before doing any actions
    // Because all actions should based on the latest state
    market::accrue_all_interests(market, now);
    obligation::accrue_interests_and_rewards(obligation, market);

    // If the given coin is more than the debt, repay the debt only
    let (debt_amount, _) = obligation::debt(obligation, coin_type);
    let repay_amount = math::min(debt_amount, coin::value(&user_coin));
    let repay_coin = coin::split<COIN_GUSD>(&mut user_coin, repay_amount, ctx);

    // Put the repay asset into market
    market::handle_repay<COIN_GUSD>(market, repay_coin, ctx);

    // Decrease repay amount to the outflow limiter
    market::handle_inflow<COIN_GUSD>(market, repay_amount, now);

    // Decrease debt of the obligation according to repay amount
    obligation::decrease_debt(obligation, coin_type, repay_amount);

    // Transfer the remaining asset back to the sender if any
    if (coin::value(&user_coin) == 0) {
        coin::destroy_zero(user_coin);
    } else {
        transfer::public_transfer(user_coin, tx_context::sender(ctx));
    };

    // Emit repay event
    emit(RepayEvent {
        repayer: tx_context::sender(ctx),
        obligation: object::id(obligation),
        asset: coin_type,
        amount: repay_amount,
        time: now,
    })
}