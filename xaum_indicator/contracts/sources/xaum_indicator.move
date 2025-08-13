/// Module: xaum_indicator
/// 
/// This module periodically fetches asset prices from the Pyth oracle,
/// normalizes them to 18-decimal u256 format, and calculates technical
/// indicators such as EMA120 and EMA5. It stores the latest price, a
/// rolling price history, the average price, and EMA values for use
/// by other on-chain contracts.
///
/// Functions:
/// - Update price from Pyth (with or without timestamp validation)
/// - Convert oracle price format to standardized u256
/// - Calculate and update EMA values
/// - Provide access to latest price, history, average, and EMA data
module xaum_indicator::xaum_indicator {
    use sui::clock::{Clock};
    use std::u64;
    use std::u256;
    use pyth::price::{Self};
    use pyth::price_info::{PriceInfoObject};
    use pyth::pyth::{Self};
    use pyth::i64::{Self, I64};

    /// Stores pricing and indicator data used by the module.
    /// 
    /// Fields:
    /// - `latest_price`: Most recent price (u256, 18 decimals)
    /// - `price_history`: Rolling list of recent prices
    /// - `average_price`: Average of stored prices
    /// - `max_history_length`: Max number of prices to keep
    /// - `ema120_current` / `ema120_previous`: EMA with period 120
    /// - `ema5_current` / `ema5_previous`: EMA with period 5
    /// - `ema_initialized`: Whether EMA values have been initialized
    public struct PriceStorage has key, store {
        id: UID,
        /// Latest price (u256, with 18 decimals)
        latest_price: u256,
        /// Last 10 recorded prices (u256, with 18 decimals)
        price_history: vector<u256>,
        /// Average of the last 10 prices (u256, with 18 decimals)
        average_price: u256,
        /// Max length of price history
        max_history_length: u64,
        /// EMA120 current value (u256, with 18 decimals)
        ema120_current: u256,
        /// EMA120 previous value (u256, with 18 decimals)
        ema120_previous: u256,
        /// EMA5 current value (u256, with 18 decimals)
        ema5_current: u256,
        /// EMA5 previous value (u256, with 18 decimals)
        ema5_previous: u256,
        /// Whether EMA values have been initialized
        ema_initialized: bool,
    }

    fun create_price_storage(ctx: &mut TxContext): PriceStorage {
        PriceStorage {
            id: object::new(ctx),
            latest_price: 0u256,
            price_history: vector::empty(),
            average_price: 0u256,
            max_history_length: 10,
            ema120_current: 0u256,
            ema120_previous: 0u256,
            ema5_current: 0u256,
            ema5_previous: 0u256,
            ema_initialized: false,
        }
    }

    fun init(ctx: &mut TxContext) {
        let price_storage = create_price_storage(ctx);
        transfer::share_object(price_storage);
    }

    public entry fun init_for_testing(ctx: &mut TxContext) {
        let price_storage = create_price_storage(ctx);
        transfer::share_object(price_storage);
    }

    /// Fetches SUI price from Pyth and updates storage.
    /// SUI price ID: 0x23d7315113f5b1d3ba7a83604c44b94d79f4fd69af77f804fc7f920a6dc65744  
    /// Reference: https://docs.pyth.network/price-feeds/use-real-time-data/sui
    public entry fun update_sui_price(
        price_storage: &mut PriceStorage,
        price_info_object: &PriceInfoObject,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {
        let price_info = pyth::get_price_no_older_than(price_info_object, clock, 60);
        let price = price::get_price(&price_info);
        let expo = price::get_expo(&price_info);
        let normalized_price = convert_price_to_u256(&price, &expo);
        update_price_storage(price_storage, normalized_price);
    }

    /// Fetches SUI price from Pyth without timestamp validation.
    /// SUI price ID: 0x23d7315113f5b1d3ba7a83604c44b94d79f4fd69af77f804fc7f920a6dc65744
    public entry fun update_sui_price_without_clock(
        price_storage: &mut PriceStorage,
        price_info_object: &PriceInfoObject,
        _ctx: &mut TxContext
    ) {
        let price_info = pyth::get_price_unsafe(price_info_object);
        let price = price::get_price(&price_info);
        let expo = price::get_expo(&price_info);
        let normalized_price = convert_price_to_u256(&price, &expo);
        update_price_storage(price_storage, normalized_price);
    }

    /// Converts Pyth price to u256 with 18 decimal places.
    fun convert_price_to_u256(price: &I64, expo: &I64): u256 {
        let price_value = if (i64::get_is_negative(price)) {
            i64::get_magnitude_if_negative(price)
        } else {
            i64::get_magnitude_if_positive(price)
        };
        
        let expo_value = if (i64::get_is_negative(expo)) {
            i64::get_magnitude_if_negative(expo)
        } else {
            i64::get_magnitude_if_positive(expo)
        };
        
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

    /// Calculates EMA: EMA(t) = α × Price(t) + (1 - α) × EMA(t-1), where α = 2/(N+1)
    fun calculate_ema(new_price: u256, previous_ema: u256, period: u64): u256 {
        let precision = 1000000000000000000u256; // 10^18
        let alpha = 2 * precision / ((period + 1) as u256);
        let one_minus_alpha = precision - alpha;
        let term1 = (new_price * alpha) / precision;
        let term2 = (previous_ema * one_minus_alpha) / precision;
        term1 + term2
    }

    /// Updates EMA values for both EMA120 and EMA5.
    fun update_ema_values(price_storage: &mut PriceStorage, new_price: u256) {
        if (!price_storage.ema_initialized) {
            price_storage.ema120_current = new_price;
            price_storage.ema120_previous = new_price;
            price_storage.ema5_current = new_price;
            price_storage.ema5_previous = new_price;
            price_storage.ema_initialized = true;
        } else {
            price_storage.ema120_previous = price_storage.ema120_current;
            price_storage.ema5_previous = price_storage.ema5_current;
            price_storage.ema120_current = calculate_ema(new_price, price_storage.ema120_previous, 120);
            price_storage.ema5_current = calculate_ema(new_price, price_storage.ema5_previous, 5);
        };
    }

    fun update_price_storage(price_storage: &mut PriceStorage, new_price: u256) {
        price_storage.latest_price = new_price;
        update_ema_values(price_storage, new_price);
        vector::push_back(&mut price_storage.price_history, new_price);

        if (vector::length(&price_storage.price_history) > price_storage.max_history_length) {
            vector::remove(&mut price_storage.price_history, 0);
        };

        let mut total_price = 0u256;
        let history_length = vector::length(&price_storage.price_history);
        
        let mut i = 0;
        while (i < history_length) {
            total_price = total_price + *vector::borrow(&price_storage.price_history, i);
            i = i + 1;
        };

        if (history_length > 0) {
            price_storage.average_price = total_price / (history_length as u256);
        };
    }

    public fun get_latest_price(price_storage: &PriceStorage): u256 {
        price_storage.latest_price
    }

    public fun get_price_history(price_storage: &PriceStorage): &vector<u256> {
        &price_storage.price_history
    }

    public fun get_average_price(price_storage: &PriceStorage): u256 {
        price_storage.average_price
    }

    public fun get_history_length(price_storage: &PriceStorage): u64 {
        vector::length(&price_storage.price_history)
    }

    public fun get_max_history_length(price_storage: &PriceStorage): u64 {
        price_storage.max_history_length
    }

    public fun get_ema120_current(price_storage: &PriceStorage): u256 {
        price_storage.ema120_current
    }

    public fun get_ema120_previous(price_storage: &PriceStorage): u256 {
        price_storage.ema120_previous
    }

    public fun get_ema5_current(price_storage: &PriceStorage): u256 {
        price_storage.ema5_current
    }

    public fun get_ema5_previous(price_storage: &PriceStorage): u256 {
        price_storage.ema5_previous
    }

    public fun get_ema_initialized(price_storage: &PriceStorage): bool {
        price_storage.ema_initialized
    }
}