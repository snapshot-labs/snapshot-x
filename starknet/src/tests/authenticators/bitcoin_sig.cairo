#[cfg(test)]
mod tests {
    use starknet::{
        ContractAddress, syscalls::deploy_syscall, testing, contract_address_const, info
    };
    use sx::interfaces::{ISpaceDispatcher, ISpaceDispatcherTrait};
    use sx::space::space::Space;
    use sx::authenticators::bitcoin_sig::{
        BitcoinSigAuthenticator, IBitcoinSigAuthenticatorDispatcher,
        IBitcoinSigAuthenticatorDispatcherTrait
    };
    use core::traits::{Into, TryInto};
    use sx::tests::mocks::vanilla_execution_strategy::VanillaExecutionStrategy;
    use sx::tests::mocks::vanilla_voting_strategy::VanillaVotingStrategy;
    use sx::tests::mocks::vanilla_proposal_validation::VanillaProposalValidationStrategy;
    use sx::tests::setup::setup::setup::{setup, deploy};
    use sx::types::{
        UserAddress, Strategy, IndexedStrategy, Choice, FinalizationStatus, Proposal,
        UpdateSettingsCalldata
    };
    use sx::tests::utils::strategy_trait::{StrategyImpl};
    use sx::utils::{Bitcoin};

    fn setup_auth(
        space: ISpaceDispatcher, owner: ContractAddress
    ) -> IBitcoinSigAuthenticatorDispatcher {
        // Deploy Authenticator and whitelist in Space
        let (authenticator_address, _) = deploy_syscall(
            BitcoinSigAuthenticator::TEST_CLASS_HASH.try_into().unwrap(), 0, array![].span(), false
        )
            .unwrap();

        let authenticator = IBitcoinSigAuthenticatorDispatcher {
            contract_address: authenticator_address,
        };
        let mut updateSettingsCalldata: UpdateSettingsCalldata = Default::default();
        updateSettingsCalldata.authenticators_to_add = array![authenticator_address];
        testing::set_contract_address(owner);
        space.update_settings(updateSettingsCalldata);

        authenticator
    }

    #[test]
    #[available_gas(10000000000)]
    fn test_bitcoin_verify() {
        // Signature for 'Hello World' from wallet with address 3HSjuLQ8nFbkUaGaVDUr28Q59hJksUJZYP
        let orig_signature: Array<u8> = array![
            0x24,
            0x37,
            0x1a,
            0xff,
            0x24,
            0x98,
            0x2f,
            0x04,
            0x40,
            0xb6,
            0x75,
            0x94,
            0x94,
            0xf3,
            0xeb,
            0xb8,
            0xd8,
            0x32,
            0xa5,
            0x16,
            0x36,
            0xea,
            0x98,
            0x8e,
            0x00,
            0x91,
            0x9f,
            0x83,
            0xca,
            0x16,
            0x68,
            0x19,
            0x1b,
            0x46,
            0x3a,
            0x4a,
            0x68,
            0x14,
            0xa4,
            0x64,
            0x32,
            0xd5,
            0xf8,
            0xe2,
            0x9a,
            0x7d,
            0xab,
            0xb4,
            0x38,
            0xdf,
            0x02,
            0x08,
            0x7a,
            0xb3,
            0x4e,
            0xc4,
            0x5d,
            0x83,
            0x08,
            0xb6,
            0x1e,
            0xa5,
            0x5e,
            0x03,
            0x56
        ]; // 0x24371aff24982f440b6759494f3ebb8d832a51636ea988e0919f83ca1668191b463a4a6814a46432d5f8e29a7dabb438df287ab34ec45d838b61ea55e356

        let msg: ByteArray = "Hello World";
        let expected_address = "3HSjuLQ8nFbkUaGaVDUr28Q59hJksUJZYP";

        let state = Bitcoin::unsafe_new_contract_state();
        let received_address = Bitcoin::InternalImpl::calculate_address(
            @state, msg, orig_signature
        );

        let mut str: ByteArray = "";

        let mut i = 0;
        while (i < received_address.len()) {
            str.append_byte(*received_address[i]);
            i = i + 1;
        };
        assert!(str == expected_address, "Mismatched verification");
    }

    #[test]
    #[available_gas(10000000000)]
    fn lauriii() {
        let config = setup();
        let (_, space) = deploy(@config);
        let authenticator = setup_auth(space, config.owner);

        let quorum = 1_u256;
        let mut constructor_calldata = array![];
        quorum.serialize(ref constructor_calldata);

        // let (vanilla_execution_strategy_address, _) = deploy_syscall(
        //     VanillaExecutionStrategy::TEST_CLASS_HASH.try_into().unwrap(),
        //     0,
        //     constructor_calldata.span(),
        //     false
        // )
        //     .unwrap();
        // let vanilla_execution_strategy = StrategyImpl::from_address(
        //     vanilla_execution_strategy_address
        // );
        let author: Array<u8> = array![];

        let addr: felt252 = space.contract_address.into();
        // 87dc1cc5e043bb5b40a823f5b2d0d7ab955eba32afe6a7490251cf04a8c1c2
        println!("Orig space address {}", addr);

        // Create Proposal
        //testing::set_contract_address(author);
        authenticator
            .authenticate_propose(
                array![],
                space.contract_address,
                author //, array![], vanilla_execution_strategy, array![]
            );
    //assert(space.next_proposal_id() == 2_u256, 'next_proposal_id should be 2');
    // Update Proposal

    // let proposal_id = 1_u256;
    // // Keeping the same execution strategy contract but changing the payload
    // let mut new_payload = array![1];
    // let new_execution_strategy = Strategy {
    //     address: vanilla_execution_strategy_address, params: new_payload.clone()
    // };

    // testing::set_contract_address(author);
    // authenticator
    //     .authenticate_update_proposal(
    //         space.contract_address, author, proposal_id, new_execution_strategy, array![],
    //     );

    // // Increasing block timestamp by 1 to pass voting delay
    // testing::set_block_timestamp(1_u64);

    // let voter = contract_address_const::<0x8765>();
    // let choice = Choice::For(());
    // let mut user_voting_strategies = array![IndexedStrategy { index: 0_u8, params: array![] }];

    // // Vote on Proposal
    // testing::set_contract_address(voter);
    // authenticator
    //     .authenticate_vote(
    //         space.contract_address, voter, proposal_id, choice, user_voting_strategies, array![]
    //     );

    // testing::set_block_timestamp(2_u64);

    // // Execute Proposal
    // space.execute(1_u256, new_payload);
    }
// #[test]
// #[available_gas(10000000000)]
// #[should_panic(expected: ('Invalid Caller', 'ENTRYPOINT_FAILED'))]
// fn propose_invalid_caller() {
//     let config = setup();
//     let (_, space) = deploy(@config);
//     let authenticator = setup_stark_tx_auth(space, config.owner);

//     let quorum = 1_u256;
//     let mut constructor_calldata = array![];
//     quorum.serialize(ref constructor_calldata);

//     let (vanilla_execution_strategy_address, _) = deploy_syscall(
//         VanillaExecutionStrategy::TEST_CLASS_HASH.try_into().unwrap(),
//         0,
//         constructor_calldata.span(),
//         false
//     )
//         .unwrap();
//     let vanilla_execution_strategy = StrategyImpl::from_address(
//         vanilla_execution_strategy_address
//     );
//     let author = contract_address_const::<0x5678>();

//     // Create Proposal not from author account
//     testing::set_contract_address(config.owner);
//     authenticator
//         .authenticate_propose(
//             space.contract_address, author, array![], vanilla_execution_strategy, array![],
//         );
// }

// #[test]
// #[available_gas(10000000000)]
// #[should_panic(expected: ('Invalid Caller', 'ENTRYPOINT_FAILED'))]
// fn update_proposal_invalid_caller() {
//     let config = setup();
//     let (_, space) = deploy(@config);
//     let authenticator = setup_stark_tx_auth(space, config.owner);

//     let quorum = 1_u256;
//     let mut constructor_calldata = array![];
//     quorum.serialize(ref constructor_calldata);

//     let (vanilla_execution_strategy_address, _) = deploy_syscall(
//         VanillaExecutionStrategy::TEST_CLASS_HASH.try_into().unwrap(),
//         0,
//         constructor_calldata.span(),
//         false
//     )
//         .unwrap();
//     let vanilla_execution_strategy = StrategyImpl::from_address(
//         vanilla_execution_strategy_address
//     );
//     let author = contract_address_const::<0x5678>();

//     // Create Proposal
//     testing::set_contract_address(author);
//     authenticator
//         .authenticate_propose(
//             space.contract_address, author, array![], vanilla_execution_strategy, array![],
//         );

//     assert(space.next_proposal_id() == 2_u256, 'next_proposal_id should be 2');

//     // Update Proposal

//     let proposal_id = 1_u256;
//     // Keeping the same execution strategy contract but changing the payload
//     let mut new_payload = array![1];
//     let new_execution_strategy = Strategy {
//         address: vanilla_execution_strategy_address, params: new_payload.clone()
//     };

//     // Update proposal not from author account
//     testing::set_contract_address(config.owner);
//     authenticator
//         .authenticate_update_proposal(
//             space.contract_address, author, proposal_id, new_execution_strategy, array![]
//         );
// }

// #[test]
// #[available_gas(10000000000)]
// #[should_panic(expected: ('Invalid Caller', 'ENTRYPOINT_FAILED'))]
// fn vote_invalid_caller() {
//     let config = setup();
//     let (_, space) = deploy(@config);
//     let authenticator = setup_stark_tx_auth(space, config.owner);

//     let quorum = 1_u256;
//     let mut constructor_calldata = array![];
//     quorum.serialize(ref constructor_calldata);

//     let (vanilla_execution_strategy_address, _) = deploy_syscall(
//         VanillaExecutionStrategy::TEST_CLASS_HASH.try_into().unwrap(),
//         0,
//         constructor_calldata.span(),
//         false
//     )
//         .unwrap();
//     let vanilla_execution_strategy = StrategyImpl::from_address(
//         vanilla_execution_strategy_address
//     );
//     let author = contract_address_const::<0x5678>();

//     // Create Proposal
//     testing::set_contract_address(author);
//     authenticator
//         .authenticate_propose(
//             space.contract_address, author, array![], vanilla_execution_strategy, array![],
//         );

//     assert(space.next_proposal_id() == 2_u256, 'next_proposal_id should be 2');

//     // Update Proposal

//     let proposal_id = 1_u256;
//     // Keeping the same execution strategy contract but changing the payload
//     let mut new_payload = array![1];
//     let new_execution_strategy = Strategy {
//         address: vanilla_execution_strategy_address, params: new_payload.clone()
//     };

//     testing::set_contract_address(author);
//     authenticator
//         .authenticate_update_proposal(
//             space.contract_address, author, proposal_id, new_execution_strategy, array![]
//         );

//     // Increasing block timestamp by 1 to pass voting delay
//     testing::set_block_timestamp(1_u64);

//     let voter = contract_address_const::<0x8765>();
//     let choice = Choice::For(());
//     let mut user_voting_strategies = array![IndexedStrategy { index: 0_u8, params: array![] }];

//     // Vote on Proposal not from voter account
//     testing::set_contract_address(config.owner);
//     authenticator
//         .authenticate_vote(
//             space.contract_address, voter, proposal_id, choice, user_voting_strategies, array![]
//         );
// }
}
