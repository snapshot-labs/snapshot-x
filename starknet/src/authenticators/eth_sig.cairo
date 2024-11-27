use starknet::{ContractAddress, EthAddress};
use sx::types::{Strategy, IndexedStrategy};

#[starknet::interface]
trait IEthSigAuthenticator<TContractState> {
    /// Authenticates a propose transaction, by checking the signature using EIP712.
    /// 
    /// # Arguments
    ///
    /// * `r` - The `r` component of the signature.
    /// * `s` - The `s` component of the signature.
    /// * `v` - The `v` component of the signature.
    /// * `space` - The address of the space contract.
    /// * `author` - The address of the author of the proposal.
    /// * `metadata_uri` - The URI of the proposal's metadata.
    /// * `execution_strategy` - The execution strategy of the proposal.
    /// * `user_proposal_validation_params` - The user proposal validation params.
    /// * `salt` - The salt, used for replay protection.
    fn authenticate_propose(
        ref self: TContractState,
        r: u256,
        s: u256,
        v: u32,
        space: ContractAddress,
        author: EthAddress,
        choices: u128,
        metadata_uri: Array<felt252>,
        execution_strategy: Strategy,
        user_proposal_validation_params: Array<felt252>,
        salt: u256,
    );

    /// Authenticates a vote transaction, by checking the signature using EIP712.
    /// Salt is not needed here as the space contract prevents double voting.
    ///
    /// # Arguments
    ///
    /// * `r` - The `r` component of the signature.
    /// * `s` - The `s` component of the signature.
    /// * `v` - The `v` component of the signature.
    /// * `space` - The address of the space contract.
    /// * `voter` - The address of the voter.
    /// * `proposal_id` - The ID of the proposal.
    /// * `choice` - The choice of the voter.
    /// * `user_voting_strategies` - The user voting strategies.
    /// * `metadata_uri` - The URI of the proposal's metadata.
    fn authenticate_vote(
        ref self: TContractState,
        r: u256,
        s: u256,
        v: u32,
        space: ContractAddress,
        voter: EthAddress,
        proposal_id: u256,
        choice: u128,
        user_voting_strategies: Array<IndexedStrategy>,
        metadata_uri: Array<felt252>,
    );

    /// Authenticates an update proposal transaction, by checking the signature using EIP712.
    ///
    /// # Arguments
    ///
    /// * `r` - The `r` component of the signature.
    /// * `s` - The `s` component of the signature.
    /// * `v` - The `v` component of the signature.
    /// * `space` - The address of the space contract.
    /// * `author` - The address of the author of the proposal.
    /// * `proposal_id` - The ID of the proposal.
    /// * `execution_strategy` - The new execution strategy that will replace the old one.
    /// * `metadata_uri` - The new URI that will replace the old one.
    /// * `salt` - The salt, used for replay protection.
    fn authenticate_update_proposal(
        ref self: TContractState,
        r: u256,
        s: u256,
        v: u32,
        space: ContractAddress,
        author: EthAddress,
        proposal_id: u256,
        choices: u128,
        execution_strategy: Strategy,
        metadata_uri: Array<felt252>,
        salt: u256
    );
}

#[starknet::contract]
mod EthSigAuthenticator {
    use super::IEthSigAuthenticator;
    use starknet::{ContractAddress, EthAddress};
    use sx::interfaces::{ISpaceDispatcher, ISpaceDispatcherTrait};
    use sx::types::{Strategy, IndexedStrategy, UserAddress};
    use sx::utils::{eip712, LegacyHashEthAddress, ByteReverse};

    #[storage]
    struct Storage {
        _used_salts: LegacyMap::<(EthAddress, u256), bool>
    }

    #[abi(embed_v0)]
    impl EthSigAuthenticator of IEthSigAuthenticator<ContractState> {
        fn authenticate_propose(
            ref self: ContractState,
            r: u256,
            s: u256,
            v: u32,
            space: ContractAddress,
            author: EthAddress,
            choices: u128,
            metadata_uri: Array<felt252>,
            execution_strategy: Strategy,
            user_proposal_validation_params: Array<felt252>,
            salt: u256,
        ) {
            assert(!self._used_salts.read((author, salt)), 'Salt Already Used');

            eip712::verify_propose_sig(
                r,
                s,
                v,
                space,
                author,
                choices,
                metadata_uri.span(),
                @execution_strategy,
                user_proposal_validation_params.span(),
                salt,
            );
            self._used_salts.write((author, salt), true);
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
            r: u256,
            s: u256,
            v: u32,
            space: ContractAddress,
            voter: EthAddress,
            proposal_id: u256,
            choice: u128,
            user_voting_strategies: Array<IndexedStrategy>,
            metadata_uri: Array<felt252>,
        ) {
            // No need to check salts here, as double voting is prevented by the space itself.

            eip712::verify_vote_sig(
                r,
                s,
                v,
                space,
                voter,
                proposal_id,
                choice,
                user_voting_strategies.span(),
                metadata_uri.span(),
            );

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
            r: u256,
            s: u256,
            v: u32,
            space: ContractAddress,
            author: EthAddress,
            proposal_id: u256,
            choices: u128,
            execution_strategy: Strategy,
            metadata_uri: Array<felt252>,
            salt: u256
        ) {
            assert(!self._used_salts.read((author, salt)), 'Salt Already Used');

            eip712::verify_update_proposal_sig(
                r,
                s,
                v,
                space,
                author,
                proposal_id,
                choices,
                @execution_strategy,
                metadata_uri.span(),
                salt
            );
            self._used_salts.write((author, salt), true);
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
}
