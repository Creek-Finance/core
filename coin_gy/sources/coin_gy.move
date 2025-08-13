/// @title GY Token with Supply-based Minting
/// @notice GY token earned through staking, using Supply mechanism instead of TreasuryCap
module coin_gy::coin_gy;

use sui::coin::{Self, Coin, TreasuryCap};

public struct COIN_GY has drop {}

fun init(witness: COIN_GY, ctx: &mut TxContext) {
    let admin = tx_context::sender(ctx);
    let (treasury_cap, metadata) = coin::create_currency(
        witness,
        9,
        b"GY",
        b"GY Token",
        b"GY is a yield token earned through XAUM staking, representing yield share",
        option::none(),
        ctx,
    );
    transfer::public_transfer(treasury_cap, admin);
    transfer::public_transfer(metadata, admin);
}

public fun mint(cap: &mut TreasuryCap<COIN_GY>, amount: u64, ctx: &mut TxContext): Coin<COIN_GY> {
    coin::mint(cap, amount, ctx)
}

public fun burn(cap: &mut TreasuryCap<COIN_GY>, coin: Coin<COIN_GY>): u64 {
    coin::burn(cap, coin)
}
