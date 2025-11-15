/// @title GY Token with Supply-based Minting and DenyList Support
/// @notice GY token earned through staking, with blacklist (denylist) capability
module coin_gy::coin_gy;

use sui::balance::{Self, Supply};
use sui::coin::{Self, Coin, TreasuryCap, DenyCapV2};
use sui::coin_registry;
use sui::deny_list::DenyList;
use sui::event;

/// Struct: GY token type
public struct COIN_GY has drop {}

/// Event: address added to deny list
public struct AddressAddedToDenyListEvent has copy, drop {
    address: address,
}

/// Event: address removed from deny list
public struct AddressRemovedFromDenyListEvent has copy, drop {
    address: address,
}

/// Initialize GY token with DenyList (blacklist) support
fun init(witness: COIN_GY, ctx: &mut TxContext) {
    let admin = tx_context::sender(ctx);

    // Create regulated token via coin_registry
    let (mut currency, treasury_cap) = coin_registry::new_currency_with_otw(
        witness,
        9, // decimals
        b"GY".to_string(),
        b"Gold yield token".to_string(),
        b"Volatility token that captures gold price fluctuations for yield generation.".to_string(),
        b"https://i.ibb.co/kVbsrhbz/GY.png".to_string(),
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
public fun treasury_into_supply(treasury_cap: TreasuryCap<COIN_GY>): Supply<COIN_GY> {
    coin::treasury_into_supply(treasury_cap)
}

/// Mint GY tokens using Supply - caller must hold the Supply object
public fun mint_from_supply(
    supply: &mut Supply<COIN_GY>,
    amount: u64,
    ctx: &mut TxContext,
): Coin<COIN_GY> {
    let balance = balance::increase_supply(supply, amount);
    coin::from_balance(balance, ctx)
}

/// Burn GY tokens and reduce total supply
public fun burn_to_supply(supply: &mut Supply<COIN_GY>, coin: Coin<COIN_GY>): u64 {
    let balance = coin::into_balance(coin);
    balance::decrease_supply(supply, balance)
}

/// Add address to DenyList (blacklist)
public fun add_to_deny_list(
    denylist: &mut DenyList,
    denycap: &mut DenyCapV2<COIN_GY>,
    addr: address,
    ctx: &mut TxContext,
) {
    coin::deny_list_v2_add(denylist, denycap, addr, ctx);
    event::emit(AddressAddedToDenyListEvent { address: addr });
}

/// Remove address from DenyList (unblacklist)
public fun remove_from_deny_list(
    denylist: &mut DenyList,
    denycap: &mut DenyCapV2<COIN_GY>,
    addr: address,
    ctx: &mut TxContext,
) {
    coin::deny_list_v2_remove(denylist, denycap, addr, ctx);
    event::emit(AddressRemovedFromDenyListEvent { address: addr });
}

#[test_only]
public fun create_treasury_for_testing(ctx: &mut TxContext): TreasuryCap<COIN_GY> {
    let (treasury_cap, metadata) = coin::create_currency(
        COIN_GY {},
        9,
        b"GY",
        b"GY Token (test)",
        b"Test GY token for staking tests",
        option::none(),
        ctx,
    );
    sui::transfer::public_freeze_object(metadata);
    treasury_cap
}
