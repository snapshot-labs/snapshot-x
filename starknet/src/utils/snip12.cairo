/// SNIP12 style typed data signing implementation.
/// See here for more info: https://community.starknet.io/t/snip-off-chain-signatures-a-la-eip712/98029
#[starknet::component]
mod SNIP12Component {
    use core::serde::Serde;
    use core::traits::AddEq;
    use starknet::ContractAddress;
    use openzeppelin::account::interface::{AccountABIDispatcher, AccountABIDispatcherTrait};
    use sx::types::{Strategy, IndexedStrategy};
    use sx::utils::StructHash;
    use sx::utils::constants::{
        STARKNET_MESSAGE, DOMAIN_TYPEHASH, PROPOSE_TYPEHASH, VOTE_TYPEHASH,
        UPDATE_PROPOSAL_TYPEHASH, ERC165_ACCOUNT_INTERFACE_ID
    };

    #[storage]
    struct Storage {
        Snip12_domain_hash: felt252
    }

    #[generate_trait]
    impl InternalImpl<
        TContractState, +HasComponent<TContractState>
    > of InternalTrait<TContractState> {
        fn initializer(ref self: ComponentState<TContractState>, name: felt252, version: felt252) {
            self.Snip12_domain_hash.write(get_domain_hash(name, version));
        }

        /// Verifies the signature of the propose calldata.
        fn verify_propose_sig(
            self: @ComponentState<TContractState>,
            signature: Array<felt252>,
            space: ContractAddress,
            author: ContractAddress,
            choices: u128,
            metadata_uri: Span<felt252>,
            execution_strategy: @Strategy,
            user_proposal_validation_params: Span<felt252>,
            salt: felt252
        ) {
            let digest: felt252 = self
                .get_propose_digest(
                    space,
                    author,
                    choices,
                    metadata_uri,
                    execution_strategy,
                    user_proposal_validation_params,
                    salt
                );

            verify_signature(digest, signature, author);
        }

        /// Verifies the signature of the vote calldata.
        fn verify_vote_sig(
            self: @ComponentState<TContractState>,
            signature: Array<felt252>,
            space: ContractAddress,
            voter: ContractAddress,
            proposal_id: u256,
            choice: u128,
            user_voting_strategies: Span<IndexedStrategy>,
            metadata_uri: Span<felt252>
        ) {
            let digest: felt252 = self
                .get_vote_digest(
                    space, voter, proposal_id, choice, user_voting_strategies, metadata_uri
                );
            verify_signature(digest, signature, voter);
        }

        /// Verifies the signature of the update proposal calldata.
        fn verify_update_proposal_sig(
            self: @ComponentState<TContractState>,
            signature: Array<felt252>,
            space: ContractAddress,
            author: ContractAddress,
            proposal_id: u256,
            choices: u128,
            execution_strategy: @Strategy,
            metadata_uri: Span<felt252>,
            salt: felt252
        ) {
            let digest: felt252 = self
                .get_update_proposal_digest(
                    space, author, proposal_id, choices, execution_strategy, metadata_uri, salt
                );
            verify_signature(digest, signature, author);
        }

        /// Returns the digest of the propose calldata.
        fn get_propose_digest(
            self: @ComponentState<TContractState>,
            space: ContractAddress,
            author: ContractAddress,
            choices: u128,
            metadata_uri: Span<felt252>,
            execution_strategy: @Strategy,
            user_proposal_validation_params: Span<felt252>,
            salt: felt252
        ) -> felt252 {
            let mut encoded_data = array![];
            PROPOSE_TYPEHASH.serialize(ref encoded_data);
            space.serialize(ref encoded_data);
            author.serialize(ref encoded_data);
            choices.serialize(ref encoded_data);
            metadata_uri.struct_hash().serialize(ref encoded_data);
            execution_strategy.struct_hash().serialize(ref encoded_data);
            user_proposal_validation_params.struct_hash().serialize(ref encoded_data);
            salt.serialize(ref encoded_data);
            self.hash_typed_data(encoded_data.span().struct_hash(), author)
        }

        /// Returns the digest of the vote calldata.
        fn get_vote_digest(
            self: @ComponentState<TContractState>,
            space: ContractAddress,
            voter: ContractAddress,
            proposal_id: u256,
            choice: u128,
            user_voting_strategies: Span<IndexedStrategy>,
            metadata_uri: Span<felt252>,
        ) -> felt252 {
            let mut encoded_data = array![];
            VOTE_TYPEHASH.serialize(ref encoded_data);
            space.serialize(ref encoded_data);
            voter.serialize(ref encoded_data);
            proposal_id.struct_hash().serialize(ref encoded_data);
            choice.serialize(ref encoded_data);
            user_voting_strategies.struct_hash().serialize(ref encoded_data);
            metadata_uri.struct_hash().serialize(ref encoded_data);
            self.hash_typed_data(encoded_data.span().struct_hash(), voter)
        }


        /// Returns the digest of the update proposal calldata.
        fn get_update_proposal_digest(
            self: @ComponentState<TContractState>,
            space: ContractAddress,
            author: ContractAddress,
            proposal_id: u256,
            choices: u128,
            execution_strategy: @Strategy,
            metadata_uri: Span<felt252>,
            salt: felt252
        ) -> felt252 {
            let mut encoded_data = array![];
            UPDATE_PROPOSAL_TYPEHASH.serialize(ref encoded_data);
            space.serialize(ref encoded_data);
            author.serialize(ref encoded_data);
            proposal_id.struct_hash().serialize(ref encoded_data);
            choices.serialize(ref encoded_data);
            execution_strategy.struct_hash().serialize(ref encoded_data);
            metadata_uri.struct_hash().serialize(ref encoded_data);
            salt.serialize(ref encoded_data);
            self.hash_typed_data(encoded_data.span().struct_hash(), author)
        }

        /// Hashes typed data according to the starknet equiavalent to the EIP-712 specification.
        fn hash_typed_data(
            self: @ComponentState<TContractState>, message_hash: felt252, signer: ContractAddress
        ) -> felt252 {
            let mut encoded_data = array![];
            STARKNET_MESSAGE.serialize(ref encoded_data);
            self.Snip12_domain_hash.read().serialize(ref encoded_data);
            signer.serialize(ref encoded_data);
            message_hash.serialize(ref encoded_data);
            encoded_data.span().struct_hash()
        }
    }

    /// Returns the domain hash of the contract.
    fn get_domain_hash(name: felt252, version: felt252) -> felt252 {
        let mut encoded_data = array![];
        DOMAIN_TYPEHASH.serialize(ref encoded_data);
        name.serialize(ref encoded_data);
        version.serialize(ref encoded_data);
        starknet::get_tx_info().unbox().chain_id.serialize(ref encoded_data);
        encoded_data.span().struct_hash()
    }
    /// Verifies the signature of a message by calling the account contract.
    fn verify_signature(digest: felt252, signature: Array<felt252>, account: ContractAddress) {
        // Only SNIP-6 compliant accounts are supported.
        assert(
            AccountABIDispatcher { contract_address: account }
                .supports_interface(ERC165_ACCOUNT_INTERFACE_ID) == true,
            'Invalid Account'
        );

        assert(
            AccountABIDispatcher { contract_address: account }
                .is_valid_signature(digest, signature) == 'VALID',
            'Invalid Signature'
        );
    }
}
