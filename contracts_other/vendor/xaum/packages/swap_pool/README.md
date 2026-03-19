SwapPool use pyth as oracle for XAUM price fetch, using MMT XAUM/USDC pool as a TWAP source for pyth price check.
SwapPool use SwapCap to limit only whilelisted user can swap XAUM token.

## Mainnet related params:

| Param                                | Value                 |
|--------------------------------------|-----------------------|
| XAUM Type                            | 0x9d297676e7a4b771ab023291377b2adfaa4938fb9080b8d12430e4b108b836a9::xaum::XAUM | 
| XAUM price id                        | 0xd7db067954e28f51a96fd50c6d51775094025ced2d60af61ec9803e553471c88              | 
| XAUM priceInfoObject id              | 0x2731a8e3e9bc69b2d6af6f4c032fcd4856c77e2c21f839134d1ebcc3a16e4b1b            |
| USDC Type                            | 0xdba34672e30cb065b1f93e3ab55318768fd6fef66c15942c9f7cb846e2f900e7::usdc::USDC   |
| MMT OracleDexPool id (XAUM/USDC MMT) | 0xc5bdc685b8006071938b5cb94103dc873c9946578d717c9b5b67fc264ff941e0                |

## Mainnet Prod SwapPool Infos:

| Param             | Value                                                              |
|-------------------|--------------------------------------------------------------------|
| SwapPool Package  | 0x443ab6e1662cc575e99f368dc661dbc94ee12fbf43dd4c09538ae465b7a7acac |
| SwapPool State id | 0x6c8ba72b252b243bc3c7839046ff1284c15dc3cee506fc4838a0b68f42675ffb                                                                  |
| UpgradeCap id     | 0xf0c7612d79bb9e54289786d344c0333e5c6062d3f1de396ac1ad12019a75afce                                                                  |


