/// Module: global_config
///
/// Stores global configuration for the protocol, including treasury caps
/// for different coins and the staking manager address. Provides admin-only
/// functions to set and update these configurations, and getter functions
/// for retrieval.
module global_config::global_config;

use coin_gr::coin_gr::COIN_GR;
use coin_gy::coin_gy::COIN_GY;
use sui::coin::TreasuryCap;
use sui::dynamic_field as df;
use sui::dynamic_object_field as dof;
use sui::event;

/// Global configuration object containing admin address.
public struct GlobalConfig has key {
    id: object::UID,
    admin: address,
}

/// Event emitted when a GlobalConfig object is created.
public struct ConfigCreated has copy, drop {
    config_id: address,
}

/// Dynamic field key for storing configuration items.
public struct ObjectKey has copy, drop, store {
    name: vector<u8>,
}

/// Initializes the GlobalConfig object with the sender as admin.
fun init(ctx: &mut TxContext) {
    let admin = tx_context::sender(ctx);
    let config = GlobalConfig {
        id: object::new(ctx),
        admin,
    };
    let config_id = object::id_address(&config);
    event::emit(ConfigCreated { config_id });
    transfer::share_object(config);
}

/// Sets GR TreasuryCap (admin only).
public entry fun set_gr_treasury_cap(
    config: &mut GlobalConfig,
    cap: TreasuryCap<COIN_GR>,
    ctx: &mut TxContext,
) {
    assert!(tx_context::sender(ctx) == config.admin, 0);
    dof::add(&mut config.id, ObjectKey { name: b"coin_gr_treasury_cap" }, cap);
}

/// Sets GY TreasuryCap (admin only).
public entry fun set_gy_treasury_cap(
    config: &mut GlobalConfig,
    cap: TreasuryCap<COIN_GY>,
    ctx: &mut TxContext,
) {
    assert!(tx_context::sender(ctx) == config.admin, 0);
    dof::add(&mut config.id, ObjectKey { name: b"coin_gy_treasury_cap" }, cap);
}

/// Sets staking manager ID (admin only).
public entry fun set_staking_manager_id(
    config: &mut GlobalConfig,
    manager_id: address,
    ctx: &mut TxContext,
) {
    assert!(tx_context::sender(ctx) == config.admin, 0);
    df::add(&mut config.id, ObjectKey { name: b"staking_manager_id" }, manager_id);
}

/// Updates staking manager ID if it exists, otherwise sets it (admin only).
public fun update_staking_manager_id(
    config: &mut GlobalConfig,
    manager_id: address,
    ctx: &mut TxContext,
) {
    assert!(tx_context::sender(ctx) == config.admin, 0);
    if (df::exists_(&config.id, ObjectKey { name: b"staking_manager_id" })) {
        let _old_id: address = df::remove(
            &mut config.id,
            ObjectKey { name: b"staking_manager_id" },
        );
        df::add(&mut config.id, ObjectKey { name: b"staking_manager_id" }, manager_id);
    } else {
        df::add(&mut config.id, ObjectKey { name: b"staking_manager_id" }, manager_id);
    }
}

/// Borrows mutable reference to GR TreasuryCap from config.
public fun borrow_gr_treasury_cap(config: &mut GlobalConfig): &mut TreasuryCap<COIN_GR> {
    dof::borrow_mut(&mut config.id, ObjectKey { name: b"coin_gr_treasury_cap" })
}

/// Borrows mutable reference to GY TreasuryCap from config.
public fun borrow_gy_treasury_cap(config: &mut GlobalConfig): &mut TreasuryCap<COIN_GY> {
    dof::borrow_mut(&mut config.id, ObjectKey { name: b"coin_gy_treasury_cap" })
}

/// Retrieves staking manager ID from config.
public fun get_staking_manager_id(config: &GlobalConfig): address {
    *df::borrow(&config.id, ObjectKey { name: b"staking_manager_id" })
}
