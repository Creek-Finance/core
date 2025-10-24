/// @title GR Token with Supply-based Minting
/// @notice GR token earned through staking, using Supply mechanism instead of TreasuryCap
module coin_gr::coin_gr;

use sui::coin::{Self, Coin, TreasuryCap};
use sui::balance::{Self, Supply};

public struct COIN_GR has drop {}

fun init(witness: COIN_GR, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = coin::create_currency(
        witness,
        9,
        b"GR",
        b"GR Token",
        b"GR is a stability token pegged to gold's moving average price that captures gold's stable value.",
        option::none(),
        ctx,
    );
    
    // Transfer TreasuryCap to deployer - will be given to StakingManager
    sui::transfer::public_transfer(treasury_cap, sui::tx_context::sender(ctx));
    sui::transfer::public_freeze_object(metadata);
}

/// Convert TreasuryCap to Supply - to be used by StakingManager during initialization
public fun treasury_into_supply(treasury_cap: TreasuryCap<COIN_GR>): Supply<COIN_GR> {
    coin::treasury_into_supply(treasury_cap)
}

/// Mint GR tokens from supply - Supply holder controls minting
public fun mint_from_supply(supply: &mut Supply<COIN_GR>, amount: u64, ctx: &mut TxContext): Coin<COIN_GR> {
    let balance = balance::increase_supply(supply, amount);
    coin::from_balance(balance, ctx)
}

/// Burn GR tokens and decrease supply
public fun burn_to_supply(supply: &mut Supply<COIN_GR>, coin: Coin<COIN_GR>): u64 {
    let balance = coin::into_balance(coin);
    balance::decrease_supply(supply, balance)
}

#[test_only]
public fun create_treasury_for_testing(ctx: &mut TxContext): TreasuryCap<COIN_GR> {
    let (treasury_cap, metadata) = coin::create_currency(
        COIN_GR {},
        9,
        b"GR",
        b"GR Token (test)",
        b"Test GR token for staking tests",
        option::none(),
        ctx,
    );
    sui::transfer::public_freeze_object(metadata);
    treasury_cap
}


