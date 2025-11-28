module gusd_rule::rule {
  use sui::clock::{Self, Clock};

  use coin_gusd::coin_gusd::COIN_GUSD;
  use x_oracle::price_feed;
  use x_oracle::x_oracle::{Self, XOraclePriceUpdateRequest};

  const ONE_USD_9DEC: u64 = 1_000_000_000;

  /// Fixed $1 USD price rule for GUSD only
  public struct Rule has drop {}

  /// Set primary price source to fixed 1 USD (9 decimals)
  public fun set_price_as_primary(
    request: &mut XOraclePriceUpdateRequest<COIN_GUSD>,
    clock: &Clock,
  ) {
    let now = clock::timestamp_ms(clock) / 1000;
    let feed = price_feed::new(ONE_USD_9DEC, now);
    x_oracle::set_primary_price(Rule {}, request, feed);
  }

  /// Set secondary price source to fixed 1 USD (optional)
  public fun set_price_as_secondary(
    request: &mut XOraclePriceUpdateRequest<COIN_GUSD>,
    clock: &Clock,
  ) {
    let now = clock::timestamp_ms(clock) / 1000;
    let feed = price_feed::new(ONE_USD_9DEC, now);
    x_oracle::set_secondary_price(Rule {}, request, feed);
  }
}

