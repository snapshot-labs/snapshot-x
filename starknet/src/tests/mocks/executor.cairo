#[starknet::contract]
mod ExecutorExecutionStrategy {
    use sx::interfaces::IExecutionStrategy;
    use sx::types::{Proposal, ProposalStatus};
    use starknet::ContractAddress;
    use starknet::syscalls::call_contract_syscall;

    #[storage]
    struct Storage {}

    #[derive(Drop, Serde)]
    struct Transaction {
        target: ContractAddress,
        selector: felt252,
        data: Array<felt252>,
    }

    #[abi(embed_v0)]
    impl ExecutorExecutionStrategy of IExecutionStrategy<ContractState> {
        // Dummy function that will just execute the `Transaction` in the payload, without needing any quorum.
        fn execute(
            ref self: ContractState,
            proposal_id: u256,
            proposal: Proposal,
            votes: Array<u256>,
            payload: Array<felt252>
        ) {
            let mut sp4n = payload.span();
            let tx: Transaction = Serde::<Transaction>::deserialize(ref sp4n).unwrap();
            call_contract_syscall(tx.target, tx.selector, tx.data.span()).unwrap();
        }

        fn get_proposal_status(
            self: @ContractState, proposal: Proposal, votes: Array<u256>,
        ) -> ProposalStatus {
            panic_with_felt252('unimplemented');
            ProposalStatus::Cancelled(())
        }

        fn get_strategy_type(self: @ContractState) -> felt252 {
            'Executor'
        }
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}
}


#[starknet::contract]
mod ExecutorWithoutTxExecutionStrategy {
    use sx::interfaces::IExecutionStrategy;
    use sx::types::{Proposal, ProposalStatus};
    use core::array::ArrayTrait;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl ExecutorWithoutTxExecutionStrategy of IExecutionStrategy<ContractState> {
        // Dummy function that will do nothing
        fn execute(
            ref self: ContractState,
            proposal_id: u256,
            proposal: Proposal,
            votes: Array<u256>,
            payload: Array<felt252>
        ) {}

        fn get_proposal_status(
            self: @ContractState, proposal: Proposal, votes: Array<u256>,
        ) -> ProposalStatus {
            panic_with_felt252('unimplemented');
            ProposalStatus::Cancelled(())
        }

        fn get_strategy_type(self: @ContractState) -> felt252 {
            'ExecutorWithoutTx'
        }
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}
}
