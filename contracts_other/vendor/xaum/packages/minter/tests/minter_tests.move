#[test_only]
module minter::minter_tests;

use minter::minter;
use std::type_name;
use sui::clock;
use sui::coin;
use sui::event;
use sui::package::{test_publish, UpgradeCap};
use sui::sui::SUI;
use sui::test_scenario as ts;
use sui::test_utils::assert_eq;

const OWNER: address = @0xAD;
const ALICE: address = @0xA;
const POOLA: address = @0xB;
const POOLB: address = @0xC;
const BOB: address = @0xD;
const VERSION: u64 = 1;

public struct USDT has drop {}

#[test]
fun test_transfer_ownership() {
    let mut ts = ts::begin(@0x0);
    {
        ts.next_tx(OWNER);
        minter::create_minter(ts.ctx());
    };
    {
        ts.next_tx(OWNER);
        let mut state: minter::State = ts.take_shared();
        let upgrade_cap = test_publish(
            state.package_address().to_id(),
            ts.ctx(),
        );
        let upgrade_cap_id = object::id(&upgrade_cap);
        assert!(state.package_address() == @0x0);
        minter::init_upgrade_cap_id(&mut state, &upgrade_cap, ts.ctx());
        minter::transfer_ownership(&mut state, BOB, upgrade_cap, ts.ctx());
        ts::return_shared(state);

        ts.next_tx(BOB);
        let state: minter::State = ts.take_shared();
        assert!(state.owner() == BOB);
        let upgrade_cap = ts.take_from_sender<UpgradeCap>();
        assert_eq(object::id(&upgrade_cap), upgrade_cap_id);
        ts.return_to_sender(upgrade_cap);
        ts::return_shared(state);
    };
    ts.end();
}

#[test]
fun test_minter() {
    let mut ts = ts::begin(@0x0);
    {
        ts.next_tx(OWNER);
        minter::create_minter(ts.ctx());
    };
    {
        ts.next_tx(OWNER);
        let mut state: minter::State = ts.take_shared();
        assert_eq(state.version(), VERSION);

        minter::set_pool_account_a(&mut state, POOLA, ts.ctx());
        minter::set_pool_account_b(&mut state, POOLB, ts.ctx());

        assert_eq(state.pool_account_a(), POOLA);
        assert_eq(state.pool_account_b(), POOLB);
        ts::return_shared(state);
    };
    {
        ts.next_tx(OWNER);
        let mut state: minter::State = ts.take_shared();
        minter::set_accepted_by_a<USDT>(
            &mut state,
            true,
            ts.ctx(),
        );
        minter::set_accepted_by_b<SUI>(
            &mut state,
            true,
            ts.ctx(),
        );
        assert!(
            minter::accepted_by_a(
                &state,
                type_name::get<USDT>(),
            ),
        );
        assert!(
            minter::accepted_by_b(
                &state,
                type_name::get<SUI>(),
            ),
        );
        ts::return_shared(state);
    };
    {
        ts.next_tx(ALICE);
        let state: minter::State = ts.take_shared();
        let mut usdt = coin::mint_for_testing<USDT>(1000, ts.ctx());
        let mut _clock = clock::create_for_testing(ts.ctx());
        _clock.set_for_testing(1000 * 1000);
        minter::request_to_mint<USDT, SUI>(
            &state,
            &mut usdt,
            100,
            10,
            5,
            999,
            &_clock,
            ts.ctx(),
        );
        assert_eq(coin::value(&usdt), 900);
        assert_eq(event::num_events(), 1);
        assert_eq(
            event::events_by_type<minter::MintRequest>().pop_back(),
            minter::new_mint_request_event(
                type_name::get<USDT>(),
                type_name::get<SUI>(),
                ALICE,
                POOLA,
                100,
                10,
                5,
            ),
        );
        transfer::public_transfer(usdt, ALICE);
        ts::return_shared(state);
        clock::destroy_for_testing(_clock);
    };
    {
        ts.next_tx(POOLA);
        let usdt = ts.take_from_sender<coin::Coin<USDT>>();
        assert_eq(coin::value(&usdt), 100);
        ts.return_to_sender(usdt);
    };
    {
        ts.next_tx(ALICE);
        let state: minter::State = ts.take_shared();
        let mut sui = coin::mint_for_testing<SUI>(1000, ts.ctx());
        let mut _clock = clock::create_for_testing(ts.ctx());
        _clock.set_for_testing(1000 * 1000);
        minter::request_to_redeem<SUI, USDT>(
            &state,
            &mut sui,
            100,
            10,
            5,
            999,
            &_clock,
            ts.ctx(),
        );
        assert_eq(coin::value(&sui), 900);
        assert_eq(event::num_events(), 1);
        assert_eq(
            event::events_by_type<minter::RedeemRequest>().pop_back(),
            minter::new_redeem_request_event(
                type_name::get<SUI>(),
                type_name::get<USDT>(),
                ALICE,
                POOLB,
                100,
                10,
                5,
            ),
        );
        transfer::public_transfer(sui, ALICE);
        ts::return_shared(state);
        clock::destroy_for_testing(_clock);
    };
    {
        ts.next_tx(POOLB);
        let sui = ts.take_from_sender<coin::Coin<SUI>>();
        assert_eq(coin::value(&sui), 100);
        ts.return_to_sender(sui);
    };
    ts.end();
}

#[test, expected_failure(abort_code = minter::EInvalidTokenForMint)]
fun invalid_token_for_mint_request() {
    let mut ts = ts::begin(@0x0);
    {
        ts.next_tx(OWNER);
        minter::create_minter(ts.ctx());
    };
    {
        ts.next_tx(OWNER);
        let mut state: minter::State = ts.take_shared();
        minter::set_pool_account_a(&mut state, POOLA, ts.ctx());
        minter::set_accepted_by_a<USDT>(
            &mut state,
            true,
            ts.ctx(),
        );
        ts::return_shared(state);
    };
    {
        ts.next_tx(ALICE);
        let state: minter::State = ts.take_shared();
        let mut sui = coin::mint_for_testing<SUI>(1000, ts.ctx());
        let mut _clock = clock::create_for_testing(ts.ctx());
        _clock.set_for_testing(1000 * 1000);
        minter::request_to_mint<SUI, USDT>(
            &state,
            &mut sui,
            100,
            10,
            5,
            999,
            &_clock,
            ts.ctx(),
        );
    };
    abort
}

#[test, expected_failure(abort_code = minter::EInsufficientBalance)]
fun insufficient_token_balance_for_mint_request() {
    let mut ts = ts::begin(@0x0);
    {
        ts.next_tx(OWNER);
        minter::create_minter(ts.ctx());
    };
    {
        ts.next_tx(OWNER);
        let mut state: minter::State = ts.take_shared();
        minter::set_pool_account_a(&mut state, POOLA, ts.ctx());
        minter::set_accepted_by_a<USDT>(
            &mut state,
            true,
            ts.ctx(),
        );
        ts::return_shared(state);
    };
    {
        ts.next_tx(ALICE);
        let state: minter::State = ts.take_shared();
        let mut usdt = coin::mint_for_testing<USDT>(1000, ts.ctx());
        let mut _clock = clock::create_for_testing(ts.ctx());
        _clock.set_for_testing(1000 * 1000);
        minter::request_to_mint<USDT, SUI>(
            &state,
            &mut usdt,
            1001,
            10,
            5,
            999,
            &_clock,
            ts.ctx(),
        );
    };
    abort
}

#[test, expected_failure(abort_code = minter::EInvalidTimestamp)]
fun invalid_timestamp_for_mint_request() {
    let mut ts = ts::begin(@0x0);
    {
        ts.next_tx(OWNER);
        minter::create_minter(ts.ctx());
    };
    {
        ts.next_tx(OWNER);
        let mut state: minter::State = ts.take_shared();
        minter::set_pool_account_a(&mut state, POOLA, ts.ctx());
        minter::set_accepted_by_a<USDT>(
            &mut state,
            true,
            ts.ctx(),
        );
        ts::return_shared(state);
    };
    {
        ts.next_tx(ALICE);
        let state: minter::State = ts.take_shared();
        let mut usdt = coin::mint_for_testing<USDT>(1000, ts.ctx());
        let mut _clock = clock::create_for_testing(ts.ctx());
        _clock.set_for_testing(1000 * 1000);
        minter::request_to_mint<USDT, SUI>(
            &state,
            &mut usdt,
            100,
            10,
            5,
            900,
            &_clock,
            ts.ctx(),
        );
    };
    abort
}

#[test, expected_failure(abort_code = minter::EInvalidTokenForMint)]
fun invalid_token_for_mint_when_remove_accepted_token() {
    let mut ts = ts::begin(@0x0);
    {
        ts.next_tx(OWNER);
        minter::create_minter(ts.ctx());
    };
    {
        ts.next_tx(OWNER);
        let mut state: minter::State = ts.take_shared();
        minter::set_pool_account_a(&mut state, POOLA, ts.ctx());
        minter::set_accepted_by_a<USDT>(
            &mut state,
            true,
            ts.ctx(),
        );
        ts::return_shared(state);
    };
    {
        ts.next_tx(OWNER);
        let mut state: minter::State = ts.take_shared();
        minter::set_accepted_by_a<USDT>(
            &mut state,
            false,
            ts.ctx(),
        );
        ts::return_shared(state);
    };
    {
        ts.next_tx(ALICE);
        let state: minter::State = ts.take_shared();
        let mut usdt = coin::mint_for_testing<USDT>(1000, ts.ctx());
        let mut _clock = clock::create_for_testing(ts.ctx());
        _clock.set_for_testing(1000 * 1000);
        minter::request_to_mint<USDT, SUI>(
            &state,
            &mut usdt,
            100,
            10,
            5,
            1000,
            &_clock,
            ts.ctx(),
        );
    };
    abort
}

#[test, expected_failure(abort_code = minter::EInvalidTokenForRedeem)]
fun invalid_token_for_redeem_request() {
    let mut ts = ts::begin(@0x0);
    {
        ts.next_tx(OWNER);
        minter::create_minter(ts.ctx());
    };
    {
        ts.next_tx(OWNER);
        let mut state: minter::State = ts.take_shared();
        minter::set_pool_account_b(&mut state, POOLA, ts.ctx());
        minter::set_accepted_by_b<SUI>(
            &mut state,
            true,
            ts.ctx(),
        );
        ts::return_shared(state);
    };
    {
        ts.next_tx(ALICE);
        let state: minter::State = ts.take_shared();
        let mut usdt = coin::mint_for_testing<USDT>(1000, ts.ctx());
        let mut _clock = clock::create_for_testing(ts.ctx());
        _clock.set_for_testing(1000 * 1000);
        minter::request_to_redeem<USDT, USDT>(
            &state,
            &mut usdt,
            100,
            10,
            5,
            999,
            &_clock,
            ts.ctx(),
        );
    };
    abort
}

#[test, expected_failure(abort_code = minter::EInvalidTimestamp)]
fun invalid_timestamp_for_redeem_request() {
    let mut ts = ts::begin(@0x0);
    {
        ts.next_tx(OWNER);
        minter::create_minter(ts.ctx());
    };
    {
        ts.next_tx(OWNER);
        let mut state: minter::State = ts.take_shared();
        minter::set_pool_account_b(&mut state, POOLA, ts.ctx());
        minter::set_accepted_by_b<SUI>(
            &mut state,
            true,
            ts.ctx(),
        );
        ts::return_shared(state);
    };
    {
        ts.next_tx(ALICE);
        let state: minter::State = ts.take_shared();
        let mut sui = coin::mint_for_testing<SUI>(1000, ts.ctx());
        let mut _clock = clock::create_for_testing(ts.ctx());
        _clock.set_for_testing(1000 * 1000);
        minter::request_to_redeem<SUI, USDT>(
            &state,
            &mut sui,
            100,
            10,
            5,
            900,
            &_clock,
            ts.ctx(),
        );
    };
    abort
}

#[test, expected_failure(abort_code = minter::EInsufficientBalance)]
fun insufficient_token_balance_for_redeem_request() {
    let mut ts = ts::begin(@0x0);
    {
        ts.next_tx(OWNER);
        minter::create_minter(ts.ctx());
    };
    {
        ts.next_tx(OWNER);
        let mut state: minter::State = ts.take_shared();
        minter::set_pool_account_b(&mut state, POOLA, ts.ctx());
        minter::set_accepted_by_b<SUI>(
            &mut state,
            true,
            ts.ctx(),
        );
        ts::return_shared(state);
    };
    {
        ts.next_tx(ALICE);
        let state: minter::State = ts.take_shared();
        let mut sui = coin::mint_for_testing<SUI>(1000, ts.ctx());
        let mut _clock = clock::create_for_testing(ts.ctx());
        _clock.set_for_testing(1000 * 1000);
        minter::request_to_redeem<SUI, USDT>(
            &state,
            &mut sui,
            1001,
            10,
            5,
            999,
            &_clock,
            ts.ctx(),
        );
    };
    abort
}

#[test, expected_failure(abort_code = minter::ENotOwner)]
fun migrate_err_not_owner() {
    let mut scenario = ts::begin(@0x0);
    scenario.next_tx(OWNER);
    {
        minter::create_minter(scenario.ctx());
    };

    // migrate
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<minter::State>();
        minter::migrate(&mut state, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = minter::EWrongVersion)]
fun migrate_err_wrong_version() {
    let mut scenario = ts::begin(@0x0);
    scenario.next_tx(OWNER);
    {
        minter::create_minter(scenario.ctx());
    };

    // migrate
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<minter::State>();
        state.set_version(2);
        minter::migrate(&mut state, scenario.ctx());
    };
    abort
}

#[test]
fun migrate_ok() {
    let mut scenario = ts::begin(@0x0);
    scenario.next_tx(OWNER);
    {
        minter::create_minter(scenario.ctx());
    };

    // migrate
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<minter::State>();
        state.set_version(0);
        minter::migrate(&mut state, scenario.ctx());
        assert_eq(state.version(), VERSION);
        ts::return_shared(state);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = minter::ENotOwner)]
fun init_upgrade_cap_id_err_not_owner() {
    let mut scenario = ts::begin(@0x0);
    scenario.next_tx(OWNER);
    {
        minter::create_minter(scenario.ctx());
    };

    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<minter::State>();
        let upgrade_cap = test_publish(object::id_from_address(@0x1234), scenario.ctx());
        minter::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = minter::EUpgradeCapInvalid)]
fun init_upgrade_cap_id_err_not_matching() {
    let mut scenario = ts::begin(@0x0);
    scenario.next_tx(OWNER);
    {
        minter::create_minter(scenario.ctx());
    };

    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<minter::State>();
        let upgrade_cap = test_publish(object::id_from_address(@0x1234), scenario.ctx());
        minter::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = minter::EUpgradeCapIdNotNone)]
fun init_upgrade_cap_id_err_not_none() {
    let mut scenario = ts::begin(@0x0);
    scenario.next_tx(OWNER);
    {
        minter::create_minter(scenario.ctx());
    };

    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<minter::State>();
        let upgrade_cap = test_publish(
            state.package_address().to_id(),
            scenario.ctx(),
        );
        minter::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx()); // ok
        minter::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx()); // error!
    };
    abort
}

#[test]
fun init_upgrade_cap_id_ok() {
    let mut scenario = ts::begin(@0x0);
    scenario.next_tx(OWNER);
    {
        minter::create_minter(scenario.ctx());
    };

    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<minter::State>();
        let upgrade_cap = test_publish(
            state.package_address().to_id(),
            scenario.ctx(),
        );
        minter::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx()); // ok
        assert_eq(state.upgrade_cap_id(), option::some(object::id(&upgrade_cap)));
        transfer::public_share_object(upgrade_cap);
        ts::return_shared(state);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = minter::ENotOwner)]
fun set_owner_err_not_owner() {
    let mut scenario = ts::begin(@0x0);
    scenario.next_tx(OWNER);
    {
        minter::create_minter(scenario.ctx());
    };

    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<minter::State>();
        let upgrade_cap = test_publish(
            state.package_address().to_id(),
            scenario.ctx(),
        );
        minter::transfer_ownership(&mut state, ALICE, upgrade_cap, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = minter::EUpgradeCapInvalid)]
fun set_owner_err_upgrade_cap_invalid() {
    let mut scenario = ts::begin(@0x0);
    scenario.next_tx(OWNER);
    {
        minter::create_minter(scenario.ctx());
    };

    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<minter::State>();
        let upgrade_cap = test_publish(object::id_from_address(@0x1234), scenario.ctx());
        minter::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx());

        let upgrade_cap2 = test_publish(object::id_from_address(@0x1234), scenario.ctx());
        minter::transfer_ownership(&mut state, ALICE, upgrade_cap2, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = minter::ENotOwner)]
fun set_accepted_token_by_a_err_not_owner() {
    let mut scenario = ts::begin(@0x0);
    scenario.next_tx(OWNER);
    {
        minter::create_minter(scenario.ctx());
    };

    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<minter::State>();
        minter::set_accepted_by_a<USDT>(
            &mut state,
            true,
            scenario.ctx(),
        );
    };
    abort
}

#[test]
fun set_owner_ok() {
    let mut scenario = ts::begin(@0x0);
    scenario.next_tx(OWNER);
    {
        minter::create_minter(scenario.ctx());
    };

    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<minter::State>();
        let upgrade_cap = test_publish(
            state.package_address().to_id(),
            scenario.ctx(),
        );
        minter::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx());
        minter::transfer_ownership(&mut state, ALICE, upgrade_cap, scenario.ctx());
        ts::return_shared(state);
    };

    // check upgrade cap
    scenario.next_tx(ALICE);
    {
        let state = scenario.take_shared<minter::State>();
        let upgrade_cap = scenario.take_from_sender<UpgradeCap>();
        assert_eq(upgrade_cap.package(), state.package_address().to_id());
        scenario.return_to_sender(upgrade_cap);
        ts::return_shared(state);
    };
    scenario.end();
}

#[test]
fun set_accepted_token_by_a_ok() {
    let mut scenario = ts::begin(@0x0);
    scenario.next_tx(OWNER);
    {
        minter::create_minter(scenario.ctx());
    };
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<minter::State>();
        minter::set_accepted_by_a<USDT>(
            &mut state,
            true,
            scenario.ctx(),
        );
        minter::set_accepted_by_a<SUI>(
            &mut state,
            false,
            scenario.ctx(),
        );
        ts::return_shared(state);
    };
    scenario.next_tx(OWNER);
    {
        let state = scenario.take_shared<minter::State>();
        assert!(
            state.accepted_by_a(
                type_name::get<USDT>(),
            ),
        );
        assert!(
            !state.accepted_by_a(
                type_name::get<SUI>(),
            ),
        );
        ts::return_shared(state);
    };
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<minter::State>();
        minter::set_accepted_by_a<USDT>(
            &mut state,
            false,
            scenario.ctx(),
        );
        minter::set_accepted_by_a<SUI>(
            &mut state,
            true,
            scenario.ctx(),
        );
        ts::return_shared(state);
    };
    scenario.next_tx(OWNER);
    {
        let state = scenario.take_shared<minter::State>();
        assert!(
            !state.accepted_by_a(
                type_name::get<USDT>(),
            ),
        );
        assert!(
            state.accepted_by_a(
                type_name::get<SUI>(),
            ),
        );
        ts::return_shared(state);
    };
    // reenter
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<minter::State>();
        minter::set_accepted_by_a<USDT>(
            &mut state,
            false,
            scenario.ctx(),
        );
        minter::set_accepted_by_a<SUI>(
            &mut state,
            true,
            scenario.ctx(),
        );
        ts::return_shared(state);
    };
    scenario.next_tx(OWNER);
    {
        let state = scenario.take_shared<minter::State>();
        assert!(
            !state.accepted_by_a(
                type_name::get<USDT>(),
            ),
        );
        assert!(
            state.accepted_by_a(
                type_name::get<SUI>(),
            ),
        );
        ts::return_shared(state);
    };
    scenario.end();
}

#[test]
fun set_accepted_token_by_b_ok() {
    let mut scenario = ts::begin(@0x0);
    scenario.next_tx(OWNER);
    {
        minter::create_minter(scenario.ctx());
    };
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<minter::State>();
        minter::set_accepted_by_b<USDT>(
            &mut state,
            true,
            scenario.ctx(),
        );
        minter::set_accepted_by_b<SUI>(
            &mut state,
            false,
            scenario.ctx(),
        );
        ts::return_shared(state);
    };
    scenario.next_tx(OWNER);
    {
        let state = scenario.take_shared<minter::State>();
        assert!(
            state.accepted_by_b(
                type_name::get<USDT>(),
            ),
        );
        assert!(
            !state.accepted_by_b(
                type_name::get<SUI>(),
            ),
        );
        ts::return_shared(state);
    };
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<minter::State>();
        minter::set_accepted_by_b<USDT>(
            &mut state,
            false,
            scenario.ctx(),
        );
        minter::set_accepted_by_b<SUI>(
            &mut state,
            true,
            scenario.ctx(),
        );
        ts::return_shared(state);
    };
    scenario.next_tx(OWNER);
    {
        let state = scenario.take_shared<minter::State>();
        assert!(
            !state.accepted_by_b(
                type_name::get<USDT>(),
            ),
        );
        assert!(
            state.accepted_by_b(
                type_name::get<SUI>(),
            ),
        );
        ts::return_shared(state);
    };
    // reenter
    scenario.next_tx(OWNER);
    {
        let mut state = scenario.take_shared<minter::State>();
        minter::set_accepted_by_b<USDT>(
            &mut state,
            false,
            scenario.ctx(),
        );
        minter::set_accepted_by_b<SUI>(
            &mut state,
            true,
            scenario.ctx(),
        );
        ts::return_shared(state);
    };
    scenario.next_tx(OWNER);
    {
        let state = scenario.take_shared<minter::State>();
        assert!(
            !state.accepted_by_b(
                type_name::get<USDT>(),
            ),
        );
        assert!(
            state.accepted_by_b(
                type_name::get<SUI>(),
            ),
        );
        ts::return_shared(state);
    };
    scenario.end();
}
