/// @title GY Token with Supply-based Minting
/// @notice GY token earned through staking, using Supply mechanism instead of TreasuryCap
module coin_gy::coin_gy;

use sui::coin::{Self, Coin, TreasuryCap};
use sui::balance::{Self, Supply};

public struct COIN_GY has drop {}

fun init(witness: COIN_GY, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = coin::create_currency(
        witness,
        9,
        b"GY",
        b"GY Token",
        b"GY is a yield token earned through XAUM staking, representing yield share",
        option::none(),
        ctx,
    );
    
    // Transfer TreasuryCap to deployer - will be given to StakingManager
    sui::transfer::public_transfer(treasury_cap, sui::tx_context::sender(ctx));
    sui::transfer::public_freeze_object(metadata);
}

/// Convert TreasuryCap to Supply - to be used by StakingManager during initialization
public fun treasury_into_supply(treasury_cap: TreasuryCap<COIN_GY>): Supply<COIN_GY> {
    coin::treasury_into_supply(treasury_cap)
}

/// Mint GY tokens from supply - Supply holder controls minting
public fun mint_from_supply(supply: &mut Supply<COIN_GY>, amount: u64, ctx: &mut TxContext): Coin<COIN_GY> {
    let balance = balance::increase_supply(supply, amount);
    coin::from_balance(balance, ctx)
}

/// Burn GY tokens and decrease supply
public fun burn_to_supply(supply: &mut Supply<COIN_GY>, coin: Coin<COIN_GY>): u64 {
    let balance = coin::into_balance(coin);
    balance::decrease_supply(supply, balance)
}


