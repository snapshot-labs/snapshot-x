/// Execution strategy that will not execute anything but ensure that the
/// proposal is in the status `Accepted` or `VotingPeriodAccepted` by following
/// the `SimpleMajority` rule (`votes_for > votes_against`).
#[starknet::contract]
mod NoExecutionSimpleMajorityExecutionStrategy {
    use sx::interfaces::IExecutionStrategy;
    use sx::types::{Proposal, ProposalStatus};
    use sx::utils::simple_majority;

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl NoExecutionSimpleMajorityExecutionStrategy of IExecutionStrategy<ContractState> {
        fn execute(
            ref self: ContractState,
            proposal_id: u256,
            proposal: Proposal,
            votes: Array<u256>,
            payload: Array<felt252>
        ) {
            let proposal_status = self.get_proposal_status(proposal, votes);
            assert(proposal_status == ProposalStatus::Accepted(()), 'Invalid Proposal Status');
        }

        fn get_proposal_status(
            self: @ContractState, proposal: Proposal, votes: Array<u256>,
        ) -> ProposalStatus {
            assert(votes.len() == 3, 'Invalid votes array length');
            let votes_against = *votes[0];
            let votes_for = *votes[1];
            let votes_abstain = *votes[2];
            simple_majority::get_proposal_status(@proposal, votes_for, votes_against, votes_abstain)
        }

        fn get_strategy_type(self: @ContractState) -> felt252 {
            'NoExecutionSimpleMajority'
        }
    }
}
