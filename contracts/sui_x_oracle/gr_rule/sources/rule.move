module gr_rule::rule {
  use sui::clock::{Self, Clock};

  use coin_gr::coin_gr::COIN_GR;
  use x_oracle::price_feed;
  use x_oracle::x_oracle::{Self, XOraclePriceUpdateRequest};

  /// Placeholder rule for GR token
  /// The actual GR price is computed and overridden by x_oracle based on XAUM indicators
  /// This rule simplifies frontend integration by accepting a dummy price value (0)
  public struct Rule has drop {}

  /// Set primary price source for GR (dummy value, will be overridden by x_oracle)
  /// The x_oracle module internally computes GR price based on XAUM EMA120/EMA90
  public fun set_price_as_primary(
    request: &mut XOraclePriceUpdateRequest<COIN_GR>,
    clock: &Clock,
  ) {
    let now = clock::timestamp_ms(clock) / 1000;
    // Use 0 as placeholder since x_oracle overrides GR price with computed value
    let feed = price_feed::new(0, now);
    x_oracle::set_primary_price(Rule {}, request, feed);
  }

  /// Set secondary price source for GR (dummy value, optional)
  public fun set_price_as_secondary(
    request: &mut XOraclePriceUpdateRequest<COIN_GR>,
    clock: &Clock,
  ) {
    let now = clock::timestamp_ms(clock) / 1000;
    // Use 0 as placeholder since x_oracle overrides GR price with computed value
    let feed = price_feed::new(0, now);
    x_oracle::set_secondary_price(Rule {}, request, feed);
  }
}

