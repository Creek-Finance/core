module protocol::obligation_debts;

use std::fixed_point32;
use std::type_name::TypeName;
use x::wit_table::{Self, WitTable};

public struct ObligationDebts has drop {}

public struct Debt has copy, drop, store {
    amount: u64,
    borrow_index: u64,
}

public(package) fun new(ctx: &mut TxContext): WitTable<ObligationDebts, TypeName, Debt> {
    wit_table::new(ObligationDebts {}, true, ctx)
}

public(package) fun init_debt(
    debts: &mut WitTable<ObligationDebts, TypeName, Debt>,
    type_name: TypeName,
    borrow_index: u64,
) {
    if (wit_table::contains(debts, type_name)) return;
    let debt = Debt { amount: 0, borrow_index };
    wit_table::add(ObligationDebts {}, debts, type_name, debt);
}

public(package) fun increase(
    debts: &mut WitTable<ObligationDebts, TypeName, Debt>,
    type_name: TypeName,
    amount: u64,
) {
    let debt = wit_table::borrow_mut(ObligationDebts {}, debts, type_name);
    debt.amount = debt.amount + amount;
}

public(package) fun decrease(
    debts: &mut WitTable<ObligationDebts, TypeName, Debt>,
    type_name: TypeName,
    amount: u64,
) {
    let debt = wit_table::borrow_mut(ObligationDebts {}, debts, type_name);
    debt.amount = debt.amount - amount;
    if (debt.amount == 0) {
        wit_table::remove(ObligationDebts {}, debts, type_name);
    }
}

public(package) fun accrue_interest(
    debts: &mut WitTable<ObligationDebts, TypeName, Debt>,
    type_name: TypeName,
    new_borrow_index: u64,
): u64 {
    let debt = wit_table::borrow_mut(ObligationDebts {}, debts, type_name);

    if (debt.borrow_index == new_borrow_index) return 0;

    let prev_amount = debt.amount;
    debt.amount =
        fixed_point32::multiply_u64(
            debt.amount,
            fixed_point32::create_from_rational(new_borrow_index, debt.borrow_index),
        );
    let accrued_interest = debt.amount - prev_amount;
    debt.borrow_index = new_borrow_index;
    accrued_interest
}

public fun debt(
    debts: &WitTable<ObligationDebts, TypeName, Debt>,
    type_name: TypeName,
): (u64, u64) {
    let debt = wit_table::borrow(debts, type_name);
    (debt.amount, debt.borrow_index)
}
