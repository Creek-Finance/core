module xaum_indicator_pyth_adapter::xaum_indicator_pyth_adapter {
    use std::u64;
    use std::u256;
    use sui::clock::Clock;
    use sui::sui::SUI;
    use std::type_name::with_defining_ids;

    use pyth::i64::{Self as i64, I64};
    use pyth::price::{Self as price};
    use pyth::price_info::PriceInfoObject;
    use pyth::pyth;

    use x_oracle::x_oracle::XOracle;
    use xaum_indicator_core::xaum_indicator_core::{Self as core, AdminCap, PriceStorage};

    const ERR_NOT_SUI_STORAGE: u64 = 0xEA01;
    const ERR_FEED_ALREADY_INITIALIZED: u64 = 0xEA02;
    const ERR_FEED_NOT_INITIALIZED: u64 = 0xEA03;
    const ERR_FEED_MISMATCH: u64 = 0xEA04;

    /// Bind the Pyth price feed to core::PriceStorage using a dynamic field
    public fun init_feed(
        admin_cap: &AdminCap,
        storage: &mut PriceStorage,
        price_info_object: &PriceInfoObject,
        _ctx: &mut tx_context::TxContext,
    ) {
        core::assert_admin(storage, admin_cap);
        // Bind feed id via core helper to avoid accessing private fields
        assert!(!core::is_pyth_feed_bound(storage), ERR_FEED_ALREADY_INITIALIZED);
        let feed_id = object::id(price_info_object);
        core::bind_pyth_feed_id(storage, admin_cap, feed_id);
    }

    // no extra types

    /// Pull XAUM price from Pyth, convert to 18-decimal u256, update core, then push EMA120 to XOracle
    public fun update_xaum_price(
        admin_cap: &AdminCap,
        storage: &mut PriceStorage,
        price_info_object: &PriceInfoObject,
        x_oracle: &mut XOracle,
        clock: &Clock,
        _ctx: &mut tx_context::TxContext,
    ) {
        core::assert_admin(storage, admin_cap);
        assert!(with_defining_ids<SUI>() == core::get_asset_type(storage), ERR_NOT_SUI_STORAGE);
        // Verify feed binding
        assert!(core::is_pyth_feed_bound(storage), ERR_FEED_NOT_INITIALIZED);
        let incoming = object::id(price_info_object);
        assert!(core::is_matching_pyth_feed_id(storage, &incoming), ERR_FEED_MISMATCH);

        let price_info = pyth::get_price_no_older_than(price_info_object, clock, 60);
        let p = price::get_price(&price_info);
        if (i64::get_is_negative(&p)) { return };
        let expo = price::get_expo(&price_info);
        let expo_abs = if (i64::get_is_negative(&expo)) { i64::get_magnitude_if_negative(&expo) } else { i64::get_magnitude_if_positive(&expo) };
        if (!i64::get_is_negative(&expo) && expo_abs > 18) { return };

        let normalized = convert_price_to_u256(&p, &expo);
        core::update_price_storage_external(storage, normalized);

        core::push_gr_indicators_to_x_oracle(storage, admin_cap, x_oracle, clock, _ctx);
    }

    /// Normalize Pyth price to 18 decimals (same logic as original)
    fun convert_price_to_u256(price: &I64, expo: &I64): u256 {
        let price_value = if (i64::get_is_negative(price)) { i64::get_magnitude_if_negative(price) } else { i64::get_magnitude_if_positive(price) };
        let expo_value = if (i64::get_is_negative(expo)) { i64::get_magnitude_if_negative(expo) } else { i64::get_magnitude_if_positive(expo) };
        let is_exponent_negative = i64::get_is_negative(expo);
        let result = if (is_exponent_negative) {
            let divisor = (u64::pow(10, (expo_value as u8)) as u256);
            ((price_value as u256) * 1000000000000000000u256) / divisor
        } else {
            let multiplier = (u64::pow(10, (expo_value as u8)) as u256);
            (price_value as u256) * multiplier * u256::pow(10, (18 - expo_value) as u8)
        };
        result
    }

    // === Re-export core getters for convenience ===
    public fun get_latest_price(storage: &core::PriceStorage): u256 { core::get_latest_price(storage) }
    public fun get_ema120_current(storage: &core::PriceStorage): u256 { core::get_ema120_current(storage) }

    // No extra types needed
}