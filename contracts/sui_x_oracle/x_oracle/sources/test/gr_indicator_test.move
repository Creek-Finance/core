#[test_only, allow(deprecated_usage, unused_let_mut)]
module x_oracle::gr_indicator_test {
    use sui::test_scenario::{Self, Scenario};
    use x_oracle::x_oracle::{Self, XOracle, XOraclePolicyCap, GrIndicatorCap};
    use sui::test_utils as sui_test_utils;
    use sui::clock::{Self, Clock};

    const ADMIN: address = @0xAD;

    public struct GR has drop {}
    public struct XAUM has drop {}

    fun init_internal(scenario: &mut Scenario): (Clock, XOracle, XOraclePolicyCap, GrIndicatorCap) {
        x_oracle::init_t(test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, ADMIN);
        
        let clock = clock::create_for_testing(test_scenario::ctx(scenario));
        let x_oracle = test_scenario::take_shared<XOracle>(scenario);
        let x_oracle_policy_cap = test_scenario::take_from_address<XOraclePolicyCap>(scenario, ADMIN);
        let gr_indicator_cap = test_scenario::take_from_address<GrIndicatorCap>(scenario, ADMIN);

        (clock, x_oracle, x_oracle_policy_cap, gr_indicator_cap)
    }

    #[test]
    fun test_set_and_get_gr_indicator() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        
        // Initially should be 0
        assert!(x_oracle::gr_indicator_value(&x_oracle) == 0, 0);
        assert!(x_oracle::gr_indicator_last_updated(&x_oracle) == 0, 1);

        // Set GR indicator value (scaled to 9 decimals: 1.5 = 1_500_000_000)
        let value = 1_500_000_000u64; // 1.5
        let timestamp = 1000u64;
        x_oracle::set_gr_indicator(&mut x_oracle, &gr_indicator_cap, value, timestamp, test_scenario::ctx(scenario));

        // Verify values are set
        assert!(x_oracle::gr_indicator_value(&x_oracle) == value, 2);
        assert!(x_oracle::gr_indicator_last_updated(&x_oracle) == timestamp, 3);

        // Update to a new value with later timestamp
        let new_value = 2_000_000_000u64; // 2.0
        let new_timestamp = 2000u64;
        x_oracle::set_gr_indicator(&mut x_oracle, &gr_indicator_cap, new_value, new_timestamp, test_scenario::ctx(scenario));

        assert!(x_oracle::gr_indicator_value(&x_oracle) == new_value, 4);
        assert!(x_oracle::gr_indicator_last_updated(&x_oracle) == new_timestamp, 5);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    #[test]
    #[expected_failure]
    fun test_set_gr_indicator_non_monotonic_time_should_fail() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        
        // Set initial value
        x_oracle::set_gr_indicator(&mut x_oracle, &gr_indicator_cap, 1_000_000_000, 2000, test_scenario::ctx(scenario));

        // Try to set with earlier timestamp - should fail
        x_oracle::set_gr_indicator(&mut x_oracle, &gr_indicator_cap, 1_500_000_000, 1000, test_scenario::ctx(scenario));

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    #[test]
    #[expected_failure]
    fun test_set_gr_indicator_zero_value_should_fail() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        
        // Try to set zero value - should fail
        x_oracle::set_gr_indicator(&mut x_oracle, &gr_indicator_cap, 0, 1000, test_scenario::ctx(scenario));

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    #[test]
    fun test_set_gr_coin_type() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        
        // Set GR coin type
        x_oracle::set_gr_coin_type<GR>(&mut x_oracle, &x_oracle_policy_cap, test_scenario::ctx(scenario));

        // Note: We don't have a getter for gr_coin_type, but the function should execute without error
        // The actual effect will be tested in gr_pricing_test.move

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    #[test]
    fun test_set_xaum_coin_type() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        
        // Set XAUM coin type
        x_oracle::set_xaum_coin_type<XAUM>(&mut x_oracle, &x_oracle_policy_cap, test_scenario::ctx(scenario));

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    #[test]
    fun test_set_gr_formula_params() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        
        // Set alpha = 0.7 (700_000_000), beta = 0.3 (300_000_000)
        let alpha = 700_000_000u64;
        let beta = 300_000_000u64;
        x_oracle::set_gr_formula_params(&mut x_oracle, &x_oracle_policy_cap, alpha, beta);

        // Function should execute without error
        // The actual effect will be tested in gr_pricing_test.move

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    #[test]
    #[expected_failure]
    fun test_set_gr_formula_params_alpha_too_large() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        
        // Try to set alpha > 1e9 - should fail
        let alpha = 1_000_000_001u64;
        let beta = 500_000_000u64;
        x_oracle::set_gr_formula_params(&mut x_oracle, &x_oracle_policy_cap, alpha, beta);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    #[test]
    #[expected_failure]
    fun test_set_gr_formula_params_beta_too_large() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        
        // Try to set beta > 1e9 - should fail
        let alpha = 500_000_000u64;
        let beta = 1_000_000_001u64;
        x_oracle::set_gr_formula_params(&mut x_oracle, &x_oracle_policy_cap, alpha, beta);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    #[test]
    fun test_set_gr_indicators_basic() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        
        // Set formula params first
        let alpha = 700_000_000u64; // 0.7
        let beta = 300_000_000u64;  // 0.3
        x_oracle::set_gr_formula_params(&mut x_oracle, &x_oracle_policy_cap, alpha, beta);

        // Set GR indicators
        let ema120 = 100_000_000_000u64; // 100.0
        let ema90 = 95_000_000_000u64;   // 95.0
        let spot = 90_000_000_000u64;    // 90.0
        let timestamp = 1000u64;

        x_oracle::set_gr_indicators(&mut x_oracle, &gr_indicator_cap, ema120, ema90, spot, timestamp, test_scenario::ctx(scenario));

        // Check timestamp was updated
        assert!(x_oracle::gr_indicator_last_updated(&x_oracle) == timestamp, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    #[test]
    #[expected_failure]
    fun test_set_gr_indicators_non_monotonic_time_should_fail() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        
        // Set formula params
        x_oracle::set_gr_formula_params(&mut x_oracle, &x_oracle_policy_cap, 700_000_000, 300_000_000);

        // Set initial indicators
        x_oracle::set_gr_indicators(&mut x_oracle, &gr_indicator_cap, 100_000_000_000, 95_000_000_000, 90_000_000_000, 2000, test_scenario::ctx(scenario));

        // Try to set with earlier timestamp - should fail
        x_oracle::set_gr_indicators(&mut x_oracle, &gr_indicator_cap, 100_000_000_000, 95_000_000_000, 90_000_000_000, 1000, test_scenario::ctx(scenario));

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }
}

