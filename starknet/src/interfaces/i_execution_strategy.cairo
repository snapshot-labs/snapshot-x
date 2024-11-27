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
    /// * `proposal_id` - The id of the proposal to execute.
    /// * `proposal` - The struct of the proposal to execute.
    /// * `votes` - An array with each element representing the amount of voting power for each choice.
    /// * `payload` - The payload of the proposal.
    fn execute(
        ref self: TContractState,
        proposal_id: u256,
        proposal: Proposal,
        votes: Array<u256>,
        payload: Array<felt252>
    );

    /// View function to get the proposal status.
    ///
    /// # Arguments
    ///
    /// * `proposal` - The proposal to get the status for.
    /// * `votes` - An array with each element representing the amount of voting power for each choice.
    ///
    /// # Returns
    ///
    /// * `ProposalStatus` - The status of the proposal.
    fn get_proposal_status(
        self: @TContractState, proposal: Proposal, votes: Array<u256>
    ) -> ProposalStatus;

    /// Returns a short string describing the strategy type.
    fn get_strategy_type(self: @TContractState) -> felt252;
}
