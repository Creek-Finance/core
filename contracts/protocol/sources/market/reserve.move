module protocol::reserve;

use coin_gusd::coin_gusd::COIN_GUSD;
use math::u64;
use protocol::error;
use std::fixed_point32::{Self, FixedPoint32};
use std::type_name::{TypeName, get};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::dynamic_field;
use sui::math;
use x::balance_bag::{Self, BalanceBag};
use x::supply_bag::{Self, SupplyBag};
use x::wit_table::{Self, WitTable};

public struct BalanceSheets has drop {}

const FLASH_LOAN_FEE_DEN: u64 = 1000;
const FLASH_LOAN_FEE_NUM: u64 = 1;

public struct BalanceSheet has copy, store {
    debt: u64,
    revenue: u64,
}

public struct FlashLoan<phantom T> {
    loan_amount: u64,
    fee: u64,
}

public struct MarketCoin<phantom T> has drop {}

public struct Reserve has key, store {
    id: UID,
    revenue_balances: BalanceBag,
    balance_sheets: WitTable<BalanceSheets, TypeName, BalanceSheet>,
}

public struct BorrowFeeVaultKey has copy, drop, store {}

public fun revenue_balances(vault: &Reserve): &BalanceBag { &vault.revenue_balances }

public fun balance_sheets(vault: &Reserve): &WitTable<BalanceSheets, TypeName, BalanceSheet> {
    &vault.balance_sheets
}

public fun asset_types(self: &Reserve): vector<TypeName> {
    wit_table::keys(&self.balance_sheets)
}

public fun balance_sheet(balance_sheet: &BalanceSheet): (u64, u64) {
    (balance_sheet.debt, balance_sheet.revenue)
}

public(package) fun new(ctx: &mut TxContext): Reserve {
    Reserve {
        id: object::new(ctx),
        revenue_balances: balance_bag::new(ctx),
        balance_sheets: wit_table::new(BalanceSheets {}, true, ctx),
    }
}

public(package) fun register_coin<T>(self: &mut Reserve) {
    balance_bag::init_balance<T>(&mut self.revenue_balances);
    let balance_sheet = BalanceSheet { debt: 0, revenue: 0 };
    wit_table::add(BalanceSheets {}, &mut self.balance_sheets, get<T>(), balance_sheet);
}

public(package) fun increase_debt(
    self: &mut Reserve,
    debt_type: TypeName,
    debt_increase_rate: FixedPoint32,
) {
    let balance_sheet = wit_table::borrow_mut(
        BalanceSheets {},
        &mut self.balance_sheets,
        debt_type,
    );
    let debt_increased = fixed_point32::multiply_u64(balance_sheet.debt, debt_increase_rate);
    balance_sheet.debt = balance_sheet.debt + debt_increased;
    balance_sheet.revenue = balance_sheet.revenue + debt_increased;
}

public(package) fun handle_repay<T>(
    self: &mut Reserve,
    coin: Coin<COIN_GUSD>,
    debt_interest: u64,
): Balance<COIN_GUSD> {
    let mut balance = coin::into_balance(coin);
    let repay_amount = balance::value(&balance);
    let balance_sheet = wit_table::borrow_mut(BalanceSheets {}, &mut self.balance_sheets, get<T>());

    // calculate how much debt and interest to keep
    let debt_amount = if (balance_sheet.debt >= repay_amount) {
        repay_amount
    } else {
        balance_sheet.debt
    };
    let interest_to_keep = repay_amount - debt_amount;

    // update balance sheet
    if (balance_sheet.debt >= repay_amount) {
        balance_sheet.debt = balance_sheet.debt - repay_amount;
    } else {
        balance_sheet.debt = 0;
    };

    // insert interest to revenue
    if (interest_to_keep > 0) {
        balance_sheet.revenue = balance_sheet.revenue + interest_to_keep;
    };
    let debt_to_burn = debt_amount - debt_interest;

    if (debt_to_burn == 0) {
        // all repay amount is interest
        balance_bag::join(&mut self.revenue_balances, balance);
        return balance::zero<COIN_GUSD>()
    };

    // split the balance into debt part and interest part
    let debt_balance = balance::split(&mut balance, debt_to_burn);
    let interest_balance = balance; // interest part
    let total_interest = interest_to_keep + debt_interest;
    // keep the interest part in the reserve's underlying balances
    if (total_interest > 0) {
        balance_bag::join(&mut self.revenue_balances, interest_balance);
    } else {
        balance::destroy_zero(interest_balance); // if no interest, destroy the zero balance
    };

    // return the debt part balance to be burned
    return debt_balance
}

public(package) fun handle_borrow<COIN_GUSD>(self: &mut Reserve, amount: u64) {
    let balance_sheet = wit_table::borrow_mut(
        BalanceSheets {},
        &mut self.balance_sheets,
        get<COIN_GUSD>(),
    );
    balance_sheet.debt = balance_sheet.debt + amount;
}

public(package) fun handle_liquidation<T>(
    self: &mut Reserve,
    mut repay_balance: Balance<T>,
    revenue_balance: Balance<T>,
    repay_interest: u64,
): Balance<T> {
    let balance_sheet = wit_table::borrow_mut(BalanceSheets {}, &mut self.balance_sheets, get<T>());

    // calculate total amount
    let total_amount = balance::value(&repay_balance) + balance::value(&revenue_balance);
    let reb = balance::value(&revenue_balance);

    // calculate how much debt and interest to keep
    let debt_amount = if (balance_sheet.debt >= total_amount) {
        total_amount
    } else {
        balance_sheet.debt
    };

    let interest_to_keep = total_amount - debt_amount;

    if (interest_to_keep > 0) {
        balance_sheet.revenue = balance_sheet.revenue + interest_to_keep;
    };

    // update balance sheet
    if (balance_sheet.debt >= debt_amount) {
        balance_sheet.debt = balance_sheet.debt - debt_amount;
    } else {
        balance_sheet.debt = 0;
    };

    // combine repay_balance and revenue_balance
    balance::join(&mut repay_balance, revenue_balance);

    let repay_interest_and_revenue = repay_interest + reb;

    let debt_to_burn = if (debt_amount > repay_interest_and_revenue) {
        debt_amount - repay_interest_and_revenue
    } else {
        0
    };

    if (debt_to_burn == 0) {
        // all repay amount is interest
        balance_sheet.revenue = balance_sheet.revenue + reb;
        balance_bag::join(&mut self.revenue_balances, repay_balance);
        return balance::zero<T>()
    };

    // split the repay_balance into principal part and interest part
    let principal_balance = balance::split(&mut repay_balance, debt_to_burn);

    // The remaining balance (interest_to_keep) goes to revenue_balances
    if (balance::value(&repay_balance) > 0) {
        balance_sheet.revenue = balance_sheet.revenue + reb;
        balance_bag::join(&mut self.revenue_balances, repay_balance);
    } else {
        balance::destroy_zero(repay_balance);
    };

    principal_balance // return principal part to be burned
}

public(package) fun take_revenue<T>(self: &mut Reserve, amount: u64, ctx: &mut TxContext): Coin<T> {
    let balance_sheet = wit_table::borrow_mut(BalanceSheets {}, &mut self.balance_sheets, get<T>());
    let actual_balance = balance_bag::value<T>(&self.revenue_balances);
    let take_amount = math::min(amount, actual_balance);

    balance_sheet.revenue = balance_sheet.revenue - take_amount;

    let balance = balance_bag::split<T>(&mut self.revenue_balances, take_amount);
    coin::from_balance(balance, ctx)
}

public(package) fun add_borrow_fee<T>(
    self: &mut Reserve,
    balance: Balance<COIN_GUSD>,
    ctx: &mut TxContext,
) {
    let key = BorrowFeeVaultKey {};
    let has_record = dynamic_field::exists_with_type<BorrowFeeVaultKey, BalanceBag>(&self.id, key);
    if (!has_record) {
        dynamic_field::add(&mut self.id, key, balance_bag::new(ctx));
    };

    let balances = dynamic_field::borrow_mut<BorrowFeeVaultKey, BalanceBag>(&mut self.id, key);
    if (!balance_bag::contains<T>(balances)) {
        balance_bag::init_balance<T>(balances);
    };
    balance_bag::join<COIN_GUSD>(balances, balance);
}

public(package) fun take_borrow_fee<T>(
    self: &mut Reserve,
    amount: u64,
    ctx: &mut TxContext,
): Coin<T> {
    let key = BorrowFeeVaultKey {};
    let balances = dynamic_field::borrow_mut<BorrowFeeVaultKey, BalanceBag>(&mut self.id, key);
    let balance = balance_bag::split<T>(balances, amount);
    coin::from_balance(balance, ctx)
}

public(package) fun repay_flash_loan(
    self: &mut Reserve,
    coin: Coin<COIN_GUSD>,
    loan: FlashLoan<COIN_GUSD>,
    ctx: &mut TxContext,
): Coin<COIN_GUSD> {
    let FlashLoan { loan_amount, fee } = loan;

    let repay_amount = coin::value(&coin);
    assert!(repay_amount >= loan_amount + fee, error::flash_loan_repay_not_enough_error());

    // -- Split the principal and fee --
    let mut repay_balance = coin::into_balance(coin);
    let principal_balance = balance::split(&mut repay_balance, loan_amount);
    let coin_principal = coin::from_balance(principal_balance, ctx);

    //The remaining part = fee (the excess of the handling fee)
    let fee_balance = repay_balance;
    balance_bag::join(&mut self.revenue_balances, fee_balance);

    // Update the balance sheet
    let balance_sheet = wit_table::borrow_mut(
        BalanceSheets {},
        &mut self.balance_sheets,
        get<COIN_GUSD>(),
    );
    balance_sheet.revenue = balance_sheet.revenue + (repay_amount - loan_amount);

    coin_principal
}

public(package) fun borrow_flash_loan(_self: &mut Reserve, amount: u64): FlashLoan<COIN_GUSD> {
    let mut fee = u64::mul_div(amount, FLASH_LOAN_FEE_NUM, FLASH_LOAN_FEE_DEN);
    if (amount > 0 && ((amount % FLASH_LOAN_FEE_DEN) != 0)) {
        fee = fee + 1;
    };
    FlashLoan<COIN_GUSD> { loan_amount: amount, fee }
}

public fun flash_loan_fee(flash_loan: &FlashLoan<COIN_GUSD>): u64 { flash_loan.fee }
