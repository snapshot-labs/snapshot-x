use starknet::{ContractAddress, contract_address_to_felt252};
use array::{ArrayTrait, SpanTrait};
use traits::Into;
use clone::Clone;
use starknet::secp256k1;
use core::keccak;
use integer::u256_from_felt252;
use sx::utils::types::{Strategy, IndexedStrategy, Choice, U8ArrayIntoU256Array};
use sx::utils::math::pow;
use sx::utils::constants::{
    DOMAIN_TYPEHASH_LOW, DOMAIN_TYPEHASH_HIGH, ETHEREUM_PREFIX, STRATEGY_TYPEHASH_LOW,
    STRATEGY_TYPEHASH_HIGH, INDEXED_STRATEGY_TYPEHASH_LOW, INDEXED_STRATEGY_TYPEHASH_HIGH,
    PROPOSE_TYPEHASH_LOW, PROPOSE_TYPEHASH_HIGH, VOTE_TYPEHASH_LOW, VOTE_TYPEHASH_HIGH,
    UPDATE_PROPOSAL_TYPEHASH_LOW, UPDATE_PROPOSAL_TYPEHASH_HIGH
};

impl ContractAddressIntoU256 of Into<ContractAddress, u256> {
    fn into(self: ContractAddress) -> u256 {
        u256_from_felt252(contract_address_to_felt252(self))
    }
}

trait KeccakTypeHash<T> {
    fn hash(self: T) -> u256;
}

impl KeccakTypeHashStrategy of KeccakTypeHash<Strategy> {
    fn hash(self: Strategy) -> u256 {
        let mut encoded_data = ArrayTrait::<u256>::new();
        encoded_data.append(u256 { low: STRATEGY_TYPEHASH_LOW, high: STRATEGY_TYPEHASH_HIGH });
        encoded_data.append(self.address.into());
        encoded_data.append(self.params.hash());
        keccak::keccak_uint256s_le(encoded_data.span())
    }
}

impl KeccakTypeHashArray of KeccakTypeHash<Array<felt252>> {
    fn hash(self: Array<felt252>) -> u256 {
        // cast u8 array to u256 array so that each member is 32 bytes
        let mut encoded_data: Array<u256> = self.into();
        // TODO: little or big endian?
        keccak::keccak_uint256s_le(encoded_data.span())
    }
}

impl KeccakTypeHashIndexedStrategy of KeccakTypeHash<IndexedStrategy> {
    fn hash(self: IndexedStrategy) -> u256 {
        let mut encoded_data = ArrayTrait::<u256>::new();
        encoded_data.append(
            u256 { low: INDEXED_STRATEGY_TYPEHASH_LOW, high: INDEXED_STRATEGY_TYPEHASH_HIGH }
        );
        let index_felt: felt252 = self.index.into();
        encoded_data.append(index_felt.into());
        encoded_data.append(self.params.hash());
        keccak::keccak_uint256s_le(encoded_data.span())
    }
}

impl KeccakTypeHashIndexedStrategyArray of KeccakTypeHash<Array<IndexedStrategy>> {
    fn hash(self: Array<IndexedStrategy>) -> u256 {
        let mut encoded_data = ArrayTrait::<u256>::new();
        let mut i: usize = 0;
        loop {
            if i >= self.len() {
                break ();
            }
            encoded_data.append(self.at(i).clone().hash());
        };
        keccak::keccak_uint256s_le(encoded_data.span())
    }
}


// Reverts if the signature was not signed by the author. 
fn verify_propose_sig(
    r: u256,
    s: u256,
    v: u256,
    domain_hash: u256,
    target: ContractAddress,
    author: ContractAddress,
    execution_strategy: Strategy,
    user_proposal_validation_params: Array<felt252>,
    salt: u256,
) {
    let digest: u256 = get_propose_digest(
        domain_hash, target, author, execution_strategy, user_proposal_validation_params, salt
    );
// TODO: Actually verify the signature when it gets added
// secp256k1::verify_eth_signature(digest, r, s, v, author);
}

fn verify_vote_sig(
    r: u256,
    s: u256,
    v: u256,
    domain_hash: u256,
    target: ContractAddress,
    voter: ContractAddress,
    proposal_id: u256,
    choice: Choice,
    user_voting_strategies: Array<IndexedStrategy>
) {
    let digest: u256 = get_vote_digest(
        domain_hash, target, voter, proposal_id, choice, user_voting_strategies
    );
// TODO: Actually verify the signature when it gets added
// secp256k1::verify_eth_signature(digest, r, s, v, voter);
}

fn verify_update_proposal_sig(
    r: u256,
    s: u256,
    v: u256,
    domain_hash: u256,
    target: ContractAddress,
    author: ContractAddress,
    proposal_id: u256,
    execution_strategy: Strategy,
    salt: u256
) {
    let digest: u256 = get_update_proposal_digest(
        domain_hash, target, author, proposal_id, execution_strategy, salt
    );
// TODO: Actually verify the signature when it gets added
// secp256k1::verify_eth_signature(digest, r, s, v, author);
}


fn get_propose_digest(
    domain_hash: u256,
    space: ContractAddress,
    author: ContractAddress,
    execution_strategy: Strategy,
    user_proposal_validation_params: Array<felt252>,
    salt: u256
) -> u256 {
    let mut encoded_data = ArrayTrait::<u256>::new();
    encoded_data.append(u256 { low: PROPOSE_TYPEHASH_LOW, high: PROPOSE_TYPEHASH_HIGH });
    encoded_data.append(space.into());
    encoded_data.append(author.into());
    encoded_data.append(execution_strategy.hash());
    encoded_data.append(user_proposal_validation_params.hash());
    encoded_data.append(salt);
    let message_hash = keccak::keccak_uint256s_le(encoded_data.span());
    hash_typed_data(domain_hash, message_hash)
}

fn get_vote_digest(
    domain_hash: u256,
    space: ContractAddress,
    voter: ContractAddress,
    proposal_id: u256,
    choice: Choice,
    user_voting_strategies: Array<IndexedStrategy>
) -> u256 {
    let mut encoded_data = ArrayTrait::<u256>::new();
    encoded_data.append(u256 { low: VOTE_TYPEHASH_LOW, high: VOTE_TYPEHASH_HIGH });
    encoded_data.append(space.into());
    encoded_data.append(voter.into());
    encoded_data.append(proposal_id);
    encoded_data.append(choice.into());
    encoded_data.append(user_voting_strategies.hash());
    let message_hash = keccak::keccak_uint256s_le(encoded_data.span());
    hash_typed_data(domain_hash, message_hash)
}

fn get_update_proposal_digest(
    domain_hash: u256,
    space: ContractAddress,
    author: ContractAddress,
    proposal_id: u256,
    execution_strategy: Strategy,
    salt: u256
) -> u256 {
    let mut encoded_data = ArrayTrait::<u256>::new();
    encoded_data.append(
        u256 { low: UPDATE_PROPOSAL_TYPEHASH_LOW, high: UPDATE_PROPOSAL_TYPEHASH_HIGH }
    );
    encoded_data.append(space.into());
    encoded_data.append(author.into());
    encoded_data.append(proposal_id);
    encoded_data.append(execution_strategy.hash());
    encoded_data.append(salt);
    let message_hash = keccak::keccak_uint256s_le(encoded_data.span());
    hash_typed_data(domain_hash, message_hash)
}

fn get_domain_hash(name: felt252, version: felt252) -> u256 {
    let mut encoded_data = ArrayTrait::<u256>::new();
    encoded_data.append(u256 { low: DOMAIN_TYPEHASH_LOW, high: DOMAIN_TYPEHASH_HIGH });
    encoded_data.append(name.into());
    encoded_data.append(version.into());
    // TODO: chain id doesnt seem like its exposed atm, so just dummy value for now
    encoded_data.append(u256 { low: 'dummy', high: 0 });
    encoded_data.append(starknet::get_contract_address().into());
    keccak::keccak_uint256s_le(encoded_data.span())
}

fn hash_typed_data(domain_hash: u256, message_hash: u256) -> u256 {
    let mut encoded_data = ArrayTrait::<u256>::new();
    encoded_data.append(domain_hash);
    encoded_data.append(message_hash);
    let encoded_data = _add_prefix_array(encoded_data, ETHEREUM_PREFIX);
    keccak::keccak_uint256s_le(encoded_data.span())
}


// Prefixes a 16 bit prefix to an array of 256 bit values.
fn _add_prefix_array(input: Array<u256>, mut prefix: u128) -> Array<u256> {
    let mut out = ArrayTrait::<u256>::new();
    let mut i = 0_usize;
    loop {
        if i >= input.len() {
            // left shift so that the prefix is in the high bits
            let prefix_u256 = u256 { low: prefix, high: 0_u128 };
            let shifted_prefix = prefix_u256 * pow(u256 { low: 2_u128, high: 0_u128 }, 112_u8);
            out.append(shifted_prefix);
            break ();
        }
        let num = *input.at(i);
        let (w1, high_carry) = _add_prefix_u128(num.high, prefix);
        let (w0, low_carry) = _add_prefix_u128(num.low, high_carry);

        out.append(u256 { low: w0, high: w1 });
        prefix = low_carry;
        i += 1;
    };
    out
}

// prefixes a 16 bit prefix to a 128 bit input, returning the result and a carry if it overflows 128 bits
fn _add_prefix_u128(input: u128, prefix: u128) -> (u128, u128) {
    let prefix_u256 = u256 { low: prefix, high: 0_u128 };
    let shifted_prefix = prefix_u256 * pow(u256 { low: 2_u128, high: 0_u128 }, 128_u8);
    let with_prefix = u256 { low: input, high: 0_u128 } + shifted_prefix;
    let overflow_mask = pow(u256 { low: 2_u128, high: 0_u128 }, 16_u8) - u256 {
        low: 1_u128, high: 0_u128
    };
    let carry = with_prefix & overflow_mask;
    // Removing the carry and shifting back. The result fits in 128 bits.
    let out = ((with_prefix - carry) / pow(u256 { low: 2_u128, high: 0_u128 }, 16_u8));
    (out.low, carry.low)
}
