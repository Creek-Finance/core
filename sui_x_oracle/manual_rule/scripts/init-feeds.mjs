#!/usr/bin/env node
import 'dotenv/config';
import { SuiClient } from '@mysten/sui/client';
import { Transaction } from '@mysten/sui/transactions';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { decodeSuiPrivateKey } from '@mysten/sui/cryptography';
// import { SuiPythClient } from '@pythnetwork/pyth-sui-js'; // not needed for manual-only

function reqEnv(name) {
    const v = process.env[name];
    if (!v) throw new Error(`Missing env: ${name}`);
    return v;
}
function optEnv(name, fallback) {
    const v = process.env[name];
    return v !== undefined && v !== '' ? v : fallback;
}
async function makeKeypair() {
    const raw = process.env.SUI_PRIVATE_KEY; if (!raw) throw new Error('SUI_PRIVATE_KEY missing');
    const { secretKey, schema } = decodeSuiPrivateKey(raw);
    if (schema !== 'ED25519') throw new Error(`Unsupported key schema: ${schema}`);
    return Ed25519Keypair.fromSecretKey(secretKey);
}

async function main() {
    const cfg = {
        rpcUrl: optEnv('SUI_RPC_URL', 'https://fullnode.testnet.sui.io:443'),
        // pkgs
        xOraclePkg: reqEnv('X_ORACLE_PACKAGE_ID'),
        // no pyth/supra in manual-only setup
        manualRulePkg: reqEnv('MANUAL_RULE_PACKAGE_ID'),
        // objs
        xOracleId: reqEnv('X_ORACLE_ID'),
        xOracleCapId: reqEnv('X_ORACLE_POLICY_CAP_ID'),
        // no pyth/supra objects required
        clockId: optEnv('CLOCK_ID', '0x6'),
        // test
        testCoinType: optEnv('TEST_COIN_TYPE', '0x2::sui::SUI'),
        // no pyth/supra params required
    };

    const client = new SuiClient({ url: cfg.rpcUrl });
    const kp = await makeKeypair();

    // 1) Init rules DF if not exist
    {
        const tx = new Transaction();
        tx.moveCall({
            target: `${cfg.xOraclePkg}::x_oracle::init_rules_df_if_not_exist`,
            arguments: [tx.object(cfg.xOracleCapId), tx.object(cfg.xOracleId)],
        });
        tx.setGasBudget(100000000);
        await client.signAndExecuteTransaction({ transaction: tx, signer: kp, requestType: 'WaitForLocalExecution' });
    }

    // 2) Add rules: primary=Manual only (no secondary for now)
    async function addRule(kind, rulePkg) {
        const tx = new Transaction();
        tx.moveCall({
            target: `${cfg.xOraclePkg}::x_oracle::add_${kind}_price_update_rule_v2`,
            arguments: [tx.object(cfg.xOracleId), tx.object(cfg.xOracleCapId)],
            typeArguments: [cfg.testCoinType, `${rulePkg}::rule::Rule`],
        });
        tx.setGasBudget(100000000);
        await client.signAndExecuteTransaction({ transaction: tx, signer: kp, requestType: 'WaitForLocalExecution' });
    }
    // primary: manual only
    await addRule('primary', cfg.manualRulePkg).catch(() => { });

    console.log('Init complete.');
}

main().catch((e) => { console.error(e); process.exit(1); });


