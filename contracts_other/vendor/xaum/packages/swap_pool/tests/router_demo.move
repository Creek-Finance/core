module swap_pool::router_demo;

use mmt_v3::pool as mmt;
use pyth::price_info as pyth;
use sui::clock::Clock;
use sui::coin;
use swap_pool::swap_pool;

public struct RouterState has key {
    id: UID,
    swap_cap: option::Option<swap_pool::SwapCap>,
    // other fields
}

fun init(ctx: &mut TxContext) {
    let state = RouterState {
        id: object::new(ctx),
        swap_cap: option::none(),
    };
    // transfer::transfer(state, ctx.sender());
    transfer::share_object(state);
}

entry fun deposit_swap_cap(state: &mut RouterState, cap: swap_pool::SwapCap) {
    state.swap_cap.fill(cap);
}

public fun do_swap<InCoinType, XAUM, PairTokenType>(
    router_state: &mut RouterState,
    swap_pool_state: &mut swap_pool::State,
    coin_in: &mut coin::Coin<InCoinType>,
    amount_in: u64,
    oracle_dex_pool: &mmt::Pool<XAUM, PairTokenType>,
    price_info_object: &pyth::PriceInfoObject,
    clock: &Clock,
    ctx: &mut TxContext,
): coin::Coin<XAUM> {
    let got = swap_pool::swap(
        swap_pool_state,
        router_state.swap_cap.borrow(),
        coin_in,
        amount_in,
        oracle_dex_pool,
        price_info_object,
        clock,
        ctx,
    );
    got
}
