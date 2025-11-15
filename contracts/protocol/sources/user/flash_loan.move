module protocol::flash_loan;

use coin_gusd::coin_gusd::COIN_GUSD;
use protocol::error;
use protocol::market::{Self, Market};
use protocol::reserve::{Self, FlashLoan};
use protocol::version::{Self, Version};
use std::type_name::{Self, TypeName};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::event::emit;

public struct BorrowFlashLoanEvent has copy, drop {
    borrower: address,
    asset: TypeName,
    amount: u64,
    fee: u64,
}

public struct RepayFlashLoanEvent has copy, drop {
    borrower: address,
    asset: TypeName,
    amount: u64,
    fee: u64,
}

/// @notice Borrow flash loan
/// @dev Flash loan is a loan that is borrowed and repaid in the same transaction
/// @param version The version control object, contract version must match with this
/// @param market object, it contains base assets, and related protocol configs
/// @param amount The amount of flash loan to borrow
/// @param ctx The SUI transaction context object
/// @return The borrowed coin object and the flash loan hot potato object
/// @custom:T The type of asset to borrow
public fun borrow_flash_loan(
    version: &Version,
    market: &mut Market,
    amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (Coin<COIN_GUSD>, FlashLoan<COIN_GUSD>) {
    // global pause check
    assert!(!market::is_paused(market), error::market_paused_error());
    // check if version is supported
    version::assert_current_version(version);
    assert!(amount > 0, error::zero_amount_error());

    let (coin, receipt) = borrow_flash_loan_internal(
        market,
        amount,
        clock,
        ctx,
    );

    (coin, receipt)
}

fun borrow_flash_loan_internal(
    market: &mut Market,
    amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): (Coin<COIN_GUSD>, FlashLoan<COIN_GUSD>) {
    let now = clock::timestamp_ms(clock) / 1000;

    let coin_type = type_name::get<COIN_GUSD>();
    // check if base asset is active
    assert!(market::is_base_asset_active(market, coin_type), error::base_asset_not_active_error());

    let (coin, receipt) = market::borrow_flash_loan(market, amount, now, ctx);

    // Emit the borrow flash loan event
    emit(BorrowFlashLoanEvent {
        borrower: tx_context::sender(ctx),
        asset: coin_type,
        fee: reserve::flash_loan_fee(&receipt),
        amount,
    });

    // Return the borrowed coin object and the flash loan hot potato object
    (coin, receipt)
}

/// @notice Repay flash loan
/// @dev This is the only method to repay flash loan, consume the flash loan hot potato object
/// @param version The version control object, contract version must match with this
/// @param market object, it contains base assets, and related protocol configs
/// @param coin The coin object to repay
/// @param loan The flash loan hot potato object, which contains the borrowed amount and fee
/// @ctx The SUI transaction context object
/// @custom:T The type of asset to repay
public fun repay_flash_loan(
    version: &Version,
    market: &mut Market,
    repay_flash_coin: Coin<COIN_GUSD>,
    loan: FlashLoan<COIN_GUSD>,
    ctx: &mut TxContext,
) {
    // check if version is supported
    version::assert_current_version(version);
    assert!(!market::is_paused(market), error::market_paused_error());
    assert!(coin::value(&repay_flash_coin) > 0, error::zero_amount_error());

    // Emit the repay flash loan event
    emit(RepayFlashLoanEvent {
        borrower: tx_context::sender(ctx),
        asset: type_name::get<COIN_GUSD>(),
        amount: coin::value(&repay_flash_coin),
        fee: reserve::flash_loan_fee(&loan),
    });

    // Put the asset back to the market and consume the flash loan hot potato object
    market::repay_flash_loan(market, repay_flash_coin, loan, ctx);
}