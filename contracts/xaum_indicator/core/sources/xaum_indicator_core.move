module xaum_indicator_core::xaum_indicator_core {

    use std::type_name::{TypeName, with_defining_ids};
    use sui::{
        clock::Clock,
        dynamic_object_field,
        sui::SUI,
    };

    use x_oracle::x_oracle::{Self as x_oracle_mod, XOracle, XOracleAdminCap};

    const E_NOT_ADMIN: u64 = 0x1;

    // Core storage and indicators; independent from Pyth adapter
    public struct PriceStorage has key, store {
        id: UID,
        admin_cap_id: ID,
        asset_type: TypeName,
        // Optional bound Pyth price feed object id; set by adapter on non-local networks
        pyth_feed_id: Option<ID>,
        latest_price: u256,
        price_history: vector<u256>,
        average_price: u256,
        max_history_length: u64,
        ema120_current: u256,
        ema120_previous: u256,
        ema90_current: u256,
        ema90_previous: u256,
        ema5_current: u256,
        ema5_previous: u256,
        ema_initialized: bool,
    }

    public struct AdminCap has key, store {
        id: UID,
    }

    public struct OwnerCap has key, store {
        id: UID,
    }

    public struct AdminCapKey has copy, drop, store {}

    public fun create_price_storage(admin_cap_id: ID, ctx: &mut TxContext): PriceStorage {
        PriceStorage {
            id: object::new(ctx),
            admin_cap_id,
            asset_type: with_defining_ids<SUI>(),
            pyth_feed_id: option::none<ID>(),
            latest_price: 0u256,
            price_history: vector::empty(),
            average_price: 0u256,
            max_history_length: 10,
            ema120_current: 0u256,
            ema120_previous: 0u256,
            ema90_current: 0u256,
            ema90_previous: 0u256,
            ema5_current: 0u256,
            ema5_previous: 0u256,
            ema_initialized: false,
        }
    }

    fun init(ctx: &mut TxContext) {
        let admin = create_admin_cap(ctx);
        let admin_cap_id = object::id(&admin);
        let storage = create_price_storage(admin_cap_id, ctx);
        transfer::share_object(storage);
        let owner = create_owner_cap(ctx);
        transfer::transfer(owner, tx_context::sender(ctx));
        transfer::transfer(admin, tx_context::sender(ctx));
    }

    fun create_admin_cap(ctx: &mut TxContext): AdminCap {
        AdminCap { id: object::new(ctx) }
    }

    fun create_owner_cap(ctx: &mut TxContext): OwnerCap {
        OwnerCap { id: object::new(ctx) }
    }

    #[allow(lint(custom_state_change))]
    public fun transfer_owner_cap(owner_cap: OwnerCap, recipient: address) {
        transfer::transfer(owner_cap, recipient);
    }

    /// Owner override: mint a fresh AdminCap and assign to `new_admin`
    public fun set_admin_cap(
        _owner_cap: &OwnerCap,
        storage: &mut PriceStorage,
        new_admin: address,
        ctx: &mut TxContext,
    ) {
        let admin = create_admin_cap(ctx);
        storage.admin_cap_id = object::id(&admin);
        transfer::transfer(admin, new_admin);
    }

    #[test_only]
    public fun test_create_storage_with_admin(ctx: &mut TxContext): (PriceStorage, AdminCap) {
        let admin = create_admin_cap(ctx);
        let storage = create_price_storage(object::id(&admin), ctx);
        (storage, admin)
    }

    #[test_only]
    public fun test_destroy_admin_cap(admin_cap: AdminCap) {
        let AdminCap { id } = admin_cap;
        object::delete(id);
    }

    public fun assert_admin(storage: &PriceStorage, admin_cap: &AdminCap) {
        assert!(object::id(admin_cap) == storage.admin_cap_id, E_NOT_ADMIN);
    }

    /// Initialize EMA values with custom starting values (18-decimal precision)
    /// Can only be called once when ema_initialized is false
    public fun init_ema_values(
        admin_cap: &AdminCap,
        storage: &mut PriceStorage,
        ema120_initial: u256,
        ema90_initial: u256,
        ema5_initial: u256,
        _ctx: &mut TxContext,
    ) {
        assert_admin(storage, admin_cap);
        assert!(!storage.ema_initialized, 0);
        storage.ema120_current = ema120_initial;
        storage.ema120_previous = ema120_initial;
        storage.ema90_current = ema90_initial;
        storage.ema90_previous = ema90_initial;
        storage.ema5_current = ema5_initial;
        storage.ema5_previous = ema5_initial;
        storage.ema_initialized = true;
    }

    // Manual price setter (9-decimals) for local/general usage
    public fun set_price_9dec(
        admin_cap: &AdminCap,
        storage: &mut PriceStorage,
        value_9: u64,
        x_oracle: &mut XOracle,
        clock: &Clock,
        _ctx: &mut TxContext,
    ) {
        assert_admin(storage, admin_cap);
        assert!(value_9 > 0, 0);
        let value_18 = (value_9 as u256) * 1000000000u256;
        update_price_storage(storage, value_18);
        // Push EMA120/EMA90 to XOracle (u64 scaled to 9 decimals)
        push_gr_indicators_to_x_oracle(storage, admin_cap, x_oracle, clock, _ctx);
    }

    /// Bind XOracleAdminCap to PriceStorage so it can push EMA120/EMA90 to XOracle
    public fun bind_admin_cap(
        storage: &mut PriceStorage,
        admin_cap_auth: &AdminCap,
        admin_cap: XOracleAdminCap,
        _ctx: &mut TxContext,
    ) {
        assert_admin(storage, admin_cap_auth);
        dynamic_object_field::add<AdminCapKey, XOracleAdminCap>(&mut storage.id, AdminCapKey {}, admin_cap);
    }

    // === EMA and average calculation ===
    fun calculate_ema(new_price: u256, previous_ema: u256, period: u64): u256 {
        let precision = 1000000000000000000u256; // 1e18
        let alpha = 2 * precision / ((period + 1) as u256);
        let one_minus_alpha = precision - alpha;
        let term1 = (new_price * alpha) / precision;
        let term2 = (previous_ema * one_minus_alpha) / precision;
        term1 + term2
    }

    fun update_ema_values(storage: &mut PriceStorage, new_price: u256) {
        if (!storage.ema_initialized) {
            storage.ema120_current = new_price;
            storage.ema120_previous = new_price;
            storage.ema90_current = new_price;
            storage.ema90_previous = new_price;
            storage.ema5_current = new_price;
            storage.ema5_previous = new_price;
            storage.ema_initialized = true;
        } else {
            storage.ema120_previous = storage.ema120_current;
            storage.ema90_previous = storage.ema90_current;
            storage.ema5_previous = storage.ema5_current;
            storage.ema120_current = calculate_ema(new_price, storage.ema120_previous, 172800);
            storage.ema90_current = calculate_ema(new_price, storage.ema90_previous, 129600);
            storage.ema5_current = calculate_ema(new_price, storage.ema5_previous, 7200);
        };
    }

    fun update_price_storage(storage: &mut PriceStorage, new_price: u256) {
        storage.latest_price = new_price;
        update_ema_values(storage, new_price);
        vector::push_back(&mut storage.price_history, new_price);
        if (vector::length(&storage.price_history) > storage.max_history_length) {
            vector::remove(&mut storage.price_history, 0);
        };

        let mut total = 0u256;
        let len = vector::length(&storage.price_history);
        let mut i = 0;
        while (i < len) {
            total = total + *vector::borrow(&storage.price_history, i);
            i = i + 1;
        };
        if (len > 0) { storage.average_price = total / (len as u256); };
    }

    // External update entrypoint for adapters
    public fun update_price_storage_external(storage: &mut PriceStorage, new_price: u256) {
        update_price_storage(storage, new_price)
    }

    // Feed binding helpers (used by adapter)
    public fun bind_pyth_feed_id(storage: &mut PriceStorage, admin_cap: &AdminCap, feed_id: ID) {
        assert_admin(storage, admin_cap);
        assert!(option::is_none(&storage.pyth_feed_id), 0);
        storage.pyth_feed_id = option::some(feed_id);
    }
    public fun is_pyth_feed_bound(storage: &PriceStorage): bool { option::is_some(&storage.pyth_feed_id) }
    public fun is_matching_pyth_feed_id(storage: &PriceStorage, feed_id: &ID): bool {
        if (!option::is_some(&storage.pyth_feed_id)) { return false };
        *option::borrow(&storage.pyth_feed_id) == *feed_id
    }

    // Push EMA120/EMA90 to XOracle using the internally bound AdminCap
    public fun push_gr_indicators_to_x_oracle(
        storage: &PriceStorage,
        admin_cap: &AdminCap,
        x_oracle: &mut XOracle,
        clock: &Clock,
        _ctx: &mut TxContext,
    ) {
        assert_admin(storage, admin_cap);
        let ema120_u256 = storage.ema120_current;
        let ema90_u256 = storage.ema90_current;
        let ema120_u64 = (ema120_u256 / 1000000000u256) as u64;
        let ema90_u64 = (ema90_u256 / 1000000000u256) as u64;
        let spot_u64 = (storage.latest_price / 1000000000u256) as u64;
        let now = sui::clock::timestamp_ms(clock) / 1000;
        let admin_cap_ref = dynamic_object_field::borrow<AdminCapKey, XOracleAdminCap>(&storage.id, AdminCapKey {});
        x_oracle_mod::set_gr_indicators(x_oracle, admin_cap_ref, ema120_u64, ema90_u64, spot_u64, now, _ctx);
    }

    public fun get_latest_price(storage: &PriceStorage): u256 { storage.latest_price }
    public fun get_price_history(storage: &PriceStorage): &vector<u256> { &storage.price_history }
    public fun get_average_price(storage: &PriceStorage): u256 { storage.average_price }
    public fun get_history_length(storage: &PriceStorage): u64 { vector::length(&storage.price_history) }
    public fun get_max_history_length(storage: &PriceStorage): u64 { storage.max_history_length }
    public fun get_ema120_current(storage: &PriceStorage): u256 { storage.ema120_current }
    public fun get_ema120_previous(storage: &PriceStorage): u256 { storage.ema120_previous }
    public fun get_ema90_current(storage: &PriceStorage): u256 { storage.ema90_current }
    public fun get_ema90_previous(storage: &PriceStorage): u256 { storage.ema90_previous }
    public fun get_ema5_current(storage: &PriceStorage): u256 { storage.ema5_current }
    public fun get_ema5_previous(storage: &PriceStorage): u256 { storage.ema5_previous }
    public fun get_ema_initialized(storage: &PriceStorage): bool { storage.ema_initialized }

    // Helper for adapters to validate storage asset type
    public fun get_asset_type(storage: &PriceStorage): TypeName { storage.asset_type }
}