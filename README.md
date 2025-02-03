# Foundry DeFi Stablecoin

## About

This project implements a decentralized stablecoin where users can deposit WETH and WBTC in exchange for a token pegged to the USD. It leverages smart contract technology to maintain stability and transparency.

## Quickstart

Clone the repository and navigate to the project directory:

```bash
git clone https://github.com/datokorgalidze/defi_stablecoin.git
cd foundry-defi-stablecoin-cu
forge build
```

### Usage

#### Start a Local Node

To start a local blockchain node:

```bash
make anvil
```

#### Deploy

The deployment process defaults to your local node. Ensure the local node is running in a separate terminal before deploying:

```bash
make deploy
```

### Testing

The project includes various test tiers:

1. **Unit Tests**
2. **Fuzzing**

This repository focuses on Unit Testing and Fuzzing.

Run the tests using:

```bash
forge test
```

### Test Coverage

Generate a test coverage report:

```bash
forge coverage
```

For coverage-based testing, use:

```bash
forge coverage --report debug
```

## Mock Contract for Testing

This project uses `MockV3Aggregator` for testing purposes to simulate price feed data. Below is a detailed explanation of the contract:

### How the MockV3Aggregator Works

The `MockV3Aggregator` contract simulates an oracle that provides price feed data. It allows developers to test their contracts without relying on live Chainlink data feeds.

#### Key Features

- **Update Answer:** Set the latest price feed answer.
- **Round Data:** Access historical price information.
- **Latest Round Data:** Fetch the latest available price data.

### Conclusion

This project demonstrates the use of smart contracts for creating a stablecoin system backed by decentralized oracles and robust testing strategies.
