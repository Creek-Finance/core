# Creek Protocol

Creek Protocol is a comprehensive DeFi lending and staking protocol built on the Sui blockchain. It provides users with the ability to deposit collateral, borrow stablecoins, stake XAUM tokens for rewards, and access flash loans.

## 🏗️ Architecture Overview

The protocol consists of several key components:

- **Core Protocol**: Main lending and borrowing functionality
- **Coin System**: Custom tokens (GR, GY, GUSD) with specific roles
- **Oracle System**: Multi-source price feeds with XAUM integration
- **Staking System**: XAUM staking for GR and GY token rewards
- **Libraries**: Shared utilities for math, decimals, and data structures

## 🪙 Token System

### GR Token (Governance Rights)
- **Purpose**: Governance token earned through XAUM staking
- **Supply**: Dynamic supply controlled by StakingManager
- **Decimals**: 9
- **Minting**: Only through XAUM staking

### GY Token (Yield Share)
- **Purpose**: Yield token representing share of staking rewards
- **Supply**: Dynamic supply controlled by StakingManager
- **Decimals**: 9
- **Minting**: Only through XAUM staking

### GUSD Token (Stablecoin)
- **Purpose**: Protocol's native stablecoin for borrowing
- **Supply**: Dynamic supply controlled by Market
- **Decimals**: 9
- **Minting**: Through borrowing against collateral
- **Collateralization**: Backed by GR tokens and other assets

## 🏦 Core Features

### 1. Lending & Borrowing

#### Deposit Collateral
- Users can deposit various supported assets as collateral
- Collateral is stored in user-specific obligations
- Each collateral type has specific risk parameters

#### Borrow GUSD
- Users can borrow GUSD against their collateral
- Borrowing is subject to collateralization ratios and limits
- Interest accrues on borrowed amounts
- Only GUSD can be borrowed (single-borrow model)

#### Repay Loans
- Users can repay borrowed amounts plus accrued interest
- Partial repayments are supported
- Interest is calculated using dynamic interest models

#### Withdraw Collateral
- Users can withdraw collateral as long as health factor remains > 1
- Withdrawal amounts are limited by risk parameters
- Automatic health checks prevent over-withdrawal

### 2. Staking System

#### XAUM Staking
- Stake XAUM tokens to earn GR and GY tokens
- Fixed exchange rate: 1 XAUM = 100 GR + 100 GY
- Minimum stake amount: 0.001 XAUM
- Staking and unstaking fees are configurable

#### Staking Manager
- Centralized management of staking operations
- Controls GR and GY token supplies
- Manages XAUM pool and fee collection
- Admin-controlled fee rates

### 3. Oracle System

#### Multi-Source Price Feeds
- Primary and secondary price feed validation
- Support for multiple oracle providers:
  - Pyth Network
  - Supra Oracle
  - Switchboard
  - Manual rules
- Price validation with 1% tolerance between sources

#### XAUM Integration
- Special pricing logic for XAUM-based assets
- EMA (Exponential Moving Average) calculations
- GR token pricing based on XAUM indicators
- Cached price computations for efficiency

### 4. Flash Loans
- Borrow assets without collateral for single transaction
- Must be repaid in the same transaction
- Fee-based system (configurable rates)
- Single transaction cap: 50,000 GUSD (configurable)

### 5. Liquidation System
- Soft liquidation mechanism
- Liquidators can repay debt and receive collateral
- Liquidation amounts calculated to restore health factor to 1
- Liquidation penalties and discounts are configurable

## 🔧 Technical Components

### Market Management
- Central market object managing all protocol state
- Dynamic interest rate models
- Risk parameter management
- Asset activation controls
- Pause/unpause functionality

### Obligation System
- User-specific debt and collateral tracking
- Health factor calculations
- Interest accrual
- Lock/unlock mechanisms for atomic operations

### Risk Management
- Collateral factors (max 95%)
- Liquidation factors and penalties
- Isolated asset support
- Dynamic risk parameter updates with governance delays

### Interest Models
- Utilization-based rates
- Configurable parameters
- Time-based accrual

## 📊 Key Parameters

### Staking
- Exchange Rate: 1 XAUM = 100 GR + 100 GY
- Minimum Stake: 0.001 XAUM
- Fee Structure: Configurable staking/unstaking fees

### Lending
- Collateral Factor: Up to 95%
- Liquidation Factor: Up to 95%
- Liquidation Penalty: Up to 20%
- Flash Loan Fee: 0.1%

### Oracle
- Price Validation: 1% tolerance
- Update Frequency: Real-time with staleness checks
- Decimal Precision: 9 decimals for all prices

## 🚀 Deployment
1. Deploy coin contracts (GR, GY, GUSD)
2. Deploy oracle system
3. Deploy core protocol
4. Initialize market and staking manager
5. Configure risk parameters and interest models

## 🔒 Security Features

- **Pause Mechanism**: Emergency pause functionality
- **Version Control**: Contract versioning system
- **Access Control**: Admin-only functions for critical operations
- **Oracle Validation**: Multi-source price verification
- **Health Checks**: Continuous monitoring of user positions
- **Isolated Assets**: Support for isolated collateral types

## 📈 Governance

- Risk parameter changes require governance approval
- 7-epoch delay for risk model changes
- Admin controls for emergency functions

## 🔍 Monitoring & Events

The protocol emits comprehensive events for:
- Deposits and withdrawals
- Borrowing and repaying
- Staking and unstaking
- Liquidations
- Price updates
- Parameter changes

## 📝 License

[Add license information]

## 🤝 Contributing

[Add contribution guidelines]

## 📞 Support

[Add support information]

---

*This protocol is built on Sui blockchain and implements industry-standard DeFi practices with additional innovations in staking and oracle integration.*
