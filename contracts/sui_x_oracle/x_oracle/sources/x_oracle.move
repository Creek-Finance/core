module x_oracle::x_oracle {
  use std::type_name::{TypeName, with_defining_ids};
  use sui::table::{Self, Table};
  use sui::clock::{Self as clock, Clock};
  use sui::package;
  use sui::dynamic_field;

  use x_oracle::price_update_policy::{Self, PriceUpdatePolicy, PriceUpdateRequest, PriceUpdatePolicyCap};
  use x_oracle::price_feed::{Self, PriceFeed};

  const PRIMARY_PRICE_NOT_QUALIFIED: u64 = 720;
  const ONLY_SUPPORT_ONE_PRIMARY: u64 = 721;
  const NOT_AUTHORIZED: u64 = 722;
  const ADMIN_NOT_SET: u64 = 723;

  public struct X_ORACLE has drop {}

  public struct XOracle has key {
    id: UID,
    primary_price_update_policy: PriceUpdatePolicy,
    secondary_price_update_policy: PriceUpdatePolicy,
    prices: Table<TypeName, PriceFeed>,
    ema_prices: Table<TypeName, PriceFeed>,
    gr_coin_type: option::Option<TypeName>,
    // Cached GR indicator (EMA120 scaled to 9 decimals)
    gr_indicator_value_u64: u64,
    gr_indicator_last_updated: u64,
    // XAUM coin type for special floor condition
    xaum_coin_type: option::Option<TypeName>,
    // Cached XAUM indicators used to compute GR (scaled to 9 decimals)
    xaum_ema120_value_u64: u64,
    xaum_ema90_value_u64: u64,
    // Cached XAUM spot price (scaled to 9 decimals)
    xaum_spot_value_u64: u64,
    // Cached computed sValue (scaled to 9 decimals)
    gr_svalue_u64: u64,
    // Cached computed GR value (scaled to 9 decimals)
    gr_computed_value_u64: u64,
    // GR pricing parameters alpha/beta as fixed-point (scale 1e9, 0..1e9)
    gr_alpha_fp: u64,
    gr_beta_fp: u64,
    // Admin address (set by owner)
    admin_address: option::Option<address>,
  }

  /// Owner capability - only deployer holds this, used to set/change admin
  public struct XOracleOwnerCap has key, store {
    id: UID,
  }

  /// Admin capability - admin holds this, used for authorization
  /// The actual PolicyCap and GrIndicatorCap are stored in XOracle
  public struct XOracleAdminCap has key, store {
    id: UID,
    // Address of the admin (for verification)
    admin_address: address,
  }

  /// Policy capability wrapper - stored in XOracle dynamic field
  public struct XOraclePolicyCap has key, store {
    id: UID,
    primary_price_update_policy_cap: PriceUpdatePolicyCap,
    secondary_price_update_policy_cap: PriceUpdatePolicyCap,
  }

  /// GR indicator capability - stored in XOracle dynamic field
  public struct GrIndicatorCap has key, store { id: UID }

  /// Dynamic field keys for storing PolicyCap and GrIndicatorCap
  public struct PolicyCapKey has copy, drop, store {}
  public struct GrIndicatorCapKey has copy, drop, store {}

  public struct XOraclePriceUpdateRequest<phantom T> {
    primary_price_update_request: PriceUpdateRequest<T>,
    secondary_price_update_request: PriceUpdateRequest<T>,
  }

  // === getters ===

  public fun prices(self: &XOracle): &Table<TypeName, PriceFeed> { &self.prices }
  public fun admin_address(self: &XOracle): option::Option<address> { self.admin_address }

  // === init ===

  #[allow(lint(share_owned))]
  fun init(otw: X_ORACLE, ctx: &mut TxContext) {
    let (mut x_oracle, x_oracle_policy_cap) = new(ctx);
    
    // Create owner cap for deployer
    let owner_cap = XOracleOwnerCap { id: object::new(ctx) };
    
    // Create admin cap
    let deployer = tx_context::sender(ctx);
    let admin_cap = XOracleAdminCap {
      id: object::new(ctx),
      admin_address: deployer,
    };
    
    // Create gr indicator cap
    let gr_cap = GrIndicatorCap { id: object::new(ctx) };
    
    // Set deployer as initial admin
    x_oracle.admin_address = option::some(deployer);
    
    // Store PolicyCap and GrIndicatorCap in XOracle using dynamic fields
    dynamic_field::add(&mut x_oracle.id, PolicyCapKey {}, x_oracle_policy_cap);
    dynamic_field::add(&mut x_oracle.id, GrIndicatorCapKey {}, gr_cap);
    
    // Initialize rules dynamic fields
    init_rules_df_if_not_exist(&mut x_oracle, ctx);
    
    transfer::share_object(x_oracle);
    transfer::transfer(owner_cap, deployer);
    transfer::transfer(admin_cap, deployer);
    package::claim_and_keep(otw, ctx);
  }

  // === Admin Management ===

  /// Set or change admin address. Only owner can call this.
  /// When changing admin, the old admin cap becomes invalid automatically
  /// because all admin functions check admin_address match.
  /// Returns a new AdminCap that should be transferred to the new admin.
  public fun set_admin(
    self: &mut XOracle,
    _owner_cap: &XOracleOwnerCap,
    new_admin: address,
    ctx: &mut TxContext,
  ): XOracleAdminCap {
    // Update admin address - this invalidates old admin cap
    self.admin_address = option::some(new_admin);
    
    // Create new admin cap for new admin
    let new_admin_cap = XOracleAdminCap {
      id: object::new(ctx),
      admin_address: new_admin,
    };
    
    new_admin_cap
  }

  /// Verify admin authorization. Internal helper.
  fun verify_admin(self: &XOracle, admin_cap: &XOracleAdminCap) {
    assert!(option::is_some(&self.admin_address), ADMIN_NOT_SET);
    let current_admin = *option::borrow(&self.admin_address);
    assert!(admin_cap.admin_address == current_admin, NOT_AUTHORIZED);
  }

  /// Get PolicyCap from XOracle. Internal helper.
  fun borrow_policy_cap(self: &XOracle): &XOraclePolicyCap {
    dynamic_field::borrow<PolicyCapKey, XOraclePolicyCap>(&self.id, PolicyCapKey {})
  }

  // === GR indicator admin setter & getters ===

  /// Set GR indicator value (u64 scaled to 9 decimals) and last updated time; gated by AdminCap
  public fun set_gr_indicator(
    self: &mut XOracle,
    admin_cap: &XOracleAdminCap,
    value_u64: u64,
    updated_time_sec: u64,
    _ctx: &mut TxContext,
  ) {
    verify_admin(self, admin_cap);
    // Monotonic timestamp and non-zero value
    assert!(updated_time_sec >= self.gr_indicator_last_updated, 0);
    assert!(value_u64 > 0, 0);
    self.gr_indicator_value_u64 = value_u64;
    self.gr_indicator_last_updated = updated_time_sec;
  }

  public fun gr_indicator_value(self: &XOracle): u64 { self.gr_indicator_value_u64 }
  public fun gr_indicator_last_updated(self: &XOracle): u64 { self.gr_indicator_last_updated }

  /// Configure which CoinType is treated as GR (stored as TypeName). Gated by AdminCap.
  public fun set_gr_coin_type<CoinType>(
    self: &mut XOracle,
    admin_cap: &XOracleAdminCap,
    _ctx: &mut TxContext,
  ) {
    verify_admin(self, admin_cap);
    self.gr_coin_type = option::some(with_defining_ids<CoinType>());
  }

  /// Configure which CoinType is treated as XAUM. Gated by AdminCap.
  public fun set_xaum_coin_type<CoinType>(
    self: &mut XOracle,
    admin_cap: &XOracleAdminCap,
    _ctx: &mut TxContext,
  ) {
    verify_admin(self, admin_cap);
    self.xaum_coin_type = option::some(with_defining_ids<CoinType>());
  }

  /// Set GR pricing parameters alpha/beta as fixed-point (scale 1e9, 0..1e9). Gated by AdminCap.
  public fun set_gr_formula_params(
    self: &mut XOracle,
    admin_cap: &XOracleAdminCap,
    alpha_fp: u64,
    beta_fp: u64,
  ) {
    verify_admin(self, admin_cap);
    // 0..1e9 range (1e9 means 1.0)
    assert!(alpha_fp <= 1_000_000_000, 0);
    assert!(beta_fp  <= 1_000_000_000, 0);
    self.gr_alpha_fp = alpha_fp;
    self.gr_beta_fp = beta_fp;
  }

  /// Set GR indicators (EMA120 / EMA90), scaled to 9 decimals. Gated by AdminCap.
  public fun set_gr_indicators(
    self: &mut XOracle,
    admin_cap: &XOracleAdminCap,
    ema120_value_u64: u64,
    ema90_value_u64: u64,
    spot_value_u64: u64,
    updated_time_sec: u64,
    _ctx: &mut TxContext,
  ) {
    verify_admin(self, admin_cap);
    assert!(updated_time_sec >= self.gr_indicator_last_updated, 0);
    self.gr_indicator_last_updated = updated_time_sec;
    self.xaum_ema120_value_u64 = ema120_value_u64;
    self.xaum_ema90_value_u64 = ema90_value_u64;
    self.xaum_spot_value_u64 = spot_value_u64;

    // compute theoretical GR pricing and cache
    // sValue = α × EMA120 + (1-α) × [β × EMA90 + (1-β) × SpotPrice]
    let scale: u128 = 1_000_000_000u128; // 1e9
    let scale_sq: u128 = scale * scale;
    let alpha_u128 = (self.gr_alpha_fp as u128);
    let beta_u128 = (self.gr_beta_fp as u128);
    let ema120_u128 = (ema120_value_u64 as u128);
    let ema90_u128 = (ema90_value_u64 as u128);
    let spot_u128 = (spot_value_u64 as u128);
    let s_value: u128 = if (self.gr_alpha_fp <= 1_000_000_000 && self.gr_beta_fp <= 1_000_000_000 && ema120_value_u64 > 0 && ema90_value_u64 > 0 && spot_value_u64 > 0) {
      let beta_complement = scale - beta_u128;
      let alpha_complement = scale - alpha_u128;
      let inner_num = beta_u128 * ema90_u128 + beta_complement * spot_u128;
      let prelim_num = alpha_u128 * ema120_u128 * scale + alpha_complement * inner_num;
      let prelim: u128 = prelim_num / scale_sq; // scaled 1e9
      if (option::is_some(&self.xaum_coin_type)) {
        let xaum_tn = *option::borrow(&self.xaum_coin_type);
        if (table::contains(&self.prices, xaum_tn)) {
          let xaum_pf = table::borrow(&self.prices, xaum_tn);
          let xaum_val: u128 = ((price_feed::value(xaum_pf)) as u128);
          if (xaum_val < prelim) { xaum_val } else { prelim }
        } else { prelim }
      } else { prelim }
    } else { 0u128 };
    self.gr_svalue_u64 = (s_value as u64);
    let gr_u128 = if (s_value > 0u128) { s_value / (100 as u128) } else { 0u128 };
    self.gr_computed_value_u64 = (gr_u128 as u64);
  }

  fun new(ctx: &mut TxContext): (XOracle, XOraclePolicyCap) {
    let (primary_price_update_policy, primary_price_update_policy_cap ) = price_update_policy::new(ctx);
    let (secondary_price_update_policy, secondary_price_update_policy_cap ) = price_update_policy::new(ctx);
    let x_oracle = XOracle {
      id: object::new(ctx),
      primary_price_update_policy,
      secondary_price_update_policy,
      prices: table::new(ctx),
      ema_prices: table::new(ctx),
      gr_coin_type: option::none<TypeName>(),
      gr_indicator_value_u64: 0,
      gr_indicator_last_updated: 0,
      xaum_coin_type: option::none<TypeName>(),
      xaum_ema120_value_u64: 0,
      xaum_ema90_value_u64: 0,
      xaum_spot_value_u64: 0,
      gr_svalue_u64: 0,
      gr_computed_value_u64: 0,
      gr_alpha_fp: 0,
      gr_beta_fp: 0,
      admin_address: option::none<address>(),
    };
    let x_oracle_update_policy = XOraclePolicyCap {
      id: object::new(ctx),
      primary_price_update_policy_cap,
      secondary_price_update_policy_cap,
    };
    (x_oracle, x_oracle_update_policy)
  }

  /// Initialize rules dynamic fields. Internal helper.
  fun init_rules_df_if_not_exist(self: &mut XOracle, ctx: &mut TxContext) {
    // Extract policy IDs first to avoid borrowing conflicts
    let primary_policy_id = object::id(&self.primary_price_update_policy);
    let secondary_policy_id = object::id(&self.secondary_price_update_policy);
    price_update_policy::init_rules_df_if_not_exist_by_id(primary_policy_id, &mut self.primary_price_update_policy, ctx);
    price_update_policy::init_rules_df_if_not_exist_by_id(secondary_policy_id, &mut self.secondary_price_update_policy, ctx);
  }

  /// Initialize rules dynamic fields. Admin function.
  public fun init_rules_df_if_not_exist_admin(
    self: &mut XOracle,
    admin_cap: &XOracleAdminCap,
    ctx: &mut TxContext,
  ) {
    verify_admin(self, admin_cap);
    init_rules_df_if_not_exist(self, ctx);
  }

  // === Price Update Policy ===

  public fun add_primary_price_update_rule_v2<CoinType, Rule: drop>(
    self: &mut XOracle,
    admin_cap: &XOracleAdminCap,
  ) {
    verify_admin(self, admin_cap);
    let policy_cap = borrow_policy_cap(self);
    let primary_policy_id = price_update_policy::for_policy(&policy_cap.primary_price_update_policy_cap);
    price_update_policy::add_rule_v2_by_id<CoinType, Rule>(
      &mut self.primary_price_update_policy,
      primary_policy_id
    );
  }

  public fun remove_primary_price_update_rule_v2<CoinType, Rule: drop>(
    self: &mut XOracle,
    admin_cap: &XOracleAdminCap,
  ) {
    verify_admin(self, admin_cap);
    let policy_cap = borrow_policy_cap(self);
    let primary_policy_id = price_update_policy::for_policy(&policy_cap.primary_price_update_policy_cap);
    price_update_policy::remove_rule_v2_by_id<CoinType, Rule>(
      &mut self.primary_price_update_policy,
      primary_policy_id
    );
  }

  public fun add_primary_price_update_rule<Rule: drop>(
    self: &mut XOracle,
    admin_cap: &XOracleAdminCap,
  ) {
    verify_admin(self, admin_cap);
    let policy_cap = borrow_policy_cap(self);
    let primary_policy_id = price_update_policy::for_policy(&policy_cap.primary_price_update_policy_cap);
    price_update_policy::add_rule_by_id<Rule>(
      &mut self.primary_price_update_policy,
      primary_policy_id
    );
  }

  public fun remove_primary_price_update_rule<Rule: drop>(
    self: &mut XOracle,
    admin_cap: &XOracleAdminCap,
  ) {
    verify_admin(self, admin_cap);
    let policy_cap = borrow_policy_cap(self);
    let primary_policy_id = price_update_policy::for_policy(&policy_cap.primary_price_update_policy_cap);
    price_update_policy::remove_rule_by_id<Rule>(
      &mut self.primary_price_update_policy,
      primary_policy_id
    );
  }

  public fun add_secondary_price_update_rule_v2<CoinType, Rule: drop>(
    self: &mut XOracle,
    admin_cap: &XOracleAdminCap,
  ) {
    verify_admin(self, admin_cap);
    let policy_cap = borrow_policy_cap(self);
    let secondary_policy_id = price_update_policy::for_policy(&policy_cap.secondary_price_update_policy_cap);
    price_update_policy::add_rule_v2_by_id<CoinType, Rule>(
      &mut self.secondary_price_update_policy,
      secondary_policy_id
    );
  }

  public fun remove_secondary_price_update_rule_v2<CoinType, Rule: drop>(
    self: &mut XOracle,
    admin_cap: &XOracleAdminCap,
  ) {
    verify_admin(self, admin_cap);
    let policy_cap = borrow_policy_cap(self);
    let secondary_policy_id = price_update_policy::for_policy(&policy_cap.secondary_price_update_policy_cap);
    price_update_policy::remove_rule_v2_by_id<CoinType, Rule>(
      &mut self.secondary_price_update_policy,
      secondary_policy_id
    );
  }  

  public fun add_secondary_price_update_rule<Rule: drop>(
    self: &mut XOracle,
    admin_cap: &XOracleAdminCap,
  ) {
    verify_admin(self, admin_cap);
    let policy_cap = borrow_policy_cap(self);
    let secondary_policy_id = price_update_policy::for_policy(&policy_cap.secondary_price_update_policy_cap);
    price_update_policy::add_rule_by_id<Rule>(
      &mut self.secondary_price_update_policy,
      secondary_policy_id
    );
  }

  public fun remove_secondary_price_update_rule<Rule: drop>(
    self: &mut XOracle,
    admin_cap: &XOracleAdminCap,
  ) {
    verify_admin(self, admin_cap);
    let policy_cap = borrow_policy_cap(self);
    let secondary_policy_id = price_update_policy::for_policy(&policy_cap.secondary_price_update_policy_cap);
    price_update_policy::remove_rule_by_id<Rule>(
      &mut self.secondary_price_update_policy,
      secondary_policy_id
    );
  }

  // === Price Update ===

  public fun price_update_request<T>(
    self: &XOracle,
  ): XOraclePriceUpdateRequest<T> {
    let primary_price_update_request = price_update_policy::new_request<T>(&self.primary_price_update_policy);
    let secondary_price_update_request = price_update_policy::new_request<T>(&self.secondary_price_update_policy);
    XOraclePriceUpdateRequest {
      primary_price_update_request,
      secondary_price_update_request,
    }
  }

  public fun set_primary_price<T, Rule: drop>(
    rule: Rule,
    request: &mut XOraclePriceUpdateRequest<T>,
    price_feed: PriceFeed,
  ) {
    price_update_policy::add_price_feed(rule, &mut request.primary_price_update_request, price_feed);
  }

  public fun set_secondary_price<T, Rule: drop>(
    rule: Rule,
    request: &mut XOraclePriceUpdateRequest<T>,
    price_feed: PriceFeed,
  ) {
    price_update_policy::add_price_feed(rule, &mut request.secondary_price_update_request, price_feed);
  }

  public fun confirm_price_update_request<T>(
    self: &mut XOracle,
    request: XOraclePriceUpdateRequest<T>,
    clock: &Clock,
  ) {
    let XOraclePriceUpdateRequest { primary_price_update_request, secondary_price_update_request  } = request;
    let primary_price_feeds = price_update_policy::confirm_request(
      primary_price_update_request,
      &self.primary_price_update_policy
    );
    let secondary_price_feeds = price_update_policy::confirm_request(
      secondary_price_update_request,
      &self.secondary_price_update_policy
    );
    let coin_type = with_defining_ids<T>();
    if (!table::contains(&self.prices, coin_type)) {
      table::add(&mut self.prices, coin_type, price_feed::new(0,0));
    };
    let price_feed = determine_price(primary_price_feeds, secondary_price_feeds);

    let now = clock::timestamp_ms(clock) / 1000;
    let selected_value_from_rule: u64 = price_feed::value(&price_feed);
    let selected_value: u64 = if (option::is_some(&self.gr_coin_type) && coin_type == *option::borrow(&self.gr_coin_type) && self.gr_computed_value_u64 > 0) {
      self.gr_computed_value_u64
    } else { selected_value_from_rule };
    let new_price_feed = price_feed::new(selected_value, now);
    let current_price_feed = table::borrow_mut(&mut self.prices, with_defining_ids<T>());
    *current_price_feed = new_price_feed;
  }

  fun determine_price(
    mut primary_price_feeds: vector<PriceFeed>,
    mut secondary_price_feeds: vector<PriceFeed>,
  ): PriceFeed {
    // current we only support one primary price feed
    assert!(vector::length(&primary_price_feeds) == 1, ONLY_SUPPORT_ONE_PRIMARY);
    let primary_price_feed = vector::pop_back(&mut primary_price_feeds);
    let secondary_price_feed_num = vector::length(&secondary_price_feeds);

    // We require the primary price feed to be confirmed by at least half of the secondary price feeds
    let required_secondary_match_num = (secondary_price_feed_num + 1) / 2;
    let mut matched: u64 = 0;
    let mut i = 0;
    while (i < secondary_price_feed_num) {
      let secondary_price_feed = vector::pop_back(&mut secondary_price_feeds);
      if (price_feed_match(primary_price_feed, secondary_price_feed)) {
        matched = matched + 1;
      };
      i = i + 1;
    };
    assert!(matched >= required_secondary_match_num, PRIMARY_PRICE_NOT_QUALIFIED);

    // Use the primary price feed as the final price feed
    primary_price_feed
  }

  // Check if two price feeds are within a reasonable range
  // If price_feed1 is within 1% away from price_feed2, then they are considered to be matched
  fun price_feed_match(
    price_feed1: PriceFeed,
    price_feed2: PriceFeed,
  ): bool {
    let value1 = price_feed::value(&price_feed1);
    let value2 = price_feed::value(&price_feed2);

    let scale = 1000;
    let reasonable_diff_percent = 1;
    let reasonable_diff = reasonable_diff_percent * scale / 100;
    let diff = value1 * scale / value2;
    diff <= scale + reasonable_diff && diff >= scale - reasonable_diff
  }


  #[test_only]
  public fun init_t(ctx: &mut TxContext) {
    init(X_ORACLE {}, ctx);
  }

  #[test_only]
  public fun update_price<T>(self: &mut XOracle, clock: &Clock, value: u64) {
    let coin_type = with_defining_ids<T>();
    if (!table::contains(&self.prices, coin_type)) {
      table::add(&mut self.prices, coin_type, price_feed::new(0,0));
    };
    let price_feed = table::borrow_mut(&mut self.prices, coin_type);
    price_feed::update_price_feed(price_feed, value, clock::timestamp_ms(clock) / 1000);
  }
}