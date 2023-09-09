use sx::types::{Proposal, ProposalStatus};

/// The execution strategy interface that all execution strategies must implement.
#[starknet::interface]
trait IExecutionStrategy<TContractState> {
    /// The space contract will call this function when a proposal is `execute`-ed.
    /// It is up to the `execute` function to perform the necessary
    /// checks to ensure that the proposal should be executed.
    ///
    /// # Arguments
    ///
    /// * `proposal` - The proposal to execute.
    /// * `votes_for` - The number of votes for the proposal.
    /// * `votes_against` - The number of votes against the proposal.
    /// * `votes_abstain` - The number of votes abstaining from the proposal.
    /// * `payload` - The payload of the proposal.
    fn execute(
        ref self: TContractState,
        proposal: Proposal,
        votes_for: u256,
        votes_against: u256,
        votes_abstain: u256,
        payload: Array<felt252>
    );

    /// View function to get the proposal status.
    ///
    /// # Arguments
    ///
    /// * `proposal` - The proposal to get the status for.
    /// * `votes_for` - The number of votes for the proposal.
    /// * `votes_against` - The number of votes against the proposal.
    /// * `votes_abstain` - The number of votes abstaining from the proposal.
    ///
    /// # Returns
    ///
    /// * `ProposalStatus` - The status of the proposal.
    fn get_proposal_status(
        self: @TContractState,
        proposal: Proposal,
        votes_for: u256,
        votes_against: u256,
        votes_abstain: u256,
    ) -> ProposalStatus;

    /// Returns a short string describing the strategy type.
    fn get_strategy_type(self: @TContractState) -> felt252;
}
