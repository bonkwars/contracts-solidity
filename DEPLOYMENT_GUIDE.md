# Deployment Guide

## Prerequisites
1. Private key with sufficient ETH for deployment
2. Node.js 16+ and yarn installed
3. Foundry/Forge installed
4. Environment variables configured

## Environment Setup
Create a .env file with:
```bash
PRIVATE_KEY=your_private_key_here
ETHERSCAN_API_KEY=your_etherscan_key
INFURA_API_KEY=your_infura_key
```

## Deployment Steps

### 1. Local Testing
```bash
# Install dependencies
forge install

# Run tests
forge test -vvv

# Run gas measurements
forge snapshot
```

### 2. Testnet Deployment
```bash
# Deploy to Goerli
forge script script/DeployHydra.s.sol --rpc-url $GOERLI_RPC_URL --broadcast

# Verify contracts
forge verify-contract $CONTRACT_ADDRESS src/HydraOpenzeppelin.sol:HydraOpenzeppelin
```

### 3. Production Deployment
```bash
# Deploy to mainnet
forge script script/DeployHydra.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify
```

## Contract Addresses

### Goerli Testnet
- HydraOpenzeppelin: [address]
- SecurityManager: [address]
- MemeCoinFactory: [address]
- FalconProofRegistry: [address]

### Mainnet
- HydraOpenzeppelin: [TBD]
- SecurityManager: [TBD]
- MemeCoinFactory: [TBD]
- FalconProofRegistry: [TBD]

## Post-Deployment Steps

1. Verify contract ownership
2. Initialize access controls
3. Set security parameters
4. Register initial assets
5. Enable trading

## Security Checks

- [ ] Validate constructor parameters
- [ ] Verify ownership transfers
- [ ] Check access control settings
- [ ] Test emergency functions
- [ ] Monitor initial transactions

## Monitoring

Set up monitoring for:
1. Trading volume
2. Gas usage
3. Error rates
4. Proof verification stats
5. Emergency triggers

## Upgrade Process

1. Deploy new implementation
2. Verify bytecode
3. Update proxies
4. Validate state
5. Monitor changes

## Emergency Procedures

1. Emergency pause triggers
2. Contact information
3. Recovery procedures
4. Backup deployment
5. Incident response plan