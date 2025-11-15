module protocol::error {

  // version
  public fun version_mismatch_error(): u64 { 0x0000201 }

  // obligation
  public fun invalid_obligation_error(): u64 { 0x0000301 }
  public fun obligation_locked(): u64 { 0x0000302 }
  public fun obligation_unlock_with_wrong_key(): u64 { 0x0000303 }
  public fun obligation_already_locked(): u64 { 0x0000304 }
  public fun obligation_access_lock_key_not_in_store(): u64 { 0x0000305 }
  public fun obligation_access_reward_key_not_in_store(): u64 { 0x0000306 }
  public fun obligation_access_store_key_exists(): u64 { 0x0000307 }
  public fun obligation_access_store_key_not_found(): u64 { 0x0000308 }
  public fun obligation_cant_forcely_unlocked(): u64 { 0x0000309 }

  // oracle
  public fun oracle_stale_price_error(): u64 { 0x0000401 }
  public fun oracle_price_not_found_error(): u64 { 0x0000402 }
  public fun oracle_zero_price_error(): u64 { 0x0000403 }

  // borrow
  public fun borrow_too_much_error(): u64 { 0x0000501 }
  public fun borrow_too_small_error(): u64 { 0x0000502 }
  public fun invalid_coin_type(): u64 { 0x0000503 }
  public fun flash_loan_repay_not_enough_error(): u64 { 0x0000504 }
  public fun flashloan_exceed_single_cap_error(): u64 { 0x0000505 }

  // liquidation
  public fun unable_to_liquidate_error(): u64 { 0x0000601 }

  // collateral error
  public fun max_collateral_reached_error(): u64 { 0x0000701 }
  public fun invalid_collateral_type_error(): u64 { 0x0000702 }
  public fun withdraw_collateral_too_much_error(): u64 { 0x0000703 }

  // admin
  public fun interest_model_type_not_match_error(): u64 { 0x0000901 }
  public fun risk_model_type_not_match_error(): u64 { 0x0000902 }
  public fun invalid_params_error(): u64 { 0x0000903 }

  // misc
  public fun outflow_reach_limit_error(): u64 { 0x0001001 }

  // asset not active errors
  public fun base_asset_not_active_error(): u64 { 0x0012001 }
  public fun collateral_not_active_error(): u64 { 0x0012002 }

  // risk model & interest model errors
  public fun risk_model_param_error(): u64 { 0x0013001 }
  public fun interest_model_param_error(): u64 { 0x0013002 }

  // pool liquidity errors
  public fun collateral_not_enough(): u64 { 0x0014001 }
  public fun borrow_limit_reached_error(): u64 { 0x0014002 }

  // repay
  public fun zero_amount_error(): u64 { 0x0015001 }
  public fun no_debt_error(): u64 { 0x0015002 }


  // market
  public fun market_paused_error(): u64 { 0x0016001 }

  // staking
  public fun staking_min_xaum_error(): u64 { 0x0017001 }
  public fun staking_gr_gy_mismatch_error(): u64 { 0x0017002 }
  public fun staking_insufficient_gr_gy_error(): u64 { 0x0017003 }
  public fun staking_not_admin_error(): u64 { 0x0017004 }
  public fun staking_invalid_params_error(): u64 { 0x0017005 }
  // XAUM pool not enough when users try to unstake or owner withdraws
  public fun staking_pool_xaum_not_enough_error(): u64 { 0x0017006 }
  // Fee exceeds or equals amount which makes net amount non-positive
  public fun staking_fee_exceeds_amount_error(): u64 { 0x0017007 }
  // GR/GY amount not divisible by EXCHANGE_RATE, causing rounding loss
  public fun staking_gr_amount_not_divisible_error(): u64 { 0x0017008 }
  // Total staking cap exceeded
  public fun staking_stake_cap_exceeded_error(): u64 { 0x0017009 }

  // app
  public fun invalid_reward_address_error(): u64 { 0x0018001 }
}
