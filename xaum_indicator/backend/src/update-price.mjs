#!/usr/bin/env node
import 'dotenv/config';
import { SuiClient } from '@mysten/sui/client';
import { Transaction } from '@mysten/sui/transactions';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { decodeSuiPrivateKey } from '@mysten/sui/cryptography';
import { SuiPythClient } from '@pythnetwork/pyth-sui-js';

function reqEnv(name) {
    const v = process.env[name];
    if (v === undefined || v === '') {
        throw new Error(`Missing env: ${name}`);
    }
    return v;
}

function optEnv(name, fallback) {
    const v = process.env[name];
    return v !== undefined && v !== '' ? v : fallback;
}

function parseArgs(argv) {
    const args = new Set(argv.slice(2));
    return {
        noClock: args.has('--no-clock'),
        onlyPyth: args.has('--only-pyth'),
        onlyContract: args.has('--only-contract'),
        verbose: args.has('-v') || args.has('--verbose'),
    };
}

function logInfo(msg) {
    console.log(`[INFO] ${new Date().toISOString()} ${msg}`);
}
function logWarn(msg) {
    console.warn(`[WARN] ${new Date().toISOString()} ${msg}`);
}
function logError(msg, err) {
    console.error(`[ERROR] ${new Date().toISOString()} ${msg}`);
    if (err) console.error(err);
}

function sleep(ms) {
    return new Promise((r) => setTimeout(r, ms));
}

async function ensureObjectReadable(client, objectId, attempts = 10, delayMs = 1000) {
    for (let i = 0; i < attempts; i++) {
        try {
            const obj = await client.getObject({ id: objectId, options: { showContent: true } });
            if (obj?.data?.content?.dataType === 'moveObject') {
                return true;
            }
        } catch (_) {
            // ignore and retry
        }
        await sleep(delayMs);
    }
    return false;
}

async function makeKeypair() {
    const raw = process.env.SUI_PRIVATE_KEY;
    if (!raw) throw new Error('SUI_PRIVATE_KEY missing in env');

    // Expected format: value from `sui keytool export --key-type ed25519` (e.g., "suiprivkey1...")
    try {
        const { secretKey, schema } = decodeSuiPrivateKey(raw);
        if (schema !== 'ED25519') {
            throw new Error(`Unsupported key schema: ${schema}. Please provide ed25519 key.`);
        }
        return Ed25519Keypair.fromSecretKey(secretKey);
    } catch (e) {
        throw new Error('Failed to decode SUI_PRIVATE_KEY. Ensure it is exported via `sui keytool export --key-type ed25519`.');
    }
}

async function waitForExecution(client, digest, { timeoutMs = 30000, pollMs = 1000, maxPolls = 30 } = {}) {
    try {
        const res = await client.waitForTransaction({ digest, timeout: timeoutMs });
        const ok = res.effects?.status?.status === 'success';
        if (ok) return true;
        // If explicitly failed, return false early
        if (res.effects?.status?.status === 'failure') return false;
    } catch (e) {
        logWarn(`waitForTransaction failed: ${e?.message || e}. Falling back to polling getTransactionBlock.`);
    }

    // Fallback polling
    for (let i = 0; i < maxPolls; i++) {
        try {
            const info = await client.getTransactionBlock({ digest, options: { showEffects: true } });
            const status = info.effects?.status?.status;
            if (status === 'success') return true;
            if (status === 'failure') return false;
        } catch (_) {
            // swallow and continue polling
        }
        await sleep(pollMs);
    }
    return false;
}

async function printTxDiagnostics(client, digest, title = 'Transaction Diagnostics') {
    try {
        const info = await client.getTransactionBlock({
            digest,
            options: {
                showInput: true,
                showEffects: true,
                showEvents: true,
                showObjectChanges: true,
                showBalanceChanges: true,
            },
        });
        console.log('===== ' + title + ' =====');
        console.log('Digest:', digest);
        console.log('Status:', info.effects?.status?.status);
        if (info.effects?.status?.error) console.log('Error:', info.effects.status.error);
        if (info.balanceChanges && info.balanceChanges.length) console.log('BalanceChanges:', info.balanceChanges);
        if (info.objectChanges && info.objectChanges.length) console.log('ObjectChanges:', info.objectChanges.slice(0, 5), '...');
        if (info.events && info.events.length) console.log('Events count:', info.events.length);
    } catch (e) {
        logWarn(`Failed to fetch tx diagnostics for ${digest}: ${e?.message || e}`);
    }
}

async function readPythOnChainInfo(client, priceInfoObjectId) {
    try {
        const obj = await client.getObject({ id: priceInfoObjectId, options: { showContent: true } });
        if (obj.data?.content?.dataType !== 'moveObject') return null;
        const fields = obj.data.content.fields;
        if (!fields?.price_info?.fields?.price_feed?.fields?.price?.fields) return null;
        const price = fields.price_info.fields.price_feed.fields.price.fields;
        const tsSec = parseInt(price.timestamp);
        const nowSec = Math.floor(Date.now() / 1000);
        const age = nowSec - tsSec;
        return { timestampSec: tsSec, ageSec: age };
    } catch (_) {
        return null;
    }
}

async function updatePythPrice({ client, priceFeedId, hermesUrl, pythStateId, wormholeStateId, keypair }) {
    logInfo('Step 1: Fetching latest VAA from Hermes');
    const idNo0x = priceFeedId.startsWith('0x') ? priceFeedId.slice(2) : priceFeedId;
    const url = `${hermesUrl}/api/latest_vaas?ids[]=${idNo0x}`;
    const resp = await fetch(url);
    if (!resp.ok) throw new Error(`Hermes HTTP ${resp.status} ${resp.statusText}`);
    const vaas = await resp.json();
    if (!Array.isArray(vaas) || vaas.length === 0) throw new Error('Hermes returned empty VAA array');
    const vaaBase64 = vaas[0];
    logInfo(`Received VAA (base64 length=${vaaBase64.length})`);

    const vaaBuffer = Buffer.from(vaaBase64, 'base64');

    logInfo('Creating tx to update Pyth price feeds');
    const tx = new Transaction();
    const pythClient = new SuiPythClient(client, pythStateId, wormholeStateId);
    const priceInfoIds = await pythClient.updatePriceFeeds(tx, [vaaBuffer], [priceFeedId]);
    if (!priceInfoIds || priceInfoIds.length === 0) throw new Error('Failed to get PriceInfoObject ids from SuiPythClient');
    const priceInfoObjectId = String(priceInfoIds[0]);

    tx.setGasBudget(100000000);
    logInfo('Signing & executing Pyth update tx');
    const result = await client.signAndExecuteTransaction({ transaction: tx, signer: keypair });
    logInfo(`Pyth update digest: ${result.digest}`);

    const executed = await waitForExecution(client, result.digest);
    if (!executed) {
        // Double-check via getTransactionBlock to avoid false negatives
        try {
            const info = await client.getTransactionBlock({ digest: result.digest, options: { showEffects: true } });
            if (info.effects?.status?.status === 'success') {
                logWarn('waitForTransaction returned false, but tx status is success; continuing');
            } else {
                await printTxDiagnostics(client, result.digest, 'Pyth Update Failure');
                throw new Error('Pyth update transaction not executed successfully');
            }
        } catch (_) {
            await printTxDiagnostics(client, result.digest, 'Pyth Update Failure');
            throw new Error('Pyth update transaction not executed successfully');
        }
    }

    // Ensure the returned PriceInfoObject is actually readable on-chain before proceeding
    const readable = await ensureObjectReadable(client, priceInfoObjectId, 15, 1000);
    if (!readable) {
        throw new Error(`PriceInfoObject not readable after execution: ${priceInfoObjectId}`);
    }

    // Log the on-chain Pyth timestamp to help with the 60s freshness check
    const pythInfo = await readPythOnChainInfo(client, priceInfoObjectId);
    if (pythInfo) {
        logInfo(`Pyth on-chain timestamp: ${new Date(pythInfo.timestampSec * 1000).toISOString()} (age ${pythInfo.ageSec}s)`);
        if (pythInfo.ageSec > 60) {
            logWarn('Pyth price age > 60s; contract freshness check may fail');
        }
    }

    return { digest: result.digest, priceInfoObjectId };
}

async function callContractUpdate({ client, pkgId, storageId, priceInfoObjectId, clockId, noClock, keypair }) {
    const fn = noClock ? 'update_sui_price_without_clock' : 'update_sui_price';
    logInfo(`Step 2: Calling contract function ${fn}`);

    const tx = new Transaction();
    tx.moveCall({
        target: `${pkgId}::xaum_indicator::${fn}`,
        arguments: noClock
            ? [tx.object(storageId), tx.object(priceInfoObjectId)]
            : [tx.object(storageId), tx.object(priceInfoObjectId), tx.object(clockId)],
    });
    tx.setGasBudget(100000000);

    const result = await client.signAndExecuteTransaction({ transaction: tx, signer: keypair });
    logInfo(`Contract call digest: ${result.digest}`);
    const executed = await waitForExecution(client, result.digest);
    if (!executed) {
        // Double-check via getTransactionBlock to avoid false negatives
        try {
            const info = await client.getTransactionBlock({ digest: result.digest, options: { showEffects: true } });
            if (info.effects?.status?.status === 'success') {
                logWarn('waitForTransaction returned false for contract call, but tx status is success; continuing');
            } else {
                await printTxDiagnostics(client, result.digest, 'Contract Call Failure');
                throw new Error('Contract update transaction not executed successfully');
            }
        } catch (_) {
            await printTxDiagnostics(client, result.digest, 'Contract Call Failure');
            throw new Error('Contract update transaction not executed successfully');
        }
    }
    return { digest: result.digest };
}

async function main() {
    const args = parseArgs(process.argv);

    const cfg = {
        rpcUrl: optEnv('SUI_RPC_URL', 'https://fullnode.testnet.sui.io:443'),
        pythStateId: reqEnv('PYTH_STATE_ID'),
        wormholeStateId: reqEnv('WORMHOLE_STATE_ID'),
        hermesUrl: reqEnv('HERMES_URL'),
        priceFeedId: reqEnv('PRICE_FEED_ID'),
        pkgId: reqEnv('CONTRACT_PACKAGE_ID'),
        storageId: reqEnv('PRICE_STORAGE_ID'),
        clockId: reqEnv('CLOCK_ID'),
        knownPriceInfoObjectId: optEnv('KNOWN_PRICE_INFO_OBJECT_ID', ''),
        useKnown: /^true$/i.test(optEnv('USE_KNOWN_PRICE_INFO_OBJECT', 'false')),
    };

    logInfo('Bootstrapping Sui client and keypair');
    const client = new SuiClient({ url: cfg.rpcUrl });
    const keypair = await makeKeypair();
    const address = keypair.getPublicKey().toSuiAddress();
    logInfo(`Signer address: ${address}`);

    let priceInfoObjectId = undefined;

    try {
        if (!args.onlyContract) {
            if (cfg.useKnown && cfg.knownPriceInfoObjectId) {
                logInfo(`Skipping Step 1; using known PriceInfoObject id: ${cfg.knownPriceInfoObjectId}`);
                priceInfoObjectId = cfg.knownPriceInfoObjectId;
            } else {
                const { priceInfoObjectId: pid } = await updatePythPrice({
                    client,
                    priceFeedId: cfg.priceFeedId,
                    hermesUrl: cfg.hermesUrl,
                    pythStateId: cfg.pythStateId,
                    wormholeStateId: cfg.wormholeStateId,
                    keypair,
                });
                priceInfoObjectId = pid;
            }
        }

        if (!args.onlyPyth) {
            if (!priceInfoObjectId) {
                if (!cfg.knownPriceInfoObjectId) throw new Error('No PriceInfoObject id available. Set USE_KNOWN_PRICE_INFO_OBJECT=true and provide KNOWN_PRICE_INFO_OBJECT_ID, or do not use --only-contract.');
                priceInfoObjectId = cfg.knownPriceInfoObjectId;
            }
            await callContractUpdate({
                client,
                pkgId: cfg.pkgId,
                storageId: cfg.storageId,
                priceInfoObjectId,
                clockId: cfg.clockId,
                noClock: args.noClock,
                keypair,
            });
        }

        logInfo('All steps completed');
    } catch (e) {
        logError('Failed to execute update flow', e);
        process.exitCode = 1;
    }
}

main();


