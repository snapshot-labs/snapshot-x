use starknet::ContractAddress;
use sx::types::{Strategy, IndexedStrategy};

#[starknet::interface]
trait IStarkTxAuthenticator<TContractState> {
    /// Authenticates a propose transaction by checking that the message sender is indeed `author`.
    ///
    /// # Arguments
    ///
    /// * `space` - The address of the space contract.
    /// * `author` - The starknet address of the author.
    /// * `metadata_uri` - The URI of the metadata.
    /// * `execution_strategy` - The execution strategy of the proposal.
    /// * `user_proposal_validation_params` - The user proposal validation params.
    fn authenticate_propose(
        ref self: TContractState,
        space: ContractAddress,
        author: ContractAddress,
        choices: u128,
        metadata_uri: Array<felt252>,
        execution_strategy: Strategy,
        user_proposal_validation_params: Array<felt252>,
    );

    /// Authenticates a vote transaction by checking that the message sender is indeed `voter`.
    ///
    /// # Arguments
    ///
    /// * `space` - The address of the space contract.
    /// * `voter` - The starknet address of the voter.
    /// * `proposal_id` - The id of the proposal.
    /// * `choice` - The choice of the voter.
    /// * `user_voting_strategies` - The user voting strategies.
    /// * `metadata_uri` - The URI of the metadata.
    fn authenticate_vote(
        ref self: TContractState,
        space: ContractAddress,
        voter: ContractAddress,
        proposal_id: u256,
        choice: u128,
        user_voting_strategies: Array<IndexedStrategy>,
        metadata_uri: Array<felt252>
    );

    /// Authenticates an update proposal transaction by checking that the message sender is indeed `author`.
    ///
    /// # Arguments
    ///
    /// * `space` - The address of the space contract.
    /// * `author` - The starknet address of the author.
    /// * `proposal_id` - The id of the proposal.
    /// * `execution_strategy` - The execution strategy of the proposal.
    /// * `metadata_uri` - The URI of the metadata.
    fn authenticate_update_proposal(
        ref self: TContractState,
        space: ContractAddress,
        author: ContractAddress,
        proposal_id: u256,
        choices: u128,
        execution_strategy: Strategy,
        metadata_uri: Array<felt252>
    );
}

#[starknet::contract]
mod StarkTxAuthenticator {
    use super::IStarkTxAuthenticator;
    use starknet::{ContractAddress, info};
    use sx::interfaces::{ISpaceDispatcher, ISpaceDispatcherTrait};
    use sx::types::{UserAddress, Strategy, IndexedStrategy};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl StarkTxAuthenticator of IStarkTxAuthenticator<ContractState> {
        fn authenticate_propose(
            ref self: ContractState,
            space: ContractAddress,
            author: ContractAddress,
            choices: u128,
            metadata_uri: Array<felt252>,
            execution_strategy: Strategy,
            user_proposal_validation_params: Array<felt252>,
        ) {
            assert(info::get_caller_address() == author, 'Invalid Caller');

            ISpaceDispatcher { contract_address: space }
                .propose(
                    UserAddress::Starknet(author),
                    choices,
                    metadata_uri,
                    execution_strategy,
                    user_proposal_validation_params,
                );
        }

        fn authenticate_vote(
            ref self: ContractState,
            space: ContractAddress,
            voter: ContractAddress,
            proposal_id: u256,
            choice: u128,
            user_voting_strategies: Array<IndexedStrategy>,
            metadata_uri: Array<felt252>
        ) {
            assert(info::get_caller_address() == voter, 'Invalid Caller');

            ISpaceDispatcher { contract_address: space }
                .vote(
                    UserAddress::Starknet(voter),
                    proposal_id,
                    choice,
                    user_voting_strategies,
                    metadata_uri,
                );
        }

        fn authenticate_update_proposal(
            ref self: ContractState,
            space: ContractAddress,
            author: ContractAddress,
            proposal_id: u256,
            choices: u128,
            execution_strategy: Strategy,
            metadata_uri: Array<felt252>
        ) {
            assert(info::get_caller_address() == author, 'Invalid Caller');

            ISpaceDispatcher { contract_address: space }
                .update_proposal(
                    UserAddress::Starknet(author), proposal_id, choices, execution_strategy, metadata_uri
                );
        }
    }
}
