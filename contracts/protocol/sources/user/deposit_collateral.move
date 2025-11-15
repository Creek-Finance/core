/// @title A module dedicated for handling the collateral deposit request from user
/// @author Creek Labs
module protocol::deposit_collateral;

use protocol::error;
use protocol::market::{Self, Market};
use protocol::obligation::{Self, Obligation};
use protocol::version::{Self, Version};
use std::type_name::{Self, TypeName};
use sui::coin::{Self, Coin};
use sui::event::emit;

public struct CollateralDepositEvent has copy, drop {
    provider: address,
    obligation: ID,
    deposit_asset: TypeName,
    deposit_amount: u64,
}

/// @notice Deposit collateral into the given obligation
/// @dev There's a overall collateral limit in the protocol configs, since market contains the configs, so market is also involved here
/// @param version The version control object, contract version must match with this
/// @param obligation The obligation object to deposit collateral
/// @param market The Creek market object, it contains base assets, and related protocol configs
/// @param coin The collateral to be deposited
/// @param ctx The SUI transaction context object
/// @custom:T The type of the collateral
public fun deposit_collateral<T>(
    version: &Version,
    obligation: &mut Obligation,
    market: &mut Market,
    deposit_coin: Coin<T>,
    ctx: &mut TxContext,
) {
    // check version
    version::assert_current_version(version);
    // global pause check
    assert!(!market::is_paused(market), error::market_paused_error());

    assert!(coin::value(&deposit_coin) > 0, error::zero_amount_error());

    // check if obligation is locked, if locked, unlock operation is required before calling this function
    // This is a mechanism to enforce some operations before calling the function
    assert!(obligation::deposit_collateral_locked(obligation) == false, error::obligation_locked());

    let coin_type = type_name::get<T>();
    // check if collateral state is active
    assert!(market::is_collateral_active(market, coin_type), error::collateral_not_active_error());

    // Make sure the protocol supports the collateral type
    let has_risk_model = market::has_risk_model(market, coin_type);
    assert!(has_risk_model == true, error::invalid_collateral_type_error());

    // Emit collateral deposit event
    emit(CollateralDepositEvent {
        provider: tx_context::sender(ctx),
        obligation: object::id(obligation),
        deposit_asset: coin_type,
        deposit_amount: coin::value(&deposit_coin),
    });

    // Update the total collateral amount in the market
    market::handle_add_collateral<T>(market, coin::value(&deposit_coin));

    // Put the collateral into the obligation
    obligation::deposit_collateral(obligation, coin::into_balance(deposit_coin))
}