module coin_gusd::coin_gusd;

use sui::coin::{Self, Coin, TreasuryCap, DenyCapV2};
use sui::coin_registry;
use sui::deny_list::DenyList;
use sui::event;

/// Struct for GUSD token
public struct COIN_GUSD has drop {}

/// Event for when an address is added to the deny list
public struct AddressAddedToDenyListEvent has copy, drop {
    address: address,
}

/// Event for when an address is removed from the deny list
public struct AddressRemovedFromDenyListEvent has copy, drop {
    address: address,
}

/// Initialize GUSD currency with deny list support
fun init(witness: COIN_GUSD, ctx: &mut TxContext) {
    let admin = tx_context::sender(ctx);

    // Create regulated currency with DenyList capability
    let (mut currency, treasury_cap) = coin_registry::new_currency_with_otw(
        witness,
        9, // decimals
        b"GUSD".to_string(),
        b"Gold-backed USD token".to_string(),
        b"Stablecoin token that maintains USD parity through over-collateralized gold reserves.".to_string(),
        b"https://i.ibb.co/ZpM0fZqd/GUSD.png".to_string(),
        ctx,
    );

    // Make currency regulated and get DenyCapV2
    let deny_cap = currency.make_regulated(true, ctx);
    let metadata_cap = currency.finalize(ctx);

    // Transfer all capabilities to admin
    transfer::public_transfer(treasury_cap, admin);
    transfer::public_transfer(metadata_cap, admin);
    transfer::public_transfer(deny_cap, admin);
}

/// Mint GUSD tokens
public fun mint(
    cap: &mut TreasuryCap<COIN_GUSD>,
    amount: u64,
    ctx: &mut TxContext,
): Coin<COIN_GUSD> {
    coin::mint(cap, amount, ctx)
}

/// Burn GUSD tokens
public fun burn(cap: &mut TreasuryCap<COIN_GUSD>, coin: Coin<COIN_GUSD>): u64 {
    coin::burn(cap, coin)
}

/// Add address to deny list (blacklist)
public fun add_to_deny_list(
    denylist: &mut DenyList,
    denycap: &mut DenyCapV2<COIN_GUSD>,
    addr: address,
    ctx: &mut TxContext,
) {
    coin::deny_list_v2_add(denylist, denycap, addr, ctx);

    event::emit(AddressAddedToDenyListEvent {
        address: addr,
    });
}

/// Remove address from deny list (unblacklist)
public fun remove_from_deny_list(
    denylist: &mut DenyList,
    denycap: &mut DenyCapV2<COIN_GUSD>,
    addr: address,
    ctx: &mut TxContext,
) {
    coin::deny_list_v2_remove(denylist, denycap, addr, ctx);

    event::emit(AddressRemovedFromDenyListEvent {
        address: addr,
    });
}
