use starknet::{ContractAddress, EthAddress};
use sx::types::{Strategy, IndexedStrategy, Choice};

#[starknet::interface]
trait IBitcoinSigAuthenticator<TContractState> {
    /// Authenticates a propose transaction, by checking the signature using Bitcoin signature verification
    /// 
    /// # Arguments
    ///
    /// * `signature` - The signature of message digest.
    /// * `space` - The address of the space contract.
    /// * `author` - The starkent address of the author of the proposal.
    /// * `metadata_uri` - The URI of the proposal metadata.
    /// * `execution_strategy` - The execution strategy of the proposal.
    /// * `user_proposal_validation_params` - The user proposal validation params of the proposal.
    /// * `salt` - The salt, used for replay protection.
    fn authenticate_propose(
        ref self: TContractState, signature: Array<u8>, space: ContractAddress, author: Array<u8>,
    // msg: ByteArray,
    // metadata_uri: Array<felt252>,
    // execution_strategy: Strategy,
    // user_proposal_validation_params: Array<felt252>,
    // salt: u256,
    );
}

#[starknet::contract]
mod BitcoinSigAuthenticator {
    use super::IBitcoinSigAuthenticator;

    // use alexandria_data_structures::byte_appender::ByteAppender;
    // use core::byte_array::ByteArrayTrait;
    // use core::option::OptionTrait;
    // use core::array::ArrayTrait;
    // use alexandria_data_structures::array_ext::ArrayTraitExt;
    // use starknet::{EthAddress, SyscallResultTrait};
    // use starknet::secp256_trait::{
    //     Signature, recover_public_key, Secp256PointTrait, signature_from_vrs, is_valid_signature
    // };
    // use starknet::secp256k1::{Secp256k1Point};
    // use starknet::eth_signature::verify_eth_signature;
    // use core::traits::{Into, TryInto};
    // use alexandria_bytes::{Bytes, BytesTrait};
    // use alexandria_encoding::sol_abi::decode::SolAbiDecodeTrait;
    // use alexandria_encoding::sol_abi::decode::SolAbiDecodeBytes;
    // use starknet::{ContractAddress};
    // use alexandria_encoding::base64::{
    //     Base64Encoder, Base64Decoder, Base64UrlEncoder, Base64UrlDecoder
    // };

    // use alexandria_math::{sha256, fast_power};
    use sx::utils::{Bitcoin};
    use starknet::{ContractAddress, EthAddress};

    #[storage]
    struct Storage { //_used_salts: LegacyMap::<(EthAddress, u256), bool>
    }

    #[abi(embed_v0)]
    impl BitcoinSigAuthenticator of IBitcoinSigAuthenticator<ContractState> {
        fn authenticate_propose(
            ref self: ContractState,
            signature: Array<u8>,
            space: ContractAddress,
            author: Array<u8>,
        //msg: ByteArray,
        // metadata_uri: Array<felt252>,
        // execution_strategy: Strategy,
        // user_proposal_validation_params: Array<felt252>,
        // salt: u256
        ) {
            let state = Bitcoin::unsafe_new_contract_state();
            Bitcoin::InternalImpl::verify_propose_sig(@state, signature, space, author,// metadata_uri.span(),
            // @execution_strategy,
            // user_proposal_validation_params.span(),
            // salt
            );
        }
    }
}


//#[test]
fn test_sig_verification() { // Should use: ECDSA verification, P2WPKH-P2SH compressed address
// // Signature for Hello World from wallet
// let orig_signature: Array<u8> = array![
//     0x24,
//     0x37,
//     0x1a,
//     0xff,
//     0x24,
//     0x98,
//     0x2f,
//     0x04,
//     0x40,
//     0xb6,
//     0x75,
//     0x94,
//     0x94,
//     0xf3,
//     0xeb,
//     0xb8,
//     0xd8,
//     0x32,
//     0xa5,
//     0x16,
//     0x36,
//     0xea,
//     0x98,
//     0x8e,
//     0x00,
//     0x91,
//     0x9f,
//     0x83,
//     0xca,
//     0x16,
//     0x68,
//     0x19,
//     0x1b,
//     0x46,
//     0x3a,
//     0x4a,
//     0x68,
//     0x14,
//     0xa4,
//     0x64,
//     0x32,
//     0xd5,
//     0xf8,
//     0xe2,
//     0x9a,
//     0x7d,
//     0xab,
//     0xb4,
//     0x38,
//     0xdf,
//     0x02,
//     0x08,
//     0x7a,
//     0xb3,
//     0x4e,
//     0xc4,
//     0x5d,
//     0x83,
//     0x08,
//     0xb6,
//     0x1e,
//     0xa5,
//     0x5e,
//     0x03,
//     0x56
// ]; // 0x24371aff24982f440b6759494f3ebb8d832a51636ea988e0919f83ca1668191b463a4a6814a46432d5f8e29a7dabb438df287ab34ec45d838b61ea55e356

// let msg: ByteArray = "Hello World";
// calculate_address(msg, orig_signature);
}
//  verify_eth_signature(:msg_hash, :signature, :eth_address);
// 
// priv: 3af4ba068b2a5df595ec95f992a87597ee4366b8e15da91089a265a252a6abfd
// pub compressed: 03ffd665e11c73cfc92b2200ee28315ddd7aea485cb55d1eb62e53b15d3be521ef
// sha'd: f35258d64035912d83d363a0a3076b403e579bcde8785b073a4e6157507eb93d
// ripe'd: 79f574bd245e676a25b11a81cb53838da522150b

// legacy:
// add zeros: 0079f574bd245e676a25b11a81cb53838da522150b
// base58 plus check'd: 1C7roo4QqzgCWnCx7QMN5SNdE1vUFsJCRt

// P2SH (segwit):
// from ripe'd to redeemed: 001479f574bd245e676a25b11a81cb53838da522150b
// sha'd: 3757c502531d6f260fa38cd72b05562feb9d709aeb53db93f2e62fb23b15158d
// ripe'd: d96d7d329a97d31eacb6fdc07e019b8a6854d95c
// versioned: 05d96d7d329a97d31eacb6fdc07e019b8a6854d95c
// encoded: 3MWfibyH3KVEvg1JEnjzn2DUDhbgYm3ceu


