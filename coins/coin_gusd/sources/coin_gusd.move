module coin_gusd::coin_gusd;

use sui::coin::{Self, Coin, TreasuryCap};

public struct COIN_GUSD has drop {}

fun init(witness: COIN_GUSD, ctx: &mut TxContext) {
    let admin = tx_context::sender(ctx);
    let (treasury_cap, metadata) = coin::create_currency(
        witness,
        9,
        b"GUSD",
        b"GUSD Token",
        b"GUSD is a stablecoin collateralized with GR tokens",
        option::none(),
        ctx,
    );
    transfer::public_transfer(treasury_cap, admin);
    transfer::public_transfer(metadata, admin);
}

public fun mint(cap: &mut TreasuryCap<COIN_GUSD>, amount: u64, ctx: &mut TxContext): Coin<COIN_GUSD> {
    coin::mint(cap, amount, ctx)
}

public fun burn(cap: &mut TreasuryCap<COIN_GUSD>, coin: Coin<COIN_GUSD>): u64 {
    coin::burn(cap, coin)
}


