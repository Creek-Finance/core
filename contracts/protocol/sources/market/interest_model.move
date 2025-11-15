module protocol::interest_model;

use protocol::error;
use std::fixed_point32::{Self, FixedPoint32};
use std::type_name::{TypeName, get};
use sui::event::emit;
use x::ac_table::{Self, AcTable, AcTableCap};
use x::one_time_lock_value::{Self, OneTimeLockValue};

const InterestModelChangeEffectiveEpoches: u64 = 7;

// Interest model structure, add the public keyword
public struct InterestModel has copy, drop, store {
    asset_type: TypeName,
    base_borrow_rate_per_sec: FixedPoint32,
    interest_rate_scale: u64,
    revenue_factor: FixedPoint32,
    min_borrow_amount: u64,
}

// Create an event structure for the interest model change and add the public keyword
public struct InterestModelChangeCreated has copy, drop {
    interest_model: InterestModel,
    current_epoch: u64,
    delay_epoches: u64,
    effective_epoches: u64,
}

// Add an event structure to the interest model and add the public keyword
public struct InterestModelAdded has copy, drop {
    interest_model: InterestModel,
    current_epoch: u64,
}

public fun base_borrow_rate(model: &InterestModel): FixedPoint32 { model.base_borrow_rate_per_sec }

public fun interest_rate_scale(model: &InterestModel): u64 { model.interest_rate_scale }

public fun revenue_factor(model: &InterestModel): FixedPoint32 { model.revenue_factor }

public fun min_borrow_amount(model: &InterestModel): u64 { model.min_borrow_amount }

public fun asset_type(model: &InterestModel): TypeName { model.asset_type }

public struct InterestModels has drop {}

// Create a new interest model table and change it to public(package)
public(package) fun new(
    ctx: &mut TxContext,
): (AcTable<InterestModels, TypeName, InterestModel>, AcTableCap<InterestModels>) {
    ac_table::new<InterestModels, TypeName, InterestModel>(InterestModels {}, true, ctx)
}

// Create an interest model change and change it to public(package)
public(package) fun create_interest_model_change<T>(
    _: &AcTableCap<InterestModels>,
    base_rate_per_sec: u64,
    interest_rate_scale: u64,
    revenue_factor: u64,
    scale: u64,
    min_borrow_amount: u64,
    change_delay: u64,
    ctx: &mut TxContext,
): OneTimeLockValue<InterestModel> {

    let base_borrow_rate_per_sec = fixed_point32::create_from_rational(base_rate_per_sec, scale);
   
    let revenue_factor = fixed_point32::create_from_rational(revenue_factor, scale);
    let interest_model = InterestModel {
        asset_type: get<T>(),
        base_borrow_rate_per_sec,
        interest_rate_scale,
        revenue_factor,
        min_borrow_amount,
    };
    emit(InterestModelChangeCreated {
        interest_model,
        current_epoch: tx_context::epoch(ctx),
        delay_epoches: change_delay,
        effective_epoches: tx_context::epoch(ctx) + change_delay,
    });
    one_time_lock_value::new(interest_model, change_delay, InterestModelChangeEffectiveEpoches, ctx)
}

// Add the interest model and change it to public(package)
public(package) fun add_interest_model<T>(
    interest_model_table: &mut AcTable<InterestModels, TypeName, InterestModel>,
    cap: &AcTableCap<InterestModels>,
    interest_model_change: OneTimeLockValue<InterestModel>,
    ctx: &mut TxContext,
) {
    let interest_model = one_time_lock_value::get_value(interest_model_change, ctx);

    let type_name = get<T>();
    assert!(interest_model.asset_type == type_name, error::interest_model_type_not_match_error());

    if (ac_table::contains(interest_model_table, type_name)) {
        ac_table::remove(interest_model_table, cap, type_name);
    };
    ac_table::add(interest_model_table, cap, type_name, interest_model);
    emit(InterestModelAdded {
        interest_model,
        current_epoch: tx_context::epoch(ctx),
    });
}

#[test_only]
public struct USDC has drop {}

#[test_only]
use std::type_name;

#[test_only]
fun shift_decimal(number: FixedPoint32, number_of_shift: u8): u64 {
    use sui::math;
    fixed_point32::multiply_u64(math::pow(10, number_of_shift), number)
}