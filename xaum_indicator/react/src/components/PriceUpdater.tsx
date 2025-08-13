import React, { useEffect } from 'react';
import { usePyth } from '../hooks/usePyth';
import { useCurrentAccount, ConnectButton } from '@mysten/dapp-kit';
import '../PriceUpdater.css';

const PriceUpdater: React.FC = () => {
    const account = useCurrentAccount();
    const {
        loading, error, priceData, onChainPriceData, lastUpdate, lastPriceInfoObjectId, contractData,
        fetchLatestPrice, fetchOnChainPrice, updatePythOracle, callContract, callContractWithoutClock, updatePriceOnChain,
        readContractData,
    } = usePyth();

    useEffect(() => {
        // Do not auto-fetch on mount - wait for manual refresh
    }, []);

    const handleRefreshHermesPrice = async () => {
        await fetchLatestPrice();
    };

    const handleRefreshOnChainPrice = async () => {
        if (lastPriceInfoObjectId) {
            await fetchOnChainPrice();
        } else {
            alert('No PriceInfoObject ID available. Please update Pyth Oracle first.');
        }
    };

    const handleUpdatePythOracle = async () => {
        const result = await updatePythOracle();
        if (result.success) {
            await fetchOnChainPrice(result.priceInfoObjectId); // Fetch the new on-chain price
        } else {
            alert(`Failed to update Pyth Oracle: ${result.error}`);
        }
    };

    const handleCallContract = async () => {
        const result = await callContract();
        if (result.success) {
            // The latest data is automatically read after the contract is called
            await readContractData();
        } else {
            alert(`Failed to call contract: ${result.error}`);
        }
    };

    const handleCallContractWithoutClock = async () => {
        const result = await callContractWithoutClock();
        if (result.success) {
            await readContractData();
        } else {
            alert(`Failed to call contract without clock: ${result.error}`);
        }
    };

    const handleFullUpdate = async () => {
        const result = await updatePriceOnChain();
        if (result.success) {
            await fetchOnChainPrice(result.priceInfoObjectId);
            await readContractData();
        } else {
            alert(`Failed to complete full update: ${result.error}`);
        }
    };

    const handleReadContractData = async () => {
        await readContractData();
    };

    const formatPrice = (price: number) => {
        // Handle the price in u256 format and express it to 18 decimal places
        // Select the appropriate precision display according to the price size
        if (price < 0.000001) {
            return `$${price.toFixed(12)}`; // 极小价格显示更多小数位
        } else if (price < 0.01) {
            return `$${price.toFixed(8)}`; // 小价格显示 8 位小数
        } else if (price < 1) {
            return `$${price.toFixed(6)}`; // 小于 1 的价格显示 6 位小数
        } else if (price < 100) {
            return `$${price.toFixed(4)}`; // 正常价格显示 4 位小数
        } else {
            return `$${price.toFixed(2)}`; // 大价格显示 2 位小数
        }
    };

    const formatEMAValue = (emaValue: number, period: string) => {
        // The EMA value usually requires higher precision display
        if (emaValue < 0.000001) {
            return `$${emaValue.toFixed(12)}`;
        } else if (emaValue < 0.01) {
            return `$${emaValue.toFixed(8)}`;
        } else if (emaValue < 1) {
            return `$${emaValue.toFixed(6)}`;
        } else {
            return `$${emaValue.toFixed(4)}`;
        }
    };

    return (
        <div className="price-updater-container">
            {/* Wallet Connection */}
            <div className="wallet-section">
                <h2>🔗 Wallet Connection</h2>
                <ConnectButton />
                {account && <p>Connected: {account.address}</p>}
            </div>

            {/* Status Indicator */}
            <div className="status-indicator">
                <div className="status-item">
                    <span className="status-label">Wallet:</span>
                    <span className={`status-value ${account ? 'connected' : 'disconnected'}`}>
                        {account ? '✅ Connected' : '❌ Disconnected'}
                    </span>
                </div>
                <div className="status-item">
                    <span className="status-label">Pyth Oracle:</span>
                    <span className={`status-value ${lastPriceInfoObjectId ? 'ready' : 'pending'}`}>
                        {lastPriceInfoObjectId ? '✅ Ready' : '⏳ Pending'}
                    </span>
                </div>
                <div className="status-item">
                    <span className="status-label">Contract:</span>
                    <span className={`status-value ${contractData ? 'loaded' : 'not-loaded'}`}>
                        {contractData ? '✅ Loaded' : '📋 Not Loaded'}
                    </span>
                </div>
                {loading && (
                    <div className="status-item loading">
                        <span className="status-label">Status:</span>
                        <span className="status-value">🔄 Processing...</span>
                    </div>
                )}
            </div>

            {/* Error Display */}
            {error && (
                <div className="error-display">
                    <h3>❌ Error</h3>
                    <p>{error}</p>
                </div>
            )}

            {/* Price Display - Two Sources */}
            <div className="price-display-container">
                {/* Hermes API Price */}
                <div className="price-display hermes-price">
                    <h3>🌐 Hermes API Price (Latest)</h3>
                    <button onClick={handleRefreshHermesPrice} disabled={loading} className="btn-refresh-small">
                        🔄 Refresh Hermes
                    </button>
                    {priceData ? (
                        <div className="price-info">
                            <p><strong>Price:</strong> {formatPrice(priceData.price)}</p>
                            <p><strong>Confidence:</strong> {formatPrice(priceData.confidence)}</p>
                            <p><strong>Timestamp:</strong> {priceData.timestamp.toLocaleString()}</p>
                            {priceData.timeDiff && <p><strong>Age:</strong> {priceData.timeDiff}</p>}
                        </div>
                    ) : (
                        <div className="no-price">
                            <p>No price data available</p>
                            <p className="hint">Click refresh button above</p>
                        </div>
                    )}
                </div>

                {/* On-Chain Pyth Price */}
                <div className="price-display onchain-price">
                    <h3>⛓️ On-Chain Pyth Price</h3>
                    <button onClick={handleRefreshOnChainPrice} disabled={loading || !lastPriceInfoObjectId} className="btn-refresh-small">
                        🔄 Refresh On-Chain
                    </button>
                    {onChainPriceData ? (
                        <div className="price-info">
                            <p><strong>Price:</strong> {formatPrice(onChainPriceData.price)}</p>
                            <p><strong>Confidence:</strong> {formatPrice(onChainPriceData.confidence)}</p>
                            <p><strong>Timestamp:</strong> {onChainPriceData.timestamp.toLocaleString()}</p>
                            {onChainPriceData.timeDiff && <p><strong>Age:</strong> {onChainPriceData.timeDiff}</p>}
                            {onChainPriceData.objectId && <p><strong>Object ID:</strong> <code>{onChainPriceData.objectId}</code></p>}
                        </div>
                    ) : (
                        <div className="no-price">
                            <p>No on-chain price available</p>
                            <p className="hint">{lastPriceInfoObjectId ? 'Click refresh button above' : 'Update Pyth Oracle first'}</p>
                        </div>
                    )}
                </div>
            </div>

            {/* Contract Data Display */}
            <div className="contract-data-section">
                <h3>📊 Contract Data</h3>
                <button onClick={handleReadContractData} disabled={loading} className="btn-read-contract">
                    📖 Read Contract Data
                </button>

                {contractData ? (
                    <div className="contract-data">
                        <div className="data-row">
                            <div className="data-item">
                                <strong>Latest Price:</strong> {formatPrice(contractData.latestPrice)}
                            </div>
                            <div className="data-item">
                                <strong>Average Price:</strong> {formatPrice(contractData.averagePrice)}
                            </div>
                        </div>
                        <div className="data-row">
                            <div className="data-item">
                                <strong>History Length:</strong> {contractData.historyLength} / {contractData.maxHistoryLength}
                            </div>
                        </div>
                        <div className="data-row">
                            <div className="data-item">
                                <strong>EMA120 Current:</strong> {formatEMAValue(contractData.ema120Current, '120')}
                            </div>
                            <div className="data-item">
                                <strong>EMA120 Previous:</strong> {formatEMAValue(contractData.ema120Previous, '120')}
                            </div>
                        </div>
                        <div className="data-row">
                            <div className="data-item">
                                <strong>EMA5 Current:</strong> {formatEMAValue(contractData.ema5Current, '5')}
                            </div>
                            <div className="data-item">
                                <strong>EMA5 Previous:</strong> {formatEMAValue(contractData.ema5Previous, '5')}
                            </div>
                        </div>
                        <div className="data-row">
                            <div className="data-item">
                                <strong>EMA Initialized:</strong> {contractData.emaInitialized ? '✅ Yes' : '❌ No'}
                            </div>
                        </div>
                        {contractData.emaInitialized && (
                            <div className="ema-info">
                                <p className="hint">
                                    📊 <strong>EMA Calculation:</strong> EMA(t) = α × Price(t) + (1-α) × EMA(t-1)<br />
                                    📈 <strong>EMA120:</strong> α = 2/(120+1) ≈ 0.0165 (Long-term trend)<br />
                                    📉 <strong>EMA5:</strong> α = 2/(5+1) ≈ 0.3333 (Short-term trend)
                                </p>
                            </div>
                        )}
                        <div className="price-history">
                            <strong>Price History (Last 10):</strong>
                            <div className="history-grid">
                                {contractData.priceHistory.slice(-10).map((price, index) => (
                                    <div key={index} className="history-item">
                                        {formatPrice(price)}
                                    </div>
                                ))}
                            </div>
                        </div>
                    </div>
                ) : (
                    <div className="no-contract-data">
                        <p>No contract data available</p>
                        <p className="hint">Click "Read Contract Data" button above</p>
                    </div>
                )}
            </div>

            {/* Price Info Object ID Display */}
            {lastPriceInfoObjectId && (
                <div className="object-id-display">
                    <h4>📋 Last Price Info Object ID</h4>
                    <code className="object-id">{lastPriceInfoObjectId}</code>
                    <p className="hint">Use this ID for manual contract calls</p>
                </div>
            )}

            {/* Action Buttons */}
            <div className="actions">
                <h3>🎮 Actions</h3>

                {/* 流程说明 */}
                <div className="flow-explanation">
                    <h4>📋 How It Works</h4>
                    <div className="flow-steps">
                        <div className="step">
                            <span className="step-number">1</span>
                            <span className="step-text">Update Pyth Oracle: Fetches latest price from Hermes and creates a PriceInfoObject on-chain</span>
                        </div>
                        <div className="step">
                            <span className="step-number">2</span>
                            <span className="step-text">Call Contract: Updates your contract with the latest price, calculates EMA values, and stores price history</span>
                        </div>
                    </div>
                    <p className="hint">💡 You can do these steps separately or use the "Full Update" button for both steps at once.</p>
                </div>

                <div className="two-step-process">
                    <h4>Two-Step Process (Separate)</h4>
                    <button onClick={handleUpdatePythOracle} disabled={loading} className="btn-pyth">
                        1️⃣ Update Pyth Oracle Only
                    </button>
                    <button onClick={handleCallContract} disabled={loading || !lastPriceInfoObjectId} className="btn-contract">
                        2️⃣ Call Contract Only
                    </button>
                </div>
                <div className="separator"></div>
                <div className="two-step-process">
                    <h4>Alternative Contract Call (No Clock Validation)</h4>
                    <button onClick={handleCallContractWithoutClock} disabled={loading || !lastPriceInfoObjectId} className="btn-contract-no-clock">
                        ⏰ Call Contract Without Clock Validation
                    </button>
                    <p className="hint">⚠️ This may use older Pyth prices (no 60-second freshness check)</p>
                </div>
                <div className="separator"></div>
                <button onClick={handleFullUpdate} disabled={loading} className="btn-full-update">
                    🚀 Full Update (Pyth + Contract)
                </button>
            </div>

            {/* Last Update Time */}
            {lastUpdate && (
                <div className="last-update">
                    <p><strong>Last Update:</strong> {lastUpdate.toLocaleString()}</p>
                </div>
            )}
        </div>
    );
};

export default PriceUpdater;