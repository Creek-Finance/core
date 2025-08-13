#!/bin/bash

# Color definition
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Contract sequence (dependency)
CONTRACTS=(
    "coin_xaum"
    "coin_gr"
    "coin_gy"
    "global_config"
    "protocol"
)

# Instructions for Use
usage() {
    echo "Usage: $0 [build|deploy|all] [--network <network>]"
    echo ""
    echo "Commands:"
    echo "  build    - Build all contracts"
    echo "  deploy   - Deploy all contracts (requires built packages)"
    echo "  all      - Build and deploy all contracts"
    echo ""
    echo "Options:"
    echo "  --network <network>  - Network to deploy to (testnet, mainnet, devnet)"
    echo "                        Default: testnet"
    echo ""
    echo "Example:"
    echo "  $0 build"
    echo "  $0 deploy --network testnet"
    echo "  $0 all --network devnet"
    exit 1
}

# Print messages with colors
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

# Check whether the command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 command not found. Please install Sui CLI."
        exit 1
    fi
}

# Compile a single contract
build_contract() {
    local contract=$1
    print_info "Building $contract..."
    
    cd "$contract" || {
        print_error "Failed to enter $contract directory"
        return 1
    }
    
    if sui move build --skip-fetch-latest-git-deps; then
        print_success "$contract built successfully"
        cd ..
        return 0
    else
        print_error "Failed to build $contract"
        cd ..
        return 1
    fi
}

# Compile all contracts
build_all() {
    print_info "Starting to build all contracts..."
    
    for contract in "${CONTRACTS[@]}"; do
        if ! build_contract "$contract"; then
            print_error "Build process failed at $contract"
            return 1
        fi
        echo ""
    done
    
    print_success "All contracts built successfully!"
    return 0
}

# Update the address of the dependent package
update_dependency_addresses() {
    local deployed_contract=$1
    local deployed_address=$2
    
    print_info "Updating dependency addresses for $deployed_contract..."
    
    # Update the corresponding dependencies according to the deployed contract
    case $deployed_contract in
        coin_gr)
            # Update the coin_gr address in global_config and protocol
            for pkg in global_config protocol; do
                if [ -f "$pkg/Move.toml" ]; then
                    print_info "Updating $pkg/Move.toml with coin_gr address"
                    sed -i.bak "s/coin_gr = \"0x0\"/coin_gr = \"$deployed_address\"/" "$pkg/Move.toml"
                fi
            done
            ;;
        coin_gy)
            # Update the coin_gy address in global_config and protocol
            for pkg in global_config protocol; do
                if [ -f "$pkg/Move.toml" ]; then
                    print_info "Updating $pkg/Move.toml with coin_gy address"
                    sed -i.bak "s/coin_gy = \"0x0\"/coin_gy = \"$deployed_address\"/" "$pkg/Move.toml"
                fi
            done
            ;;
        coin_xaum)
            # Update the coin_xaum address in the protocol
            if [ -f "protocol/Move.toml" ]; then
                print_info "Updating protocol/Move.toml with coin_xaum address"
                sed -i.bak "s/coin_xaum = \"0x0\"/coin_xaum = \"$deployed_address\"/" "protocol/Move.toml"
            fi
            ;;
        global_config)
            # Update the global_config address in the protocol
            if [ -f "protocol/Move.toml" ]; then
                print_info "Updating protocol/Move.toml with global_config address"
                sed -i.bak "s/global_config = \"0x0\"/global_config = \"$deployed_address\"/" "protocol/Move.toml"
            fi
            ;;
    esac
}

# Deploy a single contract
deploy_contract() {
    local contract=$1
    local network=$2
    
    print_info "Deploying $contract to $network..."
    
    cd "$contract" || {
        print_error "Failed to enter $contract directory"
        return 1
    }
    
    # Check if there are any compiled packages
    if [ ! -d "build" ]; then
        print_error "No build directory found. Please build $contract first."
        cd ..
        return 1
    fi
    
    # Deployment contract
    print_info "Publishing $contract package..."
    
    # Save the original output to a temporary file
    temp_output="../${contract}_deploy_output_${network}.txt"
    
    # Execute the deployment and save the output
    if sui client publish --gas-budget 100000000 > "$temp_output" 2>&1; then
        print_success "$contract deployed successfully"
        
        # Read the output content
        output=$(cat "$temp_output")
        
        # Parse the PackageID - Find it in the "Published Objects:" section
        package_id=$(echo "$output" | grep -A 5 "Published Objects:" | grep "PackageID:" | grep -o "0x[a-fA-F0-9]\{64\}" | head -1)
        
        if [ -n "$package_id" ]; then
            echo "PackageID: $package_id"
            
            # Save the deployment information
            echo "$contract PackageID: $package_id" >> ../deployment_info_${network}.txt
            
            # Update the dependency addresses in the Move.toml of other packages
            update_dependency_addresses "$contract" "$package_id"
        else
            print_warning "Could not extract PackageID from output"
        fi
        
        # Handle different types of contracts specially
        case $contract in
            coin_xaum)
                # Search for the GlobalMintCap object
                mint_cap_id=$(echo "$output" | grep -B 5 "GlobalMintCap" | grep "ObjectID:" | grep -o "0x[a-fA-F0-9]\{64\}" | head -1)
                if [ -n "$mint_cap_id" ]; then
                    echo "GlobalMintCap ObjectID: $mint_cap_id"
                    echo "GlobalMintCap ObjectID: $mint_cap_id" >> ../deployment_info_${network}.txt
                fi
                ;;
            coin_gr|coin_gy)
                # Search for the TreasuryCap object
                treasury_cap_id=$(echo "$output" | grep -B 5 "TreasuryCap" | grep "ObjectID:" | grep -o "0x[a-fA-F0-9]\{64\}" | head -1)
                if [ -n "$treasury_cap_id" ]; then
                    echo "TreasuryCap ObjectID: $treasury_cap_id"
                    echo "$contract TreasuryCap ObjectID: $treasury_cap_id" >> ../deployment_info_${network}.txt
                fi
                ;;
            global_config)
                # Search for the GlobalConfig object (which needs to be obtained from the output of the init function)
                # Usually, GlobalConfig is a Shared object
                config_id=$(echo "$output" | grep -B 5 "Shared(" | grep "ObjectID:" | grep -o "0x[a-fA-F0-9]\{64\}" | head -1)
                if [ -n "$config_id" ]; then
                    echo "GlobalConfig ObjectID: $config_id"
                    echo "GlobalConfig ObjectID: $config_id" >> ../deployment_info_${network}.txt
                fi
                ;;
        esac
        
        # Save the complete output for debugging
        echo "" >> ../deployment_info_${network}.txt
        echo "=== $contract Full Output ===" >> ../deployment_info_${network}.txt
        cat "$temp_output" >> ../deployment_info_${network}.txt
        echo "=== End of $contract Output ===" >> ../deployment_info_${network}.txt
        echo "" >> ../deployment_info_${network}.txt
        
        cd ..
        return 0
    else
        print_error "Failed to deploy $contract"
        print_error "Error output saved to: $temp_output"
        cat "$temp_output"
        cd ..
        return 1
    fi
}

# Deploy all contracts
deploy_all() {
    local network=$1
    
    print_info "Starting to deploy all contracts to $network..."
    
    # Clear the previous deployment information
    > deployment_info_${network}.txt
    echo "Deployment Information - $(date)" >> deployment_info_${network}.txt
    echo "Network: $network" >> deployment_info_${network}.txt
    echo "===================================" >> deployment_info_${network}.txt
    echo "" >> deployment_info_${network}.txt
    
    for contract in "${CONTRACTS[@]}"; do
        if ! deploy_contract "$contract" "$network"; then
            print_error "Deployment process failed at $contract"
            return 1
        fi
        echo ""
        
        # If it is a contract that requires waiting, give some delay
        if [ "$contract" = "coin_xaum" ] || [ "$contract" = "coin_gr" ] || [ "$contract" = "coin_gy" ]; then
            print_info "Waiting for transaction to be confirmed..."
            sleep 3
        fi
    done
    
    print_success "All contracts deployed successfully!"
    print_info "Deployment information saved to deployment_info_${network}.txt"
    
    # Display deployment summary
    echo ""
    print_info "=== Deployment Summary ==="
    
    # Extract and display key information
    local xaum_package=$(grep "coin_xaum PackageID:" deployment_info_${network}.txt | tail -1 | awk '{print $NF}')
    local gr_package=$(grep "coin_gr PackageID:" deployment_info_${network}.txt | tail -1 | awk '{print $NF}')
    local gy_package=$(grep "coin_gy PackageID:" deployment_info_${network}.txt | tail -1 | awk '{print $NF}')
    local config_package=$(grep "global_config PackageID:" deployment_info_${network}.txt | tail -1 | awk '{print $NF}')
    local protocol_package=$(grep "protocol PackageID:" deployment_info_${network}.txt | tail -1 | awk '{print $NF}')
    local global_config_id=$(grep "GlobalConfig ObjectID:" deployment_info_${network}.txt | tail -1 | awk '{print $NF}')
    
    echo "XAUM Package: ${xaum_package:-Not found}"
    echo "GR Package: ${gr_package:-Not found}"
    echo "GY Package: ${gy_package:-Not found}"
    echo "GlobalConfig Package: ${config_package:-Not found}"
    echo "Protocol Package: ${protocol_package:-Not found}"
    echo "GlobalConfig Object: ${global_config_id:-Not found}"
    
    # Display the subsequent steps
    echo ""
    print_info "Next steps:"
    echo "1. Initialize the system using:"
    echo "   ./initialize_system.sh deployment_info_${network}.txt"
    echo ""
    echo "2. Or manually transfer TreasuryCaps and initialize:"
    echo "   - Transfer COIN_GR TreasuryCap to GlobalConfig"
    echo "   - Transfer COIN_GY TreasuryCap to GlobalConfig"
    echo "   - Initialize StakingManager"
    
    return 0
}

# Main function
main() {
    # Check the sui command
    check_command "sui"
    
    # Parsing parameters
    if [ $# -eq 0 ]; then
        usage
    fi
    
    COMMAND=$1
    NETWORK="testnet"
    
    # Parse network parameters
    shift
    while [ $# -gt 0 ]; do
        case $1 in
            --network)
                shift
                if [ $# -eq 0 ]; then
                    print_error "Network value required after --network"
                    usage
                fi
                NETWORK=$1
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                ;;
        esac
        shift
    done
    
    # Verification network
    case $NETWORK in
        testnet|mainnet|devnet)
            ;;
        *)
            print_error "Invalid network: $NETWORK"
            print_error "Valid networks are: testnet, mainnet, devnet"
            exit 1
            ;;
    esac
    
    # Switch to the correct network
    print_info "Switching to $NETWORK..."
    sui client switch --env $NETWORK
    
    # Execute the command
    case $COMMAND in
        build)
            build_all
            ;;
        deploy)
            deploy_all $NETWORK
            ;;
        all)
            if build_all; then
                echo ""
                deploy_all $NETWORK
            fi
            ;;
        *)
            print_error "Unknown command: $COMMAND"
            usage
            ;;
    esac
}

# Run the main function
main "$@"