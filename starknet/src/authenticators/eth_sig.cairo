use starknet::{ContractAddress, EthAddress};
use sx::types::{Strategy, IndexedStrategy, Choice};

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
        choice: Choice,
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
    use sx::types::{Strategy, IndexedStrategy, Choice, UserAddress};
    use sx::utils::{EIP712, LegacyHashEthAddress, LegacyHashUsedSalts, ByteReverse};

    #[storage]
    struct Storage {
        _domain_hash: u256,
        _used_salts: LegacyMap::<(EthAddress, u256), bool>
    }

    #[external(v0)]
    impl EthSigAuthenticator of IEthSigAuthenticator<ContractState> {
        fn authenticate_propose(
            ref self: ContractState,
            r: u256,
            s: u256,
            v: u32,
            space: ContractAddress,
            author: EthAddress,
            metadata_uri: Array<felt252>,
            execution_strategy: Strategy,
            user_proposal_validation_params: Array<felt252>,
            salt: u256,
        ) {
            assert(!self._used_salts.read((author, salt)), 'Salt Already Used');

            let state = EIP712::unsafe_new_contract_state();
            EIP712::InternalImpl::verify_propose_sig(
                @state,
                r,
                s,
                v,
                space,
                author,
                metadata_uri.span(),
                @execution_strategy,
                user_proposal_validation_params.span(),
                salt,
            );
            self._used_salts.write((author, salt), true);
            ISpaceDispatcher { contract_address: space }
                .propose(
                    UserAddress::Ethereum(author),
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
            choice: Choice,
            user_voting_strategies: Array<IndexedStrategy>,
            metadata_uri: Array<felt252>,
        ) {
            // No need to check salts here, as double voting is prevented by the space itself.

            let state = EIP712::unsafe_new_contract_state();
            EIP712::InternalImpl::verify_vote_sig(
                @state,
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
            execution_strategy: Strategy,
            metadata_uri: Array<felt252>,
            salt: u256
        ) {
            assert(!self._used_salts.read((author, salt)), 'Salt Already Used');

            let state = EIP712::unsafe_new_contract_state();
            EIP712::InternalImpl::verify_update_proposal_sig(
                @state,
                r,
                s,
                v,
                space,
                author,
                proposal_id,
                @execution_strategy,
                metadata_uri.span(),
                salt
            );
            self._used_salts.write((author, salt), true);
            ISpaceDispatcher { contract_address: space }
                .update_proposal(
                    UserAddress::Ethereum(author), proposal_id, execution_strategy, metadata_uri
                );
        }
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        let mut state = EIP712::unsafe_new_contract_state();
        EIP712::InternalImpl::initializer(ref state);
    }
}
