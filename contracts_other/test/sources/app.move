#[test_only]
module protocol_test::app_t;

use coin_gusd::coin_gusd::COIN_GUSD;
use protocol::app::{Self, AdminCap};
use protocol::market::Market;
use sui::test_scenario::{Self, Scenario};

public fun app_init(scenario: &mut Scenario): (Market, AdminCap) {
    app::init_t(test_scenario::ctx(scenario));
    let sender = test_scenario::sender(scenario);
    test_scenario::next_tx(scenario, sender);
    let adminCap = test_scenario::take_from_sender<AdminCap>(scenario);
    let mut market = test_scenario::take_shared<Market>(scenario);

    app::update_borrow_fee<COIN_GUSD>(
        &adminCap,
        &mut market,
        0,
        1,
    );

    app::update_borrow_fee<COIN_GUSD>(
        &adminCap,
        &mut market,
        0,
        1,
    );

    app::update_borrow_limit<COIN_GUSD>(
        &adminCap,
        &mut market,
        1_000_000 * sui::math::pow(10, 9),
    );

    (market, adminCap)
}
