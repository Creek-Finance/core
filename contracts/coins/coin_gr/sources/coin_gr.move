/// @title GR Token with Supply-based Minting and DenyList support
/// @notice GR token earned through staking, with blacklist (denylist) capability
module coin_gr::coin_gr;

use sui::balance::{Self, Supply};
use sui::coin::{Self, Coin, TreasuryCap, DenyCapV2};
use sui::coin_registry;
use sui::deny_list::DenyList;
use sui::event;

/// GR token type
public struct COIN_GR has drop {}

/// Event: address added to deny list
public struct AddressAddedToDenyListEvent has copy, drop {
    address: address,
}

/// Event: address removed from deny list
public struct AddressRemovedFromDenyListEvent has copy, drop {
    address: address,
}

/// Initialize GR token with blacklist (deny list) support
fun init(witness: COIN_GR, ctx: &mut TxContext) {
    let admin = tx_context::sender(ctx);

    // Use registry to create a regulated token that supports DenyList
    let (mut currency, treasury_cap) = coin_registry::new_currency_with_otw(
        witness,
        9, // decimals
        b"GR".to_string(),
        b"Gold reserve token".to_string(),
        b"Stability token that tracks gold moving average for value preservation.".to_string(),
        b"https://i.ibb.co/WpkTrHT9/GR.png".to_string(),
        ctx,
    );

    // Enable regulation -> returns DenyCapV2
    let deny_cap = currency.make_regulated(true, ctx);
    let metadata_cap = currency.finalize(ctx);

    // Transfer all capabilities to admin
    transfer::public_transfer(treasury_cap, admin);
    transfer::public_transfer(metadata_cap, admin);
    transfer::public_transfer(deny_cap, admin);
}

/// Convert TreasuryCap to Supply - for StakingManager or similar modules
public fun treasury_into_supply(treasury_cap: TreasuryCap<COIN_GR>): Supply<COIN_GR> {
    coin::treasury_into_supply(treasury_cap)
}

/// Mint GR tokens using Supply - caller must hold the supply object
public fun mint_from_supply(
    supply: &mut Supply<COIN_GR>,
    amount: u64,
    ctx: &mut TxContext,
): Coin<COIN_GR> {
    let balance = balance::increase_supply(supply, amount);
    coin::from_balance(balance, ctx)
}

/// Burn GR tokens and reduce total supply
public fun burn_to_supply(supply: &mut Supply<COIN_GR>, coin: Coin<COIN_GR>): u64 {
    let balance = coin::into_balance(coin);
    balance::decrease_supply(supply, balance)
}

/// Add address to deny list (blacklist)
public fun add_to_deny_list(
    denylist: &mut DenyList,
    denycap: &mut DenyCapV2<COIN_GR>,
    addr: address,
    ctx: &mut TxContext,
) {
    coin::deny_list_v2_add(denylist, denycap, addr, ctx);
    event::emit(AddressAddedToDenyListEvent { address: addr });
}

/// Remove address from deny list (unblacklist)
public fun remove_from_deny_list(
    denylist: &mut DenyList,
    denycap: &mut DenyCapV2<COIN_GR>,
    addr: address,
    ctx: &mut TxContext,
) {
    coin::deny_list_v2_remove(denylist, denycap, addr, ctx);
    event::emit(AddressRemovedFromDenyListEvent { address: addr });
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
