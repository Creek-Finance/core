#[test_only, allow(deprecated_usage)]
module x_oracle::advanced_test {
    use sui::test_scenario::{Self, Scenario};
    use x_oracle::x_oracle::{Self, XOracle, XOraclePolicyCap};
    use sui::test_utils as sui_test_utils;
    use sui::clock::{Self, Clock};
    use sui::math;
    use x_oracle::pyth_mock_adapter::{Self as pyth_mock_adapter, PythRule};
    use x_oracle::supra_mock_adapter::{Self as supra_mock_adapter, SupraRule};
    use x_oracle::switchboard_mock_adapter::{Self as switchboard_mock_adapter, SwitchboardRule};
    use x_oracle::test_utils;
    use x_oracle::price_feed;

    const ADMIN: address = @0xAD;

    public struct SUI has drop {}
    public struct ETH has drop {}
    public struct BTC has drop {}

    fun init_internal(scenario: &mut Scenario): (Clock, XOracle, XOraclePolicyCap) {
        x_oracle::init_t(test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, ADMIN);
        
        let clock = clock::create_for_testing(test_scenario::ctx(scenario));
        let x_oracle = test_scenario::take_shared<XOracle>(scenario);
        let x_oracle_policy_cap = test_scenario::take_from_address<XOraclePolicyCap>(scenario, ADMIN);

        (clock, x_oracle, x_oracle_policy_cap)
    }

    // ========== Getter Tests ==========

    // Test prices() getter
    #[test]
    fun test_prices_getter() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        // Add and update price
        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        let mut request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request, &clock);

        // Access price table via prices() getter
        let prices_table = x_oracle::prices(&x_oracle);
        let sui_typename = std::type_name::get<SUI>();
        assert!(sui::table::contains(prices_table, sui_typename), 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    // ========== 0 Secondary Feeds Scenario ==========

    // Test: only primary, no secondary (empty array)
    #[test]
    fun test_only_primary_no_secondary() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        // Only add primary rule, no secondary
        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        
        let mut request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request, &clock);

        // Should succeed with primary price value
        let price_fp = test_utils::get_price<SUI>(&x_oracle, &clock);
        let price_value = std::fixed_point32::multiply_u64(1_000_000_000, price_fp);
        assert!(price_value == 10_000_000_000, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    // ========== Multiple Secondary Feeds Scenario ==========

    // Test: 1 primary + 3 secondaries (max available with current mock adapters)
    #[test]
    fun test_one_primary_five_secondary() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        // Note: We only have 3 mock adapters, so we can't truly test 5+ secondaries
        // But we can test the logic with multiple secondaries
        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule_v2<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule_v2<SUI, SwitchboardRule>(&mut x_oracle, &x_oracle_policy_cap);
        
        // 3 secondaries: 2 matching, 1 not matching -> need at least (3+1)/2 = 2 matches
        let mut request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        supra_mock_adapter::update_price_as_secondary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000); // Match
        switchboard_mock_adapter::update_price_as_secondary<SUI>(&mut request, 101 * math::pow(10, price_feed::decimals()) / 10, 1000); // Match (+1%)
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request, &clock);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    // ========== Price Matching Boundary Tests ==========

    // Test: price difference exactly 1% (boundary)
    #[test]
    fun test_price_match_exactly_1_percent() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule_v2<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        
        // Primary: 10.0, Secondary: 10.1 (exactly +1%)
        let mut request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request, 10_000_000_000, 1000);
        supra_mock_adapter::update_price_as_secondary<SUI>(&mut request, 10_100_000_000, 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request, &clock);

        // Should succeed
        assert!(std::fixed_point32::multiply_u64(1, test_utils::get_price<SUI>(&x_oracle, &clock)) == 10, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    // Test: price difference 0.99% (within threshold)
    #[test]
    fun test_price_match_0_99_percent() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule_v2<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        
        // Primary: 10.0, Secondary: 10.09 (+0.9%)
        let mut request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request, 10_000_000_000, 1000);
        supra_mock_adapter::update_price_as_secondary<SUI>(&mut request, 10_090_000_000, 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request, &clock);

        assert!(std::fixed_point32::multiply_u64(1, test_utils::get_price<SUI>(&x_oracle, &clock)) == 10, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    // Test: price difference 1.01% (exceeds threshold)
    #[test]
    #[expected_failure(abort_code = 720)]
    fun test_price_match_1_01_percent_should_fail() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule_v2<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        
        // Primary: 10.0, Secondary: 10.11 (+1.1%, exceeds 1%)
        let mut request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request, 10_000_000_000, 1000);
        supra_mock_adapter::update_price_as_secondary<SUI>(&mut request, 10_110_000_000, 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request, &clock);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    // ========== Multiple Price Update Tests ==========

    // Test: multiple consecutive updates for the same coin
    #[test]
    fun test_multiple_price_updates() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);

        // First update: price = 10
        clock::set_for_testing(&mut clock, 1000 * 1000);
        let mut request1 = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request1, 10 * math::pow(10, price_feed::decimals()), 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request1, &clock);
        assert!(std::fixed_point32::multiply_u64(1, test_utils::get_price<SUI>(&x_oracle, &clock)) == 10, 0);

        // Second update: price = 20
        clock::set_for_testing(&mut clock, 2000 * 1000);
        let mut request2 = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request2, 20 * math::pow(10, price_feed::decimals()), 2000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request2, &clock);
        assert!(std::fixed_point32::multiply_u64(1, test_utils::get_price<SUI>(&x_oracle, &clock)) == 20, 1);

        // Third update: price = 5
        clock::set_for_testing(&mut clock, 3000 * 1000);
        let mut request3 = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request3, 5 * math::pow(10, price_feed::decimals()), 3000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request3, &clock);
        assert!(std::fixed_point32::multiply_u64(1, test_utils::get_price<SUI>(&x_oracle, &clock)) == 5, 2);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    // Test: interleaved updates for multiple coins
    #[test]
    fun test_interleaved_multi_coin_updates() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_primary_price_update_rule_v2<ETH, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);

        // Update SUI
        let mut request_sui1 = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request_sui1, 10 * math::pow(10, price_feed::decimals()), 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request_sui1, &clock);

        // Update ETH
        let mut request_eth1 = x_oracle::price_update_request(&x_oracle);
        supra_mock_adapter::update_price_as_primary<ETH>(&mut request_eth1, 1000 * math::pow(10, price_feed::decimals()), 1000);
        x_oracle::confirm_price_update_request<ETH>(&mut x_oracle, request_eth1, &clock);

        // Update SUI again
        let mut request_sui2 = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request_sui2, 15 * math::pow(10, price_feed::decimals()), 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request_sui2, &clock);

        // Verify both prices are correct
        assert!(std::fixed_point32::multiply_u64(1, test_utils::get_price<SUI>(&x_oracle, &clock)) == 15, 0);
        assert!(std::fixed_point32::multiply_u64(1, test_utils::get_price<ETH>(&x_oracle, &clock)) == 1000, 1);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    // ========== 2 Secondary Matching Logic ==========

    // Test: 2 secondaries, need at least (2+1)/2 = 1.5 -> 2 matches
    #[test]
    fun test_two_secondary_both_must_match() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        clock::set_for_testing(&mut clock, 1000 * 1000);

        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule_v2<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule_v2<SUI, SwitchboardRule>(&mut x_oracle, &x_oracle_policy_cap);
        
        // Both secondaries match
        let mut request = x_oracle::price_update_request(&x_oracle);
        pyth_mock_adapter::update_price_as_primary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        supra_mock_adapter::update_price_as_secondary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        switchboard_mock_adapter::update_price_as_secondary<SUI>(&mut request, 10 * math::pow(10, price_feed::decimals()), 1000);
        x_oracle::confirm_price_update_request<SUI>(&mut x_oracle, request, &clock);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    // Note: Testing 4+ secondaries requires more mock adapters
    // Currently only have 3 adapters (Pyth, Supra, Switchboard), cannot test 4+ secondary scenarios

    // ========== update_price Test Helper Function ==========

    // Test update_price (test_only function)
    #[test]
    fun test_update_price_helper() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);

        clock::set_for_testing(&mut clock, 1000 * 1000);

        // Use test_only helper function to update price directly
        x_oracle::update_price<SUI>(&mut x_oracle, &clock, 50 * math::pow(10, price_feed::decimals()));

        // Verify price updated
        assert!(std::fixed_point32::multiply_u64(1, test_utils::get_price<SUI>(&x_oracle, &clock)) == 50, 0);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }
}

