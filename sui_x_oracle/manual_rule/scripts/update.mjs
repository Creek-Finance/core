#!/usr/bin/env node
import 'dotenv/config';
import { SuiClient } from '@mysten/sui/client';
import { Transaction } from '@mysten/sui/transactions';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { decodeSuiPrivateKey } from '@mysten/sui/cryptography';

function reqEnv(name) { const v = process.env[name]; if (!v) throw new Error(`Missing env: ${name}`); return v; }
function optEnv(name, fallback) { const v = process.env[name]; return v !== undefined && v !== '' ? v : fallback; }
async function makeKeypair() {
    const raw = process.env.SUI_PRIVATE_KEY; if (!raw) throw new Error('SUI_PRIVATE_KEY missing');
    const { secretKey, schema } = decodeSuiPrivateKey(raw);
    if (schema !== 'ED25519') throw new Error(`Unsupported key schema: ${schema}`);
    return Ed25519Keypair.fromSecretKey(secretKey);
}

function to9DecInteger(priceFloat) {
    return BigInt(Math.round(priceFloat * 1e9));
}

async function main() {
    const cfg = {
        rpcUrl: optEnv('SUI_RPC_URL', 'https://fullnode.testnet.sui.io:443'),
        xOraclePkg: reqEnv('X_ORACLE_PACKAGE_ID'),
        manualRulePkg: reqEnv('MANUAL_RULE_PACKAGE_ID'),
        xOracleId: reqEnv('X_ORACLE_ID'),
        clockId: optEnv('CLOCK_ID', '0x6'),
        testCoinType: optEnv('TEST_COIN_TYPE', '0x2::sui::SUI'),
    };

    const client = new SuiClient({ url: cfg.rpcUrl });
    const kp = await makeKeypair();

    const tx = new Transaction();

    // 1) Create request
    const [request] = tx.moveCall({
        target: `${cfg.xOraclePkg}::x_oracle::price_update_request`,
        arguments: [tx.object(cfg.xOracleId)],
        typeArguments: [cfg.testCoinType],
    });

    // 2) Set manual price as primary only
    const value9 = to9DecInteger(parseFloat(optEnv('MANUAL_PRICE', '1.2345')));
    tx.moveCall({
        target: `${cfg.manualRulePkg}::rule::set_price_as_primary`,
        arguments: [request, tx.pure.u64(Number(value9)), tx.object(cfg.clockId)],
        typeArguments: [cfg.testCoinType],
    });

    // 3) Confirm update
    tx.moveCall({
        target: `${cfg.xOraclePkg}::x_oracle::confirm_price_update_request`,
        arguments: [tx.object(cfg.xOracleId), request, tx.object(cfg.clockId)],
        typeArguments: [cfg.testCoinType],
    });

    tx.setGasBudget(100000000);
    const res = await client.signAndExecuteTransaction({ transaction: tx, signer: kp, requestType: 'WaitForLocalExecution', options: { showEffects: true, showEvents: true } });
    const ok = res.effects?.status?.status === 'success';
    if (!ok) {
        console.error('Update tx failed:', res.effects?.status?.error);
        process.exit(1);
    }
    console.log('Update Digest:', res.digest);
}

main().catch((e) => { console.error(e); process.exit(1); });


