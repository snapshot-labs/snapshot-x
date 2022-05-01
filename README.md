[![GitHub license](https://img.shields.io/badge/license-MIT-blue.svg)](https://raw.githubusercontent.com/snapshot-labs/sx-core/master/LICENSE)

# Snapshot X

Programmable governance on StarkNet.

#### [Documentation](https://docs.snapshotx.xyz)


## Usage

### Clone repository:

```bash 
git clone https://github.com/snapshot-labs/sx-core.git
git submodule update --init --recursive
```
Note: The submodule included in the repo is the [Fossil](https://github.com/OilerNetwork/fossil) Storage Verifier

### Install Python and Yarn requirements: 

```bash
python3.7 -m venv ~/cairo_venv
source ~/cairo_venv/bin/activate
pip3 install -r requirements.txt
yarn
```

### Compile all contracts:

```bash
yarn compile
# You can also use yarn compile:l1 to just compile solidity contracts
# or yarn compile:l2 to just compile cairo contracts
```

### Testing

Tests are separated into three categories:

- Ethereum tests in `tests/ethereum`: Tests for our solidity contracts
- Starknet tests in `tests/starknet`: Tests for our cairo contracts
- Cross chain tests in `tests/crosschain`: Tests that will cover interaction between solidity and cairo contracts.

To run these tests locally: 

#### Install and run [StarkNet Devnet](https://github.com/Shard-Labs/starknet-devnet) (In a separate terminal):
```bash
yarn chain:l2
```

#### Run an ethereum hardhat node (In a separate terminal)

```bash
yarn chain:l1
```

#### Run tests:
```bash
yarn test:l1
yarn test:l2 
yarn test:crosschain
```

## DISCLAIMER: STILL IN DEVELOPMENT

This project is still under heavy development. Feel free to contact us on [Discord](https://discord.snapshot.org)!

## License

Snapshot X contracts are open-source software licensed under the © [MIT license](LICENSE).

