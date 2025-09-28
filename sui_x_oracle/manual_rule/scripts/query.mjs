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

async function main() {
    const cfg = {
        rpcUrl: optEnv('SUI_RPC_URL', 'https://fullnode.testnet.sui.io:443'),
        xOraclePkg: reqEnv('X_ORACLE_PACKAGE_ID'),
        xOracleId: reqEnv('X_ORACLE_ID'),
        clockId: optEnv('CLOCK_ID', '0x6'),
        testCoinType: optEnv('TEST_COIN_TYPE', '0x2::sui::SUI'),
    };

    const client = new SuiClient({ url: cfg.rpcUrl });
    const kp = await makeKeypair();

    const tx = new Transaction();
    const [coinTypeName] = tx.moveCall({
        target: `0x1::type_name::get`,
        arguments: [],
        typeArguments: [cfg.testCoinType],
    });
    // Call the protocol-like read path via oracle_x_demo::query (if deployed) or emulate inline
    tx.moveCall({
        target: `${reqEnv('ORACLE_X_DEMO_PACKAGE_ID')}::query::read_price`,
        arguments: [tx.object(cfg.xOracleId), coinTypeName, tx.object(cfg.clockId)],
    });

    tx.setGasBudget(100000000);
    const res = await client.signAndExecuteTransaction({ transaction: tx, signer: kp, requestType: 'WaitForLocalExecution', options: { showEffects: true, showEvents: true } });
    const ok = res.effects?.status?.status === 'success';
    if (!ok) {
        console.error('Query tx failed:', res.effects?.status?.error);
        process.exit(1);
    }
    console.log('Query Digest:', res.digest);
    if (res.events) {
        const ev = res.events.find(e => e.type.includes('DemoPriceEvent'));
        if (ev) console.log('Query price event:', ev.parsedJson);
        else console.log('No DemoPriceEvent found (ensure demo package and query module deployed).');
    }
}

main().catch((e) => { console.error(e); process.exit(1); });


