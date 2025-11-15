module x_oracle::price_update_policy {

  use std::type_name::{TypeName, with_defining_ids};
  use sui::vec_set::{Self, VecSet};
  use sui::table::{Self, Table};
  use sui::dynamic_field;

  use x_oracle::price_feed::PriceFeed;

  const REQUIRE_ALL_RULES_FOLLOWED: u64 = 721;
  const REQUST_NOT_FOR_THIS_POLICY: u64 = 722;
  const WRONG_POLICY_CAP: u64 = 723;

  public struct PriceUpdateRequest<phantom T> {
    for_policy: ID,
    receipts: VecSet<TypeName>,
    price_feeds: vector<PriceFeed>,
  }

  public struct PriceUpdatePolicy has key, store {
    id: UID,
    rules: VecSet<TypeName>,
  }

  public struct PriceUpdatePolicyCap has key, store {
    id: UID,
    for_policy: ID,
  }

  public fun for_policy(cap: &PriceUpdatePolicyCap): ID {
    cap.for_policy
  }

  public struct PriceUpdatePolicyRulesKey has copy, drop, store {}

  public fun new(ctx: &mut TxContext): (PriceUpdatePolicy, PriceUpdatePolicyCap) {
    let policy = PriceUpdatePolicy {
      id: object::new(ctx),
      rules: vec_set::empty(),
    };
    let cap = PriceUpdatePolicyCap {
      id: object::new(ctx),
      for_policy: object::id(&policy),
    };
    (policy, cap)
  }

  public fun new_request<T>(policy: &PriceUpdatePolicy): PriceUpdateRequest<T> {
    PriceUpdateRequest {
      for_policy: object::id(policy),
      receipts: vec_set::empty(),
      price_feeds: vector::empty(),
    }
  }

  public(package) fun init_rules_df_if_not_exist(_policy_cap: &PriceUpdatePolicyCap, policy: &mut PriceUpdatePolicy, ctx: &mut TxContext) {
    init_rules_df_if_not_exist_by_id(object::id(policy), policy, ctx);
  }

  // Version that accepts policy_id instead of cap to avoid borrowing conflicts
  public(package) fun init_rules_df_if_not_exist_by_id(_policy_id: ID, policy: &mut PriceUpdatePolicy, ctx: &mut TxContext) {
    if(!dynamic_field::exists_<PriceUpdatePolicyRulesKey>(
        &policy.id,
        PriceUpdatePolicyRulesKey {},
    )) {
      dynamic_field::add<PriceUpdatePolicyRulesKey, Table<TypeName, VecSet<TypeName>>>(&mut policy.id, PriceUpdatePolicyRulesKey {}, table::new(ctx));
    }
  }

  public fun get_price_update_policy<CoinType>(policy: &PriceUpdatePolicy): VecSet<TypeName> {
    let rules_table = dynamic_field::borrow<PriceUpdatePolicyRulesKey, Table<TypeName, VecSet<TypeName>>>(
        &policy.id,
        PriceUpdatePolicyRulesKey {},
    );
    let coin_type = with_defining_ids<CoinType>();
    if (!table::contains(rules_table, coin_type)) {
      return vec_set::empty()
    };
    
    let rules = table::borrow(rules_table, coin_type);
    *rules
  }

  public(package) fun add_rule_v2<CoinType, Rule>(
    policy: &mut PriceUpdatePolicy,
    cap: &PriceUpdatePolicyCap,
  ) {
    add_rule_v2_by_id<CoinType, Rule>(policy, for_policy(cap));
  }

  // Version that accepts policy_id instead of cap to avoid borrowing conflicts
  public(package) fun add_rule_v2_by_id<CoinType, Rule>(
    policy: &mut PriceUpdatePolicy,
    policy_id: ID,
  ) {
    assert!(object::id(policy) == policy_id, WRONG_POLICY_CAP);
    let rules_table = dynamic_field::borrow_mut<PriceUpdatePolicyRulesKey, Table<TypeName, VecSet<TypeName>>>(
        &mut policy.id,
        PriceUpdatePolicyRulesKey {},
    );

    let coin_type = with_defining_ids<CoinType>();
    // add record if not exist
    if (!table::contains(rules_table, coin_type)) {
      table::add(rules_table, coin_type, vec_set::empty());
    };

    let rules = table::borrow_mut(rules_table, coin_type);
    vec_set::insert(rules, with_defining_ids<Rule>());
  }

  public fun add_rule<Rule>(
    policy: &mut PriceUpdatePolicy,
    cap: &PriceUpdatePolicyCap,
  ) {
    add_rule_by_id<Rule>(policy, for_policy(cap));
  }

  // Version that accepts policy_id instead of cap to avoid borrowing conflicts
  public fun add_rule_by_id<Rule>(
    policy: &mut PriceUpdatePolicy,
    policy_id: ID,
  ) {
    assert!(object::id(policy) == policy_id, WRONG_POLICY_CAP);
    vec_set::insert(&mut policy.rules, with_defining_ids<Rule>());
  }

  public(package) fun remove_rule_v2<CoinType, Rule>(
    policy: &mut PriceUpdatePolicy,
    cap: &PriceUpdatePolicyCap,
  ) {
    remove_rule_v2_by_id<CoinType, Rule>(policy, for_policy(cap));
  }

  // Version that accepts policy_id instead of cap to avoid borrowing conflicts
  public(package) fun remove_rule_v2_by_id<CoinType, Rule>(
    policy: &mut PriceUpdatePolicy,
    policy_id: ID,
  ) {
    assert!(object::id(policy) == policy_id, WRONG_POLICY_CAP);
    let rules_table = dynamic_field::borrow_mut<PriceUpdatePolicyRulesKey, Table<TypeName, VecSet<TypeName>>>(
        &mut policy.id,
        PriceUpdatePolicyRulesKey {},
    );

    let coin_type = with_defining_ids<CoinType>();
    // skip if not exist
    if (!table::contains(rules_table, coin_type)) {
      return
    };

    let rules = table::borrow_mut(rules_table, coin_type);
    vec_set::remove<TypeName>(rules, &with_defining_ids<Rule>());
  }  

  public fun remove_rule<Rule>(
    policy: &mut PriceUpdatePolicy,
    cap: &PriceUpdatePolicyCap,
  ) {
    remove_rule_by_id<Rule>(policy, for_policy(cap));
  }

  // Version that accepts policy_id instead of cap to avoid borrowing conflicts
  public fun remove_rule_by_id<Rule>(
    policy: &mut PriceUpdatePolicy,
    policy_id: ID,
  ) {
    assert!(object::id(policy) == policy_id, WRONG_POLICY_CAP);
    vec_set::remove<TypeName>(&mut policy.rules, &with_defining_ids<Rule>());
  }

  public fun add_price_feed<CoinType, Rule: drop>(
    _rule: Rule,
    request: &mut PriceUpdateRequest<CoinType>,
    feed: PriceFeed,
  ) {
    vec_set::insert(&mut request.receipts, with_defining_ids<Rule>());
    vector::push_back(&mut request.price_feeds, feed);
  }

  public fun confirm_request<CoinType>(request: PriceUpdateRequest<CoinType>, policy: &PriceUpdatePolicy): vector<PriceFeed> {
    let PriceUpdateRequest { receipts, for_policy, price_feeds } = request;
    assert!(for_policy == object::id(policy), REQUST_NOT_FOR_THIS_POLICY);

    let mut receipts = vec_set::into_keys(receipts);
    let completed = vector::length(&receipts);
    let rules = get_price_update_policy<CoinType>(policy);
    assert!(completed == vec_set::length(&rules), REQUIRE_ALL_RULES_FOLLOWED);
    let mut i = 0;
    while(i < completed) {
      let receipt = vector::pop_back(&mut receipts);
      assert!(vec_set::contains(&rules, &receipt), REQUIRE_ALL_RULES_FOLLOWED);
      i = i + 1;
    };
    price_feeds
  }
}
