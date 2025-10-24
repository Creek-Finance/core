#[test_only]
module xaum_indicator_core::xaum_indicator_core_test {
    use sui::test_scenario;
    use sui::test_utils as sui_test_utils;
    use sui::clock as clock;

    use x_oracle::x_oracle::{Self as x_oracle, XOracle, XOraclePolicyCap, GrIndicatorCap};
    use xaum_indicator_core::xaum_indicator_core as core;

    const ADMIN: address = @0xA11CE;

    fun get_e(storage: &core::PriceStorage): u64 {
        (core::get_ema120_current(storage) / 1000000000u256) as u64
    }

    fun check(prev: u64, price: u64, cur: u64) {
        if (price >= prev) { assert!(cur >= prev && cur <= price, 0) } else { assert!(cur <= prev && cur >= price, 0) }
    }

    // Helper: initialize XOracle shared object and policy caps, and create a testing clock
    fun init_oracle_and_clock(
        scenario: &mut test_scenario::Scenario,
    ): (clock::Clock, XOracle, XOraclePolicyCap) {
        x_oracle::init_t(test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, ADMIN);
        let clk = clock::create_for_testing(test_scenario::ctx(scenario));
        let mut xo = test_scenario::take_shared<XOracle>(scenario);
        let xocap = test_scenario::take_from_address<XOraclePolicyCap>(scenario, ADMIN);
        x_oracle::init_rules_df_if_not_exist(&xocap, &mut xo, test_scenario::ctx(scenario));
        (clk, xo, xocap)
    }

    // Helper: create core storage and bind dedicated GrIndicatorCap
    fun create_storage_and_bind_cap(
        scenario: &mut test_scenario::Scenario,
    ): core::PriceStorage {
        let mut storage = core::create_price_storage(test_scenario::ctx(scenario));
        let gr_cap = test_scenario::take_from_address<GrIndicatorCap>(scenario, ADMIN);
        core::bind_gr_cap(&mut storage, gr_cap, test_scenario::ctx(scenario));
        storage
    }

    // Test: set price (9-dec), advance EMA, and push GR indicators to XOracle; assert timestamp updated
    #[test]
    fun test_create_and_set_price_and_push_gr() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        // init XOracle shared + caps and clock
        let (mut clk, mut xo, xocap) = init_oracle_and_clock(scenario);

        // create core storage
        let mut storage = create_storage_and_bind_cap(scenario);

        // set price (9-dec input → scaled to 1e18), advance EMA, then push indicators to XOracle
        clock::set_for_testing(&mut clk, 1000 * 1000);
        core::set_price_9dec(&mut storage, /*9-dec*/ 123_456_789, &mut xo, &clk, test_scenario::ctx(scenario));

        // after push, XOracle's cached last_updated should equal now; indicators cached
        assert!(x_oracle::gr_indicator_last_updated(&xo) == 1000, 0);

        // push another price; timestamp must be monotonically increasing
        clock::set_for_testing(&mut clk, 2000 * 1000);
        core::set_price_9dec(&mut storage, 223_456_789, &mut xo, &clk, test_scenario::ctx(scenario));
        assert!(x_oracle::gr_indicator_last_updated(&xo) == 2000, 0);

        // cleanup resources
        transfer::public_share_object(storage);
        sui_test_utils::destroy(clk);
        sui_test_utils::destroy(xo);
        sui_test_utils::destroy(xocap);
        // storage is shared, not destroyed; end test
        test_scenario::end(scenario_value);
    }

    

    // Test: pushing indicators without binding GrIndicatorCap must abort
    #[test, expected_failure]
    fun test_push_without_gr_cap_should_fail() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clk, mut xo, xocap) = init_oracle_and_clock(scenario);

        let storage = core::create_price_storage(test_scenario::ctx(scenario));
        // no cap bound here
        clock::set_for_testing(&mut clk, 1000 * 1000);
        core::push_gr_indicators_to_x_oracle(&storage, &mut xo, &clk, test_scenario::ctx(scenario));

        // cleanup (unreachable on success)
        transfer::public_share_object(storage);
        sui_test_utils::destroy(clk);
        sui_test_utils::destroy(xo);
        sui_test_utils::destroy(xocap);
        test_scenario::end(scenario_value);
    }

    // Test: setting zero price (9-dec) should abort due to > 0 assertion
    #[test, expected_failure(abort_code = 0, location = xaum_indicator_core::xaum_indicator_core)]
    fun test_set_price_zero_should_fail() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clk, mut xo, xocap) = init_oracle_and_clock(scenario);

        let mut storage = create_storage_and_bind_cap(scenario);

        clock::set_for_testing(&mut clk, 1000 * 1000);
        core::set_price_9dec(&mut storage, 0, &mut xo, &clk, test_scenario::ctx(scenario));

        transfer::public_share_object(storage);
        sui_test_utils::destroy(clk);
        sui_test_utils::destroy(xo);
        sui_test_utils::destroy(xocap);
        test_scenario::end(scenario_value);
    }

    // Test: second push with an earlier timestamp must fail (monotonic timestamp enforced in XOracle)
    #[test, expected_failure]
    fun test_decreasing_clock_should_fail_on_monotonicity() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clk, mut xo, xocap) = init_oracle_and_clock(scenario);

        let mut storage = create_storage_and_bind_cap(scenario);

        // first push at t=2000
        clock::set_for_testing(&mut clk, 2000 * 1000);
        core::set_price_9dec(&mut storage, 100_000_000, &mut xo, &clk, test_scenario::ctx(scenario));

        // then push at earlier time t=1500, should fail monotonicity in XOracle
        clock::set_for_testing(&mut clk, 1500 * 1000);
        core::set_price_9dec(&mut storage, 101_000_000, &mut xo, &clk, test_scenario::ctx(scenario));

        transfer::public_share_object(storage);
        sui_test_utils::destroy(clk);
        sui_test_utils::destroy(xo);
        sui_test_utils::destroy(xocap);
        test_scenario::end(scenario_value);
    }

    // Test: feed 10 designed prices; EMA120 should move towards the new price each step without overshooting
    #[test]
    fun test_ema120_sequence_correctness() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clk, mut xo, xocap) = init_oracle_and_clock(scenario);

        let mut storage = create_storage_and_bind_cap(scenario);

        // predefined 10 prices (9-decimals), first initializes EMA
        let p0: u64 = 120_000_000;
        let p1: u64 = 121_000_000;
        let p2: u64 = 119_500_000;
        let p3: u64 = 122_200_000;
        let p4: u64 = 121_800_000;
        let p5: u64 = 123_000_000;
        let p6: u64 = 122_500_000;
        let p7: u64 = 121_200_000;
        let p8: u64 = 120_700_000;
        let p9: u64 = 121_300_000;

        // step 0
        clock::set_for_testing(&mut clk, 1000 * 1000);
        core::set_price_9dec(&mut storage, p0, &mut xo, &clk, test_scenario::ctx(scenario));
        let e0 = get_e(&storage);
        assert!(e0 == p0, 0);

        clock::set_for_testing(&mut clk, 1001 * 1000);
        core::set_price_9dec(&mut storage, p1, &mut xo, &clk, test_scenario::ctx(scenario));
        let e1 = get_e(&storage);
        check(e0, p1, e1);

        clock::set_for_testing(&mut clk, 1002 * 1000);
        core::set_price_9dec(&mut storage, p2, &mut xo, &clk, test_scenario::ctx(scenario));
        let e2 = get_e(&storage);
        check(e1, p2, e2);

        clock::set_for_testing(&mut clk, 1003 * 1000);
        core::set_price_9dec(&mut storage, p3, &mut xo, &clk, test_scenario::ctx(scenario));
        let e3 = get_e(&storage);
        check(e2, p3, e3);

        clock::set_for_testing(&mut clk, 1004 * 1000);
        core::set_price_9dec(&mut storage, p4, &mut xo, &clk, test_scenario::ctx(scenario));
        let e4 = get_e(&storage);
        check(e3, p4, e4);

        clock::set_for_testing(&mut clk, 1005 * 1000);
        core::set_price_9dec(&mut storage, p5, &mut xo, &clk, test_scenario::ctx(scenario));
        let e5 = get_e(&storage);
        check(e4, p5, e5);

        clock::set_for_testing(&mut clk, 1006 * 1000);
        core::set_price_9dec(&mut storage, p6, &mut xo, &clk, test_scenario::ctx(scenario));
        let e6 = get_e(&storage);
        check(e5, p6, e6);

        clock::set_for_testing(&mut clk, 1007 * 1000);
        core::set_price_9dec(&mut storage, p7, &mut xo, &clk, test_scenario::ctx(scenario));
        let e7 = get_e(&storage);
        check(e6, p7, e7);

        clock::set_for_testing(&mut clk, 1008 * 1000);
        core::set_price_9dec(&mut storage, p8, &mut xo, &clk, test_scenario::ctx(scenario));
        let e8 = get_e(&storage);
        check(e7, p8, e8);

        clock::set_for_testing(&mut clk, 1009 * 1000);
        core::set_price_9dec(&mut storage, p9, &mut xo, &clk, test_scenario::ctx(scenario));
        let e9 = get_e(&storage);
        check(e8, p9, e9);

        transfer::public_share_object(storage);
        sui_test_utils::destroy(clk);
        sui_test_utils::destroy(xo);
        sui_test_utils::destroy(xocap);
        test_scenario::end(scenario_value);
    }
}



