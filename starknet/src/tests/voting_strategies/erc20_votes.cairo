#[cfg(test)]
mod tests {
    use core::serde::Serde;
    use sx::tests::mocks::erc20_votes_preset::ERC20VotesPreset; // temporary while we wait for scarb to fix their dependencies
    use sx::interfaces::{ISpaceDispatcher, ISpaceDispatcherTrait};
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::governance::utils::interfaces::votes::{
        IVotes, IVotesDispatcher, IVotesDispatcherTrait
    };
    use starknet::{ContractAddress, info, testing, syscalls, SyscallResult};
    use sx::tests::setup::setup::setup::{setup as _setup, deploy, Config};
    use sx::interfaces::{
        IVotingStrategy, IVotingStrategyDispatcher, IVotingStrategyDispatcherTrait
    };
    use sx::tests::mocks::vanilla_authenticator::{
        VanillaAuthenticator, IVanillaAuthenticatorDispatcher, IVanillaAuthenticatorDispatcherTrait
    };
    use sx::voting_strategies::erc20_votes::ERC20VotesVotingStrategy;
    use sx::types::{
        Proposal, IndexedStrategy, Strategy, UpdateSettingsCalldata, UserAddress, UserAddressTrait
    };
    use sx::tests::utils::strategy_trait::StrategyImpl;
    use sx::utils::constants::{PROPOSE_SELECTOR, VOTE_SELECTOR};
    use sx::tests::mocks::vanilla_execution_strategy::VanillaExecutionStrategy;


    const INITIAL_SUPPLY: u256 = 1_000;

    fn OWNER() -> ContractAddress {
        starknet::contract_address_const::<0x111111>()
    }

    fn deploy_token_contract() -> ContractAddress {
        let NAME: ByteArray = "TEST";
        let SYMBOL: ByteArray = "TST";

        let mut constructor_data = array![];
        NAME.serialize(ref constructor_data);
        SYMBOL.serialize(ref constructor_data);
        INITIAL_SUPPLY.low.serialize(ref constructor_data);
        INITIAL_SUPPLY.high.serialize(ref constructor_data);
        OWNER().serialize(ref constructor_data);

        // let constructor_data = array![
        //     NAME, SYMBOL, INITIAL_SUPPLY.low.into(), INITIAL_SUPPLY.high.into(), OWNER().into()
        // ];
        // let constructor_data = (NAME, SYMBOL, INITIAL_SUPPLY.low, INITIAL_SUPPLY, OWNER());

        // Deploy ERC20
        let (token_contract, _) = syscalls::deploy_syscall(
            ERC20VotesPreset::TEST_CLASS_HASH.try_into().unwrap(),
            0,
            constructor_data.span(),
            false,
        )
            .unwrap();

        token_contract.into()
    }

    fn strategy_from_contract(token_contract: ContractAddress) -> Strategy {
        let (contract, _) = syscalls::deploy_syscall(
            ERC20VotesVotingStrategy::TEST_CLASS_HASH.try_into().unwrap(),
            0,
            array![].span(),
            false,
        )
            .unwrap();

        let params: Array<felt252> = array![token_contract.into()];

        Strategy { address: contract, params, }
    }

    fn setup_space() -> (Config, ISpaceDispatcher) {
        let config = _setup();
        let (_, space) = deploy(@config);

        let token_contract = deploy_token_contract();
        let erc20_voting_strategy = strategy_from_contract(token_contract);
        let to_remove = array![0];
        let to_add = array![erc20_voting_strategy];
        let mut settings: UpdateSettingsCalldata = Default::default();
        settings.voting_strategies_to_add = to_add;
        settings.voting_strategies_metadata_uris_to_add = array![array![]];
        settings.voting_strategies_to_remove = to_remove;

        testing::set_contract_address(config.owner);
        space.update_settings(settings);
        (config, space)
    }

    fn get_vanilla_execution_strategy() -> Strategy {
        let quorum = 1_u256;
        let mut constructor_calldata = array![];
        quorum.serialize(ref constructor_calldata);

        let (vanilla_execution_strategy_address, _) = syscalls::deploy_syscall(
            VanillaExecutionStrategy::TEST_CLASS_HASH.try_into().unwrap(),
            0,
            constructor_calldata.span(),
            false
        )
            .unwrap();
        let vanilla_execution_strategy = StrategyImpl::from_address(
            vanilla_execution_strategy_address
        );
        vanilla_execution_strategy
    }

    // Setup 5 accounts with 5 tokens each
    // They each self delegate
    fn setup_accounts(voting_strategy: Strategy) -> Array<UserAddress> {
        let mut params = voting_strategy.params.span();
        let contract = Serde::<ContractAddress>::deserialize(ref params).unwrap();

        let token_contract = IERC20Dispatcher { contract_address: contract, };
        // Create accounts
        let account0 = starknet::contract_address_const::<0x1234>();
        let account1 = starknet::contract_address_const::<0x2345>();
        let account2 = starknet::contract_address_const::<0x3456>();
        let account3 = starknet::contract_address_const::<0x4567>();
        let account4 = starknet::contract_address_const::<0x5678>();

        // Calling from ownwer account
        testing::set_contract_address(OWNER());
        // Fund them
        token_contract.transfer(account0, 5_u256);
        token_contract.transfer(account1, 5_u256);
        token_contract.transfer(account2, 5_u256);
        token_contract.transfer(account3, 5_u256);
        token_contract.transfer(account4, 5_u256);

        let token_contract = IVotesDispatcher { contract_address: contract, };

        // Make them self delegate
        testing::set_contract_address(account0);
        token_contract.delegate(account0);
        testing::set_contract_address(account1);
        token_contract.delegate(account1);
        testing::set_contract_address(account2);
        token_contract.delegate(account2);
        testing::set_contract_address(account3);
        token_contract.delegate(account3);
        testing::set_contract_address(account4);
        token_contract.delegate(account4);

        testing::set_contract_address(OWNER());

        // Return them
        return array![
            UserAddress::Starknet(account0),
            UserAddress::Starknet(account1),
            UserAddress::Starknet(account2),
            UserAddress::Starknet(account3),
            UserAddress::Starknet(account4),
        ];
    }

    #[test]
    #[available_gas(1000000000)]
    fn normal_flow_works() {
        let (config, space) = setup_space();
        let vanilla_execution_strategy = get_vanilla_execution_strategy();
        let accounts = setup_accounts(space.voting_strategies(1));

        let authenticator = IVanillaAuthenticatorDispatcher {
            contract_address: *config.authenticators.at(0),
        };

        let author = UserAddress::Starknet(starknet::contract_address_const::<0x5678>());
        let choices: u128 = 3;
        let mut propose_calldata = array::ArrayTrait::<felt252>::new();
        author.serialize(ref propose_calldata);
        choices.serialize(ref propose_calldata);
        ArrayTrait::<felt252>::new().serialize(ref propose_calldata);
        vanilla_execution_strategy.serialize(ref propose_calldata);
        ArrayTrait::<felt252>::new().serialize(ref propose_calldata);

        // Create a proposal
        authenticator.authenticate(space.contract_address, PROPOSE_SELECTOR, propose_calldata);

        // Advance to vote start + 1
        let current = info::get_block_timestamp();
        testing::set_block_timestamp(current + config.voting_delay.into() + 1);

        let mut vote_calldata = array::ArrayTrait::<felt252>::new();
        let voter = *accounts.at(0);
        voter.serialize(ref vote_calldata);
        let proposal_id = 1_u256;
        proposal_id.serialize(ref vote_calldata);
        let choice = 1;
        choice.serialize(ref vote_calldata);
        let mut user_voting_strategies = array![];
        user_voting_strategies.append(IndexedStrategy { index: 1, params: array![] });
        user_voting_strategies.serialize(ref vote_calldata);
        ArrayTrait::<felt252>::new().serialize(ref vote_calldata);

        // Vote on proposal
        authenticator.authenticate(space.contract_address, VOTE_SELECTOR, vote_calldata);

        testing::set_block_timestamp(current + config.max_voting_duration.into());

        // Execute proposal
        space.execute(1_u256, vanilla_execution_strategy.params);
    }

    #[test]
    #[available_gas(1000000000)]
    #[should_panic(expected: ('Votes: future Lookup', 'ENTRYPOINT_FAILED',))]
    fn revert_if_queried_at_vote_start() {
        let (config, space) = setup_space();
        let vanilla_execution_strategy = get_vanilla_execution_strategy();
        let accounts = setup_accounts(space.voting_strategies(1));

        let authenticator = IVanillaAuthenticatorDispatcher {
            contract_address: *config.authenticators.at(0),
        };

        let author = UserAddress::Starknet(starknet::contract_address_const::<0x5678>());
        let choices: u128 = 3;
        let mut propose_calldata = array::ArrayTrait::<felt252>::new();
        author.serialize(ref propose_calldata);
        choices.serialize(ref propose_calldata);
        ArrayTrait::<felt252>::new().serialize(ref propose_calldata);
        vanilla_execution_strategy.serialize(ref propose_calldata);
        ArrayTrait::<felt252>::new().serialize(ref propose_calldata);

        // Create proposal
        authenticator.authenticate(space.contract_address, PROPOSE_SELECTOR, propose_calldata);

        // Move to the exact voting period start so the strategy will revert.
        let current = info::get_block_timestamp();
        testing::set_block_timestamp(current + config.voting_delay.into());

        let mut vote_calldata = array::ArrayTrait::<felt252>::new();
        let voter = *accounts.at(0);
        voter.serialize(ref vote_calldata);
        let proposal_id = 1_u256;
        proposal_id.serialize(ref vote_calldata);
        let choice = 1;
        choice.serialize(ref vote_calldata);
        let mut user_voting_strategies = array![];
        user_voting_strategies.append(IndexedStrategy { index: 1, params: array![] });
        user_voting_strategies.serialize(ref vote_calldata);
        ArrayTrait::<felt252>::new().serialize(ref vote_calldata);

        // Vote on proposal
        authenticator.authenticate(space.contract_address, VOTE_SELECTOR, vote_calldata);
    }

    #[test]
    #[available_gas(1000000000)]
    #[should_panic(expected: ('User has no voting power', 'ENTRYPOINT_FAILED'))]
    fn no_delegation_means_no_voting_power() {
        let (config, space) = setup_space();
        let vanilla_execution_strategy = get_vanilla_execution_strategy();
        let accounts = setup_accounts(space.voting_strategies(1));

        let authenticator = IVanillaAuthenticatorDispatcher {
            contract_address: *config.authenticators.at(0),
        };

        // Account0 will delegate to another account, so he should not have any voting power
        let mut encoded_token_contract = space.voting_strategies(1).params.span();
        let token_contract = Serde::<ContractAddress>::deserialize(ref encoded_token_contract)
            .unwrap();
        let token_contract = IVotesDispatcher { contract_address: token_contract, };
        testing::set_contract_address((*accounts.at(0)).to_starknet_address());
        token_contract.delegate((starknet::contract_address_const::<0xdeadbeef>()));

        let author = UserAddress::Starknet(starknet::contract_address_const::<0x5678>());
        let choices: u128 = 3;
        let mut propose_calldata = array::ArrayTrait::<felt252>::new();
        author.serialize(ref propose_calldata);
        choices.serialize(ref propose_calldata);
        ArrayTrait::<felt252>::new().serialize(ref propose_calldata);
        vanilla_execution_strategy.serialize(ref propose_calldata);
        ArrayTrait::<felt252>::new().serialize(ref propose_calldata);

        // Create proposal
        authenticator.authenticate(space.contract_address, PROPOSE_SELECTOR, propose_calldata);

        // Move to the exact voting period start + 1
        let current = info::get_block_timestamp();
        testing::set_block_timestamp(current + config.voting_delay.into() + 1);

        let mut vote_calldata = array::ArrayTrait::<felt252>::new();
        let voter = *accounts.at(0);
        voter.serialize(ref vote_calldata);
        let proposal_id = 1_u256;
        proposal_id.serialize(ref vote_calldata);
        let choice = 1;
        choice.serialize(ref vote_calldata);
        let mut user_voting_strategies = array![];
        user_voting_strategies.append(IndexedStrategy { index: 1, params: array![] });
        user_voting_strategies.serialize(ref vote_calldata);
        ArrayTrait::<felt252>::new().serialize(ref vote_calldata);

        // Vote on proposal
        authenticator.authenticate(space.contract_address, VOTE_SELECTOR, vote_calldata);
    }
}

