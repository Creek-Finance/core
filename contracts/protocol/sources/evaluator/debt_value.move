module protocol::debt_value;

use coin_decimals_registry::coin_decimals_registry::{Self, CoinDecimalsRegistry};
use math::fixed_point32_empower;
use protocol::obligation::{Self, Obligation};
use protocol::price::get_price;
use protocol::value_calculator::usd_value;
use std::fixed_point32::FixedPoint32;
use sui::clock::Clock;
use x_oracle::x_oracle::XOracle;

public fun debts_value_usd(
    obligation: &Obligation,
    coin_decimals_registry: &CoinDecimalsRegistry,
    x_oracle: &XOracle,
    clock: &Clock,
): FixedPoint32 {
    let debt_types = obligation::debt_types(obligation);
    let mut total_value_usd = fixed_point32_empower::zero();
    let mut i = 0;
    let n = vector::length(&debt_types);
    while (i < n) {
        let debt_type = *vector::borrow(&debt_types, i);
        let decimals = coin_decimals_registry::decimals(coin_decimals_registry, debt_type);
        let (debt_amount, _, _) = obligation::debt(obligation, debt_type);
        let coin_price = get_price(x_oracle, debt_type, clock);
        let coin_value_in_usd = usd_value(coin_price, debt_amount, decimals);
        total_value_usd = fixed_point32_empower::add(total_value_usd, coin_value_in_usd);
        i = i + 1;
    };
    total_value_usd
}
