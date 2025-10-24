module protocol::gusd_usdc_vault;

use coin_gusd::coin_gusd::COIN_GUSD;
use math::u64;
use protocol::market::{Self, Market};
use sui::balance::{Self, Balance};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::event;
use sui::tx_context::sender;
use test_coin::usdc::USDC;

// Error codes
const E_INSUFFICIENT_BALANCE: u64 = 1;
const E_INVALID_AMOUNT: u64 = 2;
const E_NOT_ADMIN: u64 = 3;

// Vault structure, stores USDC balance, team address and fee rate
public struct USDCVault has key, store {
    id: UID,
    usdc_balance: Balance<USDC>, // Only stores USDC balance
    team_address: address,
    fee_rate: u64, // Fee rate, scaled by 10000 (0.3% = 30)
    admin: address,
}

// Event: GUSD minted
public struct MintEvent has copy, drop {
    user: address,
    amount: u64,
}

// Event: GUSD redeemed
public struct RedeemEvent has copy, drop {
    user: address,
    gusd_amount: u64,
    redeemed_usdc: u64,
    fee: u64,
}

// Event: Admin updated
public struct AdminUpdatedEvent has copy, drop {
    old_admin: address,
    new_admin: address,
}

// Initialize vault, set team address and admin address
fun init(ctx: &mut TxContext) {
    let vault = USDCVault {
        id: object::new(ctx),
        usdc_balance: balance::zero<USDC>(),
        team_address: sender(ctx),
        fee_rate: 30, // Default fee rate = 0.3%
        admin: sender(ctx),
    };
    transfer::share_object(vault);
}

// Mint GUSD, only accepts USDC, calls the Market module
public fun mint_gusd(
    vault: &mut USDCVault,
    market: &mut Market,
    usdc: Coin<USDC>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let amount = coin::value(&usdc);
    assert!(amount > 0, E_INVALID_AMOUNT);

    let now = clock::timestamp_ms(clock) / 1000;

    // Deposit USDC into vault
    balance::join(&mut vault.usdc_balance, coin::into_balance(usdc));

    // Call Market::mint_gusd
    let gusd = market::mint_gusd(market, amount, now, ctx);
    transfer::public_transfer(gusd, sender(ctx));

    // Emit mint event
    event::emit(MintEvent {
        user: sender(ctx),
        amount,
    });
}

// Redeem GUSD, burn GUSD to receive USDC, deducting 0.3% fee
public fun redeem_gusd(
    vault: &mut USDCVault,
    market: &mut Market,
    gusd: Coin<COIN_GUSD>,
    ctx: &mut TxContext,
) {
    let amount = coin::value(&gusd);
    assert!(amount > 0, E_INVALID_AMOUNT);

    // Check if vault has enough USDC
    let available_usdc = balance::value(&vault.usdc_balance);

    let fee = u64::mul_div(amount, vault.fee_rate, 10000);
    let redeem_amount = amount - fee;
    assert!(available_usdc >= redeem_amount, E_INSUFFICIENT_BALANCE);

    // Burn GUSD in Market
    market::burn_gusd(market, gusd, ctx);

    // Transfer USDC back to user
    let redeem_balance = balance::split(&mut vault.usdc_balance, redeem_amount);
    let redeem_coin = coin::from_balance(redeem_balance, ctx);
    transfer::public_transfer(redeem_coin, sender(ctx));

    // Transfer fee to team address
    if (fee > 0) {
        let fee_balance = balance::split(&mut vault.usdc_balance, fee);
        let fee_coin = coin::from_balance(fee_balance, ctx);
        transfer::public_transfer(fee_coin, vault.team_address);
    };

    // Emit redeem event
    event::emit(RedeemEvent {
        user: sender(ctx),
        gusd_amount: amount, // original GUSD sent by user
        redeemed_usdc: redeem_amount, // amount of USDC user receives
        fee,
    });
}

// Query vault USDC balance
public fun get_vault_balance(vault: &USDCVault): u64 {
    balance::value(&vault.usdc_balance)
}

// Query team address
public fun get_team_address(vault: &USDCVault): address {
    vault.team_address
}

// Query fee rate
public fun get_fee_rate(vault: &USDCVault): u64 {
    vault.fee_rate
}

// Admin: update team address
public fun update_team_address(
    vault: &mut USDCVault,
    new_address: address,
    ctx: &mut TxContext,
) {
    assert!(sender(ctx) == vault.admin, E_NOT_ADMIN);
    vault.team_address = new_address;
}

// Admin: update fee rate
public fun update_fee_rate(vault: &mut USDCVault, new_fee_rate: u64, ctx: &mut TxContext) {
    assert!(sender(ctx) == vault.admin, E_NOT_ADMIN);
    vault.fee_rate = new_fee_rate;
}

// Admin: update admin address
public fun update_admin(vault: &mut USDCVault, new_admin: address, ctx: &mut TxContext) {
    assert!(sender(ctx) == vault.admin, E_NOT_ADMIN);

    let old_admin = vault.admin;
    vault.admin = new_admin;

    event::emit(AdminUpdatedEvent {
        old_admin,
        new_admin,
    });
}
