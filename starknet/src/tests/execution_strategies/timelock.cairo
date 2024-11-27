#[cfg(test)]
mod tests {
    use starknet::{ContractAddress, syscalls, info, testing};
    use sx::tests::setup::setup::{setup, setup::Config};
    use sx::interfaces::{
        IQuorum, IQuorumDispatcher, IQuorumDispatcherTrait, ISpaceDispatcher, ISpaceDispatcherTrait
    };
    use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
    use sx::execution_strategies::{
        TimelockExecutionStrategy, TimelockExecutionStrategy::CallWithSalt,
        timelock::{ITimelockExecutionStrategyDispatcher, ITimelockExecutionStrategyDispatcherTrait}
    };
    use sx::tests::mocks::vanilla_authenticator::{
        VanillaAuthenticator, IVanillaAuthenticatorDispatcher, IVanillaAuthenticatorDispatcherTrait
    };
    use sx::types::{
        UserAddress, Strategy, IndexedStrategy, FinalizationStatus, Proposal, UpdateSettingsCalldata
    };
    use sx::utils::constants::{PROPOSE_SELECTOR, VOTE_SELECTOR, UPDATE_PROPOSAL_SELECTOR};

    const RENOUNCE_OWNERSHIP_SELECTOR: felt252 =
        0x52580a92c73f4428f1a260c5d768ef462b25955307de00f99957df119865d;
    const UPDATE_SETTINGS_SELECTOR: felt252 =
        0x2043d93a9b1d8b042b548f99341fc19540daf9d93a13aaeefa0361924cefe2f;

    fn setup_test() -> (Config, ISpaceDispatcher, ITimelockExecutionStrategyDispatcher) {
        let mut config = setup::setup();
        config.min_voting_duration = 0;
        let (_, space) = setup::deploy(@config);
        let ownable_space = IOwnableDispatcher { contract_address: space.contract_address };

        let spaces = array![space.contract_address];
        let timelock_delay = 100;
        let quorum = 1_u256;

        // Deploy Timelock execution strategy 
        let owner = config.owner;
        let veto_guardian = starknet::contract_address_const::<0x8765>();
        let mut constructor_calldata = array![];
        owner.serialize(ref constructor_calldata);
        veto_guardian.serialize(ref constructor_calldata);
        spaces.serialize(ref constructor_calldata);
        timelock_delay.serialize(ref constructor_calldata);
        quorum.serialize(ref constructor_calldata);

        let (timelock_address, _) = syscalls::deploy_syscall(
            TimelockExecutionStrategy::TEST_CLASS_HASH.try_into().unwrap(),
            0,
            constructor_calldata.span(),
            false
        )
            .unwrap();

        let timelock = ITimelockExecutionStrategyDispatcher { contract_address: timelock_address };

        // Set timelock as space controller
        testing::set_caller_address(config.owner);
        testing::set_contract_address(config.owner);
        ownable_space.transfer_ownership(timelock.contract_address);
        (config, space, timelock)
    }

    fn propose_and_vote(
        config: @Config,
        space: ISpaceDispatcher,
        timelock: ITimelockExecutionStrategyDispatcher,
        proposal_txs: Array<CallWithSalt>
    ) -> (u256, Array<felt252>) {
        let authenticator = IVanillaAuthenticatorDispatcher {
            contract_address: *config.authenticators.at(0),
        };
        let mut payload = array![];
        proposal_txs.serialize(ref payload);
        let timelock_execution_strategy = Strategy {
            address: timelock.contract_address, params: payload.clone()
        };

        let choices: u128 = 3;

        // Create proposal  
        let mut propose_calldata = array![];
        let author = UserAddress::Starknet(starknet::contract_address_const::<0x5678>());
        author.serialize(ref propose_calldata);
        choices.serialize(ref propose_calldata);
        let propose_metadata_uri: Array<felt252> = array![];
        propose_metadata_uri.serialize(ref propose_calldata);
        timelock_execution_strategy.serialize(ref propose_calldata);
        let user_proposal_validation_params: Array<felt252> = array![];
        user_proposal_validation_params.serialize(ref propose_calldata);
        authenticator.authenticate(space.contract_address, PROPOSE_SELECTOR, propose_calldata);

        // Pass voting delay period
        testing::set_block_timestamp(info::get_block_timestamp() + (*config.voting_delay).into());

        // Vote on proposal
        let mut vote_calldata = array![];
        let voter = UserAddress::Starknet(starknet::contract_address_const::<0x8765>());
        voter.serialize(ref vote_calldata);
        let proposal_id = space.next_proposal_id() - 1;
        proposal_id.serialize(ref vote_calldata);
        let choice: u128 = 1;
        choice.serialize(ref vote_calldata);
        let mut user_voting_strategies = array![IndexedStrategy { index: 0_u8, params: array![] }];
        user_voting_strategies.serialize(ref vote_calldata);
        let vote_metadata_uri: Array<felt252> = array![];
        vote_metadata_uri.serialize(ref vote_calldata);
        authenticator.authenticate(space.contract_address, VOTE_SELECTOR, vote_calldata);

        (proposal_id, payload)
    }

    #[test]
    #[available_gas(10000000000)]
    fn timelock_works() {
        let (config, space, timelock) = setup_test();
        let (proposal_id, payload) = propose_and_vote(
            @config,
            space,
            timelock,
            array![
                CallWithSalt {
                    to: space.contract_address,
                    selector: RENOUNCE_OWNERSHIP_SELECTOR,
                    calldata: array![],
                    salt: 0
                }
            ]
        );
        // Execute proposal on space, queueing it in the timelock
        space.execute(proposal_id, payload.clone());
        testing::set_block_timestamp(
            info::get_block_timestamp() + timelock.timelock_delay().into()
        );
        // Execute proposal on timelock - should renounce ownership of space
        timelock.execute_queued_proposal(payload.span());

        let ownable_space = IOwnableDispatcher { contract_address: space.contract_address };
        assert(ownable_space.owner().is_zero(), 'renounce ownership failed');
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Unauthorized Space', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
    fn queue_from_unauthorized_space() {
        let (config, space, timelock) = setup_test();
        let (proposal_id, payload) = propose_and_vote(
            @config,
            space,
            timelock,
            array![
                CallWithSalt {
                    to: space.contract_address,
                    selector: RENOUNCE_OWNERSHIP_SELECTOR,
                    calldata: array![],
                    salt: 0
                }
            ]
        );

        let ownable_timelock = IOwnableDispatcher { contract_address: timelock.contract_address };
        testing::set_caller_address(ownable_timelock.owner());
        testing::set_contract_address(ownable_timelock.owner());
        timelock.disable_space(space.contract_address);
        assert(timelock.is_space_enabled(space.contract_address) == false, 'disable space failed');
        // Try to execute proposal on space, should fail because the space is disabled
        space.execute(proposal_id, payload.clone());
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Invalid Proposal Status', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
    fn proposal_didnt_pass() {
        let (config, space, timelock) = setup_test();
        // Create proposal
        let authenticator = IVanillaAuthenticatorDispatcher {
            contract_address: *config.authenticators.at(0),
        };
        // Call will renounce the timelocks ownership of the space
        let proposal_tx = CallWithSalt {
            to: space.contract_address,
            selector: RENOUNCE_OWNERSHIP_SELECTOR,
            calldata: array![],
            salt: 0
        };
        let mut payload = array![];
        array![proposal_tx].serialize(ref payload);

        let choices: u128 = 3;

        let timelock_execution_strategy = Strategy {
            address: timelock.contract_address, params: payload.clone()
        };
        let mut propose_calldata = array![];
        let author = UserAddress::Starknet(starknet::contract_address_const::<0x5678>());
        author.serialize(ref propose_calldata);
        choices.serialize(ref propose_calldata);
        let propose_metadata_uri: Array<felt252> = array![];
        propose_metadata_uri.serialize(ref propose_calldata);
        timelock_execution_strategy.serialize(ref propose_calldata);
        let user_proposal_validation_params: Array<felt252> = array![];
        user_proposal_validation_params.serialize(ref propose_calldata);
        authenticator.authenticate(space.contract_address, PROPOSE_SELECTOR, propose_calldata);
        assert(space.next_proposal_id() == 2_u256, 'proposal failed');
        // No votes cast on proposal so quorum is not reached
        // Try to execute proposal on space, should fail because the proposal didn't pass
        space.execute(space.next_proposal_id() - 1, payload.clone());
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Already finalized', 'ENTRYPOINT_FAILED'))]
    fn queue_proposal_twice() {
        let (config, space, timelock) = setup_test();
        let (proposal_id, payload) = propose_and_vote(
            @config,
            space,
            timelock,
            array![
                CallWithSalt {
                    to: space.contract_address,
                    selector: RENOUNCE_OWNERSHIP_SELECTOR,
                    calldata: array![],
                    salt: 0
                }
            ]
        );
        // Execute proposal on space, queueing it in the timelock
        space.execute(proposal_id, payload.clone());
        // Try to execute proposal on space again, should fail because the proposal is already queued
        space.execute(proposal_id, payload.clone());
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Duplicate Hash', 'ENTRYPOINT_FAILED', 'ENTRYPOINT_FAILED'))]
    fn queue_duplicate_proposal() {
        let (config, space, timelock) = setup_test();
        // Creating and voting on 2 proposals with the same payload
        let (proposal_id_1, _) = propose_and_vote(
            @config,
            space,
            timelock,
            array![
                CallWithSalt {
                    to: space.contract_address,
                    selector: RENOUNCE_OWNERSHIP_SELECTOR,
                    calldata: array![],
                    salt: 0
                }
            ]
        );
        let (proposal_id_2, payload) = propose_and_vote(
            @config,
            space,
            timelock,
            array![
                CallWithSalt {
                    to: space.contract_address,
                    selector: RENOUNCE_OWNERSHIP_SELECTOR,
                    calldata: array![],
                    salt: 0
                }
            ]
        );
        // Execute proposal on space, queueing it in the timelock
        space.execute(proposal_id_1, payload.clone());
        // Try to execute the second proposal, should fail because the payload is a duplicate
        space.execute(proposal_id_2, payload.clone());
    }

    #[test]
    #[available_gas(10000000000)]
    fn queue_duplicate_proposal_unique_salt() {
        let (config, space, timelock) = setup_test();
        // Creating and voting on 2 proposals with the same payload
        let (proposal_id_1, payload_1) = propose_and_vote(
            @config,
            space,
            timelock,
            array![
                CallWithSalt {
                    to: space.contract_address,
                    selector: RENOUNCE_OWNERSHIP_SELECTOR,
                    calldata: array![],
                    salt: 0
                }
            ]
        );
        let (proposal_id_2, payload_2) = propose_and_vote(
            @config,
            space,
            timelock,
            array![
                CallWithSalt {
                    to: space.contract_address,
                    selector: RENOUNCE_OWNERSHIP_SELECTOR,
                    calldata: array![],
                    salt: 1
                }
            ]
        );
        // Execute proposal on space, queueing it in the timelock
        space.execute(proposal_id_1, payload_1.clone());
        // Execute the second proposal
        space.execute(proposal_id_2, payload_2.clone());
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Invalid payload hash', 'ENTRYPOINT_FAILED'))]
    fn queue_invalid_payload() {
        let (config, space, timelock) = setup_test();
        let (proposal_id, _) = propose_and_vote(
            @config,
            space,
            timelock,
            array![
                CallWithSalt {
                    to: space.contract_address,
                    selector: RENOUNCE_OWNERSHIP_SELECTOR,
                    calldata: array![],
                    salt: 0
                }
            ]
        );
        // Executing with invalid payload array
        space.execute(proposal_id, array![]);
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Call Failed', 'ENTRYPOINT_FAILED'))]
    fn transaction_failed() {
        let (config, space, timelock) = setup_test();
        // Invalid selector on the call
        let (proposal_id, payload) = propose_and_vote(
            @config,
            space,
            timelock,
            array![
                CallWithSalt {
                    to: space.contract_address, selector: 0x1234, calldata: array![], salt: 0
                }
            ]
        );
        space.execute(proposal_id, payload.clone());
        testing::set_block_timestamp(
            info::get_block_timestamp() + timelock.timelock_delay().into()
        );
        timelock.execute_queued_proposal(payload.span());
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Delay Not Met', 'ENTRYPOINT_FAILED'))]
    fn execute_before_timelock_delay() {
        let (config, space, timelock) = setup_test();
        let (proposal_id, payload) = propose_and_vote(
            @config,
            space,
            timelock,
            array![
                CallWithSalt {
                    to: space.contract_address,
                    selector: RENOUNCE_OWNERSHIP_SELECTOR,
                    calldata: array![],
                    salt: 0
                }
            ]
        );
        space.execute(proposal_id, payload.clone());
        // Execute proposal on timelock - should fail because the timelock delay hasn't passed
        timelock.execute_queued_proposal(payload.span());
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Proposal Not Queued', 'ENTRYPOINT_FAILED'))]
    fn execute_not_queued() {
        let (config, space, timelock) = setup_test();
        let (_, payload) = propose_and_vote(
            @config,
            space,
            timelock,
            array![
                CallWithSalt {
                    to: space.contract_address,
                    selector: RENOUNCE_OWNERSHIP_SELECTOR,
                    calldata: array![],
                    salt: 0
                }
            ]
        );
        // Proposal is not queued
        testing::set_block_timestamp(
            info::get_block_timestamp() + timelock.timelock_delay().into()
        );
        // Execute proposal on timelock - should fail because the proposal is not queued
        timelock.execute_queued_proposal(payload.span());
    }

    #[test]
    #[available_gas(10000000000)]
    fn multiple_proposal_txs() {
        let (config, space, timelock) = setup_test();
        let mut new_settings: UpdateSettingsCalldata = Default::default();
        new_settings.max_voting_duration = 1000;
        let mut new_settings_calldata = array![];
        new_settings.serialize(ref new_settings_calldata);

        let (proposal_id, payload) = propose_and_vote(
            @config,
            space,
            timelock,
            array![
                CallWithSalt {
                    to: space.contract_address,
                    selector: UPDATE_SETTINGS_SELECTOR,
                    calldata: new_settings_calldata,
                    salt: 0
                },
                CallWithSalt {
                    to: space.contract_address,
                    selector: RENOUNCE_OWNERSHIP_SELECTOR,
                    calldata: array![],
                    salt: 0
                }
            ]
        );
        // Execute proposal on space, queueing it in the timelock
        space.execute(proposal_id, payload.clone());
        testing::set_block_timestamp(
            info::get_block_timestamp() + timelock.timelock_delay().into()
        );
        // Execute proposal on timelock - should renounce ownership of space and update settings
        timelock.execute_queued_proposal(payload.span());
        assert(space.max_voting_duration() == 1000, 'update settings failed');

        let ownable_space = IOwnableDispatcher { contract_address: space.contract_address };
        assert(ownable_space.owner().is_zero(), 'renounce ownership failed');
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Call Failed', 'ENTRYPOINT_FAILED'))]
    fn multiple_proposal_txs_one_fails() {
        let (config, space, timelock) = setup_test();
        let mut new_settings: UpdateSettingsCalldata = Default::default();
        new_settings.max_voting_duration = 1000;
        let mut new_settings_calldata = array![];
        new_settings.serialize(ref new_settings_calldata);

        // The renounce ownership tx is before the update settings tx. 
        // The latter tx will fail as the owner is needed to update settings
        let (proposal_id, payload) = propose_and_vote(
            @config,
            space,
            timelock,
            array![
                CallWithSalt {
                    to: space.contract_address,
                    selector: RENOUNCE_OWNERSHIP_SELECTOR,
                    calldata: array![],
                    salt: 0
                },
                CallWithSalt {
                    to: space.contract_address,
                    selector: UPDATE_SETTINGS_SELECTOR,
                    calldata: new_settings_calldata,
                    salt: 0
                }
            ]
        );
        // Execute proposal on space, queueing it in the timelock
        space.execute(proposal_id, payload.clone());
        testing::set_block_timestamp(
            info::get_block_timestamp() + timelock.timelock_delay().into()
        );
        timelock.execute_queued_proposal(payload.span());
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Proposal Not Queued', 'ENTRYPOINT_FAILED'))]
    fn veto_proposal() {
        let (config, space, timelock) = setup_test();
        let (proposal_id, payload) = propose_and_vote(
            @config,
            space,
            timelock,
            array![
                CallWithSalt {
                    to: space.contract_address,
                    selector: RENOUNCE_OWNERSHIP_SELECTOR,
                    calldata: array![],
                    salt: 0
                }
            ]
        );
        space.execute(proposal_id, payload.clone());
        // Veto proposal
        testing::set_caller_address(timelock.veto_guardian());
        testing::set_contract_address(timelock.veto_guardian());
        timelock.veto(poseidon::poseidon_hash_span(payload.span()));
        testing::set_block_timestamp(
            info::get_block_timestamp() + timelock.timelock_delay().into()
        );
        // Execute proposal on timelock - should fail as proposal was vetoed
        timelock.execute_queued_proposal(payload.span());
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Unauthorized Caller', 'ENTRYPOINT_FAILED'))]
    fn veto_proposal_unauthorized() {
        let (config, space, timelock) = setup_test();
        let (proposal_id, payload) = propose_and_vote(
            @config,
            space,
            timelock,
            array![
                CallWithSalt {
                    to: space.contract_address,
                    selector: RENOUNCE_OWNERSHIP_SELECTOR,
                    calldata: array![],
                    salt: 0
                }
            ]
        );
        space.execute(proposal_id, payload.clone());

        let ownable_timelock = IOwnableDispatcher { contract_address: timelock.contract_address };
        testing::set_caller_address(ownable_timelock.owner());
        testing::set_contract_address(ownable_timelock.owner());

        // Veto proposal from unauthorized account
        timelock.veto(poseidon::poseidon_hash_span(payload.span()));
    }

    #[test]
    #[available_gas(10000000000)]
    fn set_timelock_delay() {
        let (_, _, timelock) = setup_test();

        let ownable_timelock = IOwnableDispatcher { contract_address: timelock.contract_address };
        testing::set_caller_address(ownable_timelock.owner());
        testing::set_contract_address(ownable_timelock.owner());
        timelock.set_timelock_delay(1000);
        assert(timelock.timelock_delay() == 1000, 'timelock delay not set');
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
    fn set_timelock_delay_unauthorized() {
        let (_, _, timelock) = setup_test();
        // Only the owner can set the timelock delay
        testing::set_caller_address(timelock.veto_guardian());
        testing::set_contract_address(timelock.veto_guardian());
        timelock.set_timelock_delay(1000);
        assert(timelock.timelock_delay() == 1000, 'timelock delay not set');
    }

    #[test]
    #[available_gas(10000000000)]
    fn set_veto_guardian() {
        let (_, _, timelock) = setup_test();

        let ownable_timelock = IOwnableDispatcher { contract_address: timelock.contract_address };
        testing::set_caller_address(ownable_timelock.owner());
        testing::set_contract_address(ownable_timelock.owner());
        timelock.set_veto_guardian(timelock.veto_guardian());
        assert(timelock.veto_guardian() == timelock.veto_guardian(), 'veto guardian not set');
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
    fn set_veto_guardian_unauthorized() {
        let (_, _, timelock) = setup_test();
        // Only the owner can set the veto guardian
        testing::set_caller_address(timelock.veto_guardian());
        testing::set_contract_address(timelock.veto_guardian());
        timelock.set_veto_guardian(starknet::contract_address_const::<0x9999>());
    }

    #[test]
    #[available_gas(10000000000)]
    fn set_owner() {
        let (_, _, timelock) = setup_test();

        let ownable_timelock = IOwnableDispatcher { contract_address: timelock.contract_address };
        testing::set_caller_address(ownable_timelock.owner());
        testing::set_contract_address(ownable_timelock.owner());
        ownable_timelock.transfer_ownership(timelock.veto_guardian());
        assert(ownable_timelock.owner() == timelock.veto_guardian(), 'owner not set');
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
    fn set_owner_unauthorized() {
        let (_, _, timelock) = setup_test();
        // Only the owner can transfer ownership
        testing::set_caller_address(timelock.veto_guardian());
        testing::set_contract_address(timelock.veto_guardian());

        let ownable_timelock = IOwnableDispatcher { contract_address: timelock.contract_address };
        ownable_timelock.transfer_ownership(starknet::contract_address_const::<0x9999>());
    }

    #[test]
    #[available_gas(10000000000)]
    fn enable_space() {
        let (_, _, timelock) = setup_test();

        let ownable_timelock = IOwnableDispatcher { contract_address: timelock.contract_address };
        testing::set_caller_address(ownable_timelock.owner());
        testing::set_contract_address(ownable_timelock.owner());
        timelock.enable_space(starknet::contract_address_const::<0x123456789>());
        assert(
            timelock.is_space_enabled(starknet::contract_address_const::<0x123456789>()),
            'space not enabled'
        );
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
    fn enable_space_unauthorized() {
        let (_, _, timelock) = setup_test();
        // Only the owner can enable a space
        testing::set_caller_address(timelock.veto_guardian());
        testing::set_contract_address(timelock.veto_guardian());
        timelock.enable_space(starknet::contract_address_const::<0x123456789>());
    }

    #[test]
    #[available_gas(10000000000)]
    fn disable_space() {
        let (_, _, timelock) = setup_test();

        let ownable_timelock = IOwnableDispatcher { contract_address: timelock.contract_address };
        testing::set_caller_address(ownable_timelock.owner());
        testing::set_contract_address(ownable_timelock.owner());
        timelock.enable_space(starknet::contract_address_const::<0x123456789>());
        timelock.disable_space(starknet::contract_address_const::<0x123456789>());
        assert(
            !timelock.is_space_enabled(starknet::contract_address_const::<0x123456789>()),
            'space not disabled'
        );
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
    fn disable_space_unauthorized() {
        let (_, _, timelock) = setup_test();
        // Only the owner can disable a space
        testing::set_caller_address(timelock.veto_guardian());
        testing::set_contract_address(timelock.veto_guardian());
        timelock.disable_space(starknet::contract_address_const::<0x123456789>());
    }
}
