deploy 
```
sui client publish --gas-budget 1000000000 --with-unpublished-dependencies --json
```


## 测试:
#### 测试 internal_rewards 和 staking_pool_rewards
先设置好奖励 token 支持,在进行存款和资金分配测试

- staking_pool_rewards 合约
  - 添加奖励支持(因为支持多个 TOKEN,测试时可以任意添加,可以用 test_coin 的 token 添加)
- internal_rewards 合约
  - 设置奖励分配地址(外部合作地址,保险基金地址,团队地址)
  - 检查分配地址和分配比例是否符合预期(分配比例初始化时已经有了,一般不需要额外在设置)
  - 调用合约存入 SUI,这个内部奖励合约目前只有 SUI
  - 查询 SUI 金库余额是否符合预期
  - 调用 SUI 分配函数(这个函数是后续 bot 执行的,需要测试 keep 权限执行,需要将 keep 权限对象转移给指定地址后测试)
  - 测试紧急提取(再次存入 SUI,查询余额,调用紧急提取函数)
- staking_pool_rewards 合约
  - 查询奖励池的资金库余额(各个 token)
  - 设置用户指定 token 的奖励金额(admin 和 keep 权限都有函数可以操作,需要测试 keep 权限)
  - 查询用户地址指定 token 的待领取奖励金额
  - 用户地址领取自己的奖励
  - 测试紧急提取

#### 测试 external_rewards 和 collateral_vault_rewards
这俩都是支持多 token 的都需要先设置奖励 token
collateral_vault_rewards 和 staking_pool_rewards 合约是一样的,主要测试其他 toekn 的奖励设置和领取奖励即可

- external_rewards 合约
  - 添加奖励支持(因为支持多个 TOKEN,测试时可以任意添加,可以用 test_coin 的 token 添加)
- collateral_vault_rewards 合约
  - 添加奖励支持(因为支持多个 TOKEN,测试时可以任意添加,可以用 test_coin 的 token 添加)
- external_rewards 合约
  - 存入不同的 token 到合约
  - 查询余额
  - 将指定 token 指定金额分配给 staking_pool_rewards
  - 将指定 token 指定金额分配给 collateral_vault_rewards
  - 测试紧急提取
- staking_pool_rewards 合约
  - 查询奖励池的资金库余额(各个 token)
  - 设置用户指定 token 的奖励金额(admin 和 keep 权限都有函数可以操作,需要测试 keep 权限)
  - 查询用户地址指定 token 的待领取奖励金额
  - 用户地址领取自己的奖励
  - 测试紧急提取
- collateral_vault_rewards 合约
  - 查询奖励池的资金库余额(各个 token)
  - 设置用户指定 token 的奖励金额(admin 和 keep 权限都有函数可以操作,需要测试 keep 权限)
  - 查询用户地址指定 token 的待领取奖励金额
  - 用户地址领取自己的奖励
  - 测试紧急提取

最后测试 admin 和 keep 转移权限 和 权限是否生效即可