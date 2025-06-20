# 🧠 Based Buster (BSTR) Token

## Overview

**BSTRToken** is a sophisticated ERC20 token with advanced governance capabilities and flexible tax mechanisms:

- 💸 **Dynamic Tax System** on Buys, Sells, and Transfers
- 🔁 **Fee Distribution** between Liquidity, Burn, and Collectors
- 💱 **Flexible Fee Collection** (ETH or Token-based)
- 💰 **Uniswap V2 Integration** with auto-swap support
- 🗳️ **DAO Governance Ready** via `ERC20Votes` and `ERC20Permit`
- ⏰ **Governance Infrastructure** with `GovernorBSTR` and timelock support

## 🔧 Contract Architecture

### 📄 `contracts/BSTRToken.sol` - Main Token Contract

**Inheritance Chain:**
```
BSTRToken
├── ERC20 ("Buster", "BSTR")
├── ERC20Permit (EIP-2612 compliant)
├── ERC20Votes (Snapshot-based voting)
├── TaxableToken (Tax logic)
├── TaxDistributor (Fee collection)
├── Ownable (Access control)
└── ReentrancyGuard (Security)
```

**Key Features:**
- **9 Decimal Precision** (custom `CUSTOM_DECIMALS`)
- **Gasless Approvals** via `ERC20Permit`
- **Snapshot Voting** via `ERC20Votes`
- **Role-based Access Control** with `taxRateUpdater`
- **Reentrancy Protection** on all state-changing functions

**Core Functions:**
| Function | Access | Description |
|---------|--------|-------------|
| `setTaxRates(buyRate, sellRate)` | `taxRateUpdater` | Update buy/sell tax rates (max 20%) |
| `setTaxRateUpdater(address)` | `owner` | Change who can update tax rates |
| `distributeFees(amount, inToken)` | `owner` | Manually distribute collected fees |
| `processFees(amount, minAmountOut)` | `owner` | Swap tokens for ETH and distribute |
| `setIsLpPool(address, bool)` | `owner` | Mark addresses as LP pools |
| `setIsExcludedFromFees(address, bool)` | `owner` | Whitelist addresses from fees |

### 📄 `contracts/libraries/TaxableToken.sol` - Tax Logic Engine

**Fee Configuration Structure:**
```solidity
struct FeeConfiguration {
    bool feesInToken;        // Collect fees as tokens (true) or ETH (false)
    uint16 buyFees;          // Buy tax (0-2000 = 0-20%)
    uint16 sellFees;         // Sell tax (0-2000 = 0-20%)
    uint16 transferFees;     // Transfer tax (0-2000 = 0-20%)
    uint16 burnFeeRatio;     // % of tax to burn (0-10000)
    uint16 liquidityFeeRatio; // % of tax to LP (0-10000)
    uint16 collectorsFeeRatio; // % of tax to collectors (0-10000)
}
```

**Tax Logic:**
- **Buy Tax**: Applied when tokens come FROM LP pool TO regular address
- **Sell Tax**: Applied when tokens go TO LP pool FROM regular address  
- **Transfer Tax**: Applied on regular transfers (not LP interactions)
- **Auto-Processing**: Automatically swaps collected fees when threshold is met

**Default Configuration:**
- Buy/Sell Tax: 5% (500/10000)
- Transfer Tax: 0%
- Burn Ratio: 0%
- Liquidity Ratio: 50%
- Collectors Ratio: 50%
- Fees in Token: `true`

### 📄 `contracts/libraries/TaxDistributor.sol` - Fee Collection System

**Features:**
- **Up to 50 Fee Collectors** (gas optimization)
- **Weighted Distribution** based on shares
- **Dynamic Management** (add/remove/update collectors)
- **Dual Distribution** (ETH or Token)

**Core Functions:**
| Function | Description |
|---------|-------------|
| `addFeeCollector(address, share)` | Add new collector with weight |
| `removeFeeCollector(address)` | Remove collector |
| `updateFeeCollectorShare(address, share)` | Update collector weight |
| `distributeFees(amount, inToken)` | Distribute fees to all collectors |

### 📄 `contracts/libraries/GovernorBSTR.sol` - Governance Infrastructure

**OpenZeppelin Governor Implementation:**
```
GovernorBSTR
├── Governor ("BSTRGovernor")
├── GovernorSettings (voting parameters)
├── GovernorCountingSimple (vote counting)
├── GovernorVotes (token-based voting)
├── GovernorVotesQuorumFraction (quorum requirements)
└── GovernorTimelockControl (timelock execution)
```

**Governance Features:**
- **Token-weighted Voting** using BSTR token balance
- **Configurable Parameters**: voting delay, voting period, proposal threshold, quorum
- **Timelock Integration** for secure proposal execution
- **Snapshot-based Voting** (voting power at proposal creation)

## 🗳️ Governance Architecture

### Complete DAO Setup

1. **BSTRToken** - The voting token with snapshot capabilities
2. **GovernorBSTR** - The governance contract for proposals
3. **TimelockController** - Secure execution with delays
4. **Frontend Integration** - For proposal creation and voting

### Governance Flow

```
Token Holders → Delegate Votes → Create Proposals → Vote → Execute (via Timelock)
```

## 🧪 Testing

### ✅ Unit Tests (`test/BSTRToken.test.ts`)

- Transfer tax logic and edge cases
- LP buy/sell simulation
- Fee collector distribution
- Access control and permissions
- Governance vote delegation
- ERC20Permit functionality

## 🚀 Deployment

### Current Deployment Configuration

```typescript
// deploy/00_deploy_your_contracts.ts
const initialSupply = parseUnits("1000000", 9); // 1M BSTR tokens
const feeReceiver = deployer; // ETH recipient
const swapRouter = "SWAP_ROUTER_ADDRESS_BASE_MAIN_NET"; // Base Sepolia
const collectors = ["COLLECTORS_ADDRESS_REX"];
const shares = [100]; // 100% to single collector
const value = "100000000000000000"; // 0.1 ETH for fee receiver
```

### To Install Dependencies Clone This Repo Then Run

```bash
yarn
```

### Test Net Deployment Command

```bash
yarn deploy --network baseSepolia
```

### Test Net Deployment Verify Command

```bash
yarn verify --api-url https://api-sepolia.basescan.org
```

### Main Net Deployment Command

```bash
yarn hardhat deploy --network base
```

### Main Net Deployment Verify Command

```bash
yarn verify --api-url https://api.basescan.org
```

## 📌 Post-Deployment Setup

### 1. Governance Setup (Optional)

```solidity
// Deploy TimelockController
TimelockController timelock = new TimelockController(
    minDelay,
    [proposer],
    [executor],
    admin
);

// Deploy GovernorBSTR
GovernorBSTR governor = new GovernorBSTR(
    bstrToken,           // voting token
    timelock,           // timelock controller
    votingDelay,        // blocks before voting starts
    votingPeriod,       // blocks voting is active
    proposalThreshold,  // minimum tokens to propose
    quorumPercentage    // minimum votes to pass
);
```

### 2. Token Configuration

```solidity
// Set up LP pools
bstrToken.setIsLpPool(uniswapPair, true);

// Exclude addresses from fees
bstrToken.setIsExcludedFromFees(treasury, true);
bstrToken.setIsExcludedFromFees(governance, true);

// Configure fee processing
bstrToken.setNumTokensToSwap(threshold);
bstrToken.setAutoprocessFees(true);
```

## 🧱 Project Structure

```
contracts/
├── BSTRToken.sol                    # Main token contract
├── interfaces/
│   ├── IBSTRToken.sol              # Minimal token interface
│   ├── IUniswapV2Factory.sol       # Uniswap factory interface
│   ├── IUniswapV2Router01.sol      # Uniswap router v1 interface
│   └── IUniswapV2Router02.sol      # Uniswap router v2 interface
└── libraries/
    ├── TaxableToken.sol            # Tax logic implementation
    ├── TaxDistributor.sol          # Fee collection system
    └── GovernorBSTR.sol            # Governance infrastructure

test/
├── BSTRToken.test.ts               # Comprehensive token tests

deploy/
└── 00_deploy_your_contracts.ts     # Deployment script
```

## 🔐 Security Features

### ✅ Implemented Security Measures

- **ReentrancyGuard** on all state-changing functions
- **Access Control** with `Ownable` and custom `taxRateUpdater` role
- **Safe ETH Transfers** using `.call{value:}("")` with success checks
- **Input Validation** on all public functions
- **Gas Optimization** with capped collector count (50 max)
- **Timelock Integration** for governance execution

### 🔲 Recommended Pre-Launch Checklist

- ✅ Core functionality unit tested
- ✅ LP interaction simulation
- ✅ Fee collection mechanisms tested
- ✅ Governance vote delegation tested
- 🔲 **Security Audit** (highly recommended)
- 🔲 **Governance Parameter Tuning**
- 🔲 **Multi-sig Treasury Setup**

## 🎯 Key Innovations

1. **Flexible Tax System**: Configurable buy/sell/transfer taxes with burn/liquidity/collector splits
2. **Governance-Ready**: Built-in `ERC20Votes` and `ERC20Permit` for immediate DAO integration
3. **Gas-Efficient**: Optimized fee collection with capped collector count
4. **Security-First**: Comprehensive access controls and reentrancy protection
5. **Uniswap V2 Compatible**: Seamless integration with existing DEX infrastructure

## 🗳️ Summary

This system provides:

- **Advanced Taxable ERC20** with governance capabilities
- **Complete DAO Infrastructure** ready for deployment
- **Flexible Fee Management** with multiple distribution options
- **Enterprise-Grade Security** with comprehensive protections
- **Gas-Optimized Architecture** for cost-effective operations

---

## 👨‍💻 Built By

Built with ❤️ by [Decentral Bros](https://decentralbros.xyz)
