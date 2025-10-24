#[test_only, allow(deprecated_usage)]
module x_oracle::gr_pricing_test {
    use sui::test_scenario::{Self, Scenario};
    use x_oracle::x_oracle::{Self, XOracle, XOraclePolicyCap, GrIndicatorCap};
    use sui::test_utils as sui_test_utils;
    use sui::clock::{Self, Clock};
    use x_oracle::pyth_mock_adapter::{Self as pyth_mock_adapter, PythRule};
    use x_oracle::test_utils;

    const ADMIN: address = @0xAD;

    public struct GR has drop {}
    public struct XAUM has drop {}
    public struct SUI has drop {}

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
    fun test_gr_pricing_override() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        // Configure GR coin type
        x_oracle::set_gr_coin_type<GR>(&mut x_oracle, &x_oracle_policy_cap, test_scenario::ctx(scenario));

        // Set formula params: alpha = 0.7, beta = 0.3
        let alpha = 700_000_000u64;
        let beta = 300_000_000u64;
        x_oracle::set_gr_formula_params(&mut x_oracle, &x_oracle_policy_cap, alpha, beta);

        // Set GR indicators
        // EMA120 = 100.0, EMA90 = 95.0, Spot = 90.0
        let ema120 = 100_000_000_000u64;
        let ema90 = 95_000_000_000u64;
        let spot = 90_000_000_000u64;
        x_oracle::set_gr_indicators(&mut x_oracle, &gr_indicator_cap, ema120, ema90, spot, 1000, test_scenario::ctx(scenario));

        // Expected sValue calculation:
        // inner = 0.3 * 95.0 + 0.7 * 90.0 = 28.5 + 63.0 = 91.5
        // sValue = 0.7 * 100.0 + 0.3 * 91.5 = 70.0 + 27.45 = 97.45
        // GR = sValue / 100 = 0.9745
        // Expected GR value (scaled to 9 decimals): 974_500_000

        // Now add price update rule for GR and update price
        x_oracle::add_primary_price_update_rule_v2<GR, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        let mut request = x_oracle::price_update_request(&x_oracle);
        
        // Try to set GR price to 1.5 from oracle, but it should be overridden to computed value
        let oracle_price = 1_500_000_000u64; // 1.5
        pyth_mock_adapter::update_price_as_primary<GR>(&mut request, oracle_price, 1000);
        x_oracle::confirm_price_update_request<GR>(&mut x_oracle, request, &clock);

        // Verify the price is the computed GR value, not the oracle price
        let price_fp = test_utils::get_price<GR>(&x_oracle, &clock);
        let price_value = std::fixed_point32::multiply_u64(1_000_000_000, price_fp);
        
        // Price should be around 974_500_000 (0.9745), not 1_500_000_000
        assert!(price_value < 1_000_000_000, 0); // Less than 1.0
        assert!(price_value > 900_000_000, 1);   // Greater than 0.9

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    #[test]
    fun test_gr_pricing_with_xaum_floor() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        // Configure GR and XAUM coin types
        x_oracle::set_gr_coin_type<GR>(&mut x_oracle, &x_oracle_policy_cap, test_scenario::ctx(scenario));
        x_oracle::set_xaum_coin_type<XAUM>(&mut x_oracle, &x_oracle_policy_cap, test_scenario::ctx(scenario));

        // Set formula params
        let alpha = 700_000_000u64; // 0.7
        let beta = 300_000_000u64;  // 0.3
        x_oracle::set_gr_formula_params(&mut x_oracle, &x_oracle_policy_cap, alpha, beta);

        // First, set XAUM price to a low value (e.g., 80.0)
        x_oracle::add_primary_price_update_rule_v2<XAUM, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        let mut xaum_request = x_oracle::price_update_request(&x_oracle);
        let xaum_price = 80_000_000_000u64; // 80.0
        pyth_mock_adapter::update_price_as_primary<XAUM>(&mut xaum_request, xaum_price, 1000);
        x_oracle::confirm_price_update_request<XAUM>(&mut x_oracle, xaum_request, &clock);

        // Set GR indicators that would result in sValue = 97.45 without floor
        // EMA120 = 100.0, EMA90 = 95.0, Spot = 90.0
        let ema120 = 100_000_000_000u64;
        let ema90 = 95_000_000_000u64;
        let spot = 90_000_000_000u64;
        x_oracle::set_gr_indicators(&mut x_oracle, &gr_indicator_cap, ema120, ema90, spot, 1000, test_scenario::ctx(scenario));

        // Expected sValue without floor = 97.45, but XAUM price is 80.0
        // So sValue should be floored to 80.0
        // GR = 80.0 / 100 = 0.8

        // Now update GR price
        x_oracle::add_primary_price_update_rule_v2<GR, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        let mut gr_request = x_oracle::price_update_request(&x_oracle);
        let oracle_gr_price = 1_500_000_000u64; // 1.5 (will be overridden)
        pyth_mock_adapter::update_price_as_primary<GR>(&mut gr_request, oracle_gr_price, 1000);
        x_oracle::confirm_price_update_request<GR>(&mut x_oracle, gr_request, &clock);

        // Verify the price is floored to XAUM / 100 = 0.8
        let price_fp = test_utils::get_price<GR>(&x_oracle, &clock);
        let price_value = std::fixed_point32::multiply_u64(1_000_000_000, price_fp);
        
        // Price should be around 800_000_000 (0.8)
        // Allow small rounding difference
        assert!(price_value >= 799_000_000 && price_value <= 801_000_000, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    #[test]
    fun test_non_gr_coin_not_affected() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        // Configure GR coin type (but we'll update SUI, not GR)
        x_oracle::set_gr_coin_type<GR>(&mut x_oracle, &x_oracle_policy_cap, test_scenario::ctx(scenario));

        // Set formula params and indicators
        x_oracle::set_gr_formula_params(&mut x_oracle, &x_oracle_policy_cap, 700_000_000, 300_000_000);
        x_oracle::set_gr_indicators(&mut x_oracle, &gr_indicator_cap, 100_000_000_000, 95_000_000_000, 90_000_000_000, 1000, test_scenario::ctx(scenario));

        // Update SUI price (not GR)
        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        let mut request = x_oracle::price_update_request(&x_oracle);
        let sui_price = 10_000_000_000u64; // 10.0
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request, sui_price, 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request, &clock);

        // Verify SUI price is exactly what we set (not overridden)
        let price_fp = test_utils::get_price<SUI>(&x_oracle, &clock);
        let price_value = std::fixed_point32::multiply_u64(1_000_000_000, price_fp);
        assert!(price_value == sui_price, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    #[test]
    fun test_gr_pricing_with_zero_computed_value() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        // Configure GR coin type
        x_oracle::set_gr_coin_type<GR>(&mut x_oracle, &x_oracle_policy_cap, test_scenario::ctx(scenario));

        // Don't set formula params or indicators (they default to 0)
        // This means gr_computed_value_u64 will be 0

        // Update GR price
        x_oracle::add_primary_price_update_rule_v2<GR, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        let mut request = x_oracle::price_update_request(&x_oracle);
        let oracle_price = 1_500_000_000u64; // 1.5
        pyth_mock_adapter::update_price_as_primary<GR>(&mut request, oracle_price, 1000);
        x_oracle::confirm_price_update_request<GR>(&mut x_oracle, request, &clock);

        // When gr_computed_value_u64 is 0, should use oracle price
        let price_fp = test_utils::get_price<GR>(&x_oracle, &clock);
        let price_value = std::fixed_point32::multiply_u64(1_000_000_000, price_fp);
        assert!(price_value == oracle_price, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    #[test]
    fun test_gr_pricing_formula_calculation() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        // Configure GR coin type
        x_oracle::set_gr_coin_type<GR>(&mut x_oracle, &x_oracle_policy_cap, test_scenario::ctx(scenario));

        // Test different formula parameters
        // Case 1: alpha = 0.5, beta = 0.5
        let alpha = 500_000_000u64; // 0.5
        let beta = 500_000_000u64;  // 0.5
        x_oracle::set_gr_formula_params(&mut x_oracle, &x_oracle_policy_cap, alpha, beta);

        // EMA120 = 100.0, EMA90 = 100.0, Spot = 100.0
        // Expected: sValue = 0.5 * 100 + 0.5 * (0.5 * 100 + 0.5 * 100) = 50 + 50 = 100
        // GR = 100 / 100 = 1.0
        let ema120 = 100_000_000_000u64;
        let ema90 = 100_000_000_000u64;
        let spot = 100_000_000_000u64;
        x_oracle::set_gr_indicators(&mut x_oracle, &gr_indicator_cap, ema120, ema90, spot, 1000, test_scenario::ctx(scenario));

        // Update GR price
        x_oracle::add_primary_price_update_rule_v2<GR, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        let mut request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<GR>(&mut request, 1_500_000_000, 1000);
        x_oracle::confirm_price_update_request<GR>(&mut x_oracle, request, &clock);

        let price_fp = test_utils::get_price<GR>(&x_oracle, &clock);
        let price_value = std::fixed_point32::multiply_u64(1_000_000_000, price_fp);
        
        // Price should be exactly 1_000_000_000 (1.0)
        assert!(price_value == 1_000_000_000, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    #[test]
    fun test_gr_pricing_with_different_indicators() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        x_oracle::set_gr_coin_type<GR>(&mut x_oracle, &x_oracle_policy_cap, test_scenario::ctx(scenario));

        // alpha = 1.0, beta = 0.0 (only use EMA120)
        let alpha = 1_000_000_000u64; // 1.0
        let beta = 0u64;              // 0.0
        x_oracle::set_gr_formula_params(&mut x_oracle, &x_oracle_policy_cap, alpha, beta);

        // EMA120 = 80.0, EMA90 = 100.0, Spot = 120.0
        // Expected: sValue = 1.0 * 80 + 0 * anything = 80
        // GR = 80 / 100 = 0.8
        let ema120 = 80_000_000_000u64;
        let ema90 = 100_000_000_000u64;
        let spot = 120_000_000_000u64;
        x_oracle::set_gr_indicators(&mut x_oracle, &gr_indicator_cap, ema120, ema90, spot, 1000, test_scenario::ctx(scenario));

        x_oracle::add_primary_price_update_rule_v2<GR, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        let mut request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<GR>(&mut request, 1_500_000_000, 1000);
        x_oracle::confirm_price_update_request<GR>(&mut x_oracle, request, &clock);

        let price_fp = test_utils::get_price<GR>(&x_oracle, &clock);
        let price_value = std::fixed_point32::multiply_u64(1_000_000_000, price_fp);
        
        // Price should be 800_000_000 (0.8)
        // Allow small rounding difference
        assert!(price_value >= 799_000_000 && price_value <= 801_000_000, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    // ========== Boundary Cases: alpha/beta Combinations ==========

    // Test: alpha=0, beta=0 (all weights zero)
    #[test]
    fun test_gr_pricing_alpha_zero_beta_zero() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        x_oracle::set_gr_coin_type<GR>(&mut x_oracle, &x_oracle_policy_cap, test_scenario::ctx(scenario));

        // alpha=0, beta=0
        x_oracle::set_gr_formula_params(&mut x_oracle, &x_oracle_policy_cap, 0, 0);

        // Set indicators
        x_oracle::set_gr_indicators(&mut x_oracle, &gr_indicator_cap, 100_000_000_000, 95_000_000_000, 90_000_000_000, 1000, test_scenario::ctx(scenario));

        // When alpha=0, beta=0: sValue = 0 * EMA120 + 1 * (0 * EMA90 + 1 * Spot) = Spot = 90
        // GR = 90 / 100 = 0.9
        x_oracle::add_primary_price_update_rule_v2<GR, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        let mut request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<GR>(&mut request, 1_500_000_000, 1000);
        x_oracle::confirm_price_update_request<GR>(&mut x_oracle, request, &clock);

        let price_fp = test_utils::get_price<GR>(&x_oracle, &clock);
        let price_value = std::fixed_point32::multiply_u64(1_000_000_000, price_fp);
        assert!(price_value >= 899_000_000 && price_value <= 901_000_000, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    // Test: alpha=1, beta=1 (all weights maximum)
    #[test]
    fun test_gr_pricing_alpha_one_beta_one() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        x_oracle::set_gr_coin_type<GR>(&mut x_oracle, &x_oracle_policy_cap, test_scenario::ctx(scenario));

        // alpha=1, beta=1
        x_oracle::set_gr_formula_params(&mut x_oracle, &x_oracle_policy_cap, 1_000_000_000, 1_000_000_000);

        // EMA120 = 100.0, EMA90 = 95.0, Spot = 90.0
        // sValue = 1.0 * 100 + 0 * (1.0 * 95 + 0 * 90) = 100
        // GR = 100 / 100 = 1.0
        x_oracle::set_gr_indicators(&mut x_oracle, &gr_indicator_cap, 100_000_000_000, 95_000_000_000, 90_000_000_000, 1000, test_scenario::ctx(scenario));

        x_oracle::add_primary_price_update_rule_v2<GR, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        let mut request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<GR>(&mut request, 1_500_000_000, 1000);
        x_oracle::confirm_price_update_request<GR>(&mut x_oracle, request, &clock);

        let price_fp = test_utils::get_price<GR>(&x_oracle, &clock);
        let price_value = std::fixed_point32::multiply_u64(1_000_000_000, price_fp);
        // Should be 1_000_000_000 (1.0)
        assert!(price_value >= 999_000_000 && price_value <= 1_001_000_000, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    // Test: alpha=0, beta=1 (only use EMA90)
    #[test]
    fun test_gr_pricing_alpha_zero_beta_one() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        x_oracle::set_gr_coin_type<GR>(&mut x_oracle, &x_oracle_policy_cap, test_scenario::ctx(scenario));

        // alpha=0, beta=1
        x_oracle::set_gr_formula_params(&mut x_oracle, &x_oracle_policy_cap, 0, 1_000_000_000);

        // EMA120 = 100.0, EMA90 = 80.0, Spot = 90.0
        // sValue = 0 * 100 + 1 * (1 * 80 + 0 * 90) = 80
        // GR = 80 / 100 = 0.8
        x_oracle::set_gr_indicators(&mut x_oracle, &gr_indicator_cap, 100_000_000_000, 80_000_000_000, 90_000_000_000, 1000, test_scenario::ctx(scenario));

        x_oracle::add_primary_price_update_rule_v2<GR, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        let mut request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<GR>(&mut request, 1_500_000_000, 1000);
        x_oracle::confirm_price_update_request<GR>(&mut x_oracle, request, &clock);

        let price_fp = test_utils::get_price<GR>(&x_oracle, &clock);
        let price_value = std::fixed_point32::multiply_u64(1_000_000_000, price_fp);
        assert!(price_value >= 799_000_000 && price_value <= 801_000_000, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    // Test: partial indicator is zero
    #[test]
    fun test_gr_pricing_with_zero_ema120() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        x_oracle::set_gr_coin_type<GR>(&mut x_oracle, &x_oracle_policy_cap, test_scenario::ctx(scenario));
        x_oracle::set_gr_formula_params(&mut x_oracle, &x_oracle_policy_cap, 500_000_000, 500_000_000);

        // EMA120 = 0 -> sValue should become 0
        x_oracle::set_gr_indicators(&mut x_oracle, &gr_indicator_cap, 0, 95_000_000_000, 90_000_000_000, 1000, test_scenario::ctx(scenario));

        x_oracle::add_primary_price_update_rule_v2<GR, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        let mut request = x_oracle::price_update_request(&x_oracle);
        let oracle_price = 1_500_000_000u64;
        pyth_mock_adapter::update_price_as_primary<GR>(&mut request, oracle_price, 1000);
        x_oracle::confirm_price_update_request<GR>(&mut x_oracle, request, &clock);

        // When any indicator is 0, gr_computed_value_u64 = 0, should use oracle price
        let price_fp = test_utils::get_price<GR>(&x_oracle, &clock);
        let price_value = std::fixed_point32::multiply_u64(1_000_000_000, price_fp);
        assert!(price_value == oracle_price, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    // Test: XAUM coin type configured but no XAUM price set
    #[test]
    fun test_gr_pricing_xaum_type_set_but_no_price() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        x_oracle::set_gr_coin_type<GR>(&mut x_oracle, &x_oracle_policy_cap, test_scenario::ctx(scenario));
        x_oracle::set_xaum_coin_type<XAUM>(&mut x_oracle, &x_oracle_policy_cap, test_scenario::ctx(scenario));
        
        // Set params and indicators
        x_oracle::set_gr_formula_params(&mut x_oracle, &x_oracle_policy_cap, 500_000_000, 500_000_000);
        x_oracle::set_gr_indicators(&mut x_oracle, &gr_indicator_cap, 100_000_000_000, 100_000_000_000, 100_000_000_000, 1000, test_scenario::ctx(scenario));

        // Note: XAUM price not set
        // sValue = 100, but since XAUM price doesn't exist, floor should not trigger, use computed value
        x_oracle::add_primary_price_update_rule_v2<GR, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        let mut request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<GR>(&mut request, 1_500_000_000, 1000);
        x_oracle::confirm_price_update_request<GR>(&mut x_oracle, request, &clock);

        let price_fp = test_utils::get_price<GR>(&x_oracle, &clock);
        let price_value = std::fixed_point32::multiply_u64(1_000_000_000, price_fp);
        // Should be 100/100 = 1.0
        assert!(price_value >= 999_000_000 && price_value <= 1_001_000_000, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    // Test: verify GR indicators can be updated multiple times (idempotence)
    #[test]
    fun test_gr_indicators_can_be_updated_multiple_times() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);

        x_oracle::set_gr_formula_params(&mut x_oracle, &x_oracle_policy_cap, 500_000_000, 500_000_000);

        // First set
        x_oracle::set_gr_indicators(&mut x_oracle, &gr_indicator_cap, 100_000_000_000, 95_000_000_000, 90_000_000_000, 1000, test_scenario::ctx(scenario));
        assert!(x_oracle::gr_indicator_last_updated(&x_oracle) == 1000, 0);

        // Second update (timestamp incremented)
        x_oracle::set_gr_indicators(&mut x_oracle, &gr_indicator_cap, 110_000_000_000, 105_000_000_000, 100_000_000_000, 2000, test_scenario::ctx(scenario));
        assert!(x_oracle::gr_indicator_last_updated(&x_oracle) == 2000, 1);

        // Third update
        x_oracle::set_gr_indicators(&mut x_oracle, &gr_indicator_cap, 120_000_000_000, 115_000_000_000, 110_000_000_000, 3000, test_scenario::ctx(scenario));
        assert!(x_oracle::gr_indicator_last_updated(&x_oracle) == 3000, 2);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    // Test: XAUM floor boundary case - XAUM price exactly equals computed sValue
    #[test]
    fun test_xaum_floor_exact_match() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        x_oracle::set_gr_coin_type<GR>(&mut x_oracle, &x_oracle_policy_cap, test_scenario::ctx(scenario));
        x_oracle::set_xaum_coin_type<XAUM>(&mut x_oracle, &x_oracle_policy_cap, test_scenario::ctx(scenario));
        x_oracle::set_gr_formula_params(&mut x_oracle, &x_oracle_policy_cap, 1_000_000_000, 0);

        // First set XAUM price = 100
        x_oracle::add_primary_price_update_rule_v2<XAUM, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        let mut xaum_request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<XAUM>(&mut xaum_request, 100_000_000_000, 1000);
        x_oracle::confirm_price_update_request<XAUM>(&mut x_oracle, xaum_request, &clock);

        // Set indicators: EMA120 = 100 -> sValue = 100 (equals XAUM)
        x_oracle::set_gr_indicators(&mut x_oracle, &gr_indicator_cap, 100_000_000_000, 0, 0, 1000, test_scenario::ctx(scenario));

        // Update GR price
        x_oracle::add_primary_price_update_rule_v2<GR, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        let mut gr_request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<GR>(&mut gr_request, 999_999_999, 1000);
        x_oracle::confirm_price_update_request<GR>(&mut x_oracle, gr_request, &clock);

        // sValue = XAUM = 100, GR = 1.0
        let price_fp = test_utils::get_price<GR>(&x_oracle, &clock);
        let price_value = std::fixed_point32::multiply_u64(1_000_000_000, price_fp);
        assert!(price_value >= 999_000_000 && price_value <= 1_001_000_000, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }

    // Test: XAUM floor boundary case - XAUM price slightly lower than sValue
    #[test]
    fun test_xaum_floor_slightly_lower() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap, gr_indicator_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        x_oracle::set_gr_coin_type<GR>(&mut x_oracle, &x_oracle_policy_cap, test_scenario::ctx(scenario));
        x_oracle::set_xaum_coin_type<XAUM>(&mut x_oracle, &x_oracle_policy_cap, test_scenario::ctx(scenario));
        x_oracle::set_gr_formula_params(&mut x_oracle, &x_oracle_policy_cap, 1_000_000_000, 0);

        // XAUM price = 99.9
        x_oracle::add_primary_price_update_rule_v2<XAUM, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        let mut xaum_request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<XAUM>(&mut xaum_request, 99_900_000_000, 1000);
        x_oracle::confirm_price_update_request<XAUM>(&mut x_oracle, xaum_request, &clock);

        // EMA120 = 100 -> sValue = 100 (higher than XAUM)
        x_oracle::set_gr_indicators(&mut x_oracle, &gr_indicator_cap, 100_000_000_000, 0, 0, 1000, test_scenario::ctx(scenario));

        x_oracle::add_primary_price_update_rule_v2<GR, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        let mut gr_request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<GR>(&mut gr_request, 999_999_999, 1000);
        x_oracle::confirm_price_update_request<GR>(&mut x_oracle, gr_request, &clock);

        // Should use XAUM floor = 99.9, GR = 0.999
        let price_fp = test_utils::get_price<GR>(&x_oracle, &clock);
        let price_value = std::fixed_point32::multiply_u64(1_000_000_000, price_fp);
        assert!(price_value >= 998_000_000 && price_value <= 1_000_000_000, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        sui_test_utils::destroy(gr_indicator_cap);
        test_scenario::end(scenario_value);
    }
}


