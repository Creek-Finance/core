module manual_rule::rule {

  use sui::clock::{Self, Clock};

  use x_oracle::x_oracle::{ Self, XOraclePriceUpdateRequest };
  use x_oracle::price_feed;

  /// Marker rule type for manual pricing. Can be used as primary or secondary.
  struct Rule has drop {}

  /// Feed price directly as 9-decimal integer; timestamp is on-chain now (seconds)
  public fun set_price_as_primary<CoinType>(
    request: &mut XOraclePriceUpdateRequest<CoinType>,
    value_9dec: u64,
    clock: &Clock,
  ) {
    let now = clock::timestamp_ms(clock) / 1000;
    let feed = price_feed::new(value_9dec, now);
    x_oracle::set_primary_price(Rule {}, request, feed);
  }

  /// Feed price directly as 9-decimal integer; timestamp is on-chain now (seconds)
  public fun set_price_as_secondary<CoinType>(
    request: &mut XOraclePriceUpdateRequest<CoinType>,
    value_9dec: u64,
    clock: &Clock,
  ) {
    let now = clock::timestamp_ms(clock) / 1000;
    let feed = price_feed::new(value_9dec, now);
    x_oracle::set_secondary_price(Rule {}, request, feed);
  }
}