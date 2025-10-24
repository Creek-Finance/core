#[test_only, allow(deprecated_usage)]
module x_oracle::price_update_policy_test {
    use sui::test_scenario::{Self, Scenario};
    use x_oracle::x_oracle::{Self, XOracle, XOraclePolicyCap};
    use sui::test_utils as sui_test_utils;
    use sui::clock::{Self, Clock};
    use x_oracle::pyth_mock_adapter::{Self as pyth_mock_adapter, PythRule};
    use x_oracle::supra_mock_adapter::{Self as supra_mock_adapter, SupraRule};
    use x_oracle::price_update_policy;

    const ADMIN: address = @0xAD;

    public struct SUI has drop {}
    public struct ETH has drop {}

    fun init_internal(scenario: &mut Scenario): (Clock, XOracle, XOraclePolicyCap) {
        x_oracle::init_t(test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, ADMIN);
        
        let clock = clock::create_for_testing(test_scenario::ctx(scenario));
        let x_oracle = test_scenario::take_shared<XOracle>(scenario);
        let x_oracle_policy_cap = test_scenario::take_from_address<XOraclePolicyCap>(scenario, ADMIN);

        (clock, x_oracle, x_oracle_policy_cap)
    }

    // Note: get_price_update_policy requires access to internal fields and cannot be tested externally
    // This functionality is indirectly tested through add/remove rule operations in price_update_test.move

    // Test non-v2 versions of add_rule and remove_rule
    #[test]
    fun test_add_remove_rule_non_v2() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        // Add rules using non-v2 versions (global rules, not coin-specific)
        x_oracle::add_primary_price_update_rule<PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::add_secondary_price_update_rule<SupraRule>(&mut x_oracle, &x_oracle_policy_cap);

        // Remove rules
        x_oracle::remove_primary_price_update_rule<PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::remove_secondary_price_update_rule<SupraRule>(&mut x_oracle, &x_oracle_policy_cap);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    // Test init_rules_df_if_not_exist multiple calls (idempotence)
    #[test]
    fun test_init_rules_df_if_not_exist_idempotent() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        
        // First initialization
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));
        
        // Second initialization (should not error, idempotent)
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));
        
        // Third call
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }

    // Test mixing v2 and non-v2 rule versions
    #[test]
    fun test_mix_v2_and_non_v2_rules() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (clock, mut x_oracle, x_oracle_policy_cap) = init_internal(scenario);
        x_oracle::init_rules_df_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, test_scenario::ctx(scenario));

        // v2 version (coin-specific)
        x_oracle::add_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        
        // Non-v2 version (global)
        x_oracle::add_secondary_price_update_rule<SupraRule>(&mut x_oracle, &x_oracle_policy_cap);

        // Remove rules
        x_oracle::remove_primary_price_update_rule_v2<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        x_oracle::remove_secondary_price_update_rule<SupraRule>(&mut x_oracle, &x_oracle_policy_cap);

        sui_test_utils::destroy(clock);
        sui_test_utils::destroy(x_oracle);
        sui_test_utils::destroy(x_oracle_policy_cap);
        test_scenario::end(scenario_value);
    }
}

