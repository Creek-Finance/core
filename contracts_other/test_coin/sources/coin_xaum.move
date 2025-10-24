module test_coin::coin_xaum;

use sui::coin::{Self, Coin, TreasuryCap};
use sui::url::{Self, Url};
use sui::event;

public struct COIN_XAUM has drop {}

// Mint event
public struct MintEvent has copy, drop {
    recipient: address,
    amount: u64,
}

public struct GlobalMintCap has key {
    id: sui::object::UID,
    treasury_cap: TreasuryCap<COIN_XAUM>,
}

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

    let global_mint_cap = GlobalMintCap { id: sui::object::new(ctx), treasury_cap };
    sui::transfer::public_freeze_object(metadata);
    sui::transfer::share_object(global_mint_cap);
}

public fun mint(
    global_mint_cap: &mut GlobalMintCap,
    amount: u64,
    recipient: address,
    ctx: &mut sui::tx_context::TxContext,
) {
    let coin = coin::mint(&mut global_mint_cap.treasury_cap, amount, ctx);
    sui::transfer::public_transfer(coin, recipient);
    
    // Emit mint event
    event::emit(MintEvent {
        recipient,
        amount,
    });
}

public fun burn(global_mint_cap: &mut GlobalMintCap, coin: Coin<COIN_XAUM>) {
    coin::burn(&mut global_mint_cap.treasury_cap, coin);
}

#[test_only]
public fun mint_coin_for_testing(
    global_mint_cap: &mut GlobalMintCap,
    amount: u64,
    ctx: &mut sui::tx_context::TxContext,
): Coin<COIN_XAUM> {
    coin::mint(&mut global_mint_cap.treasury_cap, amount, ctx)
}

#[test_only]
public fun create_global_mint_cap_for_testing(ctx: &mut sui::tx_context::TxContext) {
    let (treasury_cap, metadata) = coin::create_currency<COIN_XAUM>(
        COIN_XAUM {},
        9,
        b"XAUM",
        b"XAUM Token (test)",
        b"Test XAUM for staking tests",
        std::option::some<Url>(url::new_unsafe_from_bytes(b"https://example.com/xaum-test.png")),
        ctx,
    );
    let global_mint_cap = GlobalMintCap { id: sui::object::new(ctx), treasury_cap };
    sui::transfer::public_freeze_object(metadata);
    sui::transfer::share_object(global_mint_cap);
}


