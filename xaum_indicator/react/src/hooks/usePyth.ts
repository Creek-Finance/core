import { useState, useCallback, useEffect } from 'react';
import {
    SuiPythClient
} from '@pythnetwork/pyth-sui-js';
import { SuiClient } from '@mysten/sui/client';
import { Transaction } from '@mysten/sui/transactions';
import { useCurrentAccount, useSignAndExecuteTransaction, useConnectWallet } from '@mysten/dapp-kit';
import {
    PYTH_TESTNET_STATE_ID,
    WORMHOLE_TESTNET_STATE_ID,
    HERMES_TESTNET_URL,
    SUI_USD_PRICE_FEED_ID,
    CONTRACT_PACKAGE_ID,
    PRICE_STORAGE_ID,
    CLOCK_ID,
    SUI_TESTNET_URL,
    KNOWN_PRICE_INFO_OBJECT_ID
} from '../config/constants';

export interface PriceData {
    price: number;
    confidence: number;
    timestamp: Date;
    timeDiff?: string; // Time difference from now
}

export interface OnChainPriceData {
    price: number;
    confidence: number;
    timestamp: Date;
    timeDiff?: string;
    objectId?: string;
}

export interface UpdateResult {
    success: boolean;
    digest?: string;
    error?: string;
    priceData?: PriceData;
    priceInfoObjectId?: string; // The PriceInfoObject ID created
}

export interface ContractData {
    latestPrice: number;
    priceHistory: number[];
    averagePrice: number;
    historyLength: number;
    maxHistoryLength: number;
    ema120Current: number;
    ema120Previous: number;
    ema5Current: number;
    ema5Previous: number;
    emaInitialized: boolean;
}

export const usePyth = () => {
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [priceData, setPriceData] = useState<PriceData | null>(null);
    const [onChainPriceData, setOnChainPriceData] = useState<OnChainPriceData | null>(null);
    const [lastUpdate, setLastUpdate] = useState<Date | null>(null);
    const [lastPriceInfoObjectId, setLastPriceInfoObjectId] = useState<string | null>(null);
    const [contractData, setContractData] = useState<ContractData | null>(null);

    const account = useCurrentAccount();
    const { mutateAsync: signAndExecuteTransaction } = useSignAndExecuteTransaction();
    const { mutateAsync: connectWallet } = useConnectWallet();

    // Helper function to get cached wallet info
    const getCachedWalletInfo = useCallback(() => {
        try {
            const cached = localStorage.getItem('sui_wallet_cache');
            if (cached) {
                const walletInfo = JSON.parse(cached);
                // Check if cache is not too old (7 days)
                const cacheAge = Date.now() - walletInfo.timestamp;
                if (cacheAge < 7 * 24 * 60 * 60 * 1000) {
                    return walletInfo;
                }
            }
        } catch (error) {
            console.log('Failed to read wallet cache:', error);
        }
        return null;
    }, []);

    // Helper function to cache wallet info
    const cacheWalletInfo = useCallback((walletName: string, accountAddress?: string) => {
        try {
            const walletInfo = {
                walletName,
                accountAddress,
                timestamp: Date.now()
            };
            localStorage.setItem('sui_wallet_cache', JSON.stringify(walletInfo));
            console.log('💾 Cached wallet info:', walletInfo);
        } catch (error) {
            console.log('Failed to cache wallet info:', error);
        }
    }, []);

    // Helper function to detect available wallets
    const detectAvailableWallets = useCallback(() => {
        try {
            // Check if Sui wallet is available in window object
            const availableWallets = [];

            if (typeof window !== 'undefined') {
                // Check for common Sui wallets
                if ((window as any).suiWallet) {
                    availableWallets.push('Sui Wallet');
                }
                if ((window as any).suiet) {
                    availableWallets.push('Suiet');
                }
                if ((window as any).ethos) {
                    availableWallets.push('Ethos');
                }
                if ((window as any).slush) {
                    availableWallets.push('Slush');
                }
            }

            return availableWallets;
        } catch (error) {
            console.log('Failed to detect wallets:', error);
            return [];
        }
    }, []);

    // Helper function to calculate time difference
    const calculateTimeDiff = useCallback((timestamp: Date): string => {
        const now = new Date();
        const diffMs = now.getTime() - timestamp.getTime();
        const diffMins = Math.floor(diffMs / 60000);
        const diffSecs = Math.floor((diffMs % 60000) / 1000);

        if (diffMins > 0) {
            return `${diffMins}m ${diffSecs}s ago`;
        } else {
            return `${diffSecs}s ago`;
        }
    }, []);

    // Helper function to convert u256 price to JavaScript number
    // Contract now stores prices as u256 with 18 decimal places
    const convertU256PriceToNumber = useCallback((u256Value: string): number => {
        try {
            // Handle the price in u256 format and express it to 18 decimal places
            // Use BigInt to avoid the numerical precision limitations of JavaScript
            const bigIntValue = BigInt(u256Value);
            const divisor = BigInt(10 ** 18);

            // First, multiply by 10^6 to maintain accuracy, then divide by 10^18, and finally divide by 10^6
            const scaledValue = bigIntValue * BigInt(10 ** 6);
            const dividedValue = scaledValue / divisor;

            // Convert to JavaScript number, maintaining a precision of 6 decimal places
            const result = Number(dividedValue) / (10 ** 6);

            // Handle cases of minimum values
            if (result < 0.000001 && result > 0) {
                return Number(result.toFixed(12));
            }

            return result;
        } catch (error) {
            console.error('Error converting u256 price:', error, 'Value:', u256Value);
            return 0;
        }
    }, []);

    // Helper function to trigger wallet connection (same as clicking Connect button)
    const triggerWalletConnection = useCallback(async (): Promise<boolean> => {
        if (account) {
            return true; // Already connected
        }

        try {
            console.log('🔗 No wallet connected, attempting to connect automatically...');

            // Strategy 1: Try to connect directly using the connectWallet hook
            try {
                const availableWallets = detectAvailableWallets();
                if (availableWallets.length > 0) {
                    console.log(`🔍 Detected available wallets: ${availableWallets.join(', ')}`);

                    // Try connecting to the first available wallet
                    const firstWallet = availableWallets[0];
                    console.log(`🔄 Attempting to connect with: ${firstWallet}`);

                    await connectWallet({
                        wallet: firstWallet as any
                    });

                    console.log('✅ Wallet connection successful via connectWallet hook');
                    return true;
                }
            } catch (connectError) {
                console.log('⚠️ Direct connection failed, trying alternative methods:', connectError);
            }

            // Strategy 2: If direct connection fails, prompt the user to connect manually
            console.log('💡 Automatic connection failed. Please click the "Connect" button above to connect your wallet manually.');

            // Provide more detailed guidance
            if (typeof window !== 'undefined') {
                const hasSuiWallet = !!(window as any).suiWallet;
                const hasSuiet = !!(window as any).suiet;
                const hasEthos = !!(window as any).ethos;

                if (!hasSuiWallet && !hasSuiet && !hasEthos) {
                    console.log('📱 No Sui wallet extension detected. Please install a Sui wallet extension first.');
                } else {
                    console.log('🔌 Wallet extension detected but connection failed. Try refreshing the page or reconnecting.');
                }
            }

            return false;
        } catch (error) {
            console.log('❌ Failed to trigger wallet connection:', error);
            console.log('💡 Please connect manually using the Connect button above');
            return false;
        }
    }, [account, detectAvailableWallets, connectWallet]);

    // Helper function to wait for transaction execution and verify result
    // Currently not used but kept for future transaction verification features
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const waitForTransactionExecution = useCallback(async (digest: string): Promise<boolean> => {
        try {
            console.log(`⏳ Waiting for transaction execution: ${digest}`);
            const suiClient = new SuiClient({ url: SUI_TESTNET_URL });

            // Wait for transaction to be executed
            const txResponse = await suiClient.waitForTransaction({
                digest: digest,
                timeout: 30000, // 30 seconds timeout
            });

            console.log('📋 Transaction executed:', txResponse);

            // Check if transaction was successful
            if (txResponse.effects?.status?.status === 'success') {
                console.log('✅ Transaction executed successfully');

                // In newer Sui versions, we can't easily verify object changes
                // Just return true if the transaction succeeded
                return true;
            } else {
                console.log('❌ Transaction failed:', txResponse.effects?.status);
                return false;
            }
        } catch (error) {
            console.error('❌ Error waiting for transaction execution:', error);
            return false;
        }
    }, []);

    // Initialize available PriceInfoObject ID on mount
    useEffect(() => {
        const initializePriceInfoObject = async () => {
            // Set the known PriceInfoObject ID directly
            setLastPriceInfoObjectId(KNOWN_PRICE_INFO_OBJECT_ID);
            console.log(`🚀 Initialized with known PriceInfoObject ID: ${KNOWN_PRICE_INFO_OBJECT_ID}`);

            // Detect available wallets
            const availableWallets = detectAvailableWallets();
            if (availableWallets.length > 0) {
                console.log('🔍 Detected available wallets:', availableWallets);
            }

            // Try to get cached wallet info
            try {
                const cachedWallet = getCachedWalletInfo();
                if (cachedWallet && cachedWallet.walletName !== 'unknown') {
                    console.log('🔍 Found cached wallet info:', cachedWallet);

                    // Check if the cached wallet is still available
                    if (availableWallets.includes(cachedWallet.walletName)) {
                        console.log('✅ Cached wallet is still available. You can connect manually.');
                    } else {
                        console.log('⚠️ Cached wallet is no longer available. Please connect a different wallet.');
                    }
                } else if (cachedWallet) {
                    console.log('ℹ️ Cached wallet info has unknown wallet name');
                } else {
                    console.log('ℹ️ No cached wallet info found');
                }

                // Provide helpful connection guidance
                if (availableWallets.length > 0) {
                    console.log('💡 To connect wallet, click the "Connect" button above');
                } else {
                    console.log('💡 No Sui wallets detected. Please install a Sui wallet extension first.');
                }

            } catch (error) {
                console.log('ℹ️ Error during wallet initialization:', error);
            }
        };

        initializePriceInfoObject();
    }, [getCachedWalletInfo, detectAvailableWallets]);

    // Cache wallet info when account changes
    useEffect(() => {
        if (account) {
            // Try to get wallet name from account or use a more reliable method
            let walletName = 'unknown';

            // Check if we can get wallet info from the account object
            if ((account as any).wallet?.name) {
                walletName = (account as any).wallet.name;
            } else if ((account as any).wallet?.adapter?.name) {
                walletName = (account as any).wallet.adapter.name;
            } else if ((account as any).wallet?.adapter?.wallet?.name) {
                walletName = (account as any).wallet.adapter.wallet.name;
            }

            // If still unknown, try to infer from account address pattern or other properties
            if (walletName === 'unknown') {
                // Try to detect wallet type from account properties
                const accountProps = Object.keys(account);
                console.log('🔍 Account properties:', accountProps);

                // You can add logic here to infer wallet type based on account properties
                if (accountProps.includes('wallet')) {
                    console.log('🔍 Found wallet property, attempting to extract name');
                }
            }

            cacheWalletInfo(walletName, account.address);
            console.log(`🔗 Wallet connected: ${walletName} (${account.address})`);
        }
    }, [account, cacheWalletInfo]);

    const fetchLatestPrice = useCallback(async (): Promise<PriceData | null> => {
        try {
            // Use direct fetch API instead of SuiPriceServiceConnection to avoid browser issues
            const priceIdWithout0x = SUI_USD_PRICE_FEED_ID.replace('0x', '');
            const url = `${HERMES_TESTNET_URL}/v2/updates/price/latest?ids[]=${priceIdWithout0x}`;

            console.log('Fetching price from:', url);
            const response = await fetch(url);

            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }

            const data = await response.json();
            console.log('Received price data:', data);

            if (data.parsed && data.parsed.length > 0) {
                const priceInfo = data.parsed[0];
                const price = priceInfo.price;

                // Convert price with exponent
                const priceValue = parseInt(price.price);
                const exponent = parseInt(price.expo);
                const actualPrice = priceValue * Math.pow(10, exponent);

                // Convert confidence with same exponent
                const confidenceValue = parseInt(price.conf);
                const actualConfidence = confidenceValue * Math.pow(10, exponent);

                // Convert timestamp from seconds to milliseconds
                const timestamp = new Date(parseInt(price.publish_time) * 1000);

                const priceData: PriceData = {
                    price: actualPrice,
                    confidence: actualConfidence,
                    timestamp: timestamp,
                    timeDiff: calculateTimeDiff(timestamp)
                };

                console.log('Parsed price data:', priceData);
                setPriceData(priceData);
                return priceData;
            } else {
                throw new Error('No price data in response');
            }

        } catch (error) {
            console.error('Error fetching Pyth price:', error);

            // Return null when no data available
            setPriceData(null);
            console.log('No price data available');
            return null;
        }
    }, [calculateTimeDiff]);

    // Fetch on-chain Pyth price (read-only, no transaction)
    const fetchOnChainPrice = useCallback(async (priceInfoObjectId?: string): Promise<OnChainPriceData | null> => {
        const objectId = priceInfoObjectId || lastPriceInfoObjectId;
        if (!objectId) {
            console.log('No PriceInfoObject ID available for on-chain price fetch');
            setOnChainPriceData(null);
            return null;
        }

        try {
            console.log(`Fetching on-chain price from PriceInfoObject: ${objectId}`);
            const suiClient = new SuiClient({ url: SUI_TESTNET_URL });

            // Fetch the PriceInfoObject
            const priceObject = await suiClient.getObject({
                id: objectId,
                options: {
                    showContent: true,
                },
            });

            if (priceObject.data?.content?.dataType === "moveObject") {
                const fields = (priceObject.data.content as any).fields;

                // Parse price feed data from the actual Pyth structure
                if (fields && fields.price_info && fields.price_info.fields) {
                    const priceInfo = fields.price_info.fields;

                    // Navigate to the price feed
                    if (priceInfo.price_feed && priceInfo.price_feed.fields) {
                        const priceFeed = priceInfo.price_feed.fields;

                        // Get the current price (not ema_price)
                        if (priceFeed.price && priceFeed.price.fields) {
                            const price = priceFeed.price.fields;

                            // Parse price value
                            const priceValue = parseInt(price.price.fields.magnitude);
                            const priceNegative = price.price.fields.negative;

                            // Parse exponent
                            const expoValue = parseInt(price.expo.fields.magnitude);
                            const expoNegative = price.expo.fields.negative;

                            // Calculate actual price
                            let actualPrice = priceValue;
                            if (expoNegative) {
                                // Negative exponent means divide
                                actualPrice = priceValue / Math.pow(10, expoValue);
                            } else {
                                // Positive exponent means multiply
                                actualPrice = priceValue * Math.pow(10, expoValue);
                            }
                            if (priceNegative) actualPrice = -actualPrice;

                            // Parse confidence
                            const confValue = parseInt(price.conf);
                            let actualConf = confValue;
                            if (expoNegative) {
                                actualConf = confValue / Math.pow(10, expoValue);
                            } else {
                                actualConf = confValue * Math.pow(10, expoValue);
                            }

                            // Parse timestamp
                            const timestamp = new Date(parseInt(price.timestamp) * 1000);

                            const onChainData: OnChainPriceData = {
                                price: actualPrice,
                                confidence: actualConf,
                                timestamp: timestamp,
                                timeDiff: calculateTimeDiff(timestamp),
                                objectId: objectId
                            };

                            console.log('On-chain price data:', onChainData);
                            setOnChainPriceData(onChainData);
                            return onChainData;
                        }
                    }
                }
            }

            console.log('Could not parse on-chain price data');
            return null;

        } catch (error) {
            console.error('Error fetching on-chain price:', error);
            // Don't set error state as this is a secondary feature
            return null;
        }
    }, [lastPriceInfoObjectId, calculateTimeDiff]);

    // Step 1: Update Pyth Oracle price and get PriceInfoObject
    const updatePythOracle = useCallback(async (): Promise<UpdateResult> => {
        if (!account) {
            console.log('🔗 No wallet connected, triggering wallet connection...');
            try {
                const connected = await triggerWalletConnection();
                if (!connected) {
                    return {
                        success: false,
                        error: 'Failed to trigger wallet connection. Please connect manually using the Connect button.'
                    };
                }
                // Wait a bit for the wallet connection to be established
                await new Promise(resolve => setTimeout(resolve, 1000));
            } catch (error) {
                console.error('❌ Failed to trigger wallet connection:', error);
                return {
                    success: false,
                    error: 'Failed to trigger wallet connection. Please connect manually using the Connect button.'
                };
            }
        }

        setLoading(true);
        setError(null);

        try {
            console.log('=== Step 1: Updating Pyth Oracle Price ===');

            // Setup clients
            const suiClient = new SuiClient({ url: SUI_TESTNET_URL });
            const pythClient = new SuiPythClient(
                suiClient,
                PYTH_TESTNET_STATE_ID,
                WORMHOLE_TESTNET_STATE_ID
            );

            // Get price update data
            console.log('Fetching VAA from Hermes...');
            const priceIds = [SUI_USD_PRICE_FEED_ID];
            const priceId = SUI_USD_PRICE_FEED_ID.replace('0x', '');
            const url = `${HERMES_TESTNET_URL}/api/latest_vaas?ids[]=${priceId}`;

            const response = await fetch(url);
            if (!response.ok) {
                throw new Error(`Failed to fetch VAA: ${response.status} - ${response.statusText}`);
            }

            const vaaArray = await response.json();
            if (!vaaArray || vaaArray.length === 0) {
                throw new Error('No VAA data received from Hermes. Please try again later.');
            }

            // Convert base64 VAA to Buffer
            const vaaBase64 = vaaArray[0];
            console.log(`Received VAA data (base64 length: ${vaaBase64.length})`);

            const Buffer = (window as any).Buffer;
            if (!Buffer) {
                throw new Error('Buffer not available. Please ensure you are using a modern browser.');
            }

            const vaaBuffer = Buffer.from(vaaBase64, 'base64');
            console.log(`Converted to Buffer (length: ${vaaBuffer.length})`);

            // Create transaction for Pyth update only
            const tx = new Transaction();
            console.log('Creating Pyth price update transaction...');

            const priceInfoObjectIds = await pythClient.updatePriceFeeds(
                tx,
                [vaaBuffer],
                priceIds
            );

            if (!priceInfoObjectIds || priceInfoObjectIds.length === 0) {
                throw new Error('Failed to get price info object IDs from Pyth client.');
            }

            const suiPriceInfoObjectId = priceInfoObjectIds[0] as any;
            console.log(`✅ Price Info Object ID: ${suiPriceInfoObjectId}`);
            console.log(`📋 You can use this ID for contract calls`);

            // Store the ID for display
            setLastPriceInfoObjectId(suiPriceInfoObjectId.toString());

            tx.setGasBudget(100000000);

            // Execute transaction
            console.log('Executing Pyth update transaction...');
            const result = await signAndExecuteTransaction({
                transaction: tx
            });

            console.log('✅ Pyth Oracle updated successfully!');
            console.log(`Transaction digest: ${result.digest}`);
            setLastUpdate(new Date());

            // Wait for transaction execution and verify result
            console.log('⏳ Waiting for transaction execution...');
            const executionSuccess = await waitForTransactionExecution(result.digest);
            if (!executionSuccess) {
                console.warn('⚠️ Transaction execution verification failed, but continuing...');
            }

            // Fetch latest price after update
            await fetchLatestPrice();

            return {
                success: true,
                digest: result.digest,
                priceInfoObjectId: suiPriceInfoObjectId.toString()
            };

        } catch (err: any) {
            console.error('Error updating Pyth Oracle:', err);
            let errorMessage = 'Failed to update Pyth Oracle';

            // Provide more specific error messages
            if (err.message?.includes('VAA')) {
                errorMessage = 'Failed to fetch price data from Hermes. Please check your internet connection and try again.';
            } else if (err.message?.includes('Buffer')) {
                errorMessage = 'Browser compatibility issue. Please use a modern browser.';
            } else if (err.message?.includes('transaction')) {
                errorMessage = 'Transaction failed. Please check your wallet balance and try again.';
            } else if (err.message) {
                errorMessage = err.message;
            }

            setError(errorMessage);
            return {
                success: false,
                error: errorMessage
            };
        } finally {
            setLoading(false);
        }
    }, [account, signAndExecuteTransaction, fetchLatestPrice, triggerWalletConnection, waitForTransactionExecution]);

    // Step 2: Call contract with existing PriceInfoObject
    const callContract = useCallback(async (priceInfoObjectId?: string): Promise<UpdateResult> => {
        if (!account) {
            console.log('🔗 No wallet connected, triggering wallet connection...');
            try {
                const connected = await triggerWalletConnection();
                if (!connected) {
                    return {
                        success: false,
                        error: 'Failed to trigger wallet connection. Please connect manually using the Connect button.'
                    };
                }
                // Wait a bit for the wallet connection to be established
                await new Promise(resolve => setTimeout(resolve, 1000));
            } catch (error) {
                console.error('❌ Failed to trigger wallet connection:', error);
                return {
                    success: false,
                    error: 'Failed to trigger wallet connection. Please connect manually using the Connect button.'
                };
            }
        }

        // Use provided ID or last stored ID
        const objectId = priceInfoObjectId || lastPriceInfoObjectId;
        if (!objectId) {
            return {
                success: false,
                error: 'No PriceInfoObject ID available. Please update Pyth Oracle first.'
            };
        }

        setLoading(true);
        setError(null);

        try {
            console.log('=== Step 2: Calling Contract ===');
            console.log('Contract call parameters:');
            console.log(`  - Package ID: ${CONTRACT_PACKAGE_ID}`);
            console.log(`  - Module: xaum_indiactor`);
            console.log(`  - Function: update_sui_price`);
            console.log(`  - Arguments:`);
            console.log(`    1. PriceStorage: ${PRICE_STORAGE_ID} (shared object storing price history)`);
            console.log(`    2. PriceInfoObject: ${objectId} (Pyth oracle price object)`);
            console.log(`    3. Clock: ${CLOCK_ID} (system clock for timestamp validation)`);

            const tx = new Transaction();

            // Call our contract
            (tx as any).moveCall({
                target: `${CONTRACT_PACKAGE_ID}::xaum_indiactor::update_sui_price`,
                arguments: [
                    tx.object(PRICE_STORAGE_ID),
                    tx.object(objectId),
                    tx.object(CLOCK_ID),
                ],
            });

            tx.setGasBudget(100000000);

            console.log('Executing contract call transaction...');
            const result = await signAndExecuteTransaction({
                transaction: tx
            });

            console.log('✅ Contract updated successfully!');
            console.log(`Transaction digest: ${result.digest}`);
            setLastUpdate(new Date());

            // Wait for transaction execution and verify result
            console.log('⏳ Waiting for transaction execution...');
            const executionSuccess = await waitForTransactionExecution(result.digest);
            if (!executionSuccess) {
                console.warn('⚠️ Transaction execution verification failed, but continuing...');
            }

            return {
                success: true,
                digest: result.digest
            };

        } catch (err: any) {
            console.error('Error calling contract:', err);
            let errorMessage = 'Failed to call contract';

            // Provide more specific error messages
            if (err.message?.includes('insufficient')) {
                errorMessage = 'Insufficient gas balance. Please ensure your wallet has enough SUI for gas fees.';
            } else if (err.message?.includes('object')) {
                errorMessage = 'Contract object not found. Please check if the contract is properly deployed.';
            } else if (err.message?.includes('permission')) {
                errorMessage = 'Permission denied. Please check your wallet connection and try again.';
            } else if (err.message) {
                errorMessage = err.message;
            }

            setError(errorMessage);
            return {
                success: false,
                error: errorMessage
            };
        } finally {
            setLoading(false);
        }
    }, [account, lastPriceInfoObjectId, signAndExecuteTransaction, waitForTransactionExecution, triggerWalletConnection]);

    // Call contract without clock validation (using update_sui_price_without_clock)
    const callContractWithoutClock = useCallback(async (priceInfoObjectId?: string): Promise<UpdateResult> => {
        if (!account) {
            console.log('🔗 No wallet connected, triggering wallet connection...');
            try {
                const connected = await triggerWalletConnection();
                if (!connected) {
                    return {
                        success: false,
                        error: 'Failed to trigger wallet connection. Please connect manually using the Connect button.'
                    };
                }
                // Wait a bit for the wallet connection to be established
                await new Promise(resolve => setTimeout(resolve, 1000));
            } catch (error) {
                console.error('❌ Failed to trigger wallet connection:', error);
                return {
                    success: false,
                    error: 'Failed to trigger wallet connection. Please connect manually using the Connect button.'
                };
            }
        }

        // Use provided ID or last stored ID
        const objectId = priceInfoObjectId || lastPriceInfoObjectId;
        if (!objectId) {
            return {
                success: false,
                error: 'No PriceInfoObject ID available. Please update Pyth Oracle first or wait for initialization.'
            };
        }

        setLoading(true);
        setError(null);

        try {
            console.log('=== Calling Contract Without Clock Validation ===');
            console.log('Contract call parameters:');
            console.log(`  - Package ID: ${CONTRACT_PACKAGE_ID}`);
            console.log(`  - Module: xaum_indiactor`);
            console.log(`  - Function: update_sui_price_without_clock`);
            console.log(`  - Arguments:`);
            console.log(`    1. PriceStorage: ${PRICE_STORAGE_ID} (shared object storing price history)`);
            console.log(`    2. PriceInfoObject: ${objectId} (Pyth oracle price object)`);
            console.log(`  - Note: No clock validation - may use older prices`);

            const tx = new Transaction();

            // Call our contract without clock validation
            (tx as any).moveCall({
                target: `${CONTRACT_PACKAGE_ID}::xaum_indiactor::update_sui_price_without_clock`,
                arguments: [
                    tx.object(PRICE_STORAGE_ID),
                    tx.object(objectId),
                ],
            });

            tx.setGasBudget(100000000);

            console.log('Executing contract call without clock validation...');
            const result = await signAndExecuteTransaction({
                transaction: tx
            });

            console.log('✅ Contract updated without clock validation successfully!');
            console.log(`Transaction digest: ${result.digest}`);
            setLastUpdate(new Date());

            // Wait for transaction execution and verify result
            console.log('⏳ Waiting for transaction execution...');
            const executionSuccess = await waitForTransactionExecution(result.digest);
            if (!executionSuccess) {
                console.warn('⚠️ Transaction execution verification failed, but continuing...');
            }

            return {
                success: true,
                digest: result.digest
            };

        } catch (err: any) {
            console.error('Error calling contract without clock validation:', err);
            let errorMessage = 'Failed to call contract without clock validation';

            // Provide more specific error messages
            if (err.message?.includes('insufficient')) {
                errorMessage = 'Insufficient gas balance. Please ensure your wallet has enough SUI for gas fees.';
            } else if (err.message?.includes('object')) {
                errorMessage = 'Contract object not found. Please check if the contract is properly deployed.';
            } else if (err.message?.includes('permission')) {
                errorMessage = 'Permission denied. Please check your wallet connection and try again.';
            } else if (err.message) {
                errorMessage = err.message;
            }

            setError(errorMessage);
            return {
                success: false,
                error: errorMessage
            };
        } finally {
            setLoading(false);
        }
    }, [account, signAndExecuteTransaction, lastPriceInfoObjectId, triggerWalletConnection, waitForTransactionExecution]);

    // Combined function for full update flow
    const updatePriceOnChain = useCallback(async (): Promise<UpdateResult> => {
        console.log('=== Starting Full Price Update Flow ===');

        // Step 1: Update Pyth Oracle
        const pythResult = await updatePythOracle();
        if (!pythResult.success) {
            return pythResult;
        }

        // Step 2: Call contract with the new PriceInfoObject
        const contractResult = await callContract(pythResult.priceInfoObjectId);
        return contractResult;
    }, [updatePythOracle, callContract]);

    // A function for reading contract data
    const readContractData = useCallback(async (): Promise<ContractData | null> => {
        try {
            console.log('Reading contract data...');
            const suiClient = new SuiClient({ url: SUI_TESTNET_URL });

            const object = await suiClient.getObject({
                id: PRICE_STORAGE_ID,
                options: { showContent: true }
            });

            if (object.data?.content?.dataType === "moveObject") {
                const fields = (object.data.content as any).fields;

                // Add debugging information
                console.log('Raw contract fields:', fields);
                console.log('Raw latest_price:', fields.latest_price);
                console.log('Raw average_price:', fields.average_price);
                console.log('Raw ema120_current:', fields.ema120_current);
                console.log('Raw ema5_current:', fields.ema5_current);

                // Parse the price data (currently stored are u256 values, expressed as 18 decimal places)
                const rawLatestPrice = fields.latest_price;
                const rawAveragePrice = fields.average_price;
                const maxHistoryLength = parseInt(fields.max_history_length);

                // The price for converting to u256 format using auxiliary functions
                const latestPrice = convertU256PriceToNumber(rawLatestPrice);
                const averagePrice = convertU256PriceToNumber(rawAveragePrice);

                // Parse the price history array
                const priceHistory = fields.price_history.map((price: any) => {
                    const convertedPrice = convertU256PriceToNumber(price);
                    console.log(`Raw history price: ${price} -> Converted: ${convertedPrice}`);
                    return convertedPrice;
                });
                const historyLength = priceHistory.length;

                // Read the EMA value (also in u256 format, expressed as 18 decimal places)
                const ema120Current = convertU256PriceToNumber(fields.ema120_current);
                const ema120Previous = convertU256PriceToNumber(fields.ema120_previous);
                const ema5Current = convertU256PriceToNumber(fields.ema5_current);
                const ema5Previous = convertU256PriceToNumber(fields.ema5_previous);
                const emaInitialized = fields.ema_initialized;

                // Add detailed debugging information
                console.log('=== Price Conversion Debug Info ===');
                console.log(`Raw latest price (u256): ${rawLatestPrice}`);
                console.log(`Converted latest price: ${latestPrice}`);
                console.log(`Raw average price (u256): ${rawAveragePrice}`);
                console.log(`Converted average price: ${averagePrice}`);
                console.log(`Raw ema120_current (u256): ${fields.ema120_current}`);
                console.log(`Converted ema120_current: ${ema120Current}`);
                console.log(`Raw ema5_current (u256): ${fields.ema5_current}`);
                console.log(`Converted ema5_current: ${ema5Current}`);
                console.log(`Division factor: 10^18 (u256 with 18 decimal places)`);
                console.log(`Note: Contract stores all prices as u256 with 18 decimal precision`);
                console.log(`EMA calculation: EMA(t) = α × Price(t) + (1-α) × EMA(t-1)`);
                console.log(`Where α = 2/(N+1), N=120 for EMA120, N=5 for EMA5`);

                const data: ContractData = {
                    latestPrice,
                    priceHistory,
                    averagePrice,
                    historyLength,
                    maxHistoryLength,
                    ema120Current,
                    ema120Previous,
                    ema5Current,
                    ema5Previous,
                    emaInitialized
                };

                console.log('Contract data read successfully:', data);
                setContractData(data);
                return data;
            } else {
                throw new Error('Invalid object data type');
            }
        } catch (error) {
            console.error('Error reading contract data:', error);
            setError(`Failed to read contract data: ${error}`);
            return null;
        }
    }, [convertU256PriceToNumber]);

    // Get the latest prices
    const getLatestPrice = useCallback(async (): Promise<number | null> => {
        const data = await readContractData();
        return data?.latestPrice || null;
    }, [readContractData]);

    // Get the price history
    const getPriceHistory = useCallback(async (): Promise<number[] | null> => {
        const data = await readContractData();
        return data?.priceHistory || null;
    }, [readContractData]);

    // Obtain the average price
    const getAveragePrice = useCallback(async (): Promise<number | null> => {
        const data = await readContractData();
        return data?.averagePrice || null;
    }, [readContractData]);

    // Obtain the historical length
    const getHistoryLength = useCallback(async (): Promise<number | null> => {
        const data = await readContractData();
        return data?.historyLength || null;
    }, [readContractData]);

    // Get the maximum historical length
    const getMaxHistoryLength = useCallback(async (): Promise<number | null> => {
        const data = await readContractData();
        return data?.maxHistoryLength || null;
    }, [readContractData]);

    return {
        // State
        loading,
        error,
        priceData,
        onChainPriceData,
        lastUpdate,
        lastPriceInfoObjectId,
        contractData,

        // Actions
        fetchLatestPrice,
        fetchOnChainPrice,     // New: Fetch on-chain price
        updatePythOracle,      // New: Just update Pyth
        callContract,          // New: Just call contract
        callContractWithoutClock, // New: Call contract without clock validation
        updatePriceOnChain,    // Combined: Both steps
        readContractData,
        getLatestPrice,
        getPriceHistory,
        getAveragePrice,
        getHistoryLength,
        getMaxHistoryLength,
    };
};