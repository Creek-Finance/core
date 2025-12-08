module protocol::risk_model;

use math::fixed_point32_empower;
use protocol::error;
use std::fixed_point32::{Self, FixedPoint32};
use std::type_name::{TypeName, get};
use sui::event::emit;
use x::ac_table::{Self, AcTable, AcTableCap};
use x::one_time_lock_value::{Self, OneTimeLockValue};

const RiskModelChangeEffectiveEpoches: u64 = 7;

const MaxCollateralFactor: u64 = 95; // 95%
const MaxLiquidationFactor: u64 = 95; // 95%
const MaxLiquidationPenalty: u64 = 20; // 20%
const MaxLiquidationDiscount: u64 = 15; // 15%
const ConstantScale: u64 = 100;

public struct RiskModels has drop {}

public struct RiskModel has copy, drop, store {
    type_name: TypeName,
    collateral_factor: FixedPoint32,
    liquidation_factor: FixedPoint32,
    liquidation_penalty: FixedPoint32,
    liquidation_discount: FixedPoint32,
    liquidation_revenue_factor: FixedPoint32,
    max_collateral_amount: u64,
}

public struct RiskModelChangeCreated has copy, drop {
    risk_model: RiskModel,
    current_epoch: u64,
    delay_epoches: u64,
    effective_epoches: u64,
}

public struct RiskModelAdded has copy, drop {
    risk_model: RiskModel,
    current_epoch: u64,
}

public fun collateral_factor(model: &RiskModel): FixedPoint32 { model.collateral_factor }

public fun liq_factor(model: &RiskModel): FixedPoint32 { model.liquidation_factor }

public fun liq_penalty(model: &RiskModel): FixedPoint32 { model.liquidation_penalty }

public fun liq_discount(model: &RiskModel): FixedPoint32 { model.liquidation_discount }

public fun liq_revenue_factor(model: &RiskModel): FixedPoint32 { model.liquidation_revenue_factor }

public fun max_collateral_amount(model: &RiskModel): u64 { model.max_collateral_amount }

public fun type_name(model: &RiskModel): TypeName { model.type_name }

public(package) fun new(
    ctx: &mut TxContext,
): (AcTable<RiskModels, TypeName, RiskModel>, AcTableCap<RiskModels>) {
    ac_table::new(RiskModels {}, true, ctx)
}

public(package) fun create_risk_model_change<T>(
    _: &AcTableCap<RiskModels>,
    collateral_factor: u64,
    liquidation_factor: u64,
    liquidation_penalty: u64,
    liquidation_discount: u64,
    scale: u64,
    max_collateral_amount: u64,
    change_delay: u64,
    ctx: &mut TxContext,
): OneTimeLockValue<RiskModel> {
    let collateral_factor = fixed_point32::create_from_rational(collateral_factor, scale);
    let max_collateral_factor = fixed_point32::create_from_rational(
        MaxCollateralFactor,
        ConstantScale,
    );
    assert!(
        fixed_point32_empower::gt(collateral_factor, max_collateral_factor) == false,
        error::risk_model_param_error(),
    );

    let liquidation_factor = fixed_point32::create_from_rational(liquidation_factor, scale);
    let max_liquidation_factor = fixed_point32::create_from_rational(
        MaxLiquidationFactor,
        ConstantScale,
    );
    assert!(
        fixed_point32_empower::gt(liquidation_factor, max_liquidation_factor) == false,
        error::risk_model_param_error(),
    );

    let liquidation_penalty = fixed_point32::create_from_rational(liquidation_penalty, scale);
    let max_liquidation_penalty = fixed_point32::create_from_rational(
        MaxLiquidationPenalty,
        ConstantScale,
    );
    assert!(
        fixed_point32_empower::gt(liquidation_penalty, max_liquidation_penalty) == false,
        error::risk_model_param_error(),
    );

    let liquidation_discount = fixed_point32::create_from_rational(liquidation_discount, scale);
    let max_liquidation_discount = fixed_point32::create_from_rational(
        MaxLiquidationDiscount,
        ConstantScale,
    );
    assert!(
        fixed_point32_empower::gt(liquidation_discount, max_liquidation_discount) == false,
        error::risk_model_param_error(),
    );

    // Make sure liquidation factor is bigger than collateral factor
    assert!(
        fixed_point32_empower::gt(liquidation_factor, collateral_factor),
        error::risk_model_param_error(),
    );
    // Make sure liquidation penalty is bigger than liquidation discount
    assert!(
        fixed_point32_empower::gt(liquidation_penalty, liquidation_discount),
        error::risk_model_param_error(),
    );

    // Make sure (liquidation_factor - collateral_factor) > (liquidation_penalty + liquidation_discount)
    let liquidation_factor_minus_collateral = fixed_point32_empower::sub(
        liquidation_factor,
        collateral_factor,
    );
    let liquidation_penalty_plus_discount = fixed_point32_empower::add(
        liquidation_penalty,
        liquidation_discount,
    );
    assert!(
        fixed_point32_empower::gt(
            liquidation_factor_minus_collateral,
            liquidation_penalty_plus_discount,
        ),
        error::risk_model_param_error(),
    );

    // Make sure 1 - liquidation_penalty > liquidation_factor
    let one = fixed_point32_empower::from_u64(1);
    let one_minus_penalty = fixed_point32_empower::sub(one, liquidation_penalty);
    assert!(
        fixed_point32_empower::gt(one_minus_penalty, liquidation_factor),
        error::risk_model_param_error(),
    );

    let liquidation_revenue_factor = fixed_point32_empower::sub(
        liquidation_penalty,
        liquidation_discount,
    );
    let risk_model = RiskModel {
        type_name: get<T>(),
        collateral_factor,
        liquidation_factor,
        liquidation_penalty,
        liquidation_discount,
        liquidation_revenue_factor,
        max_collateral_amount,
    };
    emit(RiskModelChangeCreated {
        risk_model,
        current_epoch: tx_context::epoch(ctx),
        delay_epoches: change_delay,
        effective_epoches: tx_context::epoch(ctx) + change_delay,
    });
    one_time_lock_value::new(risk_model, change_delay, RiskModelChangeEffectiveEpoches, ctx)
}

public(package) fun add_risk_model<T>(
    self: &mut AcTable<RiskModels, TypeName, RiskModel>,
    cap: &AcTableCap<RiskModels>,
    risk_model_change: OneTimeLockValue<RiskModel>,
    ctx: &mut TxContext,
) {
    let risk_model = one_time_lock_value::get_value(risk_model_change, ctx);
    let type_name = get<T>();
    assert!(risk_model.type_name == type_name, error::risk_model_type_not_match_error());

    if (ac_table::contains(self, type_name)) {
        ac_table::remove(self, cap, type_name);
    };

    ac_table::add(self, cap, type_name, risk_model);

    emit(RiskModelAdded {
        risk_model,
        current_epoch: tx_context::epoch(ctx),
    });
}
