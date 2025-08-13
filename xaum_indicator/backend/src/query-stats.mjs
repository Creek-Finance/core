#!/usr/bin/env node
import 'dotenv/config';
import { SuiClient } from '@mysten/sui/client';

function reqEnv(name) {
    const v = process.env[name];
    if (!v) throw new Error(`Missing env: ${name}`);
    return v;
}

function optEnv(name, d) {
    const v = process.env[name];
    return v && v.length > 0 ? v : d;
}

function logInfo(msg) { console.log(`[INFO] ${new Date().toISOString()} ${msg}`); }
function logError(msg, e) { console.error(`[ERROR] ${new Date().toISOString()} ${msg}`); if (e) console.error(e); }

// Convert u256 (string) scaled by 1e18 into a decimal string with exactly 18 fraction digits
function u256ToDecimalString(u256Str) {
    try {
        let negative = false;
        let valStr = u256Str;
        if (valStr.startsWith('-')) { negative = true; valStr = valStr.slice(1); }
        const big = BigInt(valStr);
        const scale = 1000000000000000000n; // 1e18
        const intPart = big / scale;
        const fracPart = big % scale;
        const fracStr = fracPart.toString().padStart(18, '0');
        return `${negative ? '-' : ''}${intPart.toString()}.${fracStr}`;
    } catch (_) {
        return '0.000000000000000000';
    }
}

// Human-friendly formatting for Hermes/Pyth floats
function formatPrice(n) {
    if (n < 0.000001) return `$${n.toFixed(12)}`;
    if (n < 0.01) return `$${n.toFixed(8)}`;
    if (n < 1) return `$${n.toFixed(6)}`;
    if (n < 100) return `$${n.toFixed(4)}`;
    return `$${n.toFixed(2)}`;
}

async function fetchOnChainPythPrice(client, priceInfoObjectId) {
    const obj = await client.getObject({ id: priceInfoObjectId, options: { showContent: true } });
    if (obj.data?.content?.dataType !== 'moveObject') return null;
    const fields = obj.data.content.fields;
    if (!fields?.price_info?.fields?.price_feed?.fields?.price?.fields) return null;
    const priceStruct = fields.price_info.fields.price_feed.fields.price.fields;
    const magnitude = parseInt(priceStruct.price.fields.magnitude);
    const negPrice = priceStruct.price.fields.negative;
    const expoMag = parseInt(priceStruct.expo.fields.magnitude);
    const expoNeg = priceStruct.expo.fields.negative;
    let actualPrice = magnitude;
    if (expoNeg) actualPrice = magnitude / Math.pow(10, expoMag); else actualPrice = magnitude * Math.pow(10, expoMag);
    if (negPrice) actualPrice = -actualPrice;
    const conf = parseInt(priceStruct.conf);
    let actualConf = conf;
    if (expoNeg) actualConf = conf / Math.pow(10, expoMag); else actualConf = conf * Math.pow(10, expoMag);
    const timestamp = new Date(parseInt(priceStruct.timestamp) * 1000);
    return { price: actualPrice, confidence: actualConf, timestamp };
}

async function fetchHermesLatest(hermesUrl, priceFeedId) {
    const idNo0x = priceFeedId.startsWith('0x') ? priceFeedId.slice(2) : priceFeedId;
    const url = `${hermesUrl}/v2/updates/price/latest?ids[]=${idNo0x}`;
    const resp = await fetch(url);
    if (!resp.ok) throw new Error(`Hermes latest HTTP ${resp.status} ${resp.statusText}`);
    const data = await resp.json();
    if (!data.parsed || data.parsed.length === 0) throw new Error('Hermes latest returned no parsed data');
    const p = data.parsed[0].price;
    const value = parseInt(p.price);
    const expo = parseInt(p.expo);
    const conf = parseInt(p.conf);
    const publishTimeSec = parseInt(p.publish_time);
    const price = value * Math.pow(10, expo);
    const confidence = conf * Math.pow(10, expo);
    return { price, confidence, timestamp: new Date(publishTimeSec * 1000) };
}

async function main() {
    const rpcUrl = optEnv('SUI_RPC_URL', 'https://fullnode.testnet.sui.io:443');
    const storageId = reqEnv('PRICE_STORAGE_ID');
    const knownPriceInfoObjectId = optEnv('KNOWN_PRICE_INFO_OBJECT_ID', '');
    const hermesUrl = optEnv('HERMES_URL', 'https://hermes-beta.pyth.network');
    const priceFeedId = optEnv('PRICE_FEED_ID', '');

    const client = new SuiClient({ url: rpcUrl });
    logInfo('Reading contract storage object');
    const obj = await client.getObject({ id: storageId, options: { showContent: true } });
    if (obj.data?.content?.dataType !== 'moveObject') throw new Error('Invalid storage object');
    const f = obj.data.content.fields;

    const latestPriceStr = u256ToDecimalString(f.latest_price);
    const averagePriceStr = u256ToDecimalString(f.average_price);
    const ema120CurrentStr = u256ToDecimalString(f.ema120_current);
    const ema120PreviousStr = u256ToDecimalString(f.ema120_previous);
    const ema5CurrentStr = u256ToDecimalString(f.ema5_current);
    const ema5PreviousStr = u256ToDecimalString(f.ema5_previous);
    const historyStr = (f.price_history || []).map(u256ToDecimalString);

    console.log('===== Contract Stats (1e18 precision) =====');
    console.log(`Latest Price: ${latestPriceStr}`);
    console.log(`Average Price: ${averagePriceStr}`);
    console.log(`EMA120 Current: ${ema120CurrentStr}`);
    console.log(`EMA120 Previous: ${ema120PreviousStr}`);
    console.log(`EMA5 Current: ${ema5CurrentStr}`);
    console.log(`EMA5 Previous: ${ema5PreviousStr}`);
    console.log(`History Length: ${historyStr.length}`);
    console.log(`Max History Length: ${f.max_history_length}`);
    console.log('Last 10 Prices:', historyStr.slice(-10));

    if (knownPriceInfoObjectId) {
        try {
            logInfo('Reading on-chain Pyth price from known PriceInfoObject');
            const p = await fetchOnChainPythPrice(client, knownPriceInfoObjectId);
            if (p) {
                console.log('===== On-chain Pyth Price =====');
                console.log(`Price: ${formatPrice(p.price)}`);
                console.log(`Confidence: ${formatPrice(p.confidence)}`);
                console.log(`Timestamp: ${p.timestamp.toISOString()}`);
            }
        } catch (e) {
            logError('Failed to read on-chain Pyth price', e);
        }
    }

    if (hermesUrl && priceFeedId) {
        try {
            logInfo('Fetching latest price from Hermes');
            const h = await fetchHermesLatest(hermesUrl, priceFeedId);
            console.log('===== Hermes Latest Price =====');
            console.log(`Price: ${formatPrice(h.price)}`);
            console.log(`Confidence: ${formatPrice(h.confidence)}`);
            console.log(`Timestamp: ${h.timestamp.toISOString()}`);
        } catch (e) {
            logError('Failed to fetch Hermes latest price', e);
        }
    }
}

main().catch((e) => { logError('query-stats failed', e); process.exitCode = 1; });


