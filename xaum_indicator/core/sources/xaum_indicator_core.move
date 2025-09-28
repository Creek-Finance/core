module xaum_indicator_core::xaum_indicator_core {
    use std::vector;
    use std::option;
    use std::type_name::{Self, TypeName, with_defining_ids};
    use std::u64;
    use std::u256;
    use sui::clock::{Self as clock, Clock};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_object_field;
    use sui::sui::SUI;

    use x_oracle::x_oracle::{Self as x_oracle_mod, XOracle, GrIndicatorCap};

    // Core storage and indicators; independent from Pyth adapter
    public struct PriceStorage has key, store {
        id: UID,
        asset_type: TypeName,
        // Optional bound Pyth price feed object id; set by adapter on non-local networks
        pyth_feed_id: option::Option<ID>,
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

    public struct GrCapKey has copy, drop, store {}

    public fun create_price_storage(ctx: &mut TxContext): PriceStorage {
        PriceStorage {
            id: object::new(ctx),
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
        let storage = create_price_storage(ctx);
        transfer::share_object(storage);
    }

    // Manual price setter (9-decimals) for local/general usage
    public fun set_price_9dec(
        storage: &mut PriceStorage,
        value_9: u64,
        x_oracle: &mut XOracle,
        clock: &Clock,
        _ctx: &mut TxContext,
    ) {
        assert!(value_9 > 0, 0);
        let value_18 = (value_9 as u256) * 1000000000u256;
        update_price_storage(storage, value_18);
        // Push EMA120/EMA90 to XOracle (u64 scaled to 9 decimals)
        push_gr_indicators_to_x_oracle(storage, x_oracle, clock, _ctx);
    }

    public fun bind_gr_cap(storage: &mut PriceStorage, cap: GrIndicatorCap, _ctx: &mut TxContext) {
        dynamic_object_field::add<GrCapKey, GrIndicatorCap>(&mut storage.id, GrCapKey {}, cap);
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
    public fun bind_pyth_feed_id(storage: &mut PriceStorage, feed_id: ID) {
        assert!(option::is_none(&storage.pyth_feed_id), 0);
        storage.pyth_feed_id = option::some(feed_id);
    }
    public fun is_pyth_feed_bound(storage: &PriceStorage): bool { option::is_some(&storage.pyth_feed_id) }
    public fun is_matching_pyth_feed_id(storage: &PriceStorage, feed_id: &ID): bool {
        if (!option::is_some(&storage.pyth_feed_id)) { return false };
        *option::borrow(&storage.pyth_feed_id) == *feed_id
    }

    // Push EMA120/EMA90 to XOracle using the internally bound GrIndicatorCap
    public fun push_gr_indicators_to_x_oracle(storage: &PriceStorage, x_oracle: &mut XOracle, clock: &Clock, _ctx: &mut TxContext) {
        let ema120_u256 = storage.ema120_current;
        let ema90_u256 = storage.ema90_current;
        let ema120_u64 = (ema120_u256 / 1000000000u256) as u64;
        let ema90_u64 = (ema90_u256 / 1000000000u256) as u64;
        let spot_u64 = (storage.latest_price / 1000000000u256) as u64;
        let now = clock::timestamp_ms(clock) / 1000;
        let cap_ref = dynamic_object_field::borrow<GrCapKey, GrIndicatorCap>(&storage.id, GrCapKey {});
        x_oracle_mod::set_gr_indicators(x_oracle, cap_ref, ema120_u64, ema90_u64, spot_u64, now, _ctx);
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


