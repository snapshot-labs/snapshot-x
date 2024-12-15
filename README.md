# Snapshot X

A Cairo implementation of the Snapshot X Protocol. Refer to the [documentation](https://docs.snapshot.box) for more
information.

## Architecture

The repository is split into two different parts:
1. The Cairo files are in a [Scarb](https://github.com/software-mansion/scarb) package under `./starknet`. (Tested with Scarb version 0.7.0)
2. The Solidity files are in a [Forge](https://github.com/foundry-rs/foundry) package under `./ethereum`. (Tested with Forge version 0.2.0)

There is also Hardhat Project in the root directory for crosschain tests. 

#### Run Cairo Tests

Enter directory: 
```sh
cd starknet
```

Build contracts:
```sh
scarb build
```

Run tests:
```sh
scarb test
```

### Run Solidity Tests

Enter directory: 
```sh
cd ethereum
```

Build contracts:
```sh
forge build
```

Run tests:
```sh
forge test
```

### Run L1 <-> L2 tests and signature tests (typescript tests)

On a separate terminal, spin an L1 node (hardhat in this example, but could be anvil):
```sh
yarn hardhat node
```

Now run the tests:
```sh
yarn test-ts
```

#### Run Hardhat Tests

The Hardhat tests can be run following the procedure in the [CI](.github/workflows/test.yml). You will need local Starknet Devnet and Ethereum devnet instances running. 
