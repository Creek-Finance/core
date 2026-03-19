import 'dotenv/config';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';
import { SuiClient } from '@mysten/sui/client';
import { Transaction } from '@mysten/sui/transactions';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { decodeSuiPrivateKey } from '@mysten/sui/cryptography';
import { bcs } from '@mysten/bcs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function reqEnv(name) {
  const v = process.env[name];
  if (!v) throw new Error(`Missing env: ${name}`);
  return v;
}
function optEnv(name, fallback) {
  const v = process.env[name];
  return v !== undefined && v !== '' ? v : fallback;
}

// 读取 deploy.json
function loadDeployConfigFromJson() {
  const deployPath = path.resolve(__dirname, './deploy.json');
  if (!fs.existsSync(deployPath)) throw new Error('deploy.json not found');
  const raw = fs.readFileSync(deployPath, 'utf-8');
  const json = JSON.parse(raw);
  const objectChanges = json.objectChanges || [];
  let config = {};
  // 包ID
  const published = objectChanges.find(x => x.type === 'published');
  if (published) config.REWARDS_PACKAGE_ID = published.packageId;
  // InternalSuiVault
  const suiVault = objectChanges.find(x => x.objectType && x.objectType.includes('internal_rewards::InternalSuiVault'));
  if (suiVault) config.SUI_VAULT_ID = suiVault.objectId;
  // CollateralSuiVault
  const collateralVault = objectChanges.find(x => x.objectType && x.objectType.includes('collateral_vault_rewards::CollateralSuiVault'));
  if (collateralVault) config.COLLATERAL_VAULT_ID = collateralVault.objectId;
  // StakingPoolSuiVault
  const stakingPoolVault = objectChanges.find(x => x.objectType && x.objectType.includes('staking_pool_rewards::StakingPoolSuiVault'));
  if (stakingPoolVault) config.STAKING_POOL_VAULT_ID = stakingPoolVault.objectId;
  // AdminCap
  const adminCap = objectChanges.find(x => x.objectType && x.objectType.includes('admin::AdminCap'));
  if (adminCap) config.ADMIN_CAP_ID = adminCap.objectId;
  // KeeperCap
  const keeperCap = objectChanges.find(x => x.objectType && x.objectType.includes('admin::KeeperCap'));
  if (keeperCap) config.KEEPER_CAP_ID = keeperCap.objectId;
  // RewardProportions
  const rewardProportions = objectChanges.find(x => x.objectType && x.objectType.includes('internal_rewards::RewardProportions'));
  if (rewardProportions) config.REWARD_PROPORTIONS_ID = rewardProportions.objectId;
  // RewardDestinations
  const rewardDest = objectChanges.find(x => x.objectType && x.objectType.includes('internal_rewards::RewardDestinations'));
  if (rewardDest) config.REWARD_DESTINATIONS_ID = rewardDest.objectId;
  // StakingPool（如需用到可加）
  // const stakingPool = objectChanges.find(x => x.objectType && x.objectType.includes('staking_pool_rewards::RewardPool'));
  // if (stakingPool) config.STAKING_POOL_ID = stakingPool.objectId;
  return config;
}

const deployConfig = loadDeployConfigFromJson();

console.log('Loaded deploy config:', deployConfig);

const REWARDS_PACKAGE_ID = deployConfig.REWARDS_PACKAGE_ID;
const SUI_VAULT_ID = deployConfig.SUI_VAULT_ID;
const TOKEN_VAULT_ID = deployConfig.TOKEN_VAULT_ID;
const ADMIN_CAP_ID = deployConfig.ADMIN_CAP_ID;
const KEEPER_CAP_ID = deployConfig.KEEPER_CAP_ID;
const REWARD_PROPORTIONS_ID = deployConfig.REWARD_PROPORTIONS_ID;
const REWARD_DESTINATIONS_ID = deployConfig.REWARD_DESTINATIONS_ID;
const STAKING_POOL_VAULT_ID = deployConfig.STAKING_POOL_VAULT_ID;
const SUI_TOKEN_TYPE = '0x2::sui::SUI';

const PRIVATE_KEY = reqEnv('SUI_PRIVATE_KEY');
const { schema, secretKey } = decodeSuiPrivateKey(PRIVATE_KEY);
const SUI_NODE_URL = optEnv('SUI_RPC_URL', 'https://fullnode.testnet.sui.io');
const client = new SuiClient({ url: SUI_NODE_URL });

const keypair = Ed25519Keypair.fromSecretKey(secretKey);

async function sendTx(tx) {
  const result = await client.signAndExecuteTransaction({
    transaction: tx,
    signer: keypair,
    options: { showEffects: true, showObjectChanges: true, showEvents: true },
  });
  console.log('Digest:', result.digest);
  console.log('Status:', result.effects?.status?.status);
  if (result.effects?.status?.error) {
    console.log('Error:', result.effects.status.error);
  }
  if (result.objectChanges && result.objectChanges.length) {
    console.log('ObjectChanges:', JSON.stringify(result.objectChanges, null, 2));
  }
  if (result.events && result.events.length) {
    console.log('Events:', JSON.stringify(result.events, null, 2));
  }
  return result;
}

// 存入 SUI
async function depositSui(amount) {
  const txb = new Transaction();
  // 假设有足够的 SUI
  const [coin] = txb.splitCoins(txb.gas, [txb.pure.u64(amount)]);
  txb.moveCall({
    target: `${REWARDS_PACKAGE_ID}::internal_rewards::deposit_sui`,
    arguments: [txb.object(SUI_VAULT_ID), coin],
  });
  await sendTx(txb);
}

async function getCoinObjectId(owner, coinType, minBalance = 0, excludeCoinId) {
  const coins = await client.getCoins({ owner, coinType });
  if (!coins.data.length) throw new Error(`No coins found for ${coinType}`);

  const coin = coins.data.find(
    (c) => BigInt(c.balance) >= BigInt(minBalance) && c.coinObjectId !== excludeCoinId
  );
  if (!coin) throw new Error(`No coin with enough balance for ${coinType}`);
  return coin.coinObjectId;
}

async function depositToken(reqAddress, amount, tokenType, tokenVaultId) {
  const txb = new Transaction();

  // 获取所有 coin
  const suiCoins = await client.getCoins({ owner: reqAddress, coinType: "0x2::sui::SUI" });
  const suiCoinIds = suiCoins.data.map(c => c.coinObjectId);

  // 查找 deposit coin
  const coinObjectId = await getCoinObjectId(reqAddress, tokenType, amount, suiCoinIds[0]);

  const [coin] = txb.splitCoins(txb.object(coinObjectId), [txb.pure.u64(amount)]);

  txb.moveCall({
    target: `${REWARDS_PACKAGE_ID}::external_rewards::deposit`,
    typeArguments: [tokenType],
    arguments: [txb.object(tokenVaultId), coin],
  });

  await sendTx(txb);
}

// external_rewards添加新代币金库
async function addExternalRewardsTokenSupport(tokenType) {
  const txb = new Transaction();
  txb.moveCall({
    target: `${REWARDS_PACKAGE_ID}::external_rewards::add_token_support`,
    typeArguments: [tokenType],
    arguments: [txb.object(ADMIN_CAP_ID)],
  });
  await sendTx(txb);
}

// 修改奖励分配比例
async function updateProportions(newStaking, newExternal, newInsurance) {
  const txb = new Transaction();
  txb.moveCall({
    target: `${REWARDS_PACKAGE_ID}::internal_rewards::update_proportions`,
    arguments: [
      txb.object(ADMIN_CAP_ID),
      txb.object(REWARD_PROPORTIONS_ID),
      txb.pure(newStaking),
      txb.pure(newExternal),
      txb.pure(newInsurance),
    ],
  });
  await sendTx(txb);
}

// 修改奖励目标地址
async function updateDestinations(externalAddr, insuranceAddr, teamAddr) {
  const txb = new Transaction();
  txb.moveCall({
    target: `${REWARDS_PACKAGE_ID}::internal_rewards::update_destinations`,
    arguments: [
      txb.object(ADMIN_CAP_ID),
      txb.object(REWARD_DESTINATIONS_ID),
      txb.pure.address(externalAddr),
      txb.pure.address(insuranceAddr),
      txb.pure.address(teamAddr),
    ],
  });
  await sendTx(txb);
}

// internal_rewards 紧急提取 SUI
async function internalRewardsemergencyWithdrawSui() {
  const txb = new Transaction();
  txb.moveCall({
    target: `${REWARDS_PACKAGE_ID}::internal_rewards::emergency_withdraw_sui`,
    arguments: [txb.object(ADMIN_CAP_ID), txb.object(SUI_VAULT_ID)],
  });
  await sendTx(txb);
}

// 分配 SUI 奖励
async function distributeSuiRewards(stackingPoolVaultId) {
  const txb = new Transaction();
  txb.moveCall({
    target: `${REWARDS_PACKAGE_ID}::internal_rewards::distribute_sui_rewards_by_keeper`,
    arguments: [
      txb.object(KEEPER_CAP_ID),
      txb.object(SUI_VAULT_ID),
      txb.object(REWARD_PROPORTIONS_ID),
      txb.object(REWARD_DESTINATIONS_ID),
      txb.object(stackingPoolVaultId),
    ],
  });
  await sendTx(txb);
}

// 查询 SUI 金库余额
async function getSuiVaultBalance() {
  const res = await client.getObject({ id: SUI_VAULT_ID, options: { showContent: true } });
  // console.log(JSON.stringify(res.data?.content, null, 2));
  const balance = res.data?.content?.fields?.balance ?? '0';
  console.log('SUI Vault Balance:', balance);
}

// 查询代币金库余额
async function getExternalRewardsTokenVaultBalance(tokenVaultId) {
  const res = await client.getObject({ id: tokenVaultId, options: { showContent: true } });
  const balance = res.data?.content?.fields?.balance ?? '0';
  console.log('ExternalRewardsToken Vault Balance:', balance);
}

// 查询代币金库余额
async function getTokenVaultBalance(tokenVaultId) {
  const res = await client.getObject({ id: tokenVaultId, options: { showContent: true } });
  const balance = res.data?.content?.fields?.vault ?? '0';
  console.log('Token Vault Balance:', balance);
}

// 查询奖励分配比例
async function getProportions() {
  const res = await client.getObject({ id: REWARD_PROPORTIONS_ID, options: { showContent: true } });
  const fields = res.data?.content?.fields;
  if (!fields) return console.log('No proportions found');
  console.log('Proportions:', {
    staking_pool_rewards_bps: fields.staking_pool_rewards_bps,
    external_partner_rewards_bps: fields.external_partner_rewards_bps,
    insurance_fund_bps: fields.insurance_fund_bps,
    team_bps: fields.team_bps,
  });
}

// 查询奖励目标地址
async function getDestinations() {
  const res = await client.getObject({ id: REWARD_DESTINATIONS_ID, options: { showContent: true } });
  const fields = res.data?.content?.fields;
  if (!fields) return console.log('No destinations found');
  console.log('Destinations:', {
    external_partner_rewards_addr: fields.external_partner_rewards_addr,
    insurance_fund_addr: fields.insurance_fund_addr,
    team_addr: fields.team_addr,
  });
}

// 查询StakingPool奖励池余额
async function getStakingPoolVaultBalance() {
  const res = await client.getObject({ id: STAKING_POOL_ID, options: { showContent: true } });
  const fields = res.data?.content?.fields;
  if (!fields) return console.log('No staking pool found');
  console.log('Staking Pool Vault Balance:', fields.vault?.fields?.value);
}

// 查询StakingPool奖励池余额
async function getStakingPoolSuiVaultBalance() {
  const res = await client.getObject({ id: STAKING_POOL_VAULT_ID, options: { showContent: true } });
  const balance = res.data?.content?.fields?.balance ?? '0';
  console.log('Staking Pool Vault Balance:', balance);
}


// ========== staking_pool_rewards 合约相关调用 ==========

// 添加奖励币种
async function addStakingRewardToken(tokenType) {
  const txb = new Transaction();
  txb.moveCall({
    target: `${REWARDS_PACKAGE_ID}::staking_pool_rewards::add_reward_token`,
    typeArguments: [tokenType],
    arguments: [txb.object(ADMIN_CAP_ID)],
  });
  await sendTx(txb);
}

// 设置奖励（Admin）
async function setStakingRewardsByAdmin(recipients, amounts, vaultId, tokenType) {
  const txb = new Transaction();
  txb.moveCall({
    target: `${REWARDS_PACKAGE_ID}::staking_pool_rewards::set_rewards_by_admin`,
    typeArguments: [tokenType],
    arguments: [
      txb.object(ADMIN_CAP_ID),
      txb.object(vaultId),
      txb.pure.vector('address', recipients),
      txb.pure.vector('u64', amounts),
    ],
  });
  await sendTx(txb);
}

// 设置奖励（Keeper）
async function setStakingRewardsByKeeper(recipients, amounts, vaultId, tokenType) {
  const txb = new Transaction();
  txb.moveCall({
    target: `${REWARDS_PACKAGE_ID}::staking_pool_rewards::set_rewards_by_keeper`,
    typeArguments: [tokenType],
    arguments: [
      txb.object(KEEPER_CAP_ID),
      txb.object(vaultId),
      txb.pure.vector('address', recipients),
      txb.pure.vector('u64', amounts),
    ],
  });
  await sendTx(txb);
}


// 用户待领取奖励
async function getPendingReward(
  vaultId,
  rewardType,
  userAddress,
) {
  const txb = new Transaction();
  txb.moveCall({
    target: `${REWARDS_PACKAGE_ID}::staking_pool_rewards::get_pending_reward`,
    typeArguments: [rewardType],
    arguments: [
      txb.object(vaultId),
      txb.pure.address(userAddress)
    ],
  });

  try {
    const inspectResult = await client.devInspectTransactionBlock({
      sender: userAddress,
      transactionBlock: txb,
    });
    if (inspectResult.error) {
      throw new Error(`Inspect failed: ${inspectResult.error}`);
    }
    if (
      !inspectResult.results ||
      inspectResult.results.length === 0 ||
      !inspectResult.results[0].returnValues
    ) {
      throw new Error('Inspect failed: No return values found.');
    }
    const [bytes, type] = inspectResult.results[0].returnValues[0];
    if (type === 'u64') {
      const amountString = bcs.u64().parse(new Uint8Array(bytes));
      console.log(`Pending reward for ${userAddress} in vault ${vaultId}:`, amountString);
      return BigInt(amountString);
    } else {
      throw new Error(`Unexpected return type. Expected 'u64', got '${type}'`);
    }
  } catch (error) {
    console.error('getPendingReward failed:', error);
    return 0n;
  }
}




// staking_pool_rewards 紧急提取奖励池资金
async function emergencyWithdrawStakingReward(stackingPoolVaultId, rewardType) {
  const txb = new Transaction();
  txb.moveCall({
    target: `${REWARDS_PACKAGE_ID}::staking_pool_rewards::emergency_withdraw`,
    typeArguments: [rewardType],
    arguments: [txb.object(ADMIN_CAP_ID), txb.object(stackingPoolVaultId)],
  });
  await sendTx(txb);
}

// 用户领取奖励
async function claimStakingReward(vaultId, rewardType) {
  const txb = new Transaction();
  txb.moveCall({
    target: `${REWARDS_PACKAGE_ID}::staking_pool_rewards::claim_reward`,
    typeArguments: [rewardType],
    arguments: [txb.object(vaultId)],
  });
  await sendTx(txb);
}

// ========== external_rewards 合约相关调用（如有类似接口，可仿照 staking_pool_rewards 编写） ==========
// 分配奖励到 StakingRewardPool
async function distributeRewardsStakingPool(vaultId, stakingPoolId, amount, tokenType) {
  const txb = new Transaction();
  txb.moveCall({
    target: `${REWARDS_PACKAGE_ID}::external_rewards::distribute_rewards_staking_pool`,
    typeArguments: [tokenType],
    arguments: [
      txb.object(ADMIN_CAP_ID), // 你的 AdminCap 对象 ID
      txb.object(vaultId),      // 金库对象 ID
      txb.pure.u64(amount),         // 分配数量
      txb.object(stakingPoolId) // StakingRewardPool 对象 ID
    ],
  });

  await sendTx(txb);
}

// 入口函数示例
async function main() {
  // 合作伙伴地址
  const externalAddr = '0x086974f854e1b129afdea9a5075da31e6b08c1765cc12afdf1e07bb32ea329f6';
  // 保险基金地址
  const insuranceAddr = '0x9b8ecb1ac5c4f9cf986a9dab085f66959975d4194247685e81b424eb95bba2d2';
  // 团队地址
  const teamAddr = '0x681acccc21d18c48850afe3bd50b4f62d5cb37294034ec0c95a8bc798c6cb451';

  // 查询分配比例
  await getProportions();
  // 查询分配地址
  await getDestinations()
  // 更新分配地址
  // await updateDestinations(externalAddr, insuranceAddr, teamAddr);
  // 查询 SUI 金库余额
  // await getSuiVaultBalance();

  // 存入 SUI
  // await depositSui(100000000); // 存入 0.1 SUI

  // 查询 SUI 金库余额
  await getSuiVaultBalance();

  // -------------------外部奖励合约---------------------------
  // 添加token 支持
  const COIN_USDC_TYPE =
    "0xc9fccda95ac2e369b5f95958a426377362da338fbf02d5acdbf23dfe77ef1af8::usdc::USDC";

  // 不能一起执行写入操作会报错,需要单独执行
  // await addExternalRewardsTokenSupport(COIN_USDC_TYPE);
  // await addExternalRewardsTokenSupport(SUI_TOKEN_TYPE);

  // 存款 USDC
  // 这个类型 ID 是部署合约时创建的金库对象 ID，根据addExternalRewardsTokenSupport 调用后事件获取
  const USDC_TOKEN_ExternalRewards_VAULT_ID = '0xf66a1c0b8cc0ee99276a61c714f42f4fa5d27606dfc16b579fc5a4e8a2a2e3d1';
  const SUI_TOKEN_ExternalRewards_VAULT_ID = '0x95566f16c433e8178c53e5f97b768fcfb91faacba22791dc2d77625b512ac716';

  // await depositToken("0xad841c50ccc2dc0d21f04c14e9a76389e53dc65c6a45876105cd7389bb032ee8",
  //   1000000000, COIN_USDC_TYPE, USDC_TOKEN_ExternalRewards_VAULT_ID); // 存入 1 USDC（ USDC 有9位小数）

  // await depositToken("0xad841c50ccc2dc0d21f04c14e9a76389e53dc65c6a45876105cd7389bb032ee8",
  //   10000000, SUI_TOKEN_TYPE, SUI_TOKEN_ExternalRewards_VAULT_ID); // 存入 0.1 SUI

  // 查询代币金库余额
  await getExternalRewardsTokenVaultBalance(USDC_TOKEN_ExternalRewards_VAULT_ID);
  await getExternalRewardsTokenVaultBalance(SUI_TOKEN_ExternalRewards_VAULT_ID);


  // -------------------------staking_pool 设置---------------------------------
  // 设置 staking_pool token 奖励
  // await addStakingRewardToken(COIN_USDC_TYPE);
  // await addStakingRewardToken(SUI_TOKEN_TYPE);
  const USDC_TOKEN_Staking_VAULT_ID = '0x924d782fd117d6d7bf4e737b8c6e481db22fdb7c7303b2c4fc9fb345efd82f20';
  const SUI_TOKEN_Staking_VAULT_ID = '0xe7345d61af85f0e653d3131d03d257fd549b168ad02cc173e826005734f7cabd';

  // 查询代币金库余额
  await getTokenVaultBalance(USDC_TOKEN_Staking_VAULT_ID);
  await getTokenVaultBalance(SUI_TOKEN_Staking_VAULT_ID);

  // -------------------外部奖励合约---------------------------
  // 分配奖励到 StakingRewardPool
  // await distributeRewardsStakingPool(
  //   USDC_TOKEN_ExternalRewards_VAULT_ID,
  //   USDC_TOKEN_Staking_VAULT_ID,
  //   1000,
  //   COIN_USDC_TYPE
  // );

  // await distributeRewardsStakingPool(
  //   SUI_TOKEN_ExternalRewards_VAULT_ID,
  //   SUI_TOKEN_Staking_VAULT_ID,
  //   5000,
  //   SUI_TOKEN_TYPE
  // );

  // -------------------------staking_pool 设置---------------------------------
  // 设置质押池奖励（Keeper）
  const userAddress = ['0x0caa512f4a13e66bd98dcb32896ee6ac2cb87730d55147eafd072e8514df3214']; // 用户地址
  const rewardAmount = [1000]; // 奖励金额，单位为最小单位

  // await setStakingRewardsByKeeper(userAddress, rewardAmount, USDC_TOKEN_Staking_VAULT_ID, COIN_USDC_TYPE);
  // await setStakingRewardsByKeeper(userAddress, rewardAmount, SUI_TOKEN_Staking_VAULT_ID, SUI_TOKEN_TYPE);


  // 用户待领取金额
  await getPendingReward(USDC_TOKEN_Staking_VAULT_ID, COIN_USDC_TYPE, userAddress[0]);
  await getPendingReward(SUI_TOKEN_Staking_VAULT_ID, SUI_TOKEN_TYPE, userAddress[0]);

  // 用户领取奖励金额
  // await claimStakingReward( USDC_TOKEN_Staking_VAULT_ID, COIN_USDC_TYPE);
  // await claimStakingReward(SUI_TOKEN_Staking_VAULT_ID, SUI_TOKEN_TYPE);

  // 紧急提取 staking_pool_rewards 合约中的奖励
  // await emergencyWithdrawStakingReward(SUI_TOKEN_Staking_VAULT_ID, SUI_TOKEN_TYPE);

  // --------------------internal_rewards 合约---------------------------
  // 分配 internal_rewards 合约中的 SUI 奖励
  // await distributeSuiRewards(SUI_TOKEN_Staking_VAULT_ID);

}

main().catch(console.error);