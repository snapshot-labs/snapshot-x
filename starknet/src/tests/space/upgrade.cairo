#[cfg(test)]
mod tests {
    use starknet::{class_hash::Felt252TryIntoClassHash, ContractAddress, syscalls, testing, info};
    use sx::interfaces::{ISpaceDispatcher, ISpaceDispatcherTrait};
    use sx::space::space::Space;
    use sx::tests::mocks::vanilla_authenticator::{
        VanillaAuthenticator, IVanillaAuthenticatorDispatcher, IVanillaAuthenticatorDispatcherTrait
    };
    use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
    use sx::tests::mocks::vanilla_execution_strategy::VanillaExecutionStrategy;
    use sx::tests::mocks::vanilla_voting_strategy::VanillaVotingStrategy;
    use sx::tests::mocks::vanilla_proposal_validation::VanillaProposalValidationStrategy;
    use sx::types::{UserAddress, Strategy, IndexedStrategy, FinalizationStatus, Proposal,};
    use sx::utils::constants::{PROPOSE_SELECTOR};
    use sx::tests::setup::setup::setup::{setup, deploy};
    use sx::interfaces::{
        IProposalValidationStrategyDispatcher, IProposalValidationStrategyDispatcherTrait
    };
    use sx::tests::mocks::executor::{
        ExecutorExecutionStrategy, ExecutorExecutionStrategy::Transaction
    };
    use sx::tests::mocks::space_v2::{SpaceV2, ISpaceV2Dispatcher, ISpaceV2DispatcherTrait};
    use starknet::ClassHash;
    use starknet::SyscallResultTrait;

    #[test]
    #[available_gas(10000000000)]
    fn upgrade() {
        let config = setup();
        let (_, space) = deploy(@config);

        let new_implem = SpaceV2::TEST_CLASS_HASH.try_into().unwrap();

        testing::set_contract_address(config.owner);

        // Now upgrade the implementation
        space.upgrade(new_implem, array![7]).unwrap_syscall();

        // Ensure it works
        let new_space = ISpaceV2Dispatcher { contract_address: space.contract_address };

        assert(new_space.get_var() == 7, 'New implementation did not work');
    }

    #[test]
    #[available_gas(10000000000)]
    fn upgrade_via_execution_strategy() {
        let config = setup();
        let (_, space) = deploy(@config);
        let proposal_id = space.next_proposal_id();

        // New implementation is not a proposer space but a random contract (here, a proposal validation strategy).
        let new_implem: ClassHash = SpaceV2::TEST_CLASS_HASH.try_into().unwrap();

        let (execution_contract_address, _) = syscalls::deploy_syscall(
            ExecutorExecutionStrategy::TEST_CLASS_HASH.try_into().unwrap(),
            0,
            array![].span(),
            false
        )
            .unwrap();

        // Set the owner to be the execution strategy
        testing::set_contract_address(config.owner);
        let ownable_space = IOwnableDispatcher { contract_address: space.contract_address };
        ownable_space.transfer_ownership(execution_contract_address);

        let selector = sx::utils::constants::UPGRADE_SELECTOR;
        let mut tx_calldata = array![];
        new_implem.serialize(ref tx_calldata);
        array![7].serialize(ref tx_calldata); // initialize calldata
        let tx = Transaction { target: space.contract_address, selector, data: tx_calldata, };

        let mut execution_params = array![];
        tx.serialize(ref execution_params);

        let execution_strategy = Strategy {
            address: execution_contract_address, params: execution_params.clone(),
        };

        let choices: u128 = 3;
        let mut propose_calldata = array![];
        UserAddress::Starknet(starknet::contract_address_const::<0x7676>())
            .serialize(ref propose_calldata);
        choices.serialize(ref propose_calldata);
        ArrayTrait::<felt252>::new().serialize(ref propose_calldata);
        execution_strategy.serialize(ref propose_calldata);
        ArrayTrait::<felt252>::new().serialize(ref propose_calldata);

        let authenticator = IVanillaAuthenticatorDispatcher {
            contract_address: *config.authenticators.at(0)
        };
        authenticator
            .authenticate(space.contract_address, PROPOSE_SELECTOR, propose_calldata.clone());

        // Now upgrade the implementation
        space.execute(proposal_id, execution_params);

        // Ensure it works
        let new_space = ISpaceV2Dispatcher { contract_address: space.contract_address };

        assert(new_space.get_var() == 7, 'New implementation did not work');
    }

    #[test]
    #[available_gas(10000000000)]
    #[should_panic(expected: ('Caller is not the owner', 'ENTRYPOINT_FAILED'))]
    fn upgrade_unauthorized() {
        let config = setup();
        let (_, space) = deploy(@config);

        let new_implem = SpaceV2::TEST_CLASS_HASH.try_into().unwrap();

        testing::set_contract_address(starknet::contract_address_const::<0xdead>());

        // Upgrade should fail as caller is not owner
        space.upgrade(new_implem, array![7]).unwrap_syscall();
    }
}
