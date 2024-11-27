use starknet::{EthAddress, ContractAddress, secp256_trait};
use starknet::eth_signature::verify_eth_signature;
use starknet::secp256k1::Secp256k1Point;
use sx::types::{Strategy, IndexedStrategy};
use sx::utils::{endian, ByteReverse, KeccakStructHash, TIntoU256};
use sx::utils::constants::{
    DOMAIN_HASH_LOW, DOMAIN_HASH_HIGH, ETHEREUM_PREFIX, PROPOSE_TYPEHASH_LOW, PROPOSE_TYPEHASH_HIGH,
    VOTE_TYPEHASH_LOW, VOTE_TYPEHASH_HIGH, UPDATE_PROPOSAL_TYPEHASH_LOW,
    UPDATE_PROPOSAL_TYPEHASH_HIGH, INDEXED_STRATEGY_TYPEHASH_LOW, INDEXED_STRATEGY_TYPEHASH_HIGH,
};

/// Verifies the signature of the propose calldata.
fn verify_propose_sig(
    r: u256,
    s: u256,
    v: u32,
    space: ContractAddress,
    author: EthAddress,
    choices: u128,
    metadata_uri: Span<felt252>,
    execution_strategy: @Strategy,
    user_proposal_validation_params: Span<felt252>,
    salt: u256,
) {
    let digest: u256 = get_propose_digest(
        space,
        author,
        choices,
        metadata_uri,
        execution_strategy,
        user_proposal_validation_params,
        salt
    );
    verify_eth_signature(digest, secp256_trait::signature_from_vrs(v, r, s), author);
}

/// Verifies the signature of the vote calldata.
fn verify_vote_sig(
    r: u256,
    s: u256,
    v: u32,
    space: ContractAddress,
    voter: EthAddress,
    proposal_id: u256,
    choice: u128,
    user_voting_strategies: Span<IndexedStrategy>,
    metadata_uri: Span<felt252>,
) {
    let digest: u256 = get_vote_digest(
        space, voter, proposal_id, choice, user_voting_strategies, metadata_uri
    );
    verify_eth_signature(digest, secp256_trait::signature_from_vrs(v, r, s), voter);
}

/// Verifies the signature of the update proposal calldata.
fn verify_update_proposal_sig(
    r: u256,
    s: u256,
    v: u32,
    space: ContractAddress,
    author: EthAddress,
    proposal_id: u256,
    choices: u128,
    execution_strategy: @Strategy,
    metadata_uri: Span<felt252>,
    salt: u256
) {
    let digest: u256 = get_update_proposal_digest(
        space, author, proposal_id, choices, execution_strategy, metadata_uri, salt
    );
    verify_eth_signature(digest, secp256_trait::signature_from_vrs(v, r, s), author);
}

/// Returns the digest of the propose calldata.
fn get_propose_digest(
    space: ContractAddress,
    author: EthAddress,
    choices: u128,
    metadata_uri: Span<felt252>,
    execution_strategy: @Strategy,
    user_proposal_validation_params: Span<felt252>,
    salt: u256
) -> u256 {
    let choices_u256 = u256 { low: choices, high: 0 };
    let encoded_data = array![
        u256 { low: PROPOSE_TYPEHASH_LOW, high: PROPOSE_TYPEHASH_HIGH },
        Felt252IntoU256::into(starknet::get_tx_info().unbox().chain_id),
        starknet::get_contract_address().into(),
        space.into(),
        author.into(),
        choices_u256,
        metadata_uri.keccak_struct_hash(),
        execution_strategy.keccak_struct_hash(),
        user_proposal_validation_params.keccak_struct_hash(),
        salt
    ];
    let message_hash = keccak::keccak_u256s_be_inputs(encoded_data.span()).byte_reverse();
    hash_typed_data(message_hash)
}

/// Returns the digest of the vote calldata.
fn get_vote_digest(
    space: ContractAddress,
    voter: EthAddress,
    proposal_id: u256,
    choice: u128,
    user_voting_strategies: Span<IndexedStrategy>,
    metadata_uri: Span<felt252>,
) -> u256 {
    let choice_u256 = u256 { low: choice, high: 0 };
    let encoded_data = array![
        u256 { low: VOTE_TYPEHASH_LOW, high: VOTE_TYPEHASH_HIGH },
        Felt252IntoU256::into(starknet::get_tx_info().unbox().chain_id),
        starknet::get_contract_address().into(),
        space.into(),
        voter.into(),
        proposal_id,
        choice_u256,
        user_voting_strategies.keccak_struct_hash(),
        metadata_uri.keccak_struct_hash()
    ];
    let message_hash = keccak::keccak_u256s_be_inputs(encoded_data.span()).byte_reverse();
    hash_typed_data(message_hash)
}

/// Returns the digest of the update proposal calldata.
fn get_update_proposal_digest(
    space: ContractAddress,
    author: EthAddress,
    proposal_id: u256,
    choices: u128,
    execution_strategy: @Strategy,
    metadata_uri: Span<felt252>,
    salt: u256
) -> u256 {
    let choices_u256 = u256 { low: choices, high: 0 };
    let encoded_data = array![
        u256 { low: UPDATE_PROPOSAL_TYPEHASH_LOW, high: UPDATE_PROPOSAL_TYPEHASH_HIGH },
        Felt252IntoU256::into(starknet::get_tx_info().unbox().chain_id),
        starknet::get_contract_address().into(),
        space.into(),
        author.into(),
        proposal_id,
        choices_u256,
        execution_strategy.keccak_struct_hash(),
        metadata_uri.keccak_struct_hash(),
        salt
    ];
    let message_hash = keccak::keccak_u256s_be_inputs(encoded_data.span()).byte_reverse();
    hash_typed_data(message_hash)
}

/// Hashes typed data according to the EIP-712 specification.
fn hash_typed_data(message_hash: u256) -> u256 {
    let encoded_data = add_prefix_array(
        array![u256 { low: DOMAIN_HASH_LOW, high: DOMAIN_HASH_HIGH }, message_hash], ETHEREUM_PREFIX
    );
    let (mut u64_arr, overflow) = endian::into_le_u64_array(encoded_data);
    keccak::cairo_keccak(ref u64_arr, overflow, 2).byte_reverse()
}

/// Prefixes a 16 bit prefix to an array of 256 bit values.
fn add_prefix_array(input: Array<u256>, mut prefix: u128) -> Array<u256> {
    let mut out = ArrayTrait::<u256>::new();
    let mut input = input;
    loop {
        match input.pop_front() {
            Option::Some(num) => {
                let (w1, high_carry) = add_prefix_u128(num.high, prefix);
                let (w0, low_carry) = add_prefix_u128(num.low, high_carry);
                out.append(u256 { low: w0, high: w1 });
                prefix = low_carry;
            },
            Option::None(_) => {
                // left shift so that the prefix is in the high bits
                out
                    .append(
                        u256 { high: prefix * 0x10000000000000000000000000000_u128, low: 0_u128 }
                    );
                break ();
            }
        };
    };
    out
}

/// Adds a 16 bit prefix to a 128 bit input, returning the result and a carry.
fn add_prefix_u128(input: u128, prefix: u128) -> (u128, u128) {
    let with_prefix = u256 { low: input, high: prefix };
    let carry = with_prefix & 0xffff;
    // Removing the carry and shifting back.
    let out = (with_prefix - carry) / 0x10000;
    (out.low, carry.low)
}
