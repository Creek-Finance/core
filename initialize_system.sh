#!/bin/bash

# Initialize the system: Transfer TreasuryCap and initialize StakingManager

# Color definition
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# ===== deployment information constant =====
# The address information extracted from the deployment results

# Package IDs
COIN_XAUM_PACKAGE="0x56ced0870e2274f24a447640fcf08f37b5b4e9f8113b56f78801312392b1061c"
COIN_GR_PACKAGE="0xf3a8bbe23733473b1797fb79e710ad73943983e3c6a39730ff187b3214050ff9"
COIN_GY_PACKAGE="0x24bfd23b897cd01a1eedb965f5b6ca72fcc66dcfd2249d26a7d1caac67bac7a5"
GLOBAL_CONFIG_PACKAGE="0x63bf5a22e224a42d1c407e9c898299828acec8def26a0a947e69b3d5bdfa1cf5"
PROTOCOL_PACKAGE="0x5e941f73a10857328cf4e37ca2d683abbbd33edf1823b9f6cf21a1d29e62ba6f"

# Object IDs
GLOBAL_CONFIG_ID="0x4582bb156c452007338af284541f5225784b735473b746b0958e99424950ec0b"
XAUM_GLOBAL_MINT_CAP="0x1c6c711f337de184af55782dcb61c2401b1dc70ae50b945afdcf6a1a49d75f64"
GR_TREASURY_CAP="0xfbcad3c20c68d26cd5dd1ecefb9db9d949d472a0791900b56cb20edffb975397"
GY_TREASURY_CAP="0x3a0d7594416895cfa00c38d416395c9c29f1811c170e8c918c329f9e05dce7f0"

# Wait for transaction confirmation
wait_for_transaction() {
    print_info "Waiting for transaction confirmation..."
    sleep 5
}

# Main function
main() {
    print_info "=== Sui Coin Manager System Initialization ==="
    echo ""
    
    print_info "Deployment Information:"
    echo "├─ COIN_XAUM Package: $COIN_XAUM_PACKAGE"
    echo "├─ COIN_GR Package: $COIN_GR_PACKAGE"
    echo "├─ COIN_GY Package: $COIN_GY_PACKAGE"
    echo "├─ GlobalConfig Package: $GLOBAL_CONFIG_PACKAGE"
    echo "├─ Protocol Package: $PROTOCOL_PACKAGE"
    echo "├─ GlobalConfig Object: $GLOBAL_CONFIG_ID"
    echo "├─ GR TreasuryCap: $GR_TREASURY_CAP"
    echo "└─ GY TreasuryCap: $GY_TREASURY_CAP"
    echo ""
    
    # Get the current account address
    ACCOUNT=$(sui client active-address)
    print_info "Current account: $ACCOUNT"
    echo ""
    
    # Step 1: Transfer GR TreasuryCap to GlobalConfig
    print_info "Step 1: Transferring COIN_GR TreasuryCap to GlobalConfig..."
    
    if sui client call \
        --package "$GLOBAL_CONFIG_PACKAGE" \
        --module "global_config" \
        --function "set_gr_treasury_cap" \
        --args "$GLOBAL_CONFIG_ID" "$GR_TREASURY_CAP" \
        --gas-budget 10000000; then
        print_success "COIN_GR TreasuryCap transferred successfully"
    else
        print_error "Failed to transfer COIN_GR TreasuryCap"
        exit 1
    fi
    
    wait_for_transaction
    
    # Step 2: Transfer GY TreasuryCap to GlobalConfig
    print_info "Step 2: Transferring COIN_GY TreasuryCap to GlobalConfig..."
    
    if sui client call \
        --package "$GLOBAL_CONFIG_PACKAGE" \
        --module "global_config" \
        --function "set_gy_treasury_cap" \
        --args "$GLOBAL_CONFIG_ID" "$GY_TREASURY_CAP" \
        --gas-budget 10000000; then
        print_success "COIN_GY TreasuryCap transferred successfully"
    else
        print_error "Failed to transfer COIN_GY TreasuryCap"
        exit 1
    fi
    
    wait_for_transaction
    
    # Step 3: Initialize StakingManager
    print_info "Step 3: Initializing StakingManager..."
    
    if sui client call \
        --package "$PROTOCOL_PACKAGE" \
        --module "staking_manager" \
        --function "init_staking_manager" \
        --args "$GLOBAL_CONFIG_ID" \
        --gas-budget 10000000; then
        print_success "StakingManager initialized successfully"
        
        # Display the initialization completion information
        echo ""
        print_success "=== System Initialization Complete! ==="
        echo ""
        print_info "The system is now ready for use:"
        echo "  • Users can stake XAUM to receive GR and GY tokens"
        echo "  • Users can unstake by returning GR and GY tokens to get XAUM back"
        echo ""
        print_info "Key addresses for frontend integration:"
        echo "  • GlobalConfig: $GLOBAL_CONFIG_ID"
        echo "  • Protocol Package: $PROTOCOL_PACKAGE"
        echo ""
        print_info "Test the system with:"
        echo "  ./test_staking.sh mint testnet <amount>"
        echo "  ./test_staking.sh stake testnet <amount>"
        echo "  ./test_staking.sh unstake testnet <amount>"
    else
        print_error "Failed to initialize StakingManager"
        exit 1
    fi
}

# Run the main function
main