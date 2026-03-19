#[test_only]
module swap_pool::swap_pool_tests;

use std::type_name;
use sui::clock;
use sui::coin;
use sui::package::{test_publish, UpgradeCap};
use sui::test_scenario;
use sui::test_utils::assert_eq;
use swap_pool::swap_pool::{Self, State, SwapCap};

// test addresses
const OWNER: address = @0xAD;
const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;

// test Coins
public struct XAUM has drop {}
public struct USDC has drop {}

fun init_swap_pool(): test_scenario::Scenario {
    let mut scenario = test_scenario::begin(OWNER);
    swap_pool::init_for_testing(scenario.ctx());
    scenario
}

#[test, expected_failure(abort_code = swap_pool::ENotOwner)]
fun init_upgrade_cap_id_err_not_owner() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<State>();
        let upgrade_cap = test_publish(object::id_from_address(@0x1234), scenario.ctx());
        swap_pool::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = swap_pool::EUpgradeCapInvalid)]
fun init_upgrade_cap_id_err_not_matching() {
    let mut scenario = init_swap_pool();

    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        let upgrade_cap = test_publish(object::id_from_address(@0x1234), scenario.ctx());
        swap_pool::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = swap_pool::EUpgradeCapIdNotNone)]
fun init_upgrade_cap_id_err_not_none() {
    let mut scenario = init_swap_pool();

    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        let upgrade_cap = test_publish(
            state.package_address().to_id(),
            scenario.ctx(),
        );
        swap_pool::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx()); // ok
        swap_pool::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx()); // error!
    };
    abort
}

#[test]
fun init_upgrade_cap_id_ok() {
    let mut scenario = init_swap_pool();

    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        let upgrade_cap = test_publish(
            state.package_address().to_id(),
            scenario.ctx(),
        );
        swap_pool::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx()); // ok
        assert_eq(state.upgrade_cap_id(), option::some(object::id(&upgrade_cap)));
        transfer::public_share_object(upgrade_cap);
        test_scenario::return_shared(state);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = swap_pool::ENotOwner)]
fun set_owner_err_not_owner() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<swap_pool::State>();
        let upgrade_cap = test_publish(
            state.package_address().to_id(),
            scenario.ctx(),
        );
        swap_pool::transfer_ownership(&mut state, ALICE, upgrade_cap, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = swap_pool::EUpgradeCapInvalid)]
fun set_owner_err_upgrade_cap_invalid() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<swap_pool::State>();
        let upgrade_cap = test_publish(object::id_from_address(@0x1234), scenario.ctx());
        swap_pool::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx());

        let upgrade_cap2 = test_publish(object::id_from_address(@0x1234), scenario.ctx());
        swap_pool::transfer_ownership(&mut state, ALICE, upgrade_cap2, scenario.ctx());
    };
    abort
}

#[test]
fun set_owner_ok() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        let upgrade_cap = test_publish(
            state.package_address().to_id(),
            scenario.ctx(),
        );
        swap_pool::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx());
        swap_pool::transfer_ownership(&mut state, ALICE, upgrade_cap, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // check upgrade cap
    scenario.next_tx(ALICE);
    {
        let state = scenario.take_shared<State>();
        let upgrade_cap = scenario.take_from_sender<UpgradeCap>();
        assert_eq(upgrade_cap.package(), state.package_address().to_id());
        scenario.return_to_sender(upgrade_cap);
        test_scenario::return_shared(state);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = swap_pool::ENotOwner)]
fun set_operator_err_not_owner() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_operator(&mut state, ALICE, scenario.ctx());
    };
    abort
}

#[test]
fun set_operator_ok() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_operator(&mut state, ALICE, scenario.ctx());
        assert_eq(state.operator(), ALICE);
        test_scenario::return_shared(state);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = swap_pool::ENotOwner)]
fun set_coin_holder_err_not_owner() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_coin_holder(&mut state, ALICE, scenario.ctx());
    };
    abort
}

#[test]
fun set_coin_holder_ok() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_coin_holder(&mut state, ALICE, scenario.ctx());
        assert_eq(state.coin_holder(), ALICE);
        test_scenario::return_shared(state);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = swap_pool::ENotOwner)]
fun set_xaum_err_not_owner() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_xaum<XAUM>(&mut state, scenario.ctx());
    };
    abort
}

#[test]
fun set_xaum_ok() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_xaum<XAUM>(&mut state, scenario.ctx());
        assert_eq(state.xaum().contains(&type_name::get<XAUM>()), true);
        test_scenario::return_shared(state);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = swap_pool::ENotOwner)]
fun set_coin_whitelist_err_not_owner() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_coin_whitelist<XAUM>(&mut state, true, 8, scenario.ctx());
    };
    abort
}

#[test]
fun set_coin_whitelist_ok() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        assert_eq(state.is_coin_whitelisted<USDC>(), false);
        swap_pool::set_coin_whitelist<USDC>(&mut state, true, 8, scenario.ctx());
        assert_eq(state.is_coin_whitelisted<USDC>(), true);
        test_scenario::return_shared(state);
    };

    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_coin_whitelist<USDC>(&mut state, false, 0, scenario.ctx());
        assert_eq(state.is_coin_whitelisted<USDC>(), false);
        test_scenario::return_shared(state);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = swap_pool::ENotOwner)]
fun set_xaum_price_oracle_feed_id_err_not_owner() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_xaum_price_oracle_feed_id(&mut state, vector::empty(), scenario.ctx());
    };
    abort
}

#[test]
fun set_xaum_price_oracle_feed_id_ok() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_xaum_price_oracle_feed_id(&mut state, b"feed_id", scenario.ctx());
        assert_eq(state.xaum_price_oracle_feed_id().contains(&b"feed_id"), true);
        test_scenario::return_shared(state);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = swap_pool::ENotOwner)]
fun set_dex_pool_err_not_owner() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<State>();
        let dex_pool_id = object::id_from_address(@0x1234);
        swap_pool::set_dex_pool(&mut state, dex_pool_id, scenario.ctx());
    };
    abort
}

#[test]
fun set_dex_pool_ok() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        let dex_pool_id = object::id_from_address(@0x1234);
        swap_pool::set_dex_pool(&mut state, dex_pool_id, scenario.ctx());
        assert_eq(state.dex_pool().contains(&dex_pool_id), true);
        test_scenario::return_shared(state);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = swap_pool::ENotOwner)]
fun set_price_factor_err_not_owner() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_price_factor(&mut state, 123, 456, scenario.ctx());
    };
    abort
}

#[test]
fun set_price_factor_ok() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_price_factor(&mut state, 123, 456, scenario.ctx());
        assert_eq(state.price_factor_weekday(), 123);
        assert_eq(state.price_factor_weekend(), 456);
        test_scenario::return_shared(state);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = swap_pool::ENotOwner)]
fun set_weekday_param_err_not_owner() {
    let mut scenario = init_swap_pool();
    let _clock = clock::create_for_testing(scenario.ctx());
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_weekday_param(&mut state, 123, 456, &_clock, scenario.ctx());
    };
    abort
}

#[test]
fun set_weekday_param_ok() {
    let mut scenario = init_swap_pool();
    let mut _clock = clock::create_for_testing(scenario.ctx());
    _clock.increment_for_testing(1000000);
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_weekday_param(&mut state, 123, 456, &_clock, scenario.ctx());
        assert_eq(state.weekday_start_time(), 123);
        assert_eq(state.weekday_duration(), 456);
        test_scenario::return_shared(state);
    };
    clock::destroy_for_testing(_clock);
    scenario.end();
}

#[test, expected_failure(abort_code = swap_pool::ENotOwner)]
fun set_price_deviation_ratio_err_not_owner() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_price_deviation_ratio(&mut state, 123, scenario.ctx());
    };
    abort
}

#[test]
fun set_price_deviation_ratio_ok() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_price_deviation_ratio(&mut state, 123, scenario.ctx());
        assert_eq(state.price_deviation_ratio(), 123);
        test_scenario::return_shared(state);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = swap_pool::ENotOwner)]
fun set_price_check_err_not_owner() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_price_check(&mut state, true, scenario.ctx());
    };
    abort
}

#[test]
fun set_price_check_ok() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_price_check(&mut state, true, scenario.ctx());
        assert_eq(state.price_check(), true);
        test_scenario::return_shared(state);
    };
    scenario.end();
}

#[test, expected_failure(abort_code = swap_pool::ENotOwner)]
fun add_user_whitelist_err_not_owner() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::add_user_whitelist(&mut state, ALICE, scenario.ctx());
    };
    abort
}

#[test]
fun add_user_whitelist_ok() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::add_user_whitelist(&mut state, BOB, scenario.ctx());
        test_scenario::return_shared(state);
    };

    scenario.next_tx(BOB);
    {
        let state = scenario.take_shared<State>();
        let cap = scenario.take_from_sender<SwapCap>();
        assert_eq(swap_pool::is_cap_in_user_whitelist(&state, &cap), true);
        scenario.return_to_sender(cap);
        test_scenario::return_shared(state);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = swap_pool::ENotOperator)]
fun withdraw_err_not_operator() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::withdraw<XAUM>(&mut state, 100, scenario.ctx());
    };
    abort
}

#[test]
fun withdraw_ok() {}

#[test, expected_failure(abort_code = swap_pool::EInvalidCoinOutType)]
fun swap_err_invalid_coin_out() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::add_user_whitelist(&mut state, OWNER, scenario.ctx());
        test_scenario::return_shared(state);
    };

    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        let swap_cap = scenario.take_from_sender<SwapCap>();
        let mut coin_in = coin::zero<USDC>(scenario.ctx());
        let _coin_out = swap_pool::swap_at_price_for_testing<USDC, XAUM>(
            &mut state,
            &swap_cap,
            &mut coin_in,
            100,
            123,
            9u8,
            scenario.ctx(),
        );
    };
    abort
}

#[test, expected_failure(abort_code = swap_pool::EUserNotInWhitelist)]
fun swap_err_invalid_swap_cap() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_xaum<XAUM>(&mut state, scenario.ctx());
        swap_pool::add_user_whitelist(&mut state, OWNER, scenario.ctx());
        test_scenario::return_shared(state);
    };

    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        let swap_cap = scenario.take_from_sender<SwapCap>();
        swap_pool::update_user_whitelist(&mut state, object::id(&swap_cap), false, scenario.ctx());
        scenario.return_to_sender(swap_cap);
        test_scenario::return_shared(state);
    };

    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        let swap_cap = scenario.take_from_sender<SwapCap>();
        let mut coin_in = coin::zero<USDC>(scenario.ctx());
        let _coin_out = swap_pool::swap_at_price_for_testing<USDC, XAUM>(
            &mut state,
            &swap_cap,
            &mut coin_in,
            100,
            123,
            9u8,
            scenario.ctx(),
        );
    };
    abort
}

#[test, expected_failure(abort_code = swap_pool::ECoinNotInWhitelist)]
fun swap_err_invalid_coin_in() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_xaum<XAUM>(&mut state, scenario.ctx());
        swap_pool::add_user_whitelist(&mut state, ALICE, scenario.ctx());
        test_scenario::return_shared(state);
    };

    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<State>();
        let swap_cap = scenario.take_from_sender<SwapCap>();
        let mut coin_in = coin::zero<USDC>(scenario.ctx());
        let _coin_out = swap_pool::swap_at_price_for_testing<USDC, XAUM>(
            &mut state,
            &swap_cap,
            &mut coin_in,
            100,
            123,
            9u8,
            scenario.ctx(),
        );
    };
    abort
}

#[test, expected_failure(abort_code = swap_pool::EInvalidAmountIn)]
fun swap_err_invalid_amt_in() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_xaum<XAUM>(&mut state, scenario.ctx());
        swap_pool::add_user_whitelist(&mut state, ALICE, scenario.ctx());
        swap_pool::set_coin_whitelist<USDC>(&mut state, true, 6u8, scenario.ctx());
        test_scenario::return_shared(state);
    };

    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<State>();
        let swap_cap = scenario.take_from_sender<SwapCap>();
        let mut coin_in = coin::mint_for_testing<USDC>(100, scenario.ctx());
        let _coin_out = swap_pool::swap_at_price_for_testing<USDC, XAUM>(
            &mut state,
            &swap_cap,
            &mut coin_in,
            101,
            123,
            9u8,
            scenario.ctx(),
        );
    };
    abort
}

#[test, expected_failure(abort_code = swap_pool::EInvalidAmountOut)]
fun swap_err_not_enough_xaum() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_xaum<XAUM>(&mut state, scenario.ctx());
        swap_pool::add_user_whitelist(&mut state, ALICE, scenario.ctx());
        swap_pool::set_coin_whitelist<USDC>(&mut state, true, 6u8, scenario.ctx());

        let xaum = coin::mint_for_testing<XAUM>(100, scenario.ctx());
        transfer::public_transfer(xaum, object::id(&state).to_address());
        test_scenario::return_shared(state);
    };

    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        let xaum_receiver = test_scenario::most_recent_receiving_ticket<sui::coin::Coin<XAUM>>(
            &object::id(&state),
        );
        swap_pool::accept_payment<XAUM>(&mut state, xaum_receiver, scenario.ctx());
        test_scenario::return_shared(state);
    };

    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<State>();
        let swap_cap = scenario.take_from_sender<SwapCap>();
        let mut coin_in = coin::mint_for_testing<USDC>(200, scenario.ctx());
        let _coin_out = swap_pool::swap_at_price_for_testing<USDC, XAUM>(
            &mut state,
            &swap_cap,
            &mut coin_in,
            150,
            100,
            6u8,
            scenario.ctx(),
        );
    };
    abort
}

#[test]
fun swap_ok() {
    let mut scenario = init_swap_pool();
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        swap_pool::set_xaum<XAUM>(&mut state, scenario.ctx());
        swap_pool::add_user_whitelist(&mut state, ALICE, scenario.ctx());
        swap_pool::set_coin_whitelist<USDC>(&mut state, true, 6u8, scenario.ctx());

        // deposit 10 XAUm
        let xaum = coin::mint_for_testing<XAUM>(10_000_000_000, scenario.ctx());
        transfer::public_transfer(xaum, object::id(&state).to_address());
        test_scenario::return_shared(state);
    };

    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<State>();
        let xaum_receiver = test_scenario::most_recent_receiving_ticket<sui::coin::Coin<XAUM>>(
            &object::id(&state),
        );
        swap_pool::accept_payment<XAUM>(&mut state, xaum_receiver, scenario.ctx());
        test_scenario::return_shared(state);
    };

    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<State>();
        let swap_cap = scenario.take_from_sender<SwapCap>();
        let mut coin_in = coin::mint_for_testing<USDC>(8000_000_000, scenario.ctx()); // 8000 USDC
        let coin_out = swap_pool::swap_at_price_for_testing<USDC, XAUM>(
            &mut state,
            &swap_cap,
            &mut coin_in,
            6000_000_000, // 6000 USDC
            3000_000_000, // 3000 USDC/XAUm
            6u8,
            scenario.ctx(),
        );
        assert_eq(coin_in.value(), 2000_000_000); // 2000 USDC left
        assert_eq(coin_out.value(), 2_000_000_000); // 2 XAUm got
        transfer::public_transfer(coin_in, ALICE);
        transfer::public_transfer(coin_out, ALICE);
        scenario.return_to_sender(swap_cap);
        test_scenario::return_shared(state);
    };

    scenario.end();
}
