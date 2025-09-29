module protocol::market_dynamic_keys;

use std::type_name::TypeName;

public struct BorrowFeeKey has copy, drop, store {
    asset_type: TypeName,
}

public struct BorrowLimitKey has copy, drop, store {
    asset_type: TypeName,
}

public fun borrow_fee_key(type_name: TypeName): BorrowFeeKey {
    BorrowFeeKey { asset_type: type_name }
}

public fun borrow_limit_key(type_name: TypeName): BorrowLimitKey {
    BorrowLimitKey { asset_type: type_name }
}
