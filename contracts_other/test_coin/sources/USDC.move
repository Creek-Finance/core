module test_coin::usdc {
  use sui::tx_context::TxContext;
  use sui::coin::{Self, TreasuryCap, Coin};
  use std::option;
  use sui::tx_context;
  use sui::math::pow;
  use sui::object::UID;
  use sui::transfer;
  use sui::object;
  use sui::event;
  
  public struct USDC has drop {}
  
  // Mint event
  public struct MintEvent has copy, drop {
    recipient: address,
    amount: u64,
  }
  public struct Treasury has key { id: UID, cap: TreasuryCap<USDC> }
  fun init(wtiness: USDC, ctx: &mut TxContext) {
    let decimals = 9u8;
    let symbol = b"USDC";
    let name = b"USDC";
    let description = b"Test USDC";
    let icon_url_option = option::none();
    let (mut treasuryCap, coinMeta) = coin::create_currency(
      wtiness, decimals, symbol, name, description, icon_url_option, ctx);
    let sender = tx_context::sender(ctx);
    coin::mint_and_transfer(&mut treasuryCap, pow(10, decimals + 3), sender, ctx);
    transfer::share_object(Treasury { id: object::new(ctx), cap: treasuryCap });
    transfer::public_freeze_object(coinMeta)
  }
  public fun mint(
    treasury: &mut Treasury,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
  ) {
    let coin = coin::mint(&mut treasury.cap, amount, ctx);
    transfer::public_transfer(coin, recipient);
    
    // Emit mint event
    event::emit(MintEvent {
      recipient,
      amount,
    });
  }

  public fun burn(treasury: &mut Treasury, coin: Coin<USDC>) {
    coin::burn(&mut treasury.cap, coin);
  }
}

