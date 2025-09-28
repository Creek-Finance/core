# 手动更新 oracle 价格


1. 确保 .env 包 id 正确，包括 `x-oracle` 和 `manual_rule` 这两部分

2. 定义需要配置的代币地址以及价值信息，比如：

```
# update coin : sui
TEST_COIN_TYPE=0x2::sui::SUI
MANUAL_PRICE=3.33
```

或

```
# update coin : gr
TEST_COIN_TYPE=0xbbe8347c050690e5257d32be58bc66dedb65096a0d02de4b5081fedc129367ff::coin_gr::COIN_GR
MANUAL_PRICE=12.34
```

> 如果该代币没有初始化到 x-oracle，则需要先执行一次 `node init-feeds.mjs`。该脚本需要执行者为 x-oracle 的发布者。

3. 配置好地址和价格（并确保已初始化后），执行 `node update.mjs` 即可更新价格


> 通过 price.move 中的方式获取价格时， price.move 会验证价格是否新鲜，所以前端应该在获取价格的同时先更新该价格。

