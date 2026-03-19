module xaum::xaum;

use mtoken::mtoken;
use sui::url;

const DECIMALS: u8 = 9;
const SYMBOL: vector<u8> = b"XAUM";
const NAME: vector<u8> = b"Matrixdock Gold";
const DESCRIPTION: vector<u8> = b"Matrixdock Gold (XAUm) is a standardized token deployed on multiple chains, with a 1:1 peg to 1 troy oz. fine weight of high grade LBMA gold. The total supply of XAUm will always be equal to the amount of underlying assets stored in highly secured and reputable vaults.";
const ICON_URL: vector<u8> = b"https://app.matrixdock.com/images/xaum/xaum-64x64-icon.png";
const ALLOW_GLOBAL_PAUSE: bool = true;
const INIT_DELAY: u64 = 0;

// https://move-book.com/programmability/one-time-witness.html
public struct XAUM has drop {}

// https://move-book.com/programmability/module-initializer.html
fun init(witness: XAUM, ctx: &mut TxContext) {
    let icon_url = option::some(url::new_unsafe_from_bytes(ICON_URL));
    mtoken::create_coin(
        witness,
        DECIMALS,
        SYMBOL,
        NAME,
        DESCRIPTION,
        icon_url,
        ALLOW_GLOBAL_PAUSE,
        INIT_DELAY,
        ctx,
    );
}
