#[starknet::contract]
mod Space {
    use starknet::{ClassHash, ContractAddress, info, Store, syscalls, SyscallResult,};
    use starknet::storage_access::{StorePacking, StoreUsingPacking};
    use openzeppelin::access::ownable::OwnableComponent;
    use sx::interfaces::ISpace;
    use sx::interfaces::{
        IProposalValidationStrategyDispatcher, IProposalValidationStrategyDispatcherTrait,
        IVotingStrategyDispatcher, IVotingStrategyDispatcherTrait, IExecutionStrategyDispatcher,
        IExecutionStrategyDispatcherTrait
    };
    use sx::types::{
        UserAddress, FinalizationStatus, Strategy, IndexedStrategy, Proposal, PackedProposal,
        IndexedStrategyTrait, IndexedStrategyImpl, UpdateSettingsCalldata, NoUpdateTrait,
        NoUpdateString, strategy::StoreFelt252Array, ProposalStatus, proposal::ProposalDefault
    };
    use sx::utils::{
        BitSetter, LegacyHashUserAddress, LegacyHashVoteRegistry,
        constants::{INITIALIZE_SELECTOR, POST_UPGRADE_INITIALIZER_SELECTOR}
    };
    use sx::utils::reinitializable::ReinitializableComponent;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    component!(
        path: ReinitializableComponent, storage: reinitializable, event: ReinitializableEvent
    );

    impl ReinitializableInternalImpl = ReinitializableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        _min_voting_duration: u32,
        _max_voting_duration: u32,
        _next_proposal_id: u256,
        _voting_delay: u32,
        _dao_uri: Array<felt252>,
        _active_voting_strategies: u256,
        _voting_strategies: LegacyMap::<u8, Strategy>,
        _next_voting_strategy_index: u8,
        _proposal_validation_strategy: Strategy,
        _authenticators: LegacyMap::<ContractAddress, bool>,
        _proposals: LegacyMap::<u256, Proposal>,
        _vote_power: LegacyMap::<(u256, u128), u256>,
        _choices: LegacyMap::<u256, u128>,
        _vote_registry: LegacyMap::<(u256, UserAddress), bool>,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        reinitializable: ReinitializableComponent::Storage
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    enum Event {
        SpaceCreated: SpaceCreated,
        ProposalCreated: ProposalCreated,
        VoteCast: VoteCast,
        ProposalExecuted: ProposalExecuted,
        ProposalUpdated: ProposalUpdated,
        ProposalCancelled: ProposalCancelled,
        VotingStrategiesAdded: VotingStrategiesAdded,
        VotingStrategiesRemoved: VotingStrategiesRemoved,
        AuthenticatorsAdded: AuthenticatorsAdded,
        AuthenticatorsRemoved: AuthenticatorsRemoved,
        MetadataUriUpdated: MetadataUriUpdated,
        DaoUriUpdated: DaoUriUpdated,
        MaxVotingDurationUpdated: MaxVotingDurationUpdated,
        MinVotingDurationUpdated: MinVotingDurationUpdated,
        ProposalValidationStrategyUpdated: ProposalValidationStrategyUpdated,
        VotingDelayUpdated: VotingDelayUpdated,
        Upgraded: Upgraded,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        ReinitializableEvent: ReinitializableComponent::Event
    }


    #[derive(Drop, PartialEq, starknet::Event)]
    struct SpaceCreated {
        space: ContractAddress,
        owner: ContractAddress,
        min_voting_duration: u32,
        max_voting_duration: u32,
        voting_delay: u32,
        proposal_validation_strategy: Strategy,
        proposal_validation_strategy_metadata_uri: Span<felt252>,
        voting_strategies: Span<Strategy>,
        voting_strategy_metadata_uris: Span<Array<felt252>>,
        authenticators: Span<ContractAddress>,
        metadata_uri: Span<felt252>,
        dao_uri: Span<felt252>,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct ProposalCreated {
        proposal_id: u256,
        author: UserAddress,
        proposal: Proposal,
        metadata_uri: Span<felt252>,
        payload: Span<felt252>,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct VoteCast {
        proposal_id: u256,
        voter: UserAddress,
        choice: u128,
        voting_power: u256,
        metadata_uri: Span<felt252>,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct ProposalExecuted {
        proposal_id: u256,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct ProposalUpdated {
        proposal_id: u256,
        execution_strategy: Strategy,
        metadata_uri: Span<felt252>,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct ProposalCancelled {
        proposal_id: u256,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct VotingStrategiesAdded {
        voting_strategies: Span<Strategy>,
        voting_strategy_metadata_uris: Span<Array<felt252>>,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct VotingStrategiesRemoved {
        voting_strategy_indices: Span<u8>,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct AuthenticatorsAdded {
        authenticators: Span<ContractAddress>,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct AuthenticatorsRemoved {
        authenticators: Span<ContractAddress>,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct MaxVotingDurationUpdated {
        max_voting_duration: u32,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct MinVotingDurationUpdated {
        min_voting_duration: u32,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct ProposalValidationStrategyUpdated {
        proposal_validation_strategy: Strategy,
        proposal_validation_strategy_metadata_uri: Span<felt252>,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct VotingDelayUpdated {
        voting_delay: u32,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct Upgraded {
        class_hash: ClassHash,
        initialize_calldata: Span<felt252>,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct MetadataUriUpdated {
        metadata_uri: Span<felt252>,
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    struct DaoUriUpdated {
        dao_uri: Span<felt252>,
    }

    #[abi(embed_v0)]
    impl Space of ISpace<ContractState> {
        fn initialize(
            ref self: ContractState,
            owner: ContractAddress,
            min_voting_duration: u32,
            max_voting_duration: u32,
            voting_delay: u32,
            proposal_validation_strategy: Strategy,
            proposal_validation_strategy_metadata_uri: Array<felt252>,
            voting_strategies: Array<Strategy>,
            voting_strategy_metadata_uris: Array<Array<felt252>>,
            authenticators: Array<ContractAddress>,
            metadata_uri: Array<felt252>,
            dao_uri: Array<felt252>,
        ) {
            self
                .emit(
                    Event::SpaceCreated(
                        SpaceCreated {
                            space: info::get_contract_address(),
                            owner: owner,
                            min_voting_duration: min_voting_duration,
                            max_voting_duration: max_voting_duration,
                            voting_delay: voting_delay,
                            proposal_validation_strategy: proposal_validation_strategy.clone(),
                            proposal_validation_strategy_metadata_uri: proposal_validation_strategy_metadata_uri
                                .span(),
                            voting_strategies: voting_strategies.span(),
                            voting_strategy_metadata_uris: voting_strategy_metadata_uris.span(),
                            authenticators: authenticators.span(),
                            metadata_uri: metadata_uri.span(),
                            dao_uri: dao_uri.span()
                        }
                    )
                );

            // Checking that the contract is not already initialized
            self.reinitializable.initialize();

            assert(voting_strategies.len() != 0, 'empty voting strategies');
            assert(authenticators.len() != 0, 'empty authenticators');
            assert(voting_strategies.len() == voting_strategy_metadata_uris.len(), 'len mismatch');

            self.ownable.initializer(owner);
            self.set_dao_uri(dao_uri);
            self
                .set_max_voting_duration(
                    max_voting_duration
                ); // Need to set max before min, or else `max == 0` and set_min will revert
            self.set_min_voting_duration(min_voting_duration);
            self.set_proposal_validation_strategy(proposal_validation_strategy);
            self.set_voting_delay(voting_delay);
            self.add_voting_strategies(voting_strategies.span());
            self.add_authenticators(authenticators.span());
            self._next_proposal_id.write(1_u256);
        }

        fn propose(
            ref self: ContractState,
            author: UserAddress,
            choices: u128,
            metadata_uri: Array<felt252>,
            execution_strategy: Strategy,
            user_proposal_validation_params: Array<felt252>,
        ) {
            self.assert_only_authenticator();
            assert(author.is_non_zero(), 'Zero Address');
            assert(choices > 1, 'Invalid number of choices');

            // Proposal Validation
            let proposal_validation_strategy = self._proposal_validation_strategy.read();
            let is_valid = IProposalValidationStrategyDispatcher {
                contract_address: proposal_validation_strategy.address
            }
                .validate(
                    author,
                    proposal_validation_strategy.params.span(),
                    user_proposal_validation_params.span()
                );
            assert(is_valid, 'Proposal validation failed');

            // The snapshot block timestamp is the start of the voting period
            let start_timestamp = info::get_block_timestamp().try_into().unwrap()
                + self._voting_delay.read();
            let min_end_timestamp = start_timestamp + self._min_voting_duration.read();
            let max_end_timestamp = start_timestamp + self._max_voting_duration.read();

            let execution_payload_hash = poseidon::poseidon_hash_span(
                execution_strategy.params.span()
            );

            let proposal = Proposal {
                start_timestamp: start_timestamp,
                min_end_timestamp: min_end_timestamp,
                max_end_timestamp: max_end_timestamp,
                execution_payload_hash: execution_payload_hash,
                execution_strategy: execution_strategy.address,
                author: author,
                finalization_status: FinalizationStatus::Pending(()),
                active_voting_strategies: self._active_voting_strategies.read()
            };

            let proposal_id = self._next_proposal_id.read();
            self._proposals.write(proposal_id, proposal.clone());

            self._next_proposal_id.write(proposal_id + 1);
            self._choices.write(proposal_id, choices);

            self
                .emit(
                    Event::ProposalCreated(
                        ProposalCreated {
                            proposal_id: proposal_id,
                            author: author,
                            proposal,
                            metadata_uri: metadata_uri.span(),
                            payload: execution_strategy.params.span(),
                        }
                    )
                );
        }

        fn vote(
            ref self: ContractState,
            voter: UserAddress,
            proposal_id: u256,
            choice: u128,
            user_voting_strategies: Array<IndexedStrategy>,
            metadata_uri: Array<felt252>
        ) {
            self.assert_only_authenticator();
            assert(voter.is_non_zero(), 'Zero Address');
            let proposal = self._proposals.read(proposal_id);
            InternalImpl::assert_proposal_exists(@proposal);

            let timestamp = info::get_block_timestamp().try_into().unwrap();

            assert(timestamp < proposal.max_end_timestamp, 'Voting period has ended');
            assert(timestamp >= proposal.start_timestamp, 'Voting period has not started');
            assert(
                proposal.finalization_status == FinalizationStatus::Pending(()), 'Already finalized'
            );
            assert(
                self._vote_registry.read((proposal_id, voter)) == false, 'Voter has already voted'
            );

            // Written here to prevent reentrancy attacks via malicious voting strategies
            self._vote_registry.write((proposal_id, voter), true);

            let voting_power = self
                .get_cumulative_power(
                    voter,
                    proposal.start_timestamp,
                    user_voting_strategies.span(),
                    proposal.active_voting_strategies
                );
            assert(voting_power > 0, 'User has no voting power');

            let choices = self._choices.read(proposal_id);
            assert(choice < choices, 'Invalid choice');

            self
                ._vote_power
                .write(
                    (proposal_id, choice),
                    self._vote_power.read((proposal_id, choice)) + voting_power
                );

            // Contrary to the SX-EVM implementation, we don't differentiate between `VoteCast` and `VoteCastWithMetadata`
            // because calldata is free.
            self
                .emit(
                    Event::VoteCast(
                        VoteCast {
                            proposal_id: proposal_id,
                            voter: voter,
                            choice: choice,
                            voting_power: voting_power,
                            metadata_uri: metadata_uri.span()
                        }
                    )
                );
        }

        fn execute(ref self: ContractState, proposal_id: u256, execution_payload: Array<felt252>) {
            let mut proposal = self._proposals.read(proposal_id);
            InternalImpl::assert_proposal_exists(@proposal);

            let recovered_hash = poseidon::poseidon_hash_span(execution_payload.span());
            // Check that payload matches
            assert(recovered_hash == proposal.execution_payload_hash, 'Invalid payload hash');

            // Check that finalization status is pending
            assert(
                proposal.finalization_status == FinalizationStatus::Pending(()), 'Already finalized'
            );

            // We cache the proposal to prevent reentrancy attacks by setting
            // the finalization status to `Executed` before calling the `execute` function.
            let cached_proposal = proposal.clone();
            proposal.finalization_status = FinalizationStatus::Executed(());

            self._proposals.write(proposal_id, proposal);
            let votes = self.generate_votes_array(proposal_id);
            assert(votes.len() == 3, 'ERROR');

            IExecutionStrategyDispatcher { contract_address: cached_proposal.execution_strategy }
                .execute(proposal_id, cached_proposal, votes, execution_payload);

            self.emit(Event::ProposalExecuted(ProposalExecuted { proposal_id: proposal_id }));
        }

        fn cancel(ref self: ContractState, proposal_id: u256) {
            self.ownable.assert_only_owner();

            let mut proposal = self._proposals.read(proposal_id);
            InternalImpl::assert_proposal_exists(@proposal);
            assert(
                proposal.finalization_status == FinalizationStatus::Pending(()), 'Already finalized'
            );
            proposal.finalization_status = FinalizationStatus::Cancelled(());
            self._proposals.write(proposal_id, proposal);

            self.emit(Event::ProposalCancelled(ProposalCancelled { proposal_id: proposal_id }));
        }

        fn update_proposal(
            ref self: ContractState,
            author: UserAddress,
            proposal_id: u256,
            choices: u128,
            execution_strategy: Strategy,
            metadata_uri: Array<felt252>,
        ) {
            self.assert_only_authenticator();
            assert(author.is_non_zero(), 'Zero Address');
            let mut proposal = self._proposals.read(proposal_id);
            InternalImpl::assert_proposal_exists(@proposal);
            assert(
                proposal.finalization_status == FinalizationStatus::Pending(()), 'Already finalized'
            );
            assert(proposal.author == author, 'Invalid author');
            assert(
                info::get_block_timestamp() < proposal.start_timestamp.into(),
                'Voting period started'
            );
            assert(choices > 1, 'Invalid number of choices');

            proposal
                .execution_payload_hash =
                    poseidon::poseidon_hash_span(execution_strategy.params.span());
            proposal.execution_strategy = execution_strategy.address;

            self._choices.write(proposal_id, choices);
            self._proposals.write(proposal_id, proposal);

            self
                .emit(
                    Event::ProposalUpdated(
                        ProposalUpdated {
                            proposal_id: proposal_id,
                            execution_strategy: execution_strategy,
                            metadata_uri: metadata_uri.span()
                        }
                    )
                );
        }

        fn upgrade(
            ref self: ContractState, class_hash: ClassHash, initialize_calldata: Array<felt252>
        ) -> SyscallResult<()> {
            self.ownable.assert_only_owner();

            assert(class_hash.is_non_zero(), 'Class Hash cannot be zero');
            starknet::replace_class_syscall(class_hash)?;

            // Allowing initializer to be called again.
            self.reinitializable.reset();

            // Call `post_upgrade_initializer` on the new version.
            syscalls::call_contract_syscall(
                info::get_contract_address(),
                POST_UPGRADE_INITIALIZER_SELECTOR,
                initialize_calldata.span()
            )?;

            self
                .emit(
                    Event::Upgraded(
                        Upgraded {
                            class_hash: class_hash, initialize_calldata: initialize_calldata.span()
                        }
                    )
                );
            SyscallResult::Ok(())
        }

        fn post_upgrade_initializer(ref self: ContractState, initialize_calldata: Array<felt252>,) {
            // This code is left here to indicate to future developers that this
            // function should be called only once!
            self.reinitializable.initialize();
        // This contract being the first version, we don't expect anyone to upgrade to it.
        // We leave the implementation empty.
        }

        fn max_voting_duration(self: @ContractState) -> u32 {
            self._max_voting_duration.read()
        }

        fn min_voting_duration(self: @ContractState) -> u32 {
            self._min_voting_duration.read()
        }

        fn next_proposal_id(self: @ContractState) -> u256 {
            self._next_proposal_id.read()
        }

        fn voting_delay(self: @ContractState) -> u32 {
            self._voting_delay.read()
        }

        fn dao_uri(self: @ContractState) -> Array<felt252> {
            self._dao_uri.read()
        }

        fn authenticators(self: @ContractState, account: ContractAddress) -> bool {
            self._authenticators.read(account)
        }

        fn voting_strategies(self: @ContractState, index: u8) -> Strategy {
            self._voting_strategies.read(index)
        }

        fn active_voting_strategies(self: @ContractState) -> u256 {
            self._active_voting_strategies.read()
        }

        fn next_voting_strategy_index(self: @ContractState) -> u8 {
            self._next_voting_strategy_index.read()
        }

        fn proposal_validation_strategy(self: @ContractState) -> Strategy {
            self._proposal_validation_strategy.read()
        }

        fn proposals(self: @ContractState, proposal_id: u256) -> Proposal {
            self._proposals.read(proposal_id)
        }

        fn get_proposal_status(self: @ContractState, proposal_id: u256) -> ProposalStatus {
            let proposal = self._proposals.read(proposal_id);
            InternalImpl::assert_proposal_exists(@proposal);

            let votes = self.generate_votes_array(proposal_id);

            IExecutionStrategyDispatcher { contract_address: proposal.execution_strategy }
                .get_proposal_status(proposal, votes)
        }

        fn update_settings(ref self: ContractState, input: UpdateSettingsCalldata) {
            self.ownable.assert_only_owner();

            // Needed because the compiler will go crazy if we try to use `input` directly
            let _min_voting_duration = input.min_voting_duration;
            let _max_voting_duration = input.max_voting_duration;

            if _max_voting_duration.should_update() && _min_voting_duration.should_update() {
                // Check that min and max voting durations are valid
                // We don't use the internal `_set_min_voting_duration` and `_set_max_voting_duration` functions because
                // it would revert when `_min_voting_duration > max_voting_duration` (when the new `_min` is
                // bigger than the current `max`).
                assert(_min_voting_duration <= _max_voting_duration, 'Invalid duration');

                self._min_voting_duration.write(input.min_voting_duration);
                self
                    .emit(
                        Event::MinVotingDurationUpdated(
                            MinVotingDurationUpdated {
                                min_voting_duration: input.min_voting_duration
                            }
                        )
                    );

                self._max_voting_duration.write(input.max_voting_duration);
                self
                    .emit(
                        Event::MaxVotingDurationUpdated(
                            MaxVotingDurationUpdated {
                                max_voting_duration: input.max_voting_duration
                            }
                        )
                    );
            } else if _min_voting_duration.should_update() {
                self.set_min_voting_duration(input.min_voting_duration);
                self
                    .emit(
                        Event::MinVotingDurationUpdated(
                            MinVotingDurationUpdated {
                                min_voting_duration: input.min_voting_duration
                            }
                        )
                    );
            } else if _max_voting_duration.should_update() {
                self.set_max_voting_duration(input.max_voting_duration);
                self
                    .emit(
                        Event::MaxVotingDurationUpdated(
                            MaxVotingDurationUpdated {
                                max_voting_duration: input.max_voting_duration
                            }
                        )
                    );
            }

            if input.voting_delay.should_update() {
                self.set_voting_delay(input.voting_delay);

                self
                    .emit(
                        Event::VotingDelayUpdated(
                            VotingDelayUpdated { voting_delay: input.voting_delay }
                        )
                    );
            }

            if NoUpdateString::should_update((@input).metadata_uri) {
                self
                    .emit(
                        Event::MetadataUriUpdated(
                            MetadataUriUpdated { metadata_uri: input.metadata_uri.span() }
                        )
                    );
            }

            if NoUpdateString::should_update((@input).dao_uri) {
                self.set_dao_uri(input.dao_uri.clone());
                self.emit(Event::DaoUriUpdated(DaoUriUpdated { dao_uri: input.dao_uri.span() }));
            }

            if input.proposal_validation_strategy.should_update() {
                self.set_proposal_validation_strategy(input.proposal_validation_strategy.clone());
                self
                    .emit(
                        Event::ProposalValidationStrategyUpdated(
                            ProposalValidationStrategyUpdated {
                                proposal_validation_strategy: input
                                    .proposal_validation_strategy
                                    .clone(),
                                proposal_validation_strategy_metadata_uri: input
                                    .proposal_validation_strategy_metadata_uri
                                    .span()
                            }
                        )
                    );
            }

            if input.authenticators_to_add.should_update() {
                self.add_authenticators(input.authenticators_to_add.span());
                self
                    .emit(
                        Event::AuthenticatorsAdded(
                            AuthenticatorsAdded {
                                authenticators: input.authenticators_to_add.span()
                            }
                        )
                    );
            }

            if input.authenticators_to_remove.should_update() {
                self.remove_authenticators(input.authenticators_to_remove.span());
                self
                    .emit(
                        Event::AuthenticatorsRemoved(
                            AuthenticatorsRemoved {
                                authenticators: input.authenticators_to_remove.span()
                            }
                        )
                    );
            }

            if input.voting_strategies_to_add.should_update() {
                assert(
                    input
                        .voting_strategies_to_add
                        .len() == input
                        .voting_strategies_metadata_uris_to_add
                        .len(),
                    'len mismatch'
                );
                self.add_voting_strategies(input.voting_strategies_to_add.span());
                self
                    .emit(
                        Event::VotingStrategiesAdded(
                            VotingStrategiesAdded {
                                voting_strategies: input.voting_strategies_to_add.span(),
                                voting_strategy_metadata_uris: input
                                    .voting_strategies_metadata_uris_to_add
                                    .span()
                            }
                        )
                    );
            }

            if input.voting_strategies_to_remove.should_update() {
                self.remove_voting_strategies(input.voting_strategies_to_remove.span());
                self
                    .emit(
                        Event::VotingStrategiesRemoved(
                            VotingStrategiesRemoved {
                                voting_strategy_indices: input.voting_strategies_to_remove.span()
                            }
                        )
                    );
            }
        }

        fn vote_registry(self: @ContractState, proposal_id: u256, voter: UserAddress) -> bool {
            self._vote_registry.read((proposal_id, voter))
        }

        fn vote_power(self: @ContractState, proposal_id: u256, choice: u128) -> u256 {
            self._vote_power.read((proposal_id, choice))
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn generate_votes_array(self: @ContractState, proposal_id: u256) -> Array<u256> {
            let mut votes: Array<u256> = array![];
            let mut i = 0;
            let mut choices: u128 = self._choices.read(proposal_id);
            while i != choices {
                let vp: u256 = self._vote_power.read((proposal_id, i));
                votes.append(vp);
                i += 1;
            };
            votes
        }

        fn assert_only_authenticator(self: @ContractState) {
            let caller: ContractAddress = info::get_caller_address();
            assert(self._authenticators.read(caller), 'Caller is not an authenticator');
        }

        fn get_cumulative_power(
            self: @ContractState,
            voter: UserAddress,
            timestamp: u32,
            mut user_strategies: Span<IndexedStrategy>,
            allowed_strategies: u256
        ) -> u256 {
            user_strategies.assert_no_duplicate_indices();
            let mut total_voting_power = 0_u256;
            loop {
                match user_strategies.pop_front() {
                    Option::Some(strategy_index) => {
                        assert(
                            allowed_strategies.is_bit_set(*strategy_index.index),
                            'Invalid strategy index'
                        );
                        let strategy = self._voting_strategies.read(*strategy_index.index);
                        total_voting_power +=
                            IVotingStrategyDispatcher { contract_address: strategy.address }
                            .get_voting_power(
                                timestamp,
                                voter,
                                strategy.params.span(),
                                strategy_index.params.span()
                            );
                    },
                    Option::None => { break; },
                };
            };
            total_voting_power
        }

        fn set_max_voting_duration(ref self: ContractState, _max_voting_duration: u32) {
            assert(_max_voting_duration >= self._min_voting_duration.read(), 'Invalid duration');
            self._max_voting_duration.write(_max_voting_duration);
        }

        fn set_min_voting_duration(ref self: ContractState, _min_voting_duration: u32) {
            assert(_min_voting_duration <= self._max_voting_duration.read(), 'Invalid duration');
            self._min_voting_duration.write(_min_voting_duration);
        }

        fn set_voting_delay(ref self: ContractState, _voting_delay: u32) {
            self._voting_delay.write(_voting_delay);
        }

        fn set_dao_uri(ref self: ContractState, _dao_uri: Array<felt252>) {
            self._dao_uri.write(_dao_uri);
        }

        fn set_proposal_validation_strategy(
            ref self: ContractState, _proposal_validation_strategy: Strategy
        ) {
            self._proposal_validation_strategy.write(_proposal_validation_strategy);
        }

        fn add_voting_strategies(ref self: ContractState, mut _voting_strategies: Span<Strategy>) {
            let mut cachedActiveVotingStrategies = self._active_voting_strategies.read();
            let mut cachedNextVotingStrategyIndex = self._next_voting_strategy_index.read();
            assert(
                cachedNextVotingStrategyIndex.into() <= 256_u32 - _voting_strategies.len(),
                'Exceeds Voting Strategy Limit'
            );
            loop {
                match _voting_strategies.pop_front() {
                    Option::Some(strategy) => {
                        assert((*strategy.address).is_non_zero(), 'Invalid voting strategy');
                        cachedActiveVotingStrategies.set_bit(cachedNextVotingStrategyIndex, true);
                        self
                            ._voting_strategies
                            .write(cachedNextVotingStrategyIndex, strategy.clone());
                        cachedNextVotingStrategyIndex += 1_u8;
                    },
                    Option::None => { break; },
                };
            };
            self._active_voting_strategies.write(cachedActiveVotingStrategies);
            self._next_voting_strategy_index.write(cachedNextVotingStrategyIndex);
        }

        fn remove_voting_strategies(ref self: ContractState, mut _voting_strategies: Span<u8>) {
            let mut cachedActiveVotingStrategies = self._active_voting_strategies.read();
            loop {
                match _voting_strategies.pop_front() {
                    Option::Some(index) => { cachedActiveVotingStrategies.set_bit(*index, false); },
                    Option::None => { break; },
                };
            };

            assert(cachedActiveVotingStrategies != 0, 'No active voting strategy left');

            self._active_voting_strategies.write(cachedActiveVotingStrategies);
        }

        fn add_authenticators(ref self: ContractState, mut _authenticators: Span<ContractAddress>) {
            loop {
                match _authenticators.pop_front() {
                    Option::Some(authenticator) => {
                        self._authenticators.write(*authenticator, true);
                    },
                    Option::None => { break; },
                };
            }
        }

        fn remove_authenticators(
            ref self: ContractState, mut _authenticators: Span<ContractAddress>
        ) {
            loop {
                match _authenticators.pop_front() {
                    Option::Some(authenticator) => {
                        self._authenticators.write(*authenticator, false);
                    },
                    Option::None => { break; },
                };
            }
        }

        fn assert_proposal_exists(proposal: @Proposal) {
            assert(*proposal.start_timestamp != 0, 'Proposal does not exist');
        }
    }
}

