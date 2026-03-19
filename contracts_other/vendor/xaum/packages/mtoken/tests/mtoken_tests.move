#[test_only]
module mtoken::mtoken_tests;

use mtoken::mtoken;
use sui::balance;
use sui::clock;
use sui::coin::{Self, Coin, CoinMetadata};
use sui::deny_list::{Self, DenyList};
use sui::event;
use sui::package::{test_publish, UpgradeCap};
use sui::test_scenario;
use sui::test_utils::assert_eq;
use sui::url;

// constants are not exported, so we need to redefine them here
const VERSION: u64 = 1;
const INIT_DELAY: u64 = 5;
const MIN_DELAY: u64 = 3600;
const REQ_TTL: u64 = 3600;

// coin metadata
const DECIMALS: u8 = 9;
const SYMBOL: vector<u8> = b"MToken";
const NAME: vector<u8> = b"MToken";
const DESCRIPTION: vector<u8> = b"MToken";

// test addresses
const SYS: address = @0x0;
const ADMIN: address = @0xAD;
const ALICE: address = @0xA11CE;
const BOB: address = @0xB0B;

// OTW
public struct MTOKEN_TESTS has drop {}

fun init_xaum(): test_scenario::Scenario {
    let mut scenario = test_scenario::begin(SYS);
    deny_list::create_for_test(scenario.ctx());

    scenario.next_tx(ADMIN);
    {
        let witness = MTOKEN_TESTS {};
        mtoken::create_coin(
            witness,
            DECIMALS,
            SYMBOL,
            NAME,
            DESCRIPTION,
            option::none(),
            true,
            INIT_DELAY,
            scenario.ctx(),
        );
    };
    scenario
}

#[test]
fun init_ok() {
    let mut scenario = init_xaum();

    // check State fields
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        assert_eq(state.version(), VERSION);
        assert_eq(state.owner(), ADMIN);
        assert_eq(state.operator(), ADMIN);
        assert_eq(state.revoker(), ADMIN);
        assert_eq(state.delay(), INIT_DELAY);
        assert_eq(state.mint_budget(), 0);
        test_scenario::return_shared(state);
    };

    // check metadata
    {
        let (decimals, name, symbol, description) = (DECIMALS, NAME, SYMBOL, DESCRIPTION);
        let metadata = scenario.take_shared<CoinMetadata<MTOKEN_TESTS>>();
        assert_eq(coin::get_decimals(&metadata), decimals);
        assert_eq(coin::get_name(&metadata), name.to_string());
        assert_eq(coin::get_symbol(&metadata), symbol.to_ascii_string());
        assert_eq(coin::get_description(&metadata), description.to_string());
        assert_eq(coin::get_icon_url(&metadata).is_some(), false);
        // allow_global_pause ?
        test_scenario::return_shared(metadata);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = mtoken::ENotOwner)]
fun migrate_err_not_owner() {
    let mut scenario = init_xaum();

    // migrate
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::migrate(&mut state, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = mtoken::EWrongVersion)]
fun migrate_err_wrong_version() {
    let mut scenario = init_xaum();

    // migrate
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        state.set_version(2);
        mtoken::migrate(&mut state, scenario.ctx());
    };
    abort
}

#[test]
fun migrate_ok() {
    let mut scenario = init_xaum();

    // migrate
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        state.set_version(0);
        mtoken::migrate(&mut state, scenario.ctx());
        assert_eq(state.version(), VERSION);
        test_scenario::return_shared(state);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = mtoken::ENotOwner)]
fun set_description_err_not_owner() {
    let mut scenario = init_xaum();

    scenario.next_tx(ALICE);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let mut metadata = scenario.take_shared<CoinMetadata<MTOKEN_TESTS>>();
        let new_description = b"new description".to_string();
        mtoken::update_description(&state, &mut metadata, new_description, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = mtoken::ENotOwner)]
fun set_icon_url_err_not_owner() {
    let mut scenario = init_xaum();

    scenario.next_tx(ALICE);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let mut metadata = scenario.take_shared<CoinMetadata<MTOKEN_TESTS>>();
        let new_icon_url = b"new/icon/url".to_ascii_string();
        mtoken::update_icon_url(&state, &mut metadata, new_icon_url, scenario.ctx());
    };
    abort
}

#[test]
fun update_metadata_ok() {
    let new_description = b"new description";
    let new_icon_url = b"new/icon/url";
    let mut scenario = init_xaum();

    // update metadata
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let mut metadata = scenario.take_shared<CoinMetadata<MTOKEN_TESTS>>();
        mtoken::update_description(
            &state,
            &mut metadata,
            new_description.to_string(),
            scenario.ctx(),
        );
        mtoken::update_icon_url(
            &state,
            &mut metadata,
            new_icon_url.to_ascii_string(),
            scenario.ctx(),
        );
        test_scenario::return_shared(metadata);
        test_scenario::return_shared(state);
    };

    // check metadata
    scenario.next_tx(ALICE);
    {
        let metadata = scenario.take_shared<CoinMetadata<MTOKEN_TESTS>>();
        assert_eq(coin::get_description(&metadata), new_description.to_string());
        assert_eq(
            coin::get_icon_url(&metadata).extract(),
            url::new_unsafe_from_bytes(new_icon_url),
        );
        test_scenario::return_shared(metadata);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = mtoken::ENotOwner)]
fun init_upgrade_cap_id_err_not_owner() {
    let mut scenario = init_xaum();

    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let upgrade_cap = test_publish(object::id_from_address(@0x1234), scenario.ctx());
        mtoken::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = mtoken::EUpgradeCapInvalid)]
fun init_upgrade_cap_id_err_not_matching() {
    let mut scenario = init_xaum();

    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let upgrade_cap = test_publish(object::id_from_address(@0x1234), scenario.ctx());
        mtoken::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = mtoken::EUpgradeCapIdNotNone)]
fun init_upgrade_cap_id_err_not_none() {
    let mut scenario = init_xaum();

    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let upgrade_cap = test_publish(
            state.package_address().to_id(),
            scenario.ctx(),
        );
        mtoken::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx()); // ok
        mtoken::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx()); // error!
    };
    abort
}

#[test]
fun init_upgrade_cap_id_ok() {
    let mut scenario = init_xaum();

    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let upgrade_cap = test_publish(
            state.package_address().to_id(),
            scenario.ctx(),
        );
        mtoken::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx()); // ok
        assert_eq(state.upgrade_cap_id(), option::some(object::id(&upgrade_cap)));
        transfer::public_share_object(upgrade_cap);
        test_scenario::return_shared(state);
    };

    scenario.end();
}

#[test, expected_failure(abort_code = mtoken::ENotOwner)]
fun set_owner_req_err_not_owner() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let upgrade_cap = test_publish(
            state.package_address().to_id(),
            scenario.ctx(),
        );
        mtoken::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx());
        mtoken::request_transfer_ownership(&state, BOB, upgrade_cap, &_clock, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = mtoken::ENotNewOwner)]
fun set_owner_exec_err_not_new_owner() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let upgrade_cap = test_publish(
            state.package_address().to_id(),
            scenario.ctx(),
        );
        mtoken::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx());
        mtoken::request_transfer_ownership(&state, ALICE, upgrade_cap, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // execute
    scenario.next_tx(BOB);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::TransferOwnershipReq>();
        mtoken::execute_transfer_ownership(&mut state, req, &_clock, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = mtoken::ENotEffective)]
fun set_owner_exec_err_not_effective() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let upgrade_cap = test_publish(
            state.package_address().to_id(),
            scenario.ctx(),
        );
        mtoken::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx());
        mtoken::request_transfer_ownership(&state, ALICE, upgrade_cap, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // execute
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::TransferOwnershipReq>();
        mtoken::execute_transfer_ownership(&mut state, req, &_clock, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = mtoken::EReqExpired)]
fun set_owner_exec_err_expired() {
    let mut scenario = init_xaum();
    let mut _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let upgrade_cap = test_publish(
            state.package_address().to_id(),
            scenario.ctx(),
        );
        mtoken::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx());
        mtoken::request_transfer_ownership(&state, ALICE, upgrade_cap, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // execute
    _clock.increment_for_testing(INIT_DELAY * 1000);
    _clock.increment_for_testing(REQ_TTL * 1000);
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::TransferOwnershipReq>();
        mtoken::execute_transfer_ownership(&mut state, req, &_clock, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = mtoken::EUpgradeCapInvalid)]
fun set_owner_req_err_upgrade_cap_invalid() {
    let mut scenario = init_xaum();
    let mut _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let upgrade_cap = test_publish(
            state.package_address().to_id(),
            scenario.ctx(),
        );
        mtoken::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx());

        let upgrade_cap2 = test_publish(object::id_from_address(@0x1234), scenario.ctx());
        mtoken::request_transfer_ownership(&state, ALICE, upgrade_cap2, &_clock, scenario.ctx());
    };
    abort
}

#[test]
fun set_owner_ok() {
    let mut scenario = init_xaum();
    let mut _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let upgrade_cap = test_publish(
            state.package_address().to_id(),
            scenario.ctx(),
        );
        mtoken::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx());
        mtoken::request_transfer_ownership(&state, ALICE, upgrade_cap, &_clock, scenario.ctx());
        assert_eq(state.owner(), ADMIN);
        assert_eq(event::num_events(), 1);
        test_scenario::return_shared(state);
    };

    // execute
    _clock.increment_for_testing(INIT_DELAY * 1000);
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::TransferOwnershipReq>();
        mtoken::execute_transfer_ownership(&mut state, req, &_clock, scenario.ctx());
        assert_eq(state.owner(), ALICE);
        assert_eq(event::num_events(), 1);
        test_scenario::return_shared(state);
    };

    // check upgrade cap
    scenario.next_tx(ALICE);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let upgrade_cap = scenario.take_from_sender<UpgradeCap>();
        assert_eq(upgrade_cap.package(), state.package_address().to_id());
        scenario.return_to_sender(upgrade_cap);
        test_scenario::return_shared(state);
    };

    clock::destroy_for_testing(_clock);
    scenario.end();
}

#[test, expected_failure(abort_code = mtoken::ENotOwner)]
fun set_owner_revoke_err_not_owner() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let upgrade_cap = test_publish(
            state.package_address().to_id(),
            scenario.ctx(),
        );
        mtoken::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx());
        mtoken::request_transfer_ownership(&state, ALICE, upgrade_cap, &_clock, scenario.ctx());
        assert_eq(state.owner(), ADMIN);
        assert_eq(event::num_events(), 1);
        test_scenario::return_shared(state);
    };

    // revoke
    scenario.next_tx(ALICE);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::TransferOwnershipReq>();
        mtoken::revoke_transfer_ownership(&state, req, scenario.ctx());
    };
    abort
}

#[test]
fun set_owner_revoke_ok() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let upgrade_cap = test_publish(
            state.package_address().to_id(),
            scenario.ctx(),
        );
        mtoken::init_upgrade_cap_id(&mut state, &upgrade_cap, scenario.ctx());
        mtoken::request_transfer_ownership(&state, ALICE, upgrade_cap, &_clock, scenario.ctx());
        assert_eq(state.owner(), ADMIN);
        assert_eq(event::num_events(), 1);
        test_scenario::return_shared(state);
    };

    // revoke
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::TransferOwnershipReq>();
        mtoken::revoke_transfer_ownership(&state, req, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // check upgrade cap
    scenario.next_tx(ADMIN);
    {
        let _upgrade_cap = scenario.take_from_sender<UpgradeCap>();
        // assert_eq(object::id(&upgrade_cap), object::id_from_address(@123));
        scenario.return_to_sender(_upgrade_cap);
    };

    clock::destroy_for_testing(_clock);
    scenario.end();
}

#[test, expected_failure(abort_code = mtoken::ENotOwner)]
fun set_operator_req_err_not_owner() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ALICE);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_set_operator(&state, BOB, &_clock, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = mtoken::ENotOwner)]
fun set_operator_exec_err_not_owner() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_set_operator(&state, BOB, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // execute
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::SetOperatorReq>();
        mtoken::execute_set_operator(&mut state, req, &_clock, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = mtoken::ENotEffective)]
fun set_operator_exec_err_not_effective() {
    let mut scenario = init_xaum();
    let mut _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_set_operator(&state, ALICE, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // execute
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::SetOperatorReq>();
        mtoken::execute_set_operator(&mut state, req, &_clock, scenario.ctx());
    };
    abort
}

#[test]
fun set_operator_ok() {
    let mut scenario = init_xaum();
    let mut _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_set_operator(&state, ALICE, &_clock, scenario.ctx());
        assert_eq(state.operator(), ADMIN);
        assert_eq(event::num_events(), 1);
        test_scenario::return_shared(state);
    };

    // execute
    _clock.increment_for_testing(INIT_DELAY * 1000);
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::SetOperatorReq>();
        mtoken::execute_set_operator(&mut state, req, &_clock, scenario.ctx());
        assert_eq(state.operator(), ALICE);
        assert_eq(event::num_events(), 1);
        test_scenario::return_shared(state);
    };

    clock::destroy_for_testing(_clock);
    scenario.end();
}

#[test, expected_failure(abort_code = mtoken::ENotRevoker)]
fun set_operator_revoke_err_not_revoker() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_set_operator(&state, ALICE, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // revoke
    scenario.next_tx(ALICE);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::SetOperatorReq>();
        mtoken::revoke_set_operator(&state, req, scenario.ctx());
    };
    abort
}

#[test]
fun set_operator_revoke_ok() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_set_operator(&state, ALICE, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // revoke
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::SetOperatorReq>();
        mtoken::revoke_set_operator(&state, req, scenario.ctx());
        test_scenario::return_shared(state);
    };

    clock::destroy_for_testing(_clock);
    scenario.end();
}

#[test, expected_failure(abort_code = mtoken::ENotOwner)]
fun set_revoker_req_err_not_owner() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ALICE);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_set_revoker(&state, BOB, &_clock, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = mtoken::ENotOwner)]
fun set_revoker_exec_err_not_owner() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_set_revoker(&state, BOB, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // execute
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::SetRevokerReq>();
        mtoken::execute_set_revoker(&mut state, req, &_clock, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = mtoken::ENotEffective)]
fun set_revoker_exec_err_not_effective() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_set_revoker(&state, ALICE, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // execute
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::SetRevokerReq>();
        mtoken::execute_set_revoker(&mut state, req, &_clock, scenario.ctx());
    };
    abort
}

#[test]
fun set_revoker_ok() {
    let mut scenario = init_xaum();
    let mut _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_set_revoker(&state, ALICE, &_clock, scenario.ctx());
        assert_eq(state.revoker(), ADMIN);
        assert_eq(event::num_events(), 1);
        test_scenario::return_shared(state);
    };

    // execute
    _clock.increment_for_testing(INIT_DELAY * 1000);
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::SetRevokerReq>();
        mtoken::execute_set_revoker(&mut state, req, &_clock, scenario.ctx());
        assert_eq(state.revoker(), ALICE);
        assert_eq(event::num_events(), 1);
        test_scenario::return_shared(state);
    };

    clock::destroy_for_testing(_clock);
    scenario.end();
}

#[test, expected_failure(abort_code = mtoken::ENotOwner)]
fun set_revoker_revoke_err_not_owner() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_set_revoker(&state, ALICE, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // revoke
    scenario.next_tx(ALICE);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::SetRevokerReq>();
        mtoken::revoke_set_revoker(&state, req, scenario.ctx());
    };
    abort
}

#[test]
fun set_revoker_revoke_ok() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_set_revoker(&state, ALICE, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // revoke
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::SetRevokerReq>();
        mtoken::revoke_set_revoker(&state, req, scenario.ctx());
        test_scenario::return_shared(state);
    };

    clock::destroy_for_testing(_clock);
    scenario.end();
}

#[test, expected_failure(abort_code = mtoken::ENotOwner)]
fun set_delay_req_err_not_owner() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ALICE);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_set_delay(&state, 1234, &_clock, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = mtoken::EDelayTooShort)]
fun set_delay_req_err_too_short() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_set_delay(&state, MIN_DELAY-1, &_clock, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = mtoken::ENotOwner)]
fun set_delay_exec_err_not_owner() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_set_delay(&state, MIN_DELAY+123, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // execute
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::SetDelayReq>();
        mtoken::execute_set_delay(&mut state, req, &_clock, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = mtoken::ENotEffective)]
fun set_delay_exec_err_not_effective() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_set_delay(&state, MIN_DELAY+123, &_clock, scenario.ctx()); // ok
        test_scenario::return_shared(state);
    };

    // execute
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::SetDelayReq>();
        mtoken::execute_set_delay(&mut state, req, &_clock, scenario.ctx());
    };
    abort
}

#[test]
fun set_delay_ok() {
    let mut scenario = init_xaum();
    let mut _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_set_delay(&state, MIN_DELAY+100, &_clock, scenario.ctx());
        assert_eq(state.delay(), INIT_DELAY);
        assert_eq(event::num_events(), 1);
        test_scenario::return_shared(state);
    };

    // execute
    _clock.increment_for_testing(INIT_DELAY * 1000);
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::SetDelayReq>();
        mtoken::execute_set_delay(&mut state, req, &_clock, scenario.ctx());
        assert_eq(state.delay(), MIN_DELAY+100);
        assert_eq(event::num_events(), 1);
        test_scenario::return_shared(state);
    };

    clock::destroy_for_testing(_clock);
    scenario.end();
}

#[test, expected_failure(abort_code = mtoken::ENotRevoker)]
fun set_delay_revoke_err_not_revoker() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_set_delay(&state, MIN_DELAY, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // revoke
    scenario.next_tx(ALICE);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::SetDelayReq>();
        mtoken::revoke_set_delay(&state, req, scenario.ctx());
    };
    abort
}

#[test]
fun set_delay_revoke_ok() {
    let mut scenario = init_xaum();

    // request
    scenario.next_tx(ADMIN);
    let mut _clock = clock::create_for_testing(scenario.ctx());
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_set_delay(&state, MIN_DELAY+1, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // revoke
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::SetDelayReq>();
        mtoken::revoke_set_delay(&state, req, scenario.ctx());
        test_scenario::return_shared(state);
    };

    clock::destroy_for_testing(_clock);
    scenario.end();
}

#[test, expected_failure(abort_code = mtoken::ENotOperator)]
fun change_mint_budget_err_not_operator() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::change_mint_budget(&mut state, 123, true, scenario.ctx());
    };
    abort
}

#[test, expected_failure]
fun change_mint_budget_exec_err_overflow() {
    let mut scenario = init_xaum();
    let mut _clock = clock::create_for_testing(scenario.ctx());

    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        state.set_mint_budget(234);
        mtoken::change_mint_budget(
            &mut state,
            18446744073709551615u64,
            true,
            scenario.ctx(),
        );
        test_scenario::return_shared(state);
    };
    abort // arithmetic error
}

#[test, expected_failure]
fun change_mint_budget_exec_err_underflow() {
    let mut scenario = init_xaum();
    let mut _clock = clock::create_for_testing(scenario.ctx());

    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::change_mint_budget(&mut state, 12345, false, scenario.ctx());
        test_scenario::return_shared(state);
    };
    abort // arithmetic error
}

#[test]
fun change_mint_budget_ok() {
    let mut scenario = init_xaum();
    let mut _clock = clock::create_for_testing(scenario.ctx());

    // +budget
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::change_mint_budget(&mut state, 1234, true, scenario.ctx());
        assert_eq(state.mint_budget(), 1234);
        assert_eq(event::num_events(), 1);
        test_scenario::return_shared(state);
    };

    // -budget
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::change_mint_budget(&mut state, 234, false, scenario.ctx());
        assert_eq(state.mint_budget(), 1000);
        assert_eq(event::num_events(), 1);
        test_scenario::return_shared(state);
    };

    clock::destroy_for_testing(_clock);
    scenario.end();
}

#[test, expected_failure(abort_code = mtoken::ENotOperator)]
fun mint_req_err_not_operator() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ALICE);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_mint_to(&state, ALICE, 100, &_clock, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = mtoken::ENotOperator)]
fun mint_exec_err_not_operator() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_mint_to(&state, ALICE, 100, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // execute
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::MintReq>();
        mtoken::execute_mint_to(&mut state, req, &_clock, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = mtoken::ENotEffective)]
fun mint_exec_err_not_effective() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_mint_to(&state, ALICE, 100, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // execute
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::MintReq>();
        mtoken::execute_mint_to(&mut state, req, &_clock, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = mtoken::EMintBudgetNotEnough)]
fun mint_exec_err_budget_not_enough() {
    let mut scenario = init_xaum();
    let mut _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_mint_to(&state, ALICE, 100, &_clock, scenario.ctx());
        _clock.increment_for_testing(INIT_DELAY * 1000);
        test_scenario::return_shared(state);
    };

    // execute
    _clock.increment_for_testing(INIT_DELAY * 1000);
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::MintReq>();
        mtoken::execute_mint_to(&mut state, req, &_clock, scenario.ctx());
    };
    abort
}

#[test]
fun mint_ok() {
    let mut scenario = init_xaum();

    // request mint
    scenario.next_tx(ADMIN);
    let mut _clock = clock::create_for_testing(scenario.ctx());
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_mint_to(&state, ALICE, 100, &_clock, scenario.ctx());
        assert_eq(event::num_events(), 1);
        test_scenario::return_shared(state);
    };

    // execute mint
    _clock.increment_for_testing(INIT_DELAY * 1000);
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        state.set_mint_budget(10000);
        let req = scenario.take_shared<mtoken::MintReq>();
        let req_id = object::id(&req);
        mtoken::execute_mint_to(&mut state, req, &_clock, scenario.ctx());
        assert_eq(event::num_events(), 1);
        assert_eq(
            event::events_by_type<mtoken::MintEvent>().pop_back(),
            mtoken::new_mint_event(ALICE, 100, 0, req_id),
        );
        assert_eq(state.mint_budget(), 10000 - 100);
        test_scenario::return_shared(state);
    };

    // check supply & balance
    scenario.next_tx(ALICE);
    {
        let _xaum = scenario.take_from_sender<Coin<MTOKEN_TESTS>>();
        assert_eq(_xaum.balance().value(), 100);
        scenario.return_to_sender(_xaum);
    };
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        assert_eq(state.total_supply(), 100);
        test_scenario::return_shared(state);
    };
    clock::destroy_for_testing(_clock);
    scenario.end();
}

#[test]
fun mint_twice_ok() {
    let mut scenario = init_xaum();
    let mut _clock = clock::create_for_testing(scenario.ctx());

    // mint#1
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        state.set_mint_budget(1000);
        mtoken::request_mint_to(&state, ALICE, 100, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };
    _clock.increment_for_testing(INIT_DELAY * 1000);
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::MintReq>();
        mtoken::execute_mint_to(&mut state, req, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    scenario.next_tx(ALICE);
    let id1 = scenario.most_recent_id_for_sender<Coin<MTOKEN_TESTS>>().extract();
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let _xaum = scenario.take_from_sender<Coin<MTOKEN_TESTS>>();
        assert_eq(state.mint_budget(), 1000 - 100);
        assert_eq(_xaum.balance().value(), 100);
        test_scenario::return_shared(state);
        scenario.return_to_sender(_xaum);
    };

    // mint#2
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_mint_to(&state, ALICE, 80, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };
    _clock.increment_for_testing(INIT_DELAY * 1000);
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::MintReq>();
        mtoken::execute_mint_to(&mut state, req, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    scenario.next_tx(ALICE);
    let id2 = scenario.most_recent_id_for_sender<Coin<MTOKEN_TESTS>>().extract();
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let _xaum = scenario.take_from_sender<Coin<MTOKEN_TESTS>>();
        assert_eq(state.mint_budget(), 1000 - 180);
        assert_eq(_xaum.balance().value(), 80);
        test_scenario::return_shared(state);
        scenario.return_to_sender(_xaum);
    };

    // check all coins
    scenario.next_tx(ALICE);
    {
        let _xaum1 = scenario.take_from_sender_by_id<Coin<MTOKEN_TESTS>>(id1);
        let _xaum2 = scenario.take_from_sender_by_id<Coin<MTOKEN_TESTS>>(id2);
        assert_eq(_xaum1.balance().value(), 100);
        assert_eq(_xaum2.balance().value(), 80);
        scenario.return_to_sender(_xaum1);
        scenario.return_to_sender(_xaum2);
    };

    clock::destroy_for_testing(_clock);
    scenario.end();
}

#[test, expected_failure(abort_code = mtoken::ENotRevoker)]
fun mint_revoke_err_not_revoker() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_mint_to(&state, ALICE, 80, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // revoke
    scenario.next_tx(ALICE);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::MintReq>();
        mtoken::revoke_mint_to(&state, req, scenario.ctx());
    };
    abort
}

#[test]
fun mint_revoke_ok() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // request
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        mtoken::request_mint_to(&state, ALICE, 80, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // revoke
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::MintReq>();
        mtoken::revoke_mint_to(&state, req, scenario.ctx());
        test_scenario::return_shared(state);
    };

    clock::destroy_for_testing(_clock);
    scenario.end();
}

#[test, expected_failure(abort_code = mtoken::ENotOperator)]
fun redeem_err_not_operator() {
    let mut scenario = init_xaum();
    let _clock = clock::create_for_testing(scenario.ctx());

    // burn
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let to_be_burnt = coin::from_balance(balance::zero<MTOKEN_TESTS>(), scenario.ctx());
        mtoken::redeem(&mut state, to_be_burnt, scenario.ctx());
    };
    abort
}

#[test]
fun redeem_ok() {
    let mut scenario = init_xaum();
    let mut _clock = clock::create_for_testing(scenario.ctx());

    // mint
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        state.set_mint_budget(10000);
        mtoken::request_mint_to(&state, ADMIN, 100, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };
    _clock.increment_for_testing(INIT_DELAY * 1000);
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::MintReq>();
        mtoken::execute_mint_to(&mut state, req, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // burn
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let mut _xaum = scenario.take_from_sender<Coin<MTOKEN_TESTS>>();
        let to_be_burnt = _xaum.split(30, scenario.ctx());
        mtoken::redeem(&mut state, to_be_burnt, scenario.ctx());
        assert_eq(event::num_events(), 1);
        assert_eq(
            event::events_by_type<mtoken::RedeemEvent>().pop_back(),
            mtoken::new_redeem_event(ADMIN, 30),
        );
        scenario.return_to_sender(_xaum);
        test_scenario::return_shared(state);
    };

    // check
    scenario.next_tx(ADMIN);
    {
        let state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        assert_eq(state.mint_budget(), 10000 - 70);
        assert_eq(state.total_supply(), 70);
        test_scenario::return_shared(state);

        let _xaum = scenario.take_from_sender<Coin<MTOKEN_TESTS>>();
        assert_eq(_xaum.balance().value(), 70);
        scenario.return_to_sender(_xaum);
    };

    clock::destroy_for_testing(_clock);
    scenario.end();
}

#[test, expected_failure(abort_code = mtoken::ENotOperator)]
fun block_err_not_operator() {
    let mut scenario = init_xaum();
    let mut _clock = clock::create_for_testing(scenario.ctx());

    // block
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let mut _deny_list = scenario.take_shared<DenyList>();
        mtoken::add_to_blocked_list(&mut state, ALICE, &mut _deny_list, scenario.ctx());
    };
    abort
}

#[test, expected_failure(abort_code = mtoken::ENotOperator)]
fun unblock_err_not_operator() {
    let mut scenario = init_xaum();
    let mut _clock = clock::create_for_testing(scenario.ctx());

    // unblock
    scenario.next_tx(ALICE);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let mut _deny_list = scenario.take_shared<DenyList>();
        mtoken::remove_from_blocked_list(&mut state, ALICE, &mut _deny_list, scenario.ctx());
    };
    abort
}

#[test]
fun block_unblock_ok() {
    let mut scenario = init_xaum();
    let mut _clock = clock::create_for_testing(scenario.ctx());

    // block
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let mut _deny_list = scenario.take_shared<DenyList>();
        mtoken::add_to_blocked_list(&mut state, ALICE, &mut _deny_list, scenario.ctx());
        assert_eq(event::num_events(), 2);
        assert_eq(
            event::events_by_type<mtoken::BlockEvent>().pop_back(),
            mtoken::new_block_event(ALICE),
        );
        assert_eq(
            coin::deny_list_v2_contains_current_epoch<MTOKEN_TESTS>(
                &_deny_list,
                ALICE,
                scenario.ctx(),
            ),
            false,
        );
        assert_eq(coin::deny_list_v2_contains_next_epoch<MTOKEN_TESTS>(&_deny_list, ALICE), true);
        test_scenario::return_shared(state);
        test_scenario::return_shared(_deny_list);
    };

    scenario.next_epoch(ADMIN);
    {
        let mut _deny_list = scenario.take_shared<DenyList>();
        assert_eq(
            coin::deny_list_v2_contains_current_epoch<MTOKEN_TESTS>(
                &_deny_list,
                ALICE,
                scenario.ctx(),
            ),
            true,
        );
        assert_eq(coin::deny_list_v2_contains_next_epoch<MTOKEN_TESTS>(&_deny_list, ALICE), true);
        test_scenario::return_shared(_deny_list);
    };

    // unblock
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let mut _deny_list = scenario.take_shared<DenyList>();
        mtoken::remove_from_blocked_list(&mut state, ALICE, &mut _deny_list, scenario.ctx());
        assert_eq(event::num_events(), 1);
        assert_eq(
            event::events_by_type<mtoken::UnblockEvent>().pop_back(),
            mtoken::new_unblock_event(ALICE),
        );
        test_scenario::return_shared(state);
        test_scenario::return_shared(_deny_list);
    };

    clock::destroy_for_testing(_clock);
    scenario.end();
}

#[test]
fun transfer_ok() {
    let mut scenario = init_xaum();

    // mint
    scenario.next_tx(ADMIN);
    let mut _clock = clock::create_for_testing(scenario.ctx());
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        state.set_mint_budget(10000);
        mtoken::request_mint_to(&state, ALICE, 100, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };
    _clock.increment_for_testing(INIT_DELAY * 1000);
    scenario.next_tx(ADMIN);
    {
        let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
        let req = scenario.take_shared<mtoken::MintReq>();
        mtoken::execute_mint_to(&mut state, req, &_clock, scenario.ctx());
        test_scenario::return_shared(state);
    };

    // transfer
    scenario.next_tx(ALICE);
    {
        let mut _xaum = scenario.take_from_sender<Coin<MTOKEN_TESTS>>();
        let to_be_send = _xaum.split(30, scenario.ctx());
        transfer::public_transfer(to_be_send, BOB);
        scenario.return_to_sender(_xaum);
    };

    // check
    scenario.next_tx(BOB);
    {
        let mut _xaum = scenario.take_from_sender<Coin<MTOKEN_TESTS>>();
        assert_eq(_xaum.balance().value(), 30);
        scenario.return_to_sender(_xaum);
    };

    clock::destroy_for_testing(_clock);
    scenario.end();
}

// #[test, expected_failure]
// fun transfer_err_denied_src() {
//     let mut scenario = init_xaum();
//     let mut _clock = clock::create_for_testing(scenario.ctx());

//     scenario.next_tx(SYS);
//     {
//         deny_list::create_for_test(scenario.ctx());
//     };

//     // mint
//     scenario.next_tx(ADMIN);
//     {
//         let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
//         state.set_mint_budget(10000);
//         mtoken::request_mint_to(&state, ALICE, 100, &_clock, scenario.ctx());
//         test_scenario::return_shared(state);
//     };
//     _clock.increment_for_testing(INIT_DELAY * 1000);
//     scenario.next_tx(ADMIN);
//     {
//         let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
//         let req = scenario.take_shared<mtoken::MintReq>();
//         mtoken::execute_mint_to(&mut state, req, &_clock, scenario.ctx());
//         test_scenario::return_shared(state);
//     };

//     // add in deny_list
//     scenario.next_tx(ADMIN);
//     {
//         let mut state = scenario.take_shared<mtoken::State<MTOKEN_TESTS>>();
//         let mut _deny_list = scenario.take_shared<DenyList>();
//         mtoken::add_to_blocked_list(&mut state, ALICE, &mut _deny_list, scenario.ctx());
//         mtoken::add_to_blocked_list(&mut state, BOB, &mut _deny_list, scenario.ctx());
//         test_scenario::return_shared(state);
//         test_scenario::return_shared(_deny_list);
//     };

//     // transfer
//     scenario.next_epoch(ALICE);
//     {
//         let mut _xaum = scenario.take_from_sender<Coin<MTOKEN_TESTS>>();
//         let to_be_send = _xaum.split(30, scenario.ctx());
//         transfer::public_transfer(to_be_send, BOB);
//         scenario.return_to_sender(_xaum);
//     };

//     clock::destroy_for_testing(_clock);
//     scenario.end();
// }
