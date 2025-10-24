#[test_only]
module protocol::staking_manager_test {
    use sui::test_scenario;
    use sui::test_utils as sui_test_utils;
    use sui::coin;

    use coin_gr::coin_gr;
    use coin_gy::coin_gy;
    use test_coin::coin_xaum;
    use protocol::staking_manager;
    use std::fixed_point32 as fixed_point32;

    const ADMIN: address = @0xAA;
    const USER: address = @0xBB;

    // Initialize StakingManager and XAUM GlobalMintCap (test-only helpers)
    fun init_env(
        scenario: &mut test_scenario::Scenario,
    ): (staking_manager::StakingManager, coin_xaum::GlobalMintCap) {
        // Create GR/GY TreasuryCaps and initialize StakingManager (shared object)
        let gr_tc = coin_gr::create_treasury_for_testing(test_scenario::ctx(scenario));
        let gy_tc = coin_gy::create_treasury_for_testing(test_scenario::ctx(scenario));
        staking_manager::init_staking_manager(gr_tc, gy_tc, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, ADMIN);

        // Fetch the shared StakingManager
        let mgr = test_scenario::take_shared<staking_manager::StakingManager>(scenario);

        // Ensure XAUM GlobalMintCap exists and is shared
        coin_xaum::create_global_mint_cap_for_testing(test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, ADMIN);
        let xaum_gmc = test_scenario::take_shared<coin_xaum::GlobalMintCap>(scenario);

        (mgr, xaum_gmc)
    }

    // Mint XAUM for the given user and stake; advance one tx so GR/GY are retrievable
    fun stake_for_user(
        scenario: &mut test_scenario::Scenario,
        mgr: &mut staking_manager::StakingManager,
        xaum_gmc: &mut coin_xaum::GlobalMintCap,
        user: address,
        amount: u64,
    ) {
        test_scenario::next_tx(scenario, user);
        let xaum = coin_xaum::mint_coin_for_testing(xaum_gmc, amount, test_scenario::ctx(scenario));
        staking_manager::stake_xaum(mgr, xaum, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, user);
    }

    // Test: init staking manager with GR/GY treasury caps; stake and mint GR/GY
    #[test]
    fun test_init_and_stake_flow() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        // Setup: shared StakingManager and XAUM GlobalMintCap
        let (mut mgr, mut xaum_gmc) = init_env(scenario);

        // Stake 1 XAUM for USER
        stake_for_user(scenario, &mut mgr, &mut xaum_gmc, USER, 1_000_000_000);

        // Expect GR/GY minted to USER; withdraw and destroy them
        let gr_coin = test_scenario::take_from_address<coin::Coin<coin_gr::COIN_GR>>(scenario, USER);
        let gy_coin = test_scenario::take_from_address<coin::Coin<coin_gy::COIN_GY>>(scenario, USER);
        sui_test_utils::destroy(gr_coin);
        sui_test_utils::destroy(gy_coin);

        // Cleanup
        sui_test_utils::destroy(mgr);
        sui_test_utils::destroy(xaum_gmc);
        test_scenario::end(scenario_value);
    }

    // Test: unstake requires equal GR/GY; stake then split GR to mismatch
    #[test, expected_failure(abort_code = 0x0017002, location = protocol::staking_manager)]
    fun test_unstake_should_fail_when_gr_gy_mismatch() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut mgr, mut xaum_gmc) = init_env(scenario);
        // Mint XAUM for USER and stake to get matched GR/GY
        stake_for_user(scenario, &mut mgr, &mut xaum_gmc, USER, 2_000_000); // 0.002 XAUM (>= MIN)

        // Take minted GR/GY
        let mut gr = test_scenario::take_from_address<coin::Coin<coin_gr::COIN_GR>>(scenario, USER);
        let gy = test_scenario::take_from_address<coin::Coin<coin_gy::COIN_GY>>(scenario, USER);
        // Split GR to create a smaller amount and mismatch
        let gr_small = coin::split(&mut gr, 100, test_scenario::ctx(scenario)); // create a 100-sized GR coin
        // Call unstake with mismatched amounts (gr_small vs full gy)
        staking_manager::unstake(&mut mgr, gr_small, gy, test_scenario::ctx(scenario));

        // Cleanup
        sui_test_utils::destroy(xaum_gmc);
        sui_test_utils::destroy(gr);
        sui_test_utils::destroy(mgr);
        test_scenario::end(scenario_value);
    }

    // Test: admin can withdraw net XAUM (after stake fee) from pool
    #[test]
    fun test_admin_withdraw_after_stake_respects_net_amount() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut mgr, mut xaum_gmc) = init_env(scenario);

        // Set stake fee to 1%
        test_scenario::next_tx(scenario, ADMIN);
        staking_manager::update_stake_fee(&mut mgr, 1, 100, test_scenario::ctx(scenario));

        // USER stakes 1 XAUM
        stake_for_user(scenario, &mut mgr, &mut xaum_gmc, USER, 1_000_000_000);

        // Compute expected fee/net using same fixed_point32 logic
        let amount = 1_000_000_000;
        let rate = fixed_point32::create_from_rational(1, 100);
        let fee_expected = fixed_point32::multiply_u64(amount, rate);
        let net_expected = amount - fee_expected;

        let pool_balance = staking_manager::get_pool_balance(&mgr);
        let fee_balance = staking_manager::get_fee_pool_balance(&mgr);
        assert!(pool_balance == net_expected, 0);
        assert!(fee_balance == fee_expected, 0);

        // Admin withdraws exactly the net amount
        test_scenario::next_tx(scenario, ADMIN);
        staking_manager::owner_withdraw_xaum(&mut mgr, net_expected, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, ADMIN);
        let admin_xaum = test_scenario::take_from_address<coin::Coin<coin_xaum::COIN_XAUM>>(scenario, ADMIN);
        sui_test_utils::destroy(admin_xaum);

        // Pool should be zero now; fee pool remains intact
        assert!(staking_manager::get_pool_balance(&mgr) == 0, 0);
        assert!(staking_manager::get_fee_pool_balance(&mgr) == fee_expected, 0);

        // Cleanup
        sui_test_utils::destroy(mgr);
        sui_test_utils::destroy(xaum_gmc);
        test_scenario::end(scenario_value);
    }

    // Test: user cannot unstake if admin withdrew pool; should fail due to insufficient pool XAUM
    #[test, expected_failure(abort_code = 0x0017006, location = protocol::staking_manager)]
    fun test_unstake_fails_when_admin_withdrew_pool() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut mgr, mut xaum_gmc) = init_env(scenario);

        // Set stake fee to 1%
        test_scenario::next_tx(scenario, ADMIN);
        staking_manager::update_stake_fee(&mut mgr, 1, 100, test_scenario::ctx(scenario));

        // USER stakes 1 XAUM (net goes into pool)
        stake_for_user(scenario, &mut mgr, &mut xaum_gmc, USER, 1_000_000_000);

        // Compute net and withdraw all
        let amount = 1_000_000_000;
        let rate = fixed_point32::create_from_rational(1, 100);
        let fee_expected = fixed_point32::multiply_u64(amount, rate);
        let net_expected = amount - fee_expected;

        test_scenario::next_tx(scenario, ADMIN);
        staking_manager::owner_withdraw_xaum(&mut mgr, net_expected, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, ADMIN);
        let admin_xaum = test_scenario::take_from_address<coin::Coin<coin_xaum::COIN_XAUM>>(scenario, ADMIN);
        sui_test_utils::destroy(admin_xaum);

        // USER attempts to unstake: should fail due to insufficient XAUM in pool
        test_scenario::next_tx(scenario, USER);
        let gr = test_scenario::take_from_address<coin::Coin<coin_gr::COIN_GR>>(scenario, USER);
        let gy = test_scenario::take_from_address<coin::Coin<coin_gy::COIN_GY>>(scenario, USER);
        staking_manager::unstake(&mut mgr, gr, gy, test_scenario::ctx(scenario));

        // Cleanup (unreachable)
        sui_test_utils::destroy(mgr);
        sui_test_utils::destroy(xaum_gmc);
        test_scenario::end(scenario_value);
    }

    // Test: admin can deposit XAUM back; then user can unstake successfully
    #[test]
    fun test_admin_deposit_enables_unstake() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut mgr, mut xaum_gmc) = init_env(scenario);

        // Set stake fee to 1%
        test_scenario::next_tx(scenario, ADMIN);
        staking_manager::update_stake_fee(&mut mgr, 1, 100, test_scenario::ctx(scenario));

        // USER stakes 1 XAUM
        stake_for_user(scenario, &mut mgr, &mut xaum_gmc, USER, 1_000_000_000);

        // Compute net and withdraw all
        let amount = 1_000_000_000;
        let rate = fixed_point32::create_from_rational(1, 100);
        let fee_expected = fixed_point32::multiply_u64(amount, rate);
        let net_expected = amount - fee_expected;

        test_scenario::next_tx(scenario, ADMIN);
        staking_manager::owner_withdraw_xaum(&mut mgr, net_expected, test_scenario::ctx(scenario));
        test_scenario::next_tx(scenario, ADMIN);
        let admin_xaum = test_scenario::take_from_address<coin::Coin<coin_xaum::COIN_XAUM>>(scenario, ADMIN);

        // Admin deposits back a sufficient amount (>= user's net)
        test_scenario::next_tx(scenario, ADMIN);
        staking_manager::owner_deposit_xaum(&mut mgr, admin_xaum, test_scenario::ctx(scenario));

        // USER can now unstake
        test_scenario::next_tx(scenario, USER);
        let gr = test_scenario::take_from_address<coin::Coin<coin_gr::COIN_GR>>(scenario, USER);
        let gy = test_scenario::take_from_address<coin::Coin<coin_gy::COIN_GY>>(scenario, USER);
        staking_manager::unstake(&mut mgr, gr, gy, test_scenario::ctx(scenario));

        // Cleanup
        sui_test_utils::destroy(mgr);
        sui_test_utils::destroy(xaum_gmc);
        test_scenario::end(scenario_value);
    }

    // Test: non-admin cannot call owner withdraw
    #[test, expected_failure(abort_code = 0x0017004, location = protocol::staking_manager)]
    fun test_non_admin_cannot_owner_withdraw() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut mgr, mut xaum_gmc) = init_env(scenario);

        // USER tries to withdraw from pool -> should fail (not admin)
        test_scenario::next_tx(scenario, USER);
        staking_manager::owner_withdraw_xaum(&mut mgr, 1, test_scenario::ctx(scenario));

        // Cleanup (unreachable)
        sui_test_utils::destroy(mgr);
        sui_test_utils::destroy(xaum_gmc);
        test_scenario::end(scenario_value);
    }

    // Test: non-admin cannot deposit XAUM into pool via owner API
    #[test, expected_failure(abort_code = 0x0017004, location = protocol::staking_manager)]
    fun test_non_admin_cannot_owner_deposit() {
        let mut scenario_value = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_value;

        let (mut mgr, mut xaum_gmc) = init_env(scenario);

        // USER mints a small XAUM and tries to deposit -> should fail
        test_scenario::next_tx(scenario, USER);
        let user_xaum = coin_xaum::mint_coin_for_testing(&mut xaum_gmc, 1_000, test_scenario::ctx(scenario));
        staking_manager::owner_deposit_xaum(&mut mgr, user_xaum, test_scenario::ctx(scenario));

        // Cleanup (unreachable)
        sui_test_utils::destroy(mgr);
        sui_test_utils::destroy(xaum_gmc);
        test_scenario::end(scenario_value);
    }
}


