
切换网络
```
sui client switch --env mainnet
```

build
```
sui move build
```
发布
```
sui client publish --gas-budget 100000000 --json
```

{
  "digest": "B5kqZtQwwJjke5ESFjueXueh74tJfLAcbX6QGAAg8cwS",
  "transaction": {
    "data": {
      "messageVersion": "v1",
      "transaction": {
        "kind": "ProgrammableTransaction",
        "inputs": [
          {
            "type": "pure",
            "valueType": "address",
            "value": "0xf4945f468b27f8e9eefbecf1f54c0bcdd3b9ee5ae4034438fda4ac58295c17d6"
          }
        ],
        "transactions": [
          {
            "Publish": [
              "0x0000000000000000000000000000000000000000000000000000000000000001",
              "0x04e20ddf36af412a4096f9014f4a565af9e812db9a05cc40254846cf6ed0ad91",
              "0x0000000000000000000000000000000000000000000000000000000000000002",
              "0x5306f64e312b581766351c07af79c72fcb1cd25147157fdc2f8ad76de9a3fb6a",
              "0xcf60a40f45d46fc1e828871a647c1e25a0915dec860d2662eb10fdb382c3c1d1",
              "0x443ab6e1662cc575e99f368dc661dbc94ee12fbf43dd4c09538ae465b7a7acac"
            ]
          },
          {
            "TransferObjects": [
              [
                {
                  "Result": 0
                }
              ],
              {
                "Input": 0
              }
            ]
          }
        ]
      },
      "sender": "0xf4945f468b27f8e9eefbecf1f54c0bcdd3b9ee5ae4034438fda4ac58295c17d6",
      "gasData": {
        "payment": [
          {
            "objectId": "0xcd905b7223c5dae8e207f5a74e8e55c83c5364f9ff05039e8627a809885539d6",
            "version": 685931664,
            "digest": "FWdQWM866TCfwR8vitigZeGxwT3Bbkgd2LRRRsqr85GV"
          }
        ],
        "owner": "0xf4945f468b27f8e9eefbecf1f54c0bcdd3b9ee5ae4034438fda4ac58295c17d6",
        "price": "500",
        "budget": "100000000"
      }
    },
    "txSignatures": [
      "AHuhRaYvfdeQj3mPhOCbz/ZcPdpI4Lz5NRH45c13HwbU4Dc85/7wfUclj+X0Y2LCngXakekwsKqv7BSmGY93ywbJdbYhZRPsqYG5AxzFSGaI7w9Dwuyz+VT+IQK5tgsUNQ=="
    ]
  },
  "effects": {
    "messageVersion": "v1",
    "status": {
      "status": "success"
    },
    "executedEpoch": "946",
    "gasUsed": {
      "computationCost": "1000000",
      "storageCost": "14630000",
      "storageRebate": "978120",
      "nonRefundableStorageFee": "9880"
    },
    "modifiedAtVersions": [
      {
        "objectId": "0xcd905b7223c5dae8e207f5a74e8e55c83c5364f9ff05039e8627a809885539d6",
        "sequenceNumber": "685931664"
      }
    ],
    "transactionDigest": "B5kqZtQwwJjke5ESFjueXueh74tJfLAcbX6QGAAg8cwS",
    "created": [
      {
        "owner": {
          "AddressOwner": "0xf4945f468b27f8e9eefbecf1f54c0bcdd3b9ee5ae4034438fda4ac58295c17d6"
        },
        "reference": {
          "objectId": "0x7f06fc635dcdc32bf571a62dd54b1f41f16cb5b75327f88dcf32fd8b7432c3df",
          "version": 685931665,
          "digest": "37rKLjUbuhdjQyGQygUKNpkr5tX8rHyJinMG5Tp7RJUi"
        }
      },
      {
        "owner": {
          "Shared": {
            "initial_shared_version": 685931665
          }
        },
        "reference": {
          "objectId": "0xdb268aa7c6c1beae14db8508b5087fbba447c3fb739bc3af8810c5d16bd28f08",
          "version": 685931665,
          "digest": "E8rF7SQ3zEVmrLPGkgQZdnhcApe4DEmbxtAAEEafk9Uy"
        }
      },
      {
        "owner": "Immutable",
        "reference": {
          "objectId": "0xfd9eee14cf1a75599149d460d4a78ed9075b03535a0912b2fdf179a412dc7428",
          "version": 1,
          "digest": "ADY1t6d2qiaFKSufXi3U4jjWi4evoypvR3iYhmBUasou"
        }
      }
    ],
    "mutated": [
      {
        "owner": {
          "AddressOwner": "0xf4945f468b27f8e9eefbecf1f54c0bcdd3b9ee5ae4034438fda4ac58295c17d6"
        },
        "reference": {
          "objectId": "0xcd905b7223c5dae8e207f5a74e8e55c83c5364f9ff05039e8627a809885539d6",
          "version": 685931665,
          "digest": "FVtPrAv7JYfcnxKUCZdcjd8wUA64iRGx9uedcEaCD3hz"
        }
      }
    ],
    "gasObject": {
      "owner": {
        "AddressOwner": "0xf4945f468b27f8e9eefbecf1f54c0bcdd3b9ee5ae4034438fda4ac58295c17d6"
      },
      "reference": {
        "objectId": "0xcd905b7223c5dae8e207f5a74e8e55c83c5364f9ff05039e8627a809885539d6",
        "version": 685931665,
        "digest": "FVtPrAv7JYfcnxKUCZdcjd8wUA64iRGx9uedcEaCD3hz"
      }
    },
    "dependencies": [
      "yqtELKLqAuSGkt6PX52KHKvmDKCrV3KCLxm6HAqL6DZ",
      "6t7btBBPvRrZqnt2nr1VqpNvGUkAu8bZm3A1jKPXGJRi",
      "9aXs2UJPyeQHV8gq15yXHU91LDjaetPvNRZAVonX2TUh",
      "9ugrBxCA9yLJ4qrRDFoMnHSLbk1bP3N1A7cZ4DKvos5L",
      "C3wFcACFqgmaDqW3BArZBbb8gKc6MSrjHUYft6d7FWa3",
      "DVgPGTQ9F99fQMd4eRmZTYtGgNyMkpChMNi4UfYdus6N",
      "HgNZBJfnTbN1cfmb8juxQ9Nf68uxSqf1iHX7TqkUcTRi"
    ]
  },
  "events": [],
  "objectChanges": [
    {
      "type": "mutated",
      "sender": "0xf4945f468b27f8e9eefbecf1f54c0bcdd3b9ee5ae4034438fda4ac58295c17d6",
      "owner": {
        "AddressOwner": "0xf4945f468b27f8e9eefbecf1f54c0bcdd3b9ee5ae4034438fda4ac58295c17d6"
      },
      "objectType": "0x2::coin::Coin<0x2::sui::SUI>",
      "objectId": "0xcd905b7223c5dae8e207f5a74e8e55c83c5364f9ff05039e8627a809885539d6",
      "version": "685931665",
      "previousVersion": "685931664",
      "digest": "FVtPrAv7JYfcnxKUCZdcjd8wUA64iRGx9uedcEaCD3hz"
    },
    {
      "type": "created",
      "sender": "0xf4945f468b27f8e9eefbecf1f54c0bcdd3b9ee5ae4034438fda4ac58295c17d6",
      "owner": {
        "AddressOwner": "0xf4945f468b27f8e9eefbecf1f54c0bcdd3b9ee5ae4034438fda4ac58295c17d6"
      },
      "objectType": "0x2::package::UpgradeCap",
      "objectId": "0x7f06fc635dcdc32bf571a62dd54b1f41f16cb5b75327f88dcf32fd8b7432c3df",
      "version": "685931665",
      "digest": "37rKLjUbuhdjQyGQygUKNpkr5tX8rHyJinMG5Tp7RJUi"
    },
    {
      "type": "created",
      "sender": "0xf4945f468b27f8e9eefbecf1f54c0bcdd3b9ee5ae4034438fda4ac58295c17d6",
      "owner": {
        "Shared": {
          "initial_shared_version": 685931665
        }
      },
      "objectType": "0xfd9eee14cf1a75599149d460d4a78ed9075b03535a0912b2fdf179a412dc7428::swap_router::RouterState",
      "objectId": "0xdb268aa7c6c1beae14db8508b5087fbba447c3fb739bc3af8810c5d16bd28f08",
      "version": "685931665",
      "digest": "E8rF7SQ3zEVmrLPGkgQZdnhcApe4DEmbxtAAEEafk9Uy"
    },
    {
      "type": "published",
      "packageId": "0xfd9eee14cf1a75599149d460d4a78ed9075b03535a0912b2fdf179a412dc7428",
      "version": "1",
      "digest": "ADY1t6d2qiaFKSufXi3U4jjWi4evoypvR3iYhmBUasou",
      "modules": [
        "swap_router"
      ]
    }
  ],
  "balanceChanges": [
    {
      "owner": {
        "AddressOwner": "0xf4945f468b27f8e9eefbecf1f54c0bcdd3b9ee5ae4034438fda4ac58295c17d6"
      },
      "coinType": "0x2::sui::SUI",
      "amount": "-14651880"
    }
  ],
  "timestampMs": "1763115930070",
  "confirmedLocalExecution": true,
  "checkpoint": "212024516"
}