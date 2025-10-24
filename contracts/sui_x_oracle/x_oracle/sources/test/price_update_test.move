#[test_only, allow(deprecated_usage)]
module x_oracle::price_update_test {
    use sui::test_scenario::{Self, Scenario};
    use x_oracle::x_oracle::{Self, XOracle, XOraclePolicyCap};
    use sui::test_utils as sui_test_utils;
    use sui::sui::SUI;
    use sui::math;
    use sui::clock::{Self, Clock};
    use std::fixed_point32;
    use x_oracle::pyth_mock_adapter::{Self as pyth_mock_adapter, PythRule};
    use x_oracle::supra_mock_adapter::{Self as supra_mock_adapter, SupraRule};
    use x_oracle::switchboard_mock_adapter::{Self as switchboard_mock_adapter, SwitchboardRule};
    use x_oracle::test_utils;
    use x_oracle::price_feed;

    const ADMIN: address = @0xAD;

    public struct ETH has drop {}
    public struct USDC has drop {}

    fun init_internal(scenario: &mut Scenario): (Clock, XOracle, XOraclePolicyCap) {
        x_oracle::init_t(test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, ADMIN);
        
        let clock = clock::create_for_testing(test_scenario::ctx(scenario));
        let x_oracle = test_scenario::take_shared<XOracle>(scenario);
        let x_oracle_policy_cap = test_scenario::take_from_address<XOraclePolicyCap>(scenario, ADMIN);

        (clock, x_oracle, x_oracle_policy_cap)
    }

    // ========== Basic Primary Price Update Tests ==========

    #[test]
    fun test_primary_price_update_basic() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        // Add primary rule for SUI
        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        
        // Update price
        let mut request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request, &clock);

        // Verify price
        assert!(fixed_point32::multiply_u64(1, test_utils::get_price<SUI>(&x_oracle, &clock)) == 10, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    #[test]
    fun test_primary_price_update_multiple_coins() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        // Add primary rules for different coins with different adapters
        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_primary_price_update_rule_v2<ETH, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_primary_price_update_rule_v2<USDC, SwitchboardRule>(&mut x_oracle, &x_oracle_policy_cap);
        
        // Update SUI price
        let mut request_sui = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request_sui, 10 * math::pow(10, price_feed::decimals()), 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request_sui, &clock);

        // Update ETH price
        let mut request_eth = x_oracle::price_update_request(&x_oracle);
        supra_mock_adapter::update_price_as_primary<ETH>(&mut request_eth, 1000 * math::pow(10, price_feed::decimals()), 1000);
        x_oracle::confirm_price_update_request<ETH>(&mut x_oracle, request_eth, &clock);

        // Update USDC price
        let mut request_usdc = x_oracle::price_update_request(&x_oracle);
        switchboard_mock_adapter::update_price_as_primary<USDC>(&mut request_usdc, 1 * math::pow(10, price_feed::decimals()), 1000);
        x_oracle::confirm_price_update_request<USDC>(&mut x_oracle, request_usdc, &clock);

        // Verify all prices
        assert!(fixed_point32::multiply_u64(1, test_utils::get_price<SUI>(&x_oracle, &clock)) == 10, 0);
        assert!(fixed_point32::multiply_u64(1, test_utils::get_price<ETH>(&x_oracle, &clock)) == 1000, 1);
        assert!(fixed_point32::multiply_u64(1, test_utils::get_price<USDC>(&x_oracle, &clock)) == 1, 2);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    #[test]
    #[expected_failure(abort_code = 721)]
    fun test_two_primary_rules_should_fail() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        // Add two primary rules for the same coin - should work
        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_primary_price_update_rule_v2<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        
        // But trying to update with both should fail
        let mut request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        supra_mock_adapter::update_price_as_primary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request, &clock);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    // ========== Primary + Secondary Price Update Tests ==========

    #[test]
    fun test_primary_with_one_secondary() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule_v2<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        
        let mut request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        supra_mock_adapter::update_price_as_secondary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request, &clock);

        assert!(fixed_point32::multiply_u64(1, test_utils::get_price<SUI>(&x_oracle, &clock)) == 10, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    #[test]
    fun test_primary_with_multiple_secondary() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule_v2<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule_v2<SUI, SwitchboardRule>(&mut x_oracle, &x_oracle_policy_cap);
        
        let mut request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        supra_mock_adapter::update_price_as_secondary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        switchboard_mock_adapter::update_price_as_secondary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request, &clock);

        assert!(fixed_point32::multiply_u64(1, test_utils::get_price<SUI>(&x_oracle, &clock)) == 10, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    // ========== Price Validation Tests (1% threshold) ==========

    #[test]
    fun test_price_validation_within_threshold() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule_v2<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule_v2<SUI, SwitchboardRule>(&mut x_oracle, &x_oracle_policy_cap);
        
        let mut request = x_oracle::price_update_request(&x_oracle);
        // Primary: 10.0, Secondary1: 9.9 (-1%), Secondary2: 10.1 (+1%)
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        supra_mock_adapter::update_price_as_secondary<SUI>(&mut request, 99 * math::pow(10, price_feed::decimals()) / 10, 1000);
        switchboard_mock_adapter::update_price_as_secondary<SUI>(&mut request, 101 * math::pow(10, price_feed::decimals()) / 10, 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request, &clock);

        // Should succeed - all within 1% threshold
        assert!(fixed_point32::multiply_u64(1, test_utils::get_price<SUI>(&x_oracle, &clock)) == 10, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    #[test]
    fun test_price_validation_one_outside_threshold_but_majority_within() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule_v2<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule_v2<SUI, SwitchboardRule>(&mut x_oracle, &x_oracle_policy_cap);
        
        let mut request = x_oracle::price_update_request(&x_oracle);
        // Primary: 10.0, Secondary1: 9.5 (-5%, outside threshold), Secondary2: 10.1 (+1%, within)
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        supra_mock_adapter::update_price_as_secondary<SUI>(&mut request, 95 * math::pow(10, price_feed::decimals()) / 10, 1000);
        switchboard_mock_adapter::update_price_as_secondary<SUI>(&mut request, 101 * math::pow(10, price_feed::decimals()) / 10, 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request, &clock);

        // Should succeed - majority (1 out of 2) within threshold
        assert!(fixed_point32::multiply_u64(1, test_utils::get_price<SUI>(&x_oracle, &clock)) == 10, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    #[test]
    #[expected_failure(abort_code = 720)]
    fun test_price_validation_majority_outside_threshold_should_fail() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule_v2<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule_v2<SUI, SwitchboardRule>(&mut x_oracle, &x_oracle_policy_cap);
        
        let mut request = x_oracle::price_update_request(&x_oracle);
        // Primary: 10.0, Secondary1: 9.5 (-5%), Secondary2: 11.0 (+10%)
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        supra_mock_adapter::update_price_as_secondary<SUI>(&mut request, 95 * math::pow(10, price_feed::decimals()) / 10, 1000);
        switchboard_mock_adapter::update_price_as_secondary<SUI>(&mut request, 11 * math::pow(10, price_feed::decimals()), 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request, &clock);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    // ========== Rule Validation Tests ==========

    #[test]
    #[expected_failure(abort_code = 721)]
    fun test_missing_secondary_rule_should_fail() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule_v2<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule_v2<SUI, SwitchboardRule>(&mut x_oracle, &x_oracle_policy_cap);
        
        let mut request = x_oracle::price_update_request(&x_oracle);
        // Only update primary and one secondary, missing switchboard
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        supra_mock_adapter::update_price_as_secondary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request, &clock);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    #[test]
    #[expected_failure(abort_code = sui::vec_set::EKeyAlreadyExists, location = sui::vec_set)]
    fun test_duplicate_secondary_rule_should_fail() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule_v2<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        
        let mut request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        supra_mock_adapter::update_price_as_secondary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        // Try to add the same secondary rule again
        supra_mock_adapter::update_price_as_secondary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request, &clock);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    // ========== Rule Management Tests ==========

    #[test]
    fun test_add_and_remove_rules() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        // Add rules
        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule_v2<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        
        // Update price with both rules
        let mut request1 = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request1, 10 * math::pow(10, price_feed::decimals()), 1000);
        supra_mock_adapter::update_price_as_secondary<SUI>(&mut request1, 10 * math::pow(10, price_feed::decimals()), 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request1, &clock);

        // Remove secondary rule
        x_oracle::remove_secondary_price_update_rule_v2<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        
        // Now should be able to update with only primary
        let mut request2 = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request2, 20 * math::pow(10, price_feed::decimals()), 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request2, &clock);

        assert!(fixed_point32::multiply_u64(1, test_utils::get_price<SUI>(&x_oracle, &clock)) == 20, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }
}

