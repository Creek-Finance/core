module gr_price_query::price_query {

    use std::type_name;
    use sui::clock::{Self as clock, Clock};
    use sui::table;
    use x_oracle::price_feed;
    use x_oracle::x_oracle::{Self as x_oracle, XOracle};

    const E_PRICE_NOT_FOUND: u64 = 0;
    const E_STALE_PRICE: u64 = 1;

    /// Read cached oracle price (u64, 9 decimals) for `CoinType`.
    /// This uses the stored feeds in `x_oracle::x_oracle::prices`.
    public fun get_price_u64<CoinType>(x: &XOracle, clock: &Clock): u64 {
        let prices = x_oracle::prices(x);
        let type_name = type_name::with_defining_ids<CoinType>();
        assert!(table::contains(prices, type_name), E_PRICE_NOT_FOUND);
        let pf = table::borrow(prices, type_name);
        let now = clock::timestamp_ms(clock) / 1000;
        let last = price_feed::last_updated(pf);
        assert!(now == last, E_STALE_PRICE);
        price_feed::value(pf)
    }
}

