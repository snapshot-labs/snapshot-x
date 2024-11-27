#[starknet::contract]
mod VanillaExecutionStrategy {
    use sx::interfaces::{IExecutionStrategy, IQuorum};
    use sx::types::{Proposal, ProposalStatus};
    use sx::utils::simple_quorum::SimpleQuorumComponent;

    component!(path: SimpleQuorumComponent, storage: simple_quorum, event: SimpleQuorumEvent);

    #[abi(embed_v0)]
    impl SimpleQuorumImpl = SimpleQuorumComponent::SimpleQuorumImpl<ContractState>;
    impl SimpleQuorumInternalImpl = SimpleQuorumComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        _num_executed: felt252,
        #[substorage(v0)]
        simple_quorum: SimpleQuorumComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        SimpleQuorumEvent: SimpleQuorumComponent::Event,
    }

    /// The vanilla execution strategy is a dummy execution strategy that simply increments a `_num_executed` variable for every
    /// newly executed proposal. It uses the `SimpleQuorum` method to determine whether a proposal is accepted or not.
    #[abi(embed_v0)]
    impl VanillaExecutionStrategy of IExecutionStrategy<ContractState> {
        fn execute(
            ref self: ContractState,
            proposal_id: u256,
            proposal: Proposal,
            votes: Array<u256>,
            payload: Array<felt252>
        ) {
            let proposal_status = self.get_proposal_status(proposal, votes);
            assert(
                (proposal_status == ProposalStatus::Accepted(()))
                    | (proposal_status == ProposalStatus::VotingPeriodAccepted(())),
                'Invalid Proposal Status'
            );
            self._num_executed.write(self._num_executed.read() + 1);
        }

        fn get_proposal_status(
            self: @ContractState, proposal: Proposal, votes: Array<u256>,
        ) -> ProposalStatus {
            assert(votes.len() == 3, 'Invalid votes array length');

            let votes_against = *votes[0];
            let votes_for = *votes[1];
            let votes_abstain = *votes[2];
            self
                .simple_quorum
                .get_proposal_status(@proposal, votes_for, votes_against, votes_abstain,)
        }

        fn get_strategy_type(self: @ContractState) -> felt252 {
            'SimpleQuorumVanilla'
        }
    }

    #[constructor]
    fn constructor(ref self: ContractState, quorum: u256) {
        self.simple_quorum.initializer(quorum);
    }

    #[generate_trait]
    impl NumExecutedImpl of NumExecutedTrait {
        fn num_executed(self: @ContractState) -> felt252 {
            self._num_executed.read()
        }
    }
}
