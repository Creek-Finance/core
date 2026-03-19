module rewards::admin;

use sui::event::emit;
use sui::table::{Self, Table};

/// ================================
/// Error codes
/// ================================
const E_NOT_KEEPER: u64 = 1;
const E_KEEPER_ALREADY_EXISTS: u64 = 2;
const E_KEEPER_NOT_FOUND: u64 = 3;

/// ================================
/// Admin 能力对象（唯一）
/// ================================
public struct AdminCap has key, store {
    id: UID,
}

/// ================================
/// Keeper 注册表（Admin 托管）
/// ================================
public struct KeeperRegistry has key {
    id: UID,
    keepers: Table<address, bool>,
}

public struct KeeperAdded has copy, drop {
    keeper: address,
}

public struct KeeperRemoved has copy, drop {
    keeper: address,
}

/// ================================
/// 初始化
/// ================================
fun init(ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);

    // 创建并转移 AdminCap
    transfer::transfer(
        AdminCap { id: object::new(ctx) },
        sender,
    );

    // 创建 KeeperRegistry
    let registry = KeeperRegistry {
        id: object::new(ctx),
        keepers: table::new(ctx),
    };
    transfer::share_object(registry);
}

/// ================================
/// Admin 管理 Keeper
/// ================================

/// Admin 添加 Keeper
public entry fun add_keeper(_admin: &AdminCap, registry: &mut KeeperRegistry, keeper: address) {
    assert!(!table::contains(&registry.keepers, keeper), E_KEEPER_ALREADY_EXISTS);

    table::add(&mut registry.keepers, keeper, true);
    emit(KeeperAdded {
        keeper,
    });
}

/// Admin 删除 Keeper
public entry fun remove_keeper(_admin: &AdminCap, registry: &mut KeeperRegistry, keeper: address) {
    assert!(table::contains(&registry.keepers, keeper), E_KEEPER_NOT_FOUND);

    table::remove(&mut registry.keepers, keeper);
    emit(KeeperRemoved {
        keeper,
    });
}

/// ================================
/// Keeper-only 权限校验（内部函数）
/// ================================
public(package) fun assert_keeper(registry: &KeeperRegistry, ctx: &TxContext) {
    let sender = tx_context::sender(ctx);
    assert!(table::contains(&registry.keepers, sender), E_NOT_KEEPER);
}
