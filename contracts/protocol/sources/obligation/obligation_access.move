module protocol::obligation_access;

use protocol::error;
use std::type_name::{Self, TypeName};
use sui::vec_set::{Self, VecSet};

public struct ObligationAccessStore has key, store {
    id: UID,
    lock_keys: VecSet<TypeName>,
    reward_keys: VecSet<TypeName>,
}

fun init(ctx: &mut TxContext) {
    let store = ObligationAccessStore {
        id: object::new(ctx),
        lock_keys: vec_set::empty(),
        reward_keys: vec_set::empty(),
    };
    transfer::share_object(store);
}

#[test_only]
public fun init_test(ctx: &mut TxContext) {
    init(ctx);
}

public(package) fun add_lock_key<T: drop>(self: &mut ObligationAccessStore) {
    let key = type_name::get<T>();
    assert!(!vec_set::contains(&self.lock_keys, &key), error::obligation_access_store_key_exists());
    vec_set::insert(&mut self.lock_keys, key);
}

public(package) fun remove_lock_key<T: drop>(self: &mut ObligationAccessStore) {
    let key = type_name::get<T>();
    assert!(
        vec_set::contains(&self.lock_keys, &key),
        error::obligation_access_store_key_not_found(),
    );
    vec_set::remove(&mut self.lock_keys, &key);
}

public(package) fun add_reward_key<T: drop>(self: &mut ObligationAccessStore) {
    let key = type_name::get<T>();
    assert!(
        !vec_set::contains(&self.reward_keys, &key),
        error::obligation_access_store_key_exists(),
    );
    vec_set::insert(&mut self.reward_keys, key);
}

public(package) fun remove_reward_key<T: drop>(self: &mut ObligationAccessStore) {
    let key = type_name::get<T>();
    assert!(
        vec_set::contains(&self.reward_keys, &key),
        error::obligation_access_store_key_not_found(),
    );
    vec_set::remove(&mut self.reward_keys, &key);
}

public fun assert_lock_key_in_store<T: drop>(store: &ObligationAccessStore, _: T) {
    let key = type_name::get<T>();
    assert!(
        vec_set::contains(&store.lock_keys, &key),
        error::obligation_access_lock_key_not_in_store(),
    );
}

public fun assert_reward_key_in_store<T: drop>(store: &ObligationAccessStore, _: T) {
    let key = type_name::get<T>();
    assert!(
        vec_set::contains(&store.reward_keys, &key),
        error::obligation_access_reward_key_not_in_store(),
    );
}
