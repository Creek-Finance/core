/// @title GR Token with Supply-based Minting
/// @notice GR token earned through staking, using Supply mechanism instead of TreasuryCap
module coin_gr::coin_gr;

use sui::coin::{Self, Coin, TreasuryCap};

public struct COIN_GR has drop {}

fun init(witness: COIN_GR, ctx: &mut TxContext) {
    let admin = tx_context::sender(ctx);
    let (treasury_cap, metadata) = coin::create_currency(
        witness,
        9,
        b"GR",
        b"GR Token",
        b"GR is a reward token earned through XAUM staking, representing governance rights",
        option::none(),
        ctx,
    );
    transfer::public_transfer(treasury_cap, admin);
    transfer::public_transfer(metadata, admin);
}

public fun mint(cap: &mut TreasuryCap<COIN_GR>, amount: u64, ctx: &mut TxContext): Coin<COIN_GR> {
    coin::mint(cap, amount, ctx)
}

public fun burn(cap: &mut TreasuryCap<COIN_GR>, coin: Coin<COIN_GR>): u64 {
    coin::burn(cap, coin)
}
