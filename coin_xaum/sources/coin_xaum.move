module coin_xaum::coin_xaum;

use sui::coin::{Self, Coin, TreasuryCap};
use sui::url::{Self, Url};

/// The type identifier of coin
public struct COIN_XAUM has drop {}

public struct GlobalMintCap has key {
    id: sui::object::UID,
    treasury_cap: TreasuryCap<COIN_XAUM>,
}

/// Module initializer is called once on module publish.
fun init(witness: COIN_XAUM, ctx: &mut sui::tx_context::TxContext) {
    let (treasury_cap, metadata) = coin::create_currency<COIN_XAUM>(
        witness,
        9,
        b"XAUM",
        b"XAUM Token",
        b"XAUM is the primary token for staking and earning rewards - Test Version (Anyone can mint)",
        std::option::some<Url>(url::new_unsafe_from_bytes(b"https://example.com/xaum-icon.png")),
        ctx,
    );

    // Create global casting permissions (shared objects)
    let global_mint_cap = GlobalMintCap {
        id: sui::object::new(ctx),
        treasury_cap,
    };

    // Transfer object
    sui::transfer::public_freeze_object(metadata);
    sui::transfer::share_object(global_mint_cap);
}

// Anyone can mint XAUM tokens (for testing purposes)
public entry fun mint(
    global_mint_cap: &mut GlobalMintCap,
    amount: u64,
    recipient: address,
    ctx: &mut sui::tx_context::TxContext,
) {
    // Mint tokens
    let coin = coin::mint(&mut global_mint_cap.treasury_cap, amount, ctx);
    sui::transfer::public_transfer(coin, recipient);
}

// / Destroy tokens
public entry fun burn(global_mint_cap: &mut GlobalMintCap, coin: Coin<COIN_XAUM>) {
    coin::burn(&mut global_mint_cap.treasury_cap, coin);
}
