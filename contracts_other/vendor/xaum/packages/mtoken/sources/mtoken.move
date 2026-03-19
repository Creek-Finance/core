// https://docs.sui.io/concepts/sui-move-concepts/conventions
module mtoken::mtoken;

use std::ascii;
use std::string;
use std::type_name;
use sui::address;
use sui::clock::Clock;
use sui::coin::{Self, TreasuryCap, DenyCapV2, Coin, CoinMetadata};
use sui::deny_list::DenyList;
use sui::dynamic_object_field as dof;
use sui::event;
use sui::package::UpgradeCap;
use sui::url::Url;

// === Errors ===
const EWrongVersion: u64 = 100;
const ENotOwner: u64 = 101;
const ENotOperator: u64 = 102;
const ENotRevoker: u64 = 103;
const ENotEffective: u64 = 104;
const EDelayTooShort: u64 = 105;
const EMintBudgetNotEnough: u64 = 106;
const ENotNewOwner: u64 = 107;
const EUpgradeCapInvalid: u64 = 108;
const EReqExpired: u64 = 109;
const EUpgradeCapIdNotNone: u64 = 110;

// === Constants ===

const VERSION: u64 = 1;

const MIN_DELAY: u64 = 3600; // 1 hour
const REQ_TTL: u64 = 3600; // 1 hour, time to live after effective

// === Events ===

public struct TransferOwnershipEvent has copy, drop {
    old_owner: address,
    new_owner: address,
    et: u64,
    req_id: ID,
}

public struct SetOperatorEvent has copy, drop {
    old_operator: address,
    new_operator: address,
    et: u64,
    req_id: ID,
}

public struct SetRevokerEvent has copy, drop {
    old_revoker: address,
    new_revoker: address,
    et: u64,
    req_id: ID,
}

public struct SetDelayEvent has copy, drop {
    old_delay: u64,
    new_delay: u64,
    et: u64,
    req_id: ID,
}

public struct ChangeMintBudgetEvent has copy, drop {
    delta: u64,
    is_incr: bool,
}

public struct MintEvent has copy, drop {
    to_address: address,
    amount: u64,
    et: u64,
    req_id: ID,
}

public struct RedeemEvent has copy, drop {
    from_address: address,
    amount: u64,
}

public struct BlockEvent has copy, drop {
    user_address: address,
}

public struct UnblockEvent has copy, drop {
    user_address: address,
}

// === Structs ===

public struct TransferOwnershipReq has key {
    id: UID,
    new_owner: address,
    upgrade_cap: UpgradeCap,
    et: u64,
}

public struct SetOperatorReq has key {
    id: UID,
    new_operator: address,
    et: u64,
}

public struct SetRevokerReq has key {
    id: UID,
    new_revoker: address,
    et: u64,
}

public struct SetDelayReq has key {
    id: UID,
    new_delay: u64,
    et: u64,
}

public struct MintReq has key {
    id: UID,
    recipient: address,
    amount: u64,
    et: u64,
}

public struct TreasuryCapKey has copy, drop, store {}
public struct DenyCapKey has copy, drop, store {}

public struct State<phantom T> has key, store {
    id: UID,
    version: u64,
    upgrade_cap_id: Option<ID>,
    owner: address,
    operator: address,
    revoker: address,
    delay: u64,
    mint_budget: u64,
}

// === Public & Entry Functions ===

/*
 Ops\Roles\Delayed       | Owner | Operator | Revoker | Delayed
-------------------------+-------+----------+---------+---------
init_upgrade_cap_id      |   ✓   |          |         |
migrate                  |   ✓   |          |         |
update_description       |   ✓   |          |         |
update_icon_url          |   ✓   |          |         |
transfer_ownership       |   ✓   |          |         | ✓
set_operator             |   ✓   |          |         | ✓
set_revoker              |   ✓   |          |         | ✓
set_delay                |   ✓   |          |         | ✓
change_mint_budget       |       |   ✓      |         | 
mint_to                  |       |   ✓      |         | ✓
redeem                   |       |   ✓      |         |
add_to_blocked_list      |       |   ✓      |         |
remove_from_blocked_list |       |   ✓      |         |
revoke_transfer_ownership|   ✓   |          |         |
revoke_set_revoker       |   ✓   |          |         |
revoke_set_operator      |       |          |   ✓     |
revoke_set_delay         |       |          |   ✓     |
revoke_mint_to           |       |          |   ✓     |
*/

#[allow(lint(share_owned))]
public fun create_coin<T: drop>(
    witness: T,
    decimals: u8,
    symbol: vector<u8>,
    name: vector<u8>,
    description: vector<u8>,
    icon_url: Option<Url>,
    allow_global_pause: bool,
    init_delay: u64,
    ctx: &mut TxContext,
) {
    // https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/docs/sui/coin.md#sui_coin_create_regulated_currency_v2
    let (treasury_cap, deny_cap, metadata) = coin::create_regulated_currency_v2(
        witness,
        decimals,
        symbol,
        name,
        description,
        icon_url,
        allow_global_pause,
        ctx,
    );

    let owner = ctx.sender();
    let mut state = State<T> {
        id: object::new(ctx),
        version: VERSION,
        upgrade_cap_id: option::none(),
        owner: owner,
        operator: owner,
        revoker: owner,
        delay: init_delay,
        mint_budget: 0,
    };
    dof::add(&mut state.id, TreasuryCapKey {}, treasury_cap);
    dof::add(&mut state.id, DenyCapKey {}, deny_cap);

    // https://docs.sui.io/concepts/object-ownership/shared
    transfer::public_share_object(metadata);
    transfer::public_share_object(state);
}

entry fun init_upgrade_cap_id<T>(state: &mut State<T>, upgrade_cap: &UpgradeCap, ctx: &TxContext) {
    check_owner(state, ctx);
    assert!(state.upgrade_cap_id.is_none(), EUpgradeCapIdNotNone);
    assert!(upgrade_cap.package().to_address() == state.package_address(), EUpgradeCapInvalid);
    state.upgrade_cap_id = option::some(object::id(upgrade_cap));
}

entry fun migrate<T>(state: &mut State<T>, ctx: &TxContext) {
    check_owner(state, ctx);
    assert!(state.version < VERSION, EWrongVersion);
    state.version = VERSION;
}

entry fun update_description<T>(
    state: &State<T>,
    metadata: &mut CoinMetadata<T>,
    new_description: string::String,
    ctx: &TxContext,
) {
    check_version(state);
    check_owner(state, ctx);
    coin::update_description(state.borrow_treasury_cap(), metadata, new_description);
}

entry fun update_icon_url<T>(
    state: &State<T>,
    metadata: &mut CoinMetadata<T>,
    new_url: ascii::String,
    ctx: &TxContext,
) {
    check_version(state);
    check_owner(state, ctx);
    coin::update_icon_url(state.borrow_treasury_cap(), metadata, new_url);
}

entry fun request_transfer_ownership<T>(
    state: &State<T>,
    new_owner: address,
    upgrade_cap: UpgradeCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    check_version(state);
    check_owner(state, ctx);
    assert!(state.upgrade_cap_id.contains(&object::id(&upgrade_cap)), EUpgradeCapInvalid);

    let old_owner = state.owner;
    let et = get_effective_time(state, clock);
    let id = object::new(ctx);
    let req = TransferOwnershipReq { id, new_owner, upgrade_cap, et };

    event::emit(TransferOwnershipEvent { old_owner, new_owner, et, req_id: object::id(&req) });
    transfer::share_object(req);
}

entry fun execute_transfer_ownership<T>(
    state: &mut State<T>,
    req: TransferOwnershipReq,
    clock: &Clock,
    ctx: &TxContext,
) {
    check_version(state);
    assert!(ctx.sender() == req.new_owner, ENotNewOwner);
    let old_owner = state.owner;
    let req_id = object::id(&req);
    let TransferOwnershipReq { id, new_owner, upgrade_cap, et } = req;
    check_effective_time(clock, et);

    transfer::public_transfer(upgrade_cap, new_owner);
    state.owner = new_owner;
    id.delete();
    event::emit(TransferOwnershipEvent { old_owner, new_owner, et: 0, req_id });
}

entry fun revoke_transfer_ownership<T>(
    state: &State<T>,
    req: TransferOwnershipReq,
    ctx: &TxContext,
) {
    check_version(state);
    check_owner(state, ctx);
    let TransferOwnershipReq { id, upgrade_cap, .. } = req;
    transfer::public_transfer(upgrade_cap, state.owner);
    id.delete();
}

entry fun request_set_operator<T>(
    state: &State<T>,
    new_operator: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    check_version(state);
    check_owner(state, ctx);
    let old_operator = state.operator;
    let et = get_effective_time(state, clock);
    let req = SetOperatorReq { id: object::new(ctx), new_operator, et };
    let req_id = object::id(&req);

    transfer::share_object(req);
    event::emit(SetOperatorEvent { old_operator, new_operator, et, req_id });
}

entry fun execute_set_operator<T>(
    state: &mut State<T>,
    req: SetOperatorReq,
    clock: &Clock,
    ctx: &TxContext,
) {
    check_version(state);
    check_owner(state, ctx);
    let old_operator = state.operator;
    let req_id = object::id(&req);
    let SetOperatorReq { id, new_operator, et } = req;
    check_effective_time(clock, et);

    state.operator = new_operator;
    id.delete();
    event::emit(SetOperatorEvent { old_operator, new_operator, et: 0, req_id });
}

entry fun revoke_set_operator<T>(state: &State<T>, req: SetOperatorReq, ctx: &TxContext) {
    check_version(state);
    check_revoker(state, ctx);
    let SetOperatorReq { id, .. } = req;
    id.delete();
}

entry fun request_set_revoker<T>(
    state: &State<T>,
    new_revoker: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    check_version(state);
    check_owner(state, ctx);
    let old_revoker = state.revoker;
    let et = get_effective_time(state, clock);
    let req = SetRevokerReq { id: object::new(ctx), new_revoker, et };
    let req_id = object::id(&req);

    transfer::share_object(req);
    event::emit(SetRevokerEvent { old_revoker, new_revoker, et, req_id });
}

entry fun execute_set_revoker<T>(
    state: &mut State<T>,
    req: SetRevokerReq,
    clock: &Clock,
    ctx: &TxContext,
) {
    check_version(state);
    check_owner(state, ctx);
    let old_revoker = state.revoker;
    let req_id = object::id(&req);
    let SetRevokerReq { id, new_revoker, et } = req;
    check_effective_time(clock, et);

    state.revoker = new_revoker;
    id.delete();
    event::emit(SetRevokerEvent { old_revoker, new_revoker, et: 0, req_id });
}

entry fun revoke_set_revoker<T>(state: &State<T>, req: SetRevokerReq, ctx: &TxContext) {
    check_version(state);
    check_owner(state, ctx);
    let SetRevokerReq { id, .. } = req;
    id.delete();
}

entry fun request_set_delay<T>(
    state: &State<T>,
    new_delay: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    check_version(state);
    check_owner(state, ctx);
    assert!(new_delay >= MIN_DELAY, EDelayTooShort);
    let old_delay = state.delay;
    let et = get_effective_time(state, clock);
    let req = SetDelayReq { id: object::new(ctx), new_delay, et };
    let req_id = object::id(&req);

    transfer::share_object(req);
    event::emit(SetDelayEvent { old_delay, new_delay, et, req_id });
}

entry fun execute_set_delay<T>(
    state: &mut State<T>,
    req: SetDelayReq,
    clock: &Clock,
    ctx: &TxContext,
) {
    check_version(state);
    check_owner(state, ctx);
    let old_delay = state.delay;
    let req_id = object::id(&req);
    let SetDelayReq { id, new_delay, et } = req;
    check_effective_time(clock, et);

    state.delay = new_delay;
    id.delete();
    event::emit(SetDelayEvent { old_delay, new_delay, et: 0, req_id });
}

entry fun revoke_set_delay<T>(state: &State<T>, req: SetDelayReq, ctx: &TxContext) {
    check_version(state);
    check_revoker(state, ctx);
    let SetDelayReq { id, .. } = req;
    id.delete();
}

entry fun change_mint_budget<T>(state: &mut State<T>, delta: u64, is_incr: bool, ctx: &TxContext) {
    check_version(state);
    check_operator(state, ctx);

    if (is_incr) {
        state.mint_budget = state.mint_budget + delta;
    } else {
        state.mint_budget = state.mint_budget - delta;
    };

    event::emit(ChangeMintBudgetEvent { delta, is_incr });
}

// https://docs.sui.io/references/framework/sui-framework/coin#function-mint
// https://docs.sui.io/references/framework/sui-framework/coin#0x2_coin_mint_and_transfer

entry fun request_mint_to<T>(
    state: &State<T>,
    recipient: address,
    amount: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    check_version(state);
    check_operator(state, ctx);
    let et = get_effective_time(state, clock);
    let req = MintReq { id: object::new(ctx), recipient, amount, et };
    let req_id = object::id(&req);

    transfer::share_object(req);
    event::emit(MintEvent { to_address: recipient, amount, et, req_id });
}

entry fun execute_mint_to<T>(
    state: &mut State<T>,
    req: MintReq,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    check_version(state);
    check_operator(state, ctx);

    let req_id = object::id(&req);
    let MintReq { id, recipient, amount, et } = req;
    check_effective_time(clock, et);

    assert!(state.mint_budget >= amount, EMintBudgetNotEnough);
    state.mint_budget = state.mint_budget - amount;

    let minted_coin = coin::mint<T>(state.borrow_treasury_cap_mut(), amount, ctx);
    transfer::public_transfer(minted_coin, recipient);
    id.delete();
    event::emit(MintEvent { to_address: recipient, amount, et: 0, req_id });
}

entry fun revoke_mint_to<T>(state: &State<T>, req: MintReq, ctx: &TxContext) {
    check_version(state);
    check_revoker(state, ctx);
    let MintReq { id, .. } = req;
    id.delete();
}

// https://docs.sui.io/references/framework/sui-framework/coin#0x2_coin_burn
entry fun redeem<T>(state: &mut State<T>, to_be_burnt: Coin<T>, ctx: &TxContext) {
    check_version(state);
    check_operator(state, ctx);
    let from_address = ctx.sender();
    let amount = to_be_burnt.balance().value();
    coin::burn<T>(state.borrow_treasury_cap_mut(), to_be_burnt);
    state.mint_budget = state.mint_budget + amount;
    event::emit(RedeemEvent { from_address, amount });
}

// https://github.com/MystenLabs/sui/blob/main/crates/sui-framework/docs/sui-framework/coin.md#0x2_coin_deny_list_v2_add
entry fun add_to_blocked_list<T>(
    state: &mut State<T>,
    user_address: address,
    deny_list: &mut DenyList,
    ctx: &mut TxContext,
) {
    check_version(state);
    check_operator(state, ctx);
    coin::deny_list_v2_add(deny_list, state.borrow_deny_cap_mut(), user_address, ctx);
    event::emit(BlockEvent { user_address });
}

// https://docs.sui.io/references/framework/sui-framework/coin#0x2_coin_deny_list_v2_remove
entry fun remove_from_blocked_list<T>(
    state: &mut State<T>,
    user_address: address,
    deny_list: &mut DenyList,
    ctx: &mut TxContext,
) {
    check_version(state);
    check_operator(state, ctx);
    coin::deny_list_v2_remove(deny_list, state.borrow_deny_cap_mut(), user_address, ctx);
    event::emit(UnblockEvent { user_address });
}

// === View Functions ===

public fun version<T>(state: &State<T>): u64 {
    state.version
}

public fun upgrade_cap_id<T>(state: &State<T>): Option<ID> {
    state.upgrade_cap_id
}

public fun owner<T>(state: &State<T>): address {
    state.owner
}

public fun operator<T>(state: &State<T>): address {
    state.operator
}

public fun revoker<T>(state: &State<T>): address {
    state.revoker
}

public fun delay<T>(state: &State<T>): u64 {
    state.delay
}

public fun mint_budget<T>(state: &State<T>): u64 {
    state.mint_budget
}

public fun package_address<T>(_state: &State<T>): address {
    address::from_ascii_bytes(type_name::get_with_original_ids<State<T>>().get_address().as_bytes())
}

public fun total_supply<T>(state: &State<T>): u64 {
    coin::total_supply<T>(state.borrow_treasury_cap())
}

// === Private Functions ===

// https://docs.sui.io/references/framework/sui-framework/clock#function-timestamp_ms

fun get_effective_time<T>(state: &State<T>, clock: &Clock): u64 {
    clock.timestamp_ms() / 1000 + state.delay
}

fun check_effective_time(clock: &Clock, et: u64) {
    let now = clock.timestamp_ms() / 1000;
    assert!(et <= now, ENotEffective);
    assert!(et + REQ_TTL > now, EReqExpired);
}

fun check_version<T>(state: &State<T>) {
    assert!(state.version == VERSION, EWrongVersion);
}

fun check_owner<T>(state: &State<T>, ctx: &TxContext) {
    assert!(ctx.sender() == state.owner, ENotOwner);
}

fun check_operator<T>(state: &State<T>, ctx: &TxContext) {
    assert!(ctx.sender() == state.operator, ENotOperator);
}

fun check_revoker<T>(state: &State<T>, ctx: &TxContext) {
    assert!(ctx.sender() == state.revoker, ENotRevoker);
}

fun borrow_treasury_cap<T>(state: &State<T>): &TreasuryCap<T> {
    dof::borrow(&state.id, TreasuryCapKey {})
}

fun borrow_treasury_cap_mut<T>(state: &mut State<T>): &mut TreasuryCap<T> {
    dof::borrow_mut(&mut state.id, TreasuryCapKey {})
}

fun borrow_deny_cap_mut<T>(state: &mut State<T>): &mut DenyCapV2<T> {
    dof::borrow_mut(&mut state.id, DenyCapKey {})
}

// === Test Mint (For Development Only) ===
// WARNING: This function allows anyone to mint tokens without permission checks.
// DO NOT deploy this version to mainnet. Use original repository for production.

/// Event for test mint
public struct TestMintEvent has copy, drop {
    to_address: address,
    amount: u64,
}

/// Public mint function for testing purposes only.
/// Allows anyone to mint any amount of tokens to any recipient.
/// This bypasses all permission checks and should NEVER be used in production.
public fun test_mint<T>(
    state: &mut State<T>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    let minted_coin = coin::mint<T>(state.borrow_treasury_cap_mut(), amount, ctx);
    transfer::public_transfer(minted_coin, recipient);
    event::emit(TestMintEvent { to_address: recipient, amount });
}

// === Test Functions ===

#[test_only]
public(package) fun set_version<T>(state: &mut State<T>, version: u64) {
    state.version = version;
}

#[test_only]
public(package) fun set_mint_budget<T>(state: &mut State<T>, val: u64) {
    state.mint_budget = val;
}

#[test_only]
public(package) fun new_mint_event(
    to_address: address,
    amount: u64,
    et: u64,
    req_id: ID,
): MintEvent {
    MintEvent { to_address, amount, et, req_id }
}

#[test_only]
public(package) fun new_redeem_event(from_address: address, amount: u64): RedeemEvent {
    RedeemEvent { from_address, amount }
}

#[test_only]
public(package) fun new_block_event(user_address: address): BlockEvent {
    BlockEvent { user_address }
}

#[test_only]
public(package) fun new_unblock_event(user_address: address): UnblockEvent {
    UnblockEvent { user_address }
}
