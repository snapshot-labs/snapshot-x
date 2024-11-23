use starknet::{ContractAddress, EthAddress};
use sx::types::{Strategy, IndexedStrategy};

#[starknet::interface]
trait IEthTxAuthenticator<TContractState> {
    /// Authenticates a propose transaction by checking that `author` has indeed sent a transaction from L1
    /// to the bridge contract.
    ///
    /// # Arguments
    ///
    /// * `space` - The address of the contract to which the transaction is sent.
    /// * `author` - The author of the proposal. Expected to be an ethereum address.
    /// * `metadata_uri` - The metadata URI of the proposal.
    /// * `execution_strategy` - The execution strategy of the proposal.
    /// * `user_proposal_validation_params` - The user proposal validation params of the proposal.
    fn authenticate_propose(
        ref self: TContractState,
        space: ContractAddress,
        author: EthAddress,
        choices: u128,
        metadata_uri: Array<felt252>,
        execution_strategy: Strategy,
        user_proposal_validation_params: Array<felt252>,
    );

    /// Authenticates a vote transaction by checking that `voter` has indeed sent a transaction from L1
    /// to the bridge contract.
    ///
    /// # Arguments
    ///
    /// * `space` - The address of the contract to which the transaction is sent.
    /// * `voter` - The voter. Expected to be an ethereum address.
    /// * `proposal_id` - The id of the proposal.
    /// * `choice` - The choice of the vote.
    /// * `user_voting_strategies` - The user voting strategies of the vote.
    /// * `metadata_uri` - The metadata URI of the vote.
    fn authenticate_vote(
        ref self: TContractState,
        space: ContractAddress,
        voter: EthAddress,
        proposal_id: u256,
        choice: u128,
        user_voting_strategies: Array<IndexedStrategy>,
        metadata_uri: Array<felt252>
    );

    /// Authenticates an update_proposal transaction by checking that `author` has indeed sent a transaction from L1
    /// to the bridge contract.
    ///
    /// # Arguments
    ///
    /// * `space` - The address of the contract to which the transaction is sent.
    /// * `author` - The author of the proposal. Expected to be an ethereum address.
    /// * `proposal_id` - The id of the proposal.
    /// * `execution_strategy` - The execution strategy of the proposal.
    /// * `metadata_uri` - The metadata URI of the proposal.
    fn authenticate_update_proposal(
        ref self: TContractState,
        space: ContractAddress,
        author: EthAddress,
        proposal_id: u256,
        choices: u128,
        execution_strategy: Strategy,
        metadata_uri: Array<felt252>
    );
}

#[starknet::contract]
mod EthTxAuthenticator {
    use super::IEthTxAuthenticator;
    use starknet::{ContractAddress, EthAddress, Felt252TryIntoEthAddress, EthAddressIntoFelt252,};
    use sx::interfaces::{ISpaceDispatcher, ISpaceDispatcherTrait};
    use sx::types::{UserAddress, Strategy, IndexedStrategy};
    use sx::utils::constants::{PROPOSE_SELECTOR, VOTE_SELECTOR, UPDATE_PROPOSAL_SELECTOR};

    #[storage]
    struct Storage {
        _starknet_commit_address: EthAddress,
        _commits: LegacyMap::<(felt252, EthAddress), bool>
    }

    #[abi(embed_v0)]
    impl EthTxAuthenticator of IEthTxAuthenticator<ContractState> {
        fn authenticate_propose(
            ref self: ContractState,
            space: ContractAddress,
            author: EthAddress,
            choices: u128,
            metadata_uri: Array<felt252>,
            execution_strategy: Strategy,
            user_proposal_validation_params: Array<felt252>,
        ) {
            let mut payload = array![];
            space.serialize(ref payload);
            PROPOSE_SELECTOR.serialize(ref payload);
            author.serialize(ref payload);
            choices.serialize(ref payload);
            metadata_uri.serialize(ref payload);
            execution_strategy.serialize(ref payload);
            user_proposal_validation_params.serialize(ref payload);
            let payload_hash = poseidon::poseidon_hash_span(payload.span());

            self.consume_commit(payload_hash, author);

            ISpaceDispatcher { contract_address: space }
                .propose(
                    UserAddress::Ethereum(author),
                    choices,
                    metadata_uri,
                    execution_strategy,
                    user_proposal_validation_params,
                );
        }

        fn authenticate_vote(
            ref self: ContractState,
            space: ContractAddress,
            voter: EthAddress,
            proposal_id: u256,
            choice: u128,
            user_voting_strategies: Array<IndexedStrategy>,
            metadata_uri: Array<felt252>
        ) {
            let mut payload = array![];
            space.serialize(ref payload);
            VOTE_SELECTOR.serialize(ref payload);
            voter.serialize(ref payload);
            proposal_id.serialize(ref payload);
            choice.serialize(ref payload);
            user_voting_strategies.serialize(ref payload);
            metadata_uri.serialize(ref payload);
            let payload_hash = poseidon::poseidon_hash_span(payload.span());

            self.consume_commit(payload_hash, voter);

            ISpaceDispatcher { contract_address: space }
                .vote(
                    UserAddress::Ethereum(voter),
                    proposal_id,
                    choice,
                    user_voting_strategies,
                    metadata_uri,
                );
        }

        fn authenticate_update_proposal(
            ref self: ContractState,
            space: ContractAddress,
            author: EthAddress,
            proposal_id: u256,
            choices: u128,
            execution_strategy: Strategy,
            metadata_uri: Array<felt252>
        ) {
            let mut payload = array![];
            space.serialize(ref payload);
            UPDATE_PROPOSAL_SELECTOR.serialize(ref payload);
            author.serialize(ref payload);
            proposal_id.serialize(ref payload);
            choices.serialize(ref payload);
            execution_strategy.serialize(ref payload);
            metadata_uri.serialize(ref payload);
            let payload_hash = poseidon::poseidon_hash_span(payload.span());

            self.consume_commit(payload_hash, author);

            ISpaceDispatcher { contract_address: space }
                .update_proposal(
                    UserAddress::Ethereum(author),
                    proposal_id,
                    choices,
                    execution_strategy,
                    metadata_uri
                );
        }
    }

    #[constructor]
    fn constructor(ref self: ContractState, starknet_commit_address: EthAddress) {
        self._starknet_commit_address.write(starknet_commit_address);
    }

    #[l1_handler]
    fn commit(
        ref self: ContractState, from_address: felt252, sender_address: felt252, hash: felt252
    ) {
        assert(
            from_address == self._starknet_commit_address.read().into(), 'Invalid commit address'
        );
        let sender_address = sender_address.try_into().unwrap();
        assert(self._commits.read((hash, sender_address)) == false, 'Commit already exists');
        self._commits.write((hash, sender_address), true);
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn consume_commit(ref self: ContractState, hash: felt252, sender_address: EthAddress) {
            assert(self._commits.read((hash, sender_address)), 'Commit not found');
            // Delete the commit to prevent replay attacks.
            self._commits.write((hash, sender_address), false);
        }
    }
}
