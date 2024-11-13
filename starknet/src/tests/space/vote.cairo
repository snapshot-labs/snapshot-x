#[cfg(test)]
mod tests {
    use starknet::{ContractAddress, syscalls, testing, info};
    use sx::space::space::{Space, Space::VoteCast};
    use sx::interfaces::{ISpaceDispatcher, ISpaceDispatcherTrait};
    use sx::tests::mocks::vanilla_authenticator::{
        VanillaAuthenticator, IVanillaAuthenticatorDispatcher, IVanillaAuthenticatorDispatcherTrait
    };
    use sx::tests::mocks::executor::ExecutorWithoutTxExecutionStrategy;
    use sx::tests::mocks::vanilla_voting_strategy::VanillaVotingStrategy;
    use sx::tests::mocks::vanilla_proposal_validation::VanillaProposalValidationStrategy;
    use sx::tests::mocks::proposal_validation_always_fail::AlwaysFailProposalValidationStrategy;
    use sx::tests::mocks::no_voting_power::NoVotingPowerVotingStrategy;
    use sx::tests::setup::setup::setup::{setup, deploy};
    use sx::types::{
        UserAddress, Strategy, IndexedStrategy, FinalizationStatus, Proposal, UpdateSettingsCalldata
    };
    use sx::tests::utils::strategy_trait::{StrategyImpl};
    use sx::utils::constants::{PROPOSE_SELECTOR, VOTE_SELECTOR, UPDATE_PROPOSAL_SELECTOR};
    use openzeppelin::tests::utils;

    use Space::Space as SpaceImpl;

    fn get_execution_strategy() -> Strategy {
        let mut constructor_calldata = array![];

        let (execution_strategy_address, _) = syscalls::deploy_syscall(
            ExecutorWithoutTxExecutionStrategy::TEST_CLASS_HASH.try_into().unwrap(),
            0,
            constructor_calldata.span(),
            false
        )
            .unwrap();
        let strategy = StrategyImpl::from_address(execution_strategy_address);
        strategy
    }

    fn create_proposal(
        authenticator: IVanillaAuthenticatorDispatcher,
        space: ISpaceDispatcher,
        execution_strategy: Strategy
    ) {
        let author = UserAddress::Starknet(starknet::contract_address_const::<0x5678>());
        let choices: u128 = 3;
        let mut propose_calldata = array![];
        author.serialize(ref propose_calldata);
        choices.serialize(ref propose_calldata);
        ArrayTrait::<felt252>::new().serialize(ref propose_calldata);
        execution_strategy.serialize(ref propose_calldata);
        ArrayTrait::<felt252>::new().serialize(ref propose_calldata);

        // Create Proposal
        authenticator.authenticate(space.contract_address, PROPOSE_SELECTOR, propose_calldata);
    }

    fn assert_vote_emitted_and_correct(
        space_address: ContractAddress,
        proposal_id: u256,
        voter: UserAddress,
        choice: u128,
        voting_power: u256,
        metadata_uri: Span<felt252>,
    ) {
        let event = utils::pop_log::<Space::Event>(space_address).unwrap();
        let expected = Space::Event::VoteCast(
            VoteCast { proposal_id, voter, choice, voting_power, metadata_uri }
        );
        assert(event == expected, 'Vote event should be correct');
    }

    #[test]
    #[available_gas(10000000000)]
    fn vote_for() {
        let config = setup();
        let (_, space) = deploy(@config);

        let execution_strategy = get_execution_strategy();

        let authenticator = IVanillaAuthenticatorDispatcher {
            contract_address: *config.authenticators.at(0),
        };

        create_proposal(authenticator, space, execution_strategy);

        // Increasing block timestamp pass voting delay
        testing::set_block_timestamp(config.voting_delay.into());

        let mut vote_calldata = array![];
        let voter = UserAddress::Starknet(starknet::contract_address_const::<0x8765>());
        voter.serialize(ref vote_calldata);
        let proposal_id = 1_u256;
        proposal_id.serialize(ref vote_calldata);
        let choice = 1;
        choice.serialize(ref vote_calldata);
        let mut user_voting_strategies = array![IndexedStrategy { index: 0_u8, params: array![] }];
        user_voting_strategies.serialize(ref vote_calldata);
        let metadata_uri: Array<felt252> = array![];
        metadata_uri.serialize(ref vote_calldata);

        // empty events queue
        utils::drop_events(space.contract_address, 4);

        authenticator.authenticate(space.contract_address, VOTE_SELECTOR, vote_calldata);
        assert(space.vote_registry(proposal_id, voter) == true, 'vote registry incorrect');
        assert(space.vote_power(proposal_id, 1) == 1, 'Vote power should be 1');
        assert(space.vote_power(proposal_id, 0) == 0, 'Vote power should be 0');
        assert(space.vote_power(proposal_id, 2) == 0, 'Vote power should be 0');
        assert_vote_emitted_and_correct(
            space.contract_address, proposal_id, voter, choice, 1, metadata_uri.span()
        );
    }

    #[test]
    #[available_gas(10000000000)]
    fn vote_against() {
        let config = setup();
        let (_, space) = deploy(@config);
        let execution_strategy = get_execution_strategy();

        let authenticator = IVanillaAuthenticatorDispatcher {
            contract_address: *config.authenticators.at(0),
        };

        create_proposal(authenticator, space, execution_strategy);

        // Increasing block timestamp pass voting delay
        testing::set_block_timestamp(config.voting_delay.into());

        let mut vote_calldata = array![];
        let voter = UserAddress::Starknet(starknet::contract_address_const::<0x8765>());
        voter.serialize(ref vote_calldata);
        let proposal_id = 1_u256;
        proposal_id.serialize(ref vote_calldata);
        let choice = 0;
        choice.serialize(ref vote_calldata);
        let mut user_voting_strategies = array![IndexedStrategy { index: 0_u8, params: array![] }];
        user_voting_strategies.serialize(ref vote_calldata);
        let metadata_uri: Array<felt252> = array![];
        metadata_uri.serialize(ref vote_calldata);

        // empty events queue
        utils::drop_events(space.contract_address, 4);

        authenticator.authenticate(space.contract_address, VOTE_SELECTOR, vote_calldata);
        assert(space.vote_registry(proposal_id, voter) == true, 'vote registry incorrect');
        assert(space.vote_power(proposal_id, 1) == 0, 'Vote power should be 0');
        assert(space.vote_power(proposal_id, 0) == 1, 'Vote power should be 1');
        assert(space.vote_power(proposal_id, 2) == 0, 'Vote power should be 0');
        assert_vote_emitted_and_correct(
            space.contract_address, proposal_id, voter, choice, 1, metadata_uri.span()
        );
    }

    #[test]
    #[available_gas(10000000000)]
    fn vote_abstain() {
        let config = setup();
        let (_, space) = deploy(@config);
        let execution_strategy = get_execution_strategy();

        let authenticator = IVanillaAuthenticatorDispatcher {
            contract_address: *config.authenticators.at(0),
        };

        create_proposal(authenticator, space, execution_strategy);

        // Increasing block timestamp by voting delay
        testing::set_block_timestamp(config.voting_delay.into());

        let mut vote_calldata = array![];
        let voter = UserAddress::Starknet(starknet::contract_address_const::<0x8765>());
        voter.serialize(ref vote_calldata);
        let proposal_id = 1_u256;
        proposal_id.serialize(ref vote_calldata);
        let choice = 2;
        choice.serialize(ref vote_calldata);
        let mut user_voting_strategies = array![IndexedStrategy { index: 0_u8, params: array![] }];
        user_voting_strategies.serialize(ref vote_calldata);
        let metadata_uri: Array<felt252> = array![];
        metadata_uri.serialize(ref vote_calldata);

        // empty events queue
        utils::drop_events(space.contract_address, 4);
        authenticator.authenticate(space.contract_address, VOTE_SELECTOR, vote_calldata);
        assert(space.vote_registry(proposal_id, voter) == true, 'vote registry incorrect');
        assert(space.vote_power(proposal_id, 1) == 0, 'Vote power should be 0');
        assert(space.vote_power(proposal_id, 0) == 0, 'Vote power should be 0');
        assert(space.vote_power(proposal_id, 2) == 1, 'Vote power should be 1');
        assert_vote_emitted_and_correct(
            space.contract_address, proposal_id, voter, choice, 1, metadata_uri.span()
        );
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Voting period has not started', 'ENTRYPOINT_FAILED'))]
    fn vote_too_early() {
        let config = setup();
        let (_, space) = deploy(@config);
        let execution_strategy = get_execution_strategy();

        let authenticator = IVanillaAuthenticatorDispatcher {
            contract_address: *config.authenticators.at(0),
        };

        create_proposal(authenticator, space, execution_strategy);

        // Do NOT increase block timestamp 

        let mut vote_calldata = array![];
        let voter = UserAddress::Starknet(starknet::contract_address_const::<0x8765>());
        voter.serialize(ref vote_calldata);
        let proposal_id = 1_u256;
        proposal_id.serialize(ref vote_calldata);
        let choice = 1;
        choice.serialize(ref vote_calldata);
        let mut user_voting_strategies = array![IndexedStrategy { index: 0_u8, params: array![] }];
        user_voting_strategies.serialize(ref vote_calldata);
        ArrayTrait::<felt252>::new().serialize(ref vote_calldata);

        authenticator.authenticate(space.contract_address, VOTE_SELECTOR, vote_calldata);
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Voting period has ended', 'ENTRYPOINT_FAILED'))]
    fn vote_too_late() {
        let config = setup();
        let (_, space) = deploy(@config);
        let execution_strategy = get_execution_strategy();

        let authenticator = IVanillaAuthenticatorDispatcher {
            contract_address: *config.authenticators.at(0),
        };

        create_proposal(authenticator, space, execution_strategy);

        // Fast forward to end of voting period
        testing::set_block_timestamp(
            config.voting_delay.into() + config.max_voting_duration.into()
        );

        let mut vote_calldata = array![];
        let voter = UserAddress::Starknet(starknet::contract_address_const::<0x8765>());
        voter.serialize(ref vote_calldata);
        let proposal_id = 1_u256;
        proposal_id.serialize(ref vote_calldata);
        let choice = 1;
        choice.serialize(ref vote_calldata);
        let mut user_voting_strategies = array![IndexedStrategy { index: 0_u8, params: array![] }];
        user_voting_strategies.serialize(ref vote_calldata);
        ArrayTrait::<felt252>::new().serialize(ref vote_calldata);

        authenticator.authenticate(space.contract_address, VOTE_SELECTOR, vote_calldata);
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Already finalized', 'ENTRYPOINT_FAILED'))]
    fn vote_finalized_proposal() {
        let config = setup();
        let (_, space) = deploy(@config);
        let execution_strategy = get_execution_strategy();

        let authenticator = IVanillaAuthenticatorDispatcher {
            contract_address: *config.authenticators.at(0),
        };

        create_proposal(authenticator, space, execution_strategy);

        testing::set_block_timestamp(config.voting_delay.into());

        space
            .execute(
                1, array![]
            ); // Execute the proposal (will work because execution strategy doesn't check for finalization status or quorum)

        let mut vote_calldata = array![];
        let voter = UserAddress::Starknet(starknet::contract_address_const::<0x8765>());
        voter.serialize(ref vote_calldata);
        let proposal_id = 1_u256;
        proposal_id.serialize(ref vote_calldata);
        let choice = 1;
        choice.serialize(ref vote_calldata);
        let mut user_voting_strategies = array![IndexedStrategy { index: 0_u8, params: array![] }];
        user_voting_strategies.serialize(ref vote_calldata);
        ArrayTrait::<felt252>::new().serialize(ref vote_calldata);

        authenticator.authenticate(space.contract_address, VOTE_SELECTOR, vote_calldata);
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Caller is not an authenticator', 'ENTRYPOINT_FAILED'))]
    fn vote_without_authenticator() {
        let config = setup();
        let (_, space) = deploy(@config);
        let execution_strategy = get_execution_strategy();

        let authenticator = IVanillaAuthenticatorDispatcher {
            contract_address: *config.authenticators.at(0),
        };

        create_proposal(authenticator, space, execution_strategy);

        // Fast forward to end of voting period
        testing::set_block_timestamp(
            config.voting_delay.into() + config.max_voting_duration.into()
        );

        let voter = UserAddress::Starknet(starknet::contract_address_const::<0x8765>());
        let proposal_id = 1_u256;
        let choice = 1;
        let mut user_voting_strategies = array![IndexedStrategy { index: 0_u8, params: array![] }];
        let metadata_uri = array![];

        space.vote(voter, proposal_id, choice, user_voting_strategies, metadata_uri);
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Voter has already voted', 'ENTRYPOINT_FAILED'))]
    fn vote_twice() {
        let config = setup();
        let (_, space) = deploy(@config);

        let execution_strategy = get_execution_strategy();

        let authenticator = IVanillaAuthenticatorDispatcher {
            contract_address: *config.authenticators.at(0),
        };

        create_proposal(authenticator, space, execution_strategy);

        // Increasing block timestamp pass voting delay
        testing::set_block_timestamp(config.voting_delay.into());

        let mut vote_calldata = array![];
        let voter = UserAddress::Starknet(starknet::contract_address_const::<0x8765>());
        voter.serialize(ref vote_calldata);
        let proposal_id = 1_u256;
        proposal_id.serialize(ref vote_calldata);
        let choice = 1;
        choice.serialize(ref vote_calldata);
        let mut user_voting_strategies = array![IndexedStrategy { index: 0_u8, params: array![] }];
        user_voting_strategies.serialize(ref vote_calldata);
        ArrayTrait::<felt252>::new().serialize(ref vote_calldata);

        authenticator.authenticate(space.contract_address, VOTE_SELECTOR, vote_calldata.clone());
        authenticator.authenticate(space.contract_address, VOTE_SELECTOR, vote_calldata);
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('User has no voting power', 'ENTRYPOINT_FAILED'))]
    fn vote_no_voting_power() {
        let config = setup();
        let (_, space) = deploy(@config);

        let execution_strategy = get_execution_strategy();

        let authenticator = IVanillaAuthenticatorDispatcher {
            contract_address: *config.authenticators.at(0),
        };

        let (no_voting_power_contract, _) = syscalls::deploy_syscall(
            NoVotingPowerVotingStrategy::TEST_CLASS_HASH.try_into().unwrap(),
            0,
            array![].span(),
            false
        )
            .unwrap();
        let no_voting_power_strategy = StrategyImpl::from_address(no_voting_power_contract);

        let mut input: UpdateSettingsCalldata = Default::default();
        input.voting_strategies_to_add = array![no_voting_power_strategy];
        input.voting_strategies_metadata_uris_to_add = array![array![]];

        testing::set_contract_address(config.owner);
        space.update_settings(input);

        create_proposal(authenticator, space, execution_strategy);

        // Increasing block timestamp pass voting delay
        testing::set_block_timestamp(config.voting_delay.into());

        let mut vote_calldata = array![];
        let voter = UserAddress::Starknet(starknet::contract_address_const::<0x8765>());
        voter.serialize(ref vote_calldata);
        let proposal_id = 1_u256;
        proposal_id.serialize(ref vote_calldata);
        let choice = 1;
        choice.serialize(ref vote_calldata);
        let mut user_voting_strategies = array![
            IndexedStrategy { index: 1_u8, params: array![] }
        ]; // index 1
        user_voting_strategies.serialize(ref vote_calldata);
        ArrayTrait::<felt252>::new().serialize(ref vote_calldata);

        authenticator.authenticate(space.contract_address, VOTE_SELECTOR, vote_calldata);
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Proposal does not exist', 'ENTRYPOINT_FAILED'))]
    fn vote_inexistant_proposal() {
        let config = setup();
        let (_, space) = deploy(@config);

        let execution_strategy = get_execution_strategy();

        let authenticator = IVanillaAuthenticatorDispatcher {
            contract_address: *config.authenticators.at(0),
        };

        create_proposal(authenticator, space, execution_strategy);

        // Increasing block timestamp pass voting delay
        testing::set_block_timestamp(config.voting_delay.into());

        let mut vote_calldata = array![];
        let voter = UserAddress::Starknet(starknet::contract_address_const::<0x8765>());
        voter.serialize(ref vote_calldata);
        let proposal_id = 42_u256; // inexistent proposal
        proposal_id.serialize(ref vote_calldata);
        let choice = 1;
        choice.serialize(ref vote_calldata);
        let mut user_voting_strategies = array![IndexedStrategy { index: 0_u8, params: array![] }];
        user_voting_strategies.serialize(ref vote_calldata);
        ArrayTrait::<felt252>::new().serialize(ref vote_calldata);

        authenticator.authenticate(space.contract_address, VOTE_SELECTOR, vote_calldata);
    }
}
